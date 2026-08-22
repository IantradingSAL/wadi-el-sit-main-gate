-- ═══════════════════════════════════════════════════════════════════════════
-- 31 — كل حدث يستحق إشعاراً، وكل إشعار يُعرف مصيره
--
-- Until now exactly one thing in the whole portal pushed a notification: a
-- citizen's case, through the `notify-i18n` trigger. Everything else — a
-- directory entry approved, a proposed edit applied, a coop seller or delivery
-- agent accepted, an order confirmed, an irrigation turn coming up — told the
-- person nothing, or told them by e-mail only, or told them on WhatsApp if
-- somebody remembered to press the button.
--
-- This migration makes the database the sender:
--
--   1. `push_notify()` — one entry point. Every trigger below calls it; it
--      hands the message to the `send-push` edge function through pg_net and
--      swallows its own errors, so a notification can never break the thing it
--      is reporting on. That is the same shape as `approval_notify()` (27).
--
--   2. The call is authorised by a secret this database owns (`vault`), not by
--      the service-role key. The `notify-i18n` trigger carries that key in
--      plaintext inside its own definition, readable by anything that can read
--      pg_trigger — this path deliberately does not repeat that.
--
--   3. `push_receipts` — one row per device per send. The edge function writes
--      it at the moment it hands the message to the push service; the service
--      worker fills in `delivered_at` when the device actually receives it and
--      `opened_at` when the person taps it. Before this there was only
--      `push_log`, which recorded that the municipality had *tried*.
--
--   4. Reading all of that is its own permission — `push_log_view` — because
--      the log carries message bodies and residents' phone numbers.
--
-- The irrigation reminders are the one sender that has no event to hang off:
-- nothing changes in a table when somebody's turn approaches. They get a
-- pg_cron sweep that recomputes the cycle the same way water-admin.html draws
-- it, and a ledger so a reminder is sent once and only once.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 1 · the secret that proves a request came from this database ───────────
-- Generated here, never written down: nothing but the vault ever holds it, and
-- the edge function checks it back through `push_internal_auth()`.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'push_internal_token') then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'hex'),
      'push_internal_token',
      'يثبت أن طلب الإشعار صادر عن قاعدة البيانات نفسها — تتحقّق منه دالة send-push');
  end if;
end $$;

create or replace function public.push_internal_auth(p_token text)
returns boolean language sql stable security definer
set search_path = public, vault, pg_temp as $fn$
  select exists (
    select 1 from vault.decrypted_secrets s
     where s.name = 'push_internal_token'
       and p_token is not null
       and length(p_token) >= 32
       and s.decrypted_secret = p_token);
$fn$;
revoke execute on function public.push_internal_auth(text) from public, anon, authenticated;
grant  execute on function public.push_internal_auth(text) to service_role;


-- ── 2 · what kind of event a send belongs to ───────────────────────────────
alter table public.push_log add column if not exists event text;
create index if not exists push_log_sent_at_idx on public.push_log(sent_at desc);
create index if not exists push_log_event_idx   on public.push_log(event);


-- ── 3 · the receipts ───────────────────────────────────────────────────────
-- `push_log` says the municipality sent something. This says whether the phone
-- got it and whether the person looked at it.
create table if not exists public.push_receipts (
  id            uuid primary key default gen_random_uuid(),
  log_id        uuid not null references public.push_log(id) on delete cascade,
  endpoint      text not null,
  user_phone    text,          -- snapshot: the device can be re-labelled later
  user_name     text,
  user_role     text,
  sent_ok       boolean not null default false,
  error         text,
  sent_at       timestamptz not null default now(),
  delivered_at  timestamptz,   -- the service worker's `push` event
  opened_at     timestamptz,   -- the service worker's `notificationclick`
  unique (log_id, endpoint)
);

create index if not exists push_receipts_log_idx   on public.push_receipts(log_id);
create index if not exists push_receipts_phone_idx on public.push_receipts(user_phone);

alter table public.push_receipts enable row level security;

-- Reading is supervision, and it carries phone numbers: same key as the log.
drop policy if exists push_receipts_read on public.push_receipts;
create policy push_receipts_read on public.push_receipts
  for select to authenticated
  using (public.has_perm('push_log_view'));

-- No INSERT / UPDATE / DELETE policy at all: the edge function writes rows with
-- the service key, and a device stamps its own row through the function below.


