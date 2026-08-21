-- ═══════════════════════════════════════════════════════════════════════════
-- 27 — nothing waits for validation in silence any more
--
-- Four things in this portal need a human decision, and until now each one
-- waited to be *noticed*:
--
--   · a coop seller registers                → coop_sellers.status = 'pending'
--   · a delivery agent registers             → coop_delivery_agents.status = 'pending'
--   · someone adds or corrects a phonebook   → phonebook_entries.status = 'pending'
--     entry                                     phonebook_pending_edits
--   · someone opens an account               → auth.users
--
-- The coop pair did send an email, but from the browser: coop.html fired
-- notify-coop-registration and forgot about it, so a closed tab, a dropped
-- connection or a phone going to sleep lost the notification and nobody knew a
-- seller was waiting. The phonebook queues and new accounts sent nothing at
-- all — the super admin found them only by opening the screen.
--
-- So the notification stops being a favour the browser does. Every one of the
-- four writes a row into `approval_requests` from a DATABASE trigger, and the
-- trigger hands it to pg_net, which calls the notify-approval edge function
-- after the transaction commits. Closing the tab cannot lose it; a failed send
-- leaves notified_at null and the pg_cron sweep retries it for a week.
--
-- Reading and deciding is one permission — `approvals_manage` — and the same
-- key gates the screen and the table, as everything else in this project does.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the queue ──────────────────────────────────────────────────────────────
create table if not exists public.approval_requests (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in
                  ('coop_seller','coop_agent','phonebook_new','phonebook_edit','user_account')),
  ref_table     text not null,
  ref_id        text not null,
  title         text not null,
  summary       jsonb not null default '{}'::jsonb,   -- display-ready Arabic labels
  link          text,                                 -- where to go to review it
  requested_at  timestamptz not null default now(),
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  decided_by    uuid,
  decided_email text,
  decided_at    timestamptz,
  note          text,
  notified_at   timestamptz,
  notify_note   text,
  unique (kind, ref_id)                               -- one queue row per thing
);

create index if not exists approval_requests_pending_idx
  on public.approval_requests(requested_at desc) where status = 'pending';
create index if not exists approval_requests_kind_idx on public.approval_requests(kind, status);
create index if not exists approval_requests_notify_idx
  on public.approval_requests(requested_at) where status = 'pending' and notified_at is null;

alter table public.approval_requests enable row level security;

-- Reading the queue is the supervisory act; deciding goes through the RPC
-- below, which is security definer. Clients get no INSERT/UPDATE/DELETE at all,
-- so a queue row can only be created by the triggers that watch the real tables.
drop policy if exists approval_requests_read on public.approval_requests;
create policy approval_requests_read on public.approval_requests
  for select to authenticated
  using (public.has_perm('approvals_manage'));

-- ── who gets told ──────────────────────────────────────────────────────────
-- The addresses the coop notifier already used, plus every super_admin
-- automatically. The list is a settings row so it can be changed from the
-- screen without a deploy; the super admins are resolved live, so an account
-- that gains or loses the role is added or dropped with it.
insert into public.settings (key, value)
values ('approval_notify',
        '{"emails":["management@municipality-wadi-el-sitt.org","imadaehn@gmail.com"]}'::jsonb)
on conflict (key) do nothing;

create or replace function public.approval_recipients()
returns text[] language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(array_agg(distinct e), array[]::text[])
  from (
    select jsonb_array_elements_text(
             coalesce((select s.value->'emails' from public.settings s where s.key='approval_notify'),
                      '[]'::jsonb)) as e
    union
    select u.email
      from auth.users u
      join public.user_roles r on r.user_id = u.id
     where r.role = 'super_admin' and u.email is not null
  ) t
  where e is not null and e <> '';
$fn$;

-- Only the notifier (service role) asks this; it is a list of staff addresses.
revoke execute on function public.approval_recipients() from public, anon, authenticated;
grant  execute on function public.approval_recipients() to service_role;