-- ── the device reports back ────────────────────────────────────────────────
-- Keyed on the endpoint, which is the device's own long unguessable URL —
-- exactly the proof `push_device_update` (30) already relies on. It can only
-- ever move a null timestamp to now(), on a row that already exists, so a
-- replayed call cannot rewrite history or invent a receipt.
create or replace function public.push_receipt_mark(
  p_log_id uuid, p_endpoint text, p_event text)
returns boolean language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare n integer;
begin
  if p_log_id is null or coalesce(btrim(p_endpoint),'') = '' then return false; end if;
  if p_event not in ('delivered','opened') then return false; end if;

  update public.push_receipts r
     set delivered_at = case
           when p_event in ('delivered','opened') then coalesce(r.delivered_at, now())
           else r.delivered_at end,
         opened_at = case
           when p_event = 'opened' then coalesce(r.opened_at, now())
           else r.opened_at end
   where r.log_id = p_log_id and r.endpoint = p_endpoint;

  get diagnostics n = row_count;
  return n > 0;
exception when others then
  raise warning 'push_receipt_mark: %', sqlerrm;
  return false;
end;
$fn$;
grant execute on function public.push_receipt_mark(uuid,text,text) to anon, authenticated;


-- ── 4 · the one entry point ────────────────────────────────────────────────
-- Every trigger in this file calls this and nothing else. It refuses a send
-- with no audience — a bug that silently addressed *everybody* would be the
-- worst possible failure here.
create or replace function public.push_notify(
  p_event   text,
  p_title   text,
  p_body    text,
  p_url     text default null,
  p_phone   text default null,
  p_role    text default null,
  p_topics  text[] default null,
  p_sent_by text default 'system')
returns void language plpgsql security definer
set search_path = public, vault, pg_temp as $fn$
declare
  v_token text;
  v_phone text := nullif(btrim(coalesce(p_phone,'')), '');
begin
  if v_phone is null and p_role is null and (p_topics is null or array_length(p_topics,1) is null) then
    raise warning 'push_notify(%): no audience — refused', p_event;
    return;
  end if;
  if coalesce(btrim(coalesce(p_title,'')),'') = '' then return; end if;

  select decrypted_secret into v_token
    from vault.decrypted_secrets where name = 'push_internal_token';
  if v_token is null then
    raise warning 'push_notify(%): no internal token in the vault', p_event;
    return;
  end if;

  perform net.http_post(
    url     := 'https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/send-push',
    body    := jsonb_strip_nulls(jsonb_build_object(
                 'mun_id',       '00000000-0000-0000-0000-000000000001',
                 'title',        p_title,
                 'body',         p_body,
                 'url',          p_url,
                 'event',        p_event,
                 'to_user_phone', v_phone,
                 'to_role',      p_role,
                 'topics',       to_jsonb(p_topics),
                 'sent_by',      p_sent_by)),
    params  := '{}'::jsonb,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-wadi-push-token', v_token),
    timeout_milliseconds := 8000);
exception when others then
  -- a notification that cannot be queued must never break the thing it reports
  raise warning 'push_notify(%) failed: %', p_event, sqlerrm;
end;
$fn$;
revoke execute on function public.push_notify(text,text,text,text,text,text,text[],text) from public, anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 5 · the senders
-- ═══════════════════════════════════════════════════════════════════════════
-- Every one of them fires only on a real transition — `old.status` distinct
-- from `new.status` — so re-saving a row does not notify anybody twice, and
-- every one of them swallows its own errors.

-- ── the directory: a new entry decided ─────────────────────────────────────
create or replace function public.push_tg_phonebook_entry()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_who   text := coalesce(nullif(btrim(coalesce(new.name,'')),''),
                           btrim(coalesce(new.first,'')||' '||coalesce(new.family,'')),
                           'الجهة');
  v_phone text := coalesce(nullif(btrim(coalesce(new.submitter_phone,'')),''), new.phone);
begin
  if tg_op = 'UPDATE' and coalesce(old.status,'') is distinct from coalesce(new.status,'') then
    if new.status = 'approved' then
      perform public.push_notify('phonebook_new_approved',
        '✅ تمت الموافقة على الإضافة',
        v_who || ' أصبحت الآن في دليل بلدية وادي الست.',
        'phonebook.html#contact=' || new.id::text, v_phone);
    elsif new.status in ('rejected','declined') then
      perform public.push_notify('phonebook_new_rejected',
        'لم تتم الموافقة على الإضافة',
        'طلب إضافة ' || v_who || ' إلى الدليل لم يُعتمد. يمكنك مراجعة البلدية.',
        'phonebook.html', v_phone);
    end if;
  end if;
  return new;
exception when others then
  raise warning 'push_tg_phonebook_entry: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists push_phonebook_entry_tg on public.phonebook_entries;
create trigger push_phonebook_entry_tg
  after update of status on public.phonebook_entries
  for each row execute function public.push_tg_phonebook_entry();


-- ── the directory: a proposed edit decided ─────────────────────────────────
create or replace function public.push_tg_phonebook_edit()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_name  text;
  v_who   text;
  v_link  text;
  v_phone text := nullif(btrim(coalesce(new.submitter_phone,'')), '');
  v_what  text;
begin
  if tg_op <> 'UPDATE' or coalesce(old.status,'') is not distinct from coalesce(new.status,'') then
    return new;
  end if;
  if v_phone is null then return new; end if;

  select person_name, person_link into v_name, v_link
    from public.approval_pb_person(new.target_type, new.ref_id, new.target_entry_id);
  v_who := coalesce(nullif(btrim(coalesce(v_name,'')),''), 'جهة في الدليل');

  select string_agg(public.approval_field_label(k), '، ' order by k)
    into v_what
    from jsonb_object_keys(coalesce(new.proposed,'{}'::jsonb)) k;

  if new.status in ('approved','applied') then
    perform public.push_notify('phonebook_edit_approved',
      '✅ طُبِّق التعديل الذي اقترحته',
      'تعديل ' || v_who || coalesce(' — ' || v_what, '') || ' صار في الدليل.',
      coalesce(v_link, 'phonebook.html'), v_phone);
  elsif new.status in ('rejected','declined') then
    perform public.push_notify('phonebook_edit_rejected',
      'لم يُعتمد التعديل الذي اقترحته',
      'التعديل المقترح على ' || v_who || coalesce(' — ' || v_what, '')
        || coalesce(' · ' || nullif(btrim(coalesce(new.resolution_note,'')),''), '') || '.',
      'phonebook.html', v_phone);
  end if;
  return new;
exception when others then
  raise warning 'push_tg_phonebook_edit: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists push_phonebook_edit_tg on public.phonebook_pending_edits;
create trigger push_phonebook_edit_tg
  after update of status on public.phonebook_pending_edits
  for each row execute function public.push_tg_phonebook_edit();


-- ── the cooperative: a seller decided ──────────────────────────────────────
create or replace function public.push_tg_coop_seller()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_who text := coalesce(new.display_name, new.username, 'حسابك');
begin
  if tg_op = 'UPDATE' and coalesce(old.status,'') is distinct from coalesce(new.status,'') then
    if new.status = 'approved' then
      perform public.push_notify('coop_seller_approved',
        '✅ تمت الموافقة على حسابك كبائع',
        v_who || ' — يمكنك الآن الدخول إلى تعاونية وادي الست وعرض منتجاتك.',
        'coop.html', new.phone);
    elsif new.status in ('rejected','declined','suspended') then
      perform public.push_notify('coop_seller_rejected',
        case when new.status = 'suspended' then '⛔ أُوقف حسابك كبائع'
             else 'لم تتم الموافقة على حسابك كبائع' end,
        v_who || ' — للمراجعة يرجى الاتصال ببلدية وادي الست.',
        'coop.html', new.phone);
    end if;
  end if;
  return new;
exception when others then
  raise warning 'push_tg_coop_seller: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists push_coop_seller_tg on public.coop_sellers;
create trigger push_coop_seller_tg
  after update of status on public.coop_sellers
  for each row execute function public.push_tg_coop_seller();