-- ── the notification ───────────────────────────────────────────────────────
-- pg_net queues the POST and delivers it after commit, so a slow or failing
-- mail provider can never delay — let alone roll back — a registration.
create or replace function public.approval_notify(p_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  perform net.http_post(
    url     := 'https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/notify-approval',
    body    := jsonb_build_object('id', p_id),
    params  := '{}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 8000
  );
exception when others then
  -- a notification that cannot be queued must never break the thing being
  -- registered; the sweep below picks the row up again
  raise warning 'approval_notify(%) failed: %', p_id, sqlerrm;
end;
$fn$;
revoke execute on function public.approval_notify(uuid) from public, anon, authenticated;

create or replace function public.approval_enqueue(
  p_kind text, p_ref_table text, p_ref_id text,
  p_title text, p_summary jsonb, p_link text default null, p_notify boolean default true)
returns uuid language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_id uuid;
begin
  insert into public.approval_requests(kind, ref_table, ref_id, title, summary, link)
  values (p_kind, p_ref_table, p_ref_id,
          coalesce(nullif(btrim(p_title), ''), '—'),
          coalesce(p_summary, '{}'::jsonb), p_link)
  on conflict (kind, ref_id) do nothing
  returning id into v_id;

  if v_id is null then return null; end if;          -- already queued once
  if p_notify then perform public.approval_notify(v_id); end if;
  return v_id;
exception when others then
  raise warning 'approval_enqueue(% %) failed: %', p_kind, p_ref_id, sqlerrm;
  return null;
end;
$fn$;
revoke execute on function public.approval_enqueue(text,text,text,text,jsonb,text,boolean)
  from public, anon, authenticated;

-- ── the four watchers ──────────────────────────────────────────────────────
-- Every one of them swallows its own errors: a registration must succeed even
-- if the queue or the notifier is having a bad day.

create or replace function public.approval_tg_coop_seller()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'coop_seller', 'coop_sellers', new.id::text,
      coalesce(new.display_name, new.username, new.phone, 'بائع جديد'),
      jsonb_strip_nulls(jsonb_build_object(
        'اسم العرض', new.display_name, 'اسم المستخدم', new.username,
        'الهاتف', new.phone, 'واتساب', new.whatsapp,
        'المنطقة', new.area, 'النشاط', new.bio, 'البريد', new.email)),
      'coop.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_coop_seller: %', sqlerrm; return new;
end;
$fn$;

create or replace function public.approval_tg_coop_agent()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'coop_agent', 'coop_delivery_agents', new.id::text,
      coalesce(new.name, new.phone, 'عامل توصيل جديد'),
      jsonb_strip_nulls(jsonb_build_object(
        'الاسم', new.name, 'الهاتف', new.phone, 'واتساب', new.whatsapp,
        'المنطقة', new.area, 'وسيلة النقل', new.vehicle, 'ملاحظات', new.notes)),
      'coop.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_coop_agent: %', sqlerrm; return new;
end;
$fn$;

create or replace function public.approval_tg_phonebook_entry()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'phonebook_new', 'phonebook_entries', new.id::text,
      coalesce(new.name, btrim(coalesce(new.first,'')||' '||coalesce(new.family,'')), 'جهة جديدة'),
      jsonb_strip_nulls(jsonb_build_object(
        'الاسم', new.name, 'العائلة', new.family, 'الهاتف', new.phone,
        'المهنة', new.occupation, 'العنوان', new.address,
        'أضافها', new.submitter_name, 'هاتف المُضيف', new.submitter_phone,
        'المصدر', new.source)),
      'phonebook.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_phonebook_entry: %', sqlerrm; return new;
end;
$fn$;

create or replace function public.approval_tg_phonebook_edit()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_who text;
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    v_who := coalesce(new.submitter_name, 'زائر');
    perform public.approval_enqueue(
      'phonebook_edit', 'phonebook_pending_edits', new.id::text,
      'تعديل مقترح على جهة في الدليل — من ' || v_who,
      jsonb_strip_nulls(jsonb_build_object(
        'مقدّم الطلب', new.submitter_name, 'هاتفه', new.submitter_phone,
        'السبب', new.reason, 'نوع الهدف', new.target_type,
        'الحقول المقترَحة', (select string_agg(k, '، ') from jsonb_object_keys(new.proposed) k))),
      'phonebook.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_phonebook_edit: %', sqlerrm; return new;
end;
$fn$;

-- auth.users already carries handle_new_user(); this is a second, independent
-- trigger, equally exception-proof, so signing up can never fail because of it.
create or replace function public.approval_tg_new_user()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  perform public.approval_enqueue(
    'user_account', 'auth.users', new.id::text,
    coalesce(new.email, 'حساب جديد'),
    jsonb_strip_nulls(jsonb_build_object(
      'البريد', new.email,
      'الاسم', coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name'),
      'الهاتف', new.raw_user_meta_data->>'phone',
      'طريقة التسجيل', coalesce(new.raw_app_meta_data->>'provider', 'email'))),
    'dashboard.html');
  return new;
exception when others then
  raise warning 'approval_tg_new_user: %', sqlerrm; return new;
end;
$fn$;

drop trigger if exists approval_coop_seller_tg   on public.coop_sellers;
create trigger approval_coop_seller_tg   after insert or update of status on public.coop_sellers
  for each row execute function public.approval_tg_coop_seller();

drop trigger if exists approval_coop_agent_tg    on public.coop_delivery_agents;
create trigger approval_coop_agent_tg    after insert or update of status on public.coop_delivery_agents
  for each row execute function public.approval_tg_coop_agent();

drop trigger if exists approval_phonebook_new_tg on public.phonebook_entries;
create trigger approval_phonebook_new_tg after insert or update of status on public.phonebook_entries
  for each row execute function public.approval_tg_phonebook_entry();

drop trigger if exists approval_phonebook_edit_tg on public.phonebook_pending_edits;
create trigger approval_phonebook_edit_tg after insert or update of status on public.phonebook_pending_edits
  for each row execute function public.approval_tg_phonebook_edit();

drop trigger if exists approval_new_user_tg on auth.users;
create trigger approval_new_user_tg after insert on auth.users
  for each row execute function public.approval_tg_new_user();

-- ── applying a phonebook edit ──────────────────────────────────────────────
-- Same two branches phonebook.html used by hand: a registry proposal is
-- merged onto phonebook_extras (mun_id, ref_id), an entry proposal is written
-- onto the entry itself. The SET list is built only from columns that actually
-- exist on the target table, so a proposal cannot name anything else.
create or replace function public.approval_apply_phonebook_edit(p_edit_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  ed   public.phonebook_pending_edits%rowtype;
  sets text;
begin
  select * into ed from public.phonebook_pending_edits where id = p_edit_id;
  if not found then raise exception 'pending edit % not found', p_edit_id; end if;

  if ed.target_type = 'registry' then
    insert into public.phonebook_extras (mun_id, ref_id, status)
    values (ed.mun_id, ed.ref_id, 'approved')
    on conflict (mun_id, ref_id) do nothing;

    select string_agg(format('%I = ($1->>%L)::%s', c.column_name, c.column_name, c.udt_name), ', ')
      into sets
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'phonebook_extras'
       and ed.proposed ? c.column_name
       and c.column_name not in ('id','mun_id','ref_id','status','created_at','updated_at');
    if sets is not null then
      execute format('update public.phonebook_extras set %s, status=''approved'', updated_at=now()
                        where mun_id=$2 and ref_id=$3', sets)
        using ed.proposed, ed.mun_id, ed.ref_id;
    end if;
  else
    select string_agg(format('%I = ($1->>%L)::%s', c.column_name, c.column_name, c.udt_name), ', ')
      into sets
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'phonebook_entries'
       and ed.proposed ? c.column_name
       and c.column_name not in ('id','mun_id','status','created_at','updated_at','approved_at','approved_by');
    if sets is not null then
      execute format('update public.phonebook_entries set %s, updated_at=now() where id=$2', sets)
        using ed.proposed, ed.target_entry_id;
    end if;
  end if;
end;
$fn$;
revoke execute on function public.approval_apply_phonebook_edit(uuid) from public, anon, authenticated;

-- ── the decision ───────────────────────────────────────────────────────────
-- One call decides the queue row AND the thing it stands for, so the two can
-- never disagree. A new account is the exception: it already works the moment
-- it is created, so the decision records that a human looked at it.
create or replace function public.approval_decide(p_id uuid, p_decision text, p_note text default null)
returns public.approval_requests
language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare r public.approval_requests%rowtype; v_email text;
begin
  if not public.has_perm('approvals_manage') then
    raise exception 'لا تملك صلاحية إدارة طلبات التحقق';
  end if;
  if p_decision not in ('approved','rejected') then
    raise exception 'decision must be approved or rejected';
  end if;

  select * into r from public.approval_requests where id = p_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if r.status <> 'pending' then raise exception 'هذا الطلب مبتوت مسبقاً (%)' , r.status; end if;

  if r.kind = 'coop_seller' then
    update public.coop_sellers set status = p_decision where id = r.ref_id::uuid;

  elsif r.kind = 'coop_agent' then
    update public.coop_delivery_agents set status = p_decision, updated_at = now()
     where id = r.ref_id::uuid;

  elsif r.kind = 'phonebook_new' then
    update public.phonebook_entries
       set status      = p_decision,
           approved_at = case when p_decision='approved' then now() else approved_at end,
           approved_by = case when p_decision='approved' then auth.uid() else approved_by end,
           updated_at  = now()
     where id = r.ref_id::uuid;

  elsif r.kind = 'phonebook_edit' then
    if p_decision = 'approved' then
      perform public.approval_apply_phonebook_edit(r.ref_id::uuid);
    end if;
    update public.phonebook_pending_edits
       set status = p_decision, resolved_at = now(), resolved_by = auth.uid(),
           resolution_note = p_note
     where id = r.ref_id::uuid;

  elsif r.kind = 'user_account' then
    null;   -- nothing to switch: the account exists and works; this is the review
  end if;

  select u.email into v_email from auth.users u where u.id = auth.uid();
  update public.approval_requests
     set status = p_decision, decided_by = auth.uid(), decided_email = v_email,
         decided_at = now(), note = p_note
   where id = p_id
  returning * into r;
  return r;
end;
$fn$;
grant execute on function public.approval_decide(uuid,text,text) to authenticated;

-- ── the sweep ──────────────────────────────────────────────────────────────
-- A send that failed leaves notified_at null. Every fifteen minutes the
-- unnotified pending rows of the last week are handed to pg_net again; the
-- edge function is idempotent, so a row that did go out is never sent twice.
create or replace function public.approval_notify_sweep()
returns integer language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare n integer := 0; rec record;
begin
  for rec in
    select id from public.approval_requests
     where status = 'pending' and notified_at is null
       and requested_at > now() - interval '7 days'
     order by requested_at
     limit 50
  loop
    perform public.approval_notify(rec.id);
    n := n + 1;
  end loop;
  return n;
end;
$fn$;
revoke execute on function public.approval_notify_sweep() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('approval-notify-sweep');
exception when others then null;
end $$;
select cron.schedule('approval-notify-sweep', '*/15 * * * *',
                     $$select public.approval_notify_sweep()$$);

-- ── the permission ─────────────────────────────────────────────────────────
-- Deciding who becomes a seller, whose name enters the directory and which
-- account is legitimate is the municipality's own authority: super admin,
-- رئيس البلدية and المدير by default, and grantable to one person from the
-- user screen like every other key.
update public.role_permissions
   set perms = perms || '{"approvals_manage":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"approvals_manage":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');

-- ── the backlog that already exists ────────────────────────────────────────
-- Anything pending right now joins the queue so the screen opens on the truth,
-- but marked as already notified: turning this on must not fire a burst of
-- emails about registrations from weeks ago.
insert into public.approval_requests(kind, ref_table, ref_id, title, summary, link, notified_at, notify_note)
select 'coop_seller', 'coop_sellers', s.id::text,
       coalesce(s.display_name, s.username, s.phone, 'بائع'),
       jsonb_strip_nulls(jsonb_build_object('اسم العرض', s.display_name, 'الهاتف', s.phone, 'المنطقة', s.area)),
       'coop.html', now(), 'مُدرج عند التفعيل — بلا بريد'
  from public.coop_sellers s where coalesce(s.status,'pending') = 'pending'
on conflict (kind, ref_id) do nothing;

insert into public.approval_requests(kind, ref_table, ref_id, title, summary, link, notified_at, notify_note)
select 'coop_agent', 'coop_delivery_agents', a.id::text,
       coalesce(a.name, a.phone, 'عامل توصيل'),
       jsonb_strip_nulls(jsonb_build_object('الاسم', a.name, 'الهاتف', a.phone, 'المنطقة', a.area)),
       'coop.html', now(), 'مُدرج عند التفعيل — بلا بريد'
  from public.coop_delivery_agents a where coalesce(a.status,'pending') = 'pending'
on conflict (kind, ref_id) do nothing;

insert into public.approval_requests(kind, ref_table, ref_id, title, summary, link, notified_at, notify_note)
select 'phonebook_new', 'phonebook_entries', e.id::text,
       coalesce(e.name, 'جهة'),
       jsonb_strip_nulls(jsonb_build_object('الاسم', e.name, 'الهاتف', e.phone, 'أضافها', e.submitter_name)),
       'phonebook.html', now(), 'مُدرج عند التفعيل — بلا بريد'
  from public.phonebook_entries e where coalesce(e.status,'pending') = 'pending'
on conflict (kind, ref_id) do nothing;

insert into public.approval_requests(kind, ref_table, ref_id, title, summary, link, notified_at, notify_note)
select 'phonebook_edit', 'phonebook_pending_edits', p.id::text,
       'تعديل مقترح — من ' || coalesce(p.submitter_name,'زائر'),
       jsonb_strip_nulls(jsonb_build_object('مقدّم الطلب', p.submitter_name, 'السبب', p.reason)),
       'phonebook.html', now(), 'مُدرج عند التفعيل — بلا بريد'
  from public.phonebook_pending_edits p where coalesce(p.status,'pending') = 'pending'
on conflict (kind, ref_id) do nothing;

-- Existing accounts are NOT backfilled: every account that predates this
-- migration was already accepted by whoever created it, and a queue opening
-- with hundreds of historical accounts to "review" would be noise, not work.