-- ── the cooperative: a delivery agent decided ──────────────────────────────
create or replace function public.push_tg_coop_agent()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_who text := coalesce(new.name, 'حسابك');
begin
  if tg_op = 'UPDATE' and coalesce(old.status,'') is distinct from coalesce(new.status,'') then
    if new.status = 'approved' then
      perform public.push_notify('coop_agent_approved',
        '✅ تمت الموافقة على حسابك كعامل توصيل',
        v_who || ' — يمكنك الآن استلام الطلبات من تعاونية وادي الست.',
        'coop.html', new.phone);
    elsif new.status in ('rejected','declined','suspended') then
      perform public.push_notify('coop_agent_rejected',
        case when new.status = 'suspended' then '⛔ أُوقف حسابك كعامل توصيل'
             else 'لم تتم الموافقة على حسابك كعامل توصيل' end,
        v_who || ' — للمراجعة يرجى الاتصال ببلدية وادي الست.',
        'coop.html', new.phone);
    end if;
  end if;
  return new;
exception when others then
  raise warning 'push_tg_coop_agent: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists push_coop_agent_tg on public.coop_delivery_agents;
create trigger push_coop_agent_tg
  after update of status on public.coop_delivery_agents
  for each row execute function public.push_tg_coop_agent();


-- ── the cooperative: the buyer's own order ─────────────────────────────────
-- The buyer has no account, so the phone on the order is the only address
-- there is; `push_notify` matches it on phone_norm, which is why an order
-- taken as 03… still reaches a device registered as +9613….
create or replace function public.push_tg_coop_order()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_phone text := coalesce(nullif(btrim(coalesce(new.customer_phone,'')),''), new.buyer_phone);
  v_ref   text := '#' || upper(right(new.id::text, 6));
  v_title text; v_body text; v_event text;
begin
  if v_phone is null then return new; end if;

  if tg_op = 'UPDATE' and coalesce(old.status,'') is distinct from coalesce(new.status,'') then
    case new.status
      when 'confirmed' then
        v_event := 'coop_order_confirmed';
        v_title := '✅ تم تأكيد طلبك ' || v_ref;
        v_body  := 'وافق البائع على طلبك ويجري تحضيره الآن.';
      when 'delivered' then
        v_event := 'coop_order_delivered';
        v_title := '📦 تم تسليم طلبك ' || v_ref;
        v_body  := 'شكراً لك — نأمل أن تكون الخدمة نالت رضاك.';
      when 'cancelled' then
        v_event := 'coop_order_cancelled';
        v_title := '❌ أُلغي طلبك ' || v_ref;
        v_body  := coalesce(nullif(btrim(coalesce(new.cancellation_reason,'')),''),
                            'للاستفسار يرجى الاتصال بالتعاونية.');
      else v_event := null;
    end case;

    if v_event is not null then
      perform public.push_notify(v_event, v_title, v_body, 'coop.html', v_phone);
      return new;
    end if;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.delivery_status,'') is distinct from coalesce(new.delivery_status,'') then
    case new.delivery_status
      when 'assigned' then
        v_event := 'coop_delivery_assigned';
        v_title := '🛵 طلبك ' || v_ref || ' في طريقه إليك';
        v_body  := 'استلم أحد عمّال التوصيل طلبك.';
      when 'picked_up' then
        v_event := 'coop_delivery_picked_up';
        v_title := '🛵 خرج طلبك ' || v_ref || ' للتوصيل';
        v_body  := 'عامل التوصيل في الطريق إليك الآن.';
      when 'delivered' then
        v_event := 'coop_delivery_delivered';
        v_title := '📦 تم تسليم طلبك ' || v_ref;
        v_body  := 'شكراً لك — نأمل أن تكون الخدمة نالت رضاك.';
      else v_event := null;
    end case;

    if v_event is not null then
      perform public.push_notify(v_event, v_title, v_body, 'coop.html', v_phone);
    end if;
  end if;

  return new;
exception when others then
  raise warning 'push_tg_coop_order: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists push_coop_order_tg on public.coop_orders;
create trigger push_coop_order_tg
  after update on public.coop_orders
  for each row execute function public.push_tg_coop_order();


-- ═══════════════════════════════════════════════════════════════════════════
-- 6 · the irrigation reminders
-- ═══════════════════════════════════════════════════════════════════════════
-- Nothing changes in a table when somebody's turn approaches, so there is no
-- trigger to hang these on. The cycle is recomputed here exactly the way
-- water-admin.html draws it: subscribers in `sort_order`, each holding `hours`,
-- one cycle being the sum of them all, starting at `cycle_start_date` +
-- `day_start`, alternating day / night. Beirut time, because the schedule the
-- farmers read is on a wall in Beirut.

create table if not exists public.irr_push_sent (
  owner_id   text not null,
  cycle_num  integer not null,
  kind       text not null,          -- tomorrow | morning | one_hour | end
  sent_at    timestamptz not null default now(),
  primary key (owner_id, cycle_num, kind)
);
alter table public.irr_push_sent enable row level security;
drop policy if exists irr_push_sent_read on public.irr_push_sent;
create policy irr_push_sent_read on public.irr_push_sent
  for select to authenticated using (public.has_perm('push_log_view'));

-- every subscriber's window for one cycle number
create or replace function public.irr_windows(p_cycle integer)
returns table (owner_id text, owner_name text, phone text, land text,
               hours numeric, cycle_num integer, is_day boolean,
               starts_at timestamptz, ends_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp as $fn$
  with cfg as (
    select coalesce(nullif(btrim(cycle_start_date),''), '2026-01-01')::date as d0,
           coalesce(nullif(btrim(day_start),''), '06:00')::time            as t0,
           coalesce(total_hours, 168)                                      as total_hours
      from public.irr_config limit 1),
  own as (
    select o.id, o.name, o.phone, o.land_name, coalesce(o.hours,0) as hours,
           row_number() over (order by coalesce(o.sort_order, 0), o.id) as rn
      from public.irr_owners o
     where coalesce(o.hours,0) > 0),
  tot as (
    select case when coalesce(sum(hours),0) > 0
                then (sum(hours) * interval '1 hour')
                else ((select total_hours from cfg) * interval '1 hour') end as cycle_len
      from own),
  base as (
    select ((select d0 from cfg) + (select t0 from cfg)) at time zone 'Asia/Beirut' as t_zero)
  select o.id, o.name, o.phone, o.land_name, o.hours,
         p_cycle,
         (p_cycle % 2) = 0,
         (select t_zero from base)
           + (p_cycle * (select cycle_len from tot))
           + (coalesce((select sum(p.hours) from own p where p.rn < o.rn), 0) * interval '1 hour'),
         (select t_zero from base)
           + (p_cycle * (select cycle_len from tot))
           + (coalesce((select sum(p.hours) from own p where p.rn < o.rn), 0) * interval '1 hour')
           + (o.hours * interval '1 hour')
    from own o;
$fn$;

-- which cycle number is running right now (0-based, like the page)
create or replace function public.irr_current_cycle()
returns integer language sql stable security definer
set search_path = public, pg_temp as $fn$
  with cfg as (
    select coalesce(nullif(btrim(cycle_start_date),''), '2026-01-01')::date as d0,
           coalesce(nullif(btrim(day_start),''), '06:00')::time            as t0,
           coalesce(total_hours, 168)                                      as total_hours
      from public.irr_config limit 1),
  tot as (
    select case when coalesce(sum(coalesce(hours,0)),0) > 0
                then extract(epoch from (sum(coalesce(hours,0)) * interval '1 hour'))
                else extract(epoch from ((select total_hours from cfg) * interval '1 hour')) end as len
      from public.irr_owners where coalesce(hours,0) > 0)
  select greatest(0, floor(
           extract(epoch from (now() - (((select d0 from cfg) + (select t0 from cfg)) at time zone 'Asia/Beirut')))
           / nullif((select len from tot), 0)
         )::integer);
$fn$;

-- is this reminder switched on? (the page's own defaults when unset)
create or replace function public.irr_kind_enabled(p_kind text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(
    (select (c.notif_settings -> 'notifications' -> p_kind ->> 'enabled')::boolean
       from public.irr_config c limit 1),
    p_kind <> 'end');   -- tomorrow / morning / one_hour on, end off — as the screen ships
$fn$;

-- the sweep: run often, send once
create or replace function public.irr_push_sweep()
returns integer language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  rec   record;
  v_c   integer := public.irr_current_cycle();
  n     integer := 0;
  v_kind text;
  v_title text; v_body text;
  v_local timestamptz := now();
begin
  for rec in
    select * from public.irr_windows(v_c)
    union all
    select * from public.irr_windows(v_c + 1)
  loop
    if coalesce(btrim(coalesce(rec.phone,'')),'') = '' then continue; end if;

    v_kind := case
      when rec.starts_at - v_local between interval '20 hours' and interval '24 hours' then 'tomorrow'
      when rec.starts_at - v_local between interval '45 minutes' and interval '75 minutes' then 'one_hour'
      when (rec.starts_at at time zone 'Asia/Beirut')::date = (v_local at time zone 'Asia/Beirut')::date
           and rec.starts_at > v_local
           and (v_local at time zone 'Asia/Beirut')::time between time '07:00' and time '09:00' then 'morning'
      when v_local - rec.ends_at between interval '0 minutes' and interval '30 minutes' then 'end'
      else null end;

    if v_kind is null or not public.irr_kind_enabled(v_kind) then continue; end if;

    -- the ledger is the lock: if the row is already there, this reminder went out
    begin
      insert into public.irr_push_sent(owner_id, cycle_num, kind)
      values (rec.owner_id, rec.cycle_num, v_kind);
    exception when unique_violation then
      continue;
    end;

    select
      case v_kind
        when 'tomorrow' then '🌙 دور الري غداً'
        when 'morning'  then '🌅 دور الري اليوم'
        when 'one_hour' then '⏰ الري يبدأ بعد ساعة'
        else '🏁 انتهى دور الري' end,
      case v_kind
        when 'end' then 'انتهى دورك من '
             || to_char(rec.starts_at at time zone 'Asia/Beirut', 'HH24:MI')
             || ' حتى ' || to_char(rec.ends_at at time zone 'Asia/Beirut', 'HH24:MI')
             || '. شكراً للالتزام.'
        else coalesce(rec.owner_name || '، ', '')
             || 'دورك ' || to_char(rec.starts_at at time zone 'Asia/Beirut', 'YYYY-MM-DD')
             || ' من ' || to_char(rec.starts_at at time zone 'Asia/Beirut', 'HH24:MI')
             || ' حتى ' || to_char(rec.ends_at at time zone 'Asia/Beirut', 'HH24:MI')
             || ' (' || trim(to_char(rec.hours, 'FM999990.9')) || ' ساعة) — '
             || case when rec.is_day then '☀️ الدورة النهارية' else '🌙 الدورة الليلية' end
             || coalesce(' · ' || nullif(btrim(coalesce(rec.land,'')),''), '') end
      into v_title, v_body;

    perform public.push_notify('irrigation_' || v_kind, v_title, v_body,
                               'water.html', rec.phone, null, null, 'irrigation');
    n := n + 1;
  end loop;
  return n;
exception when others then
  raise warning 'irr_push_sweep: %', sqlerrm;
  return n;
end;
$fn$;
revoke execute on function public.irr_push_sweep() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'irrigation-push-sweep') then
    perform cron.unschedule('irrigation-push-sweep');
  end if;
  perform cron.schedule('irrigation-push-sweep', '*/15 * * * *',
                        $c$select public.irr_push_sweep()$c$);
end $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 7 · the permission: push_log_view
-- ═══════════════════════════════════════════════════════════════════════════
-- 📬 سجل الإشعارات shows every message the portal has sent, to whom, and
-- whether the phone received and opened it. That is message bodies and
-- residents' phone numbers, so it is not `push_send` — sending and reading
-- who read what are different powers, and this one is grantable on its own.
update public.role_permissions
   set perms = perms || '{"push_log_view":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');

update public.role_permissions
   set perms = perms || '{"push_log_view":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');

-- the log itself follows the same key (it was on push_send before)
drop policy if exists push_log_read_staff on public.push_log;
create policy push_log_read_staff on public.push_log
  for select to authenticated
  using (public.has_perm('push_log_view') or public.has_perm('push_send'));


-- ═══════════════════════════════════════════════════════════════════════════
-- What now sends a push, after this migration
-- ═══════════════════════════════════════════════════════════════════════════
--   المعاملات      cases                    → المواطن   (notify-i18n, unchanged)
--   الدليل         phonebook_entries        → مُقدّم الطلب
--   الدليل         phonebook_pending_edits  → مُقترح التعديل
--   التعاونية      coop_sellers             → البائع
--   التعاونية      coop_delivery_agents     → عامل التوصيل
--   التعاونية      coop_orders              → المشتري (الحالة والتوصيل)
--   الري           irr_push_sweep (pg_cron) → صاحب الدور
--
-- and every one of them lands in push_log with its `event`, with one
-- push_receipts row per device, which the service worker then stamps
-- delivered and opened.
