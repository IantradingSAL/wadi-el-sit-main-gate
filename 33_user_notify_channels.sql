-- ═══════════════════════════════════════════════════════════════════════════
-- 33 — من يملك قرار التحقق يختار كيف يصله الخبر، حدثاً حدثاً
--
-- Granting somebody `approvals_manage` from the user screen gave them the
-- decision but not the news: the notification e-mail still went only to the
-- fixed `settings.approval_notify` list plus the super admins, and no push
-- notification went to any reviewer at all. The toggles that LOOKED like they
-- did this — 📧/💬 in the old 🔐 تخصيص panel — wrote `user_metadata` that
-- nothing ever read.
--
-- The rule this migration implements, in one line:
--
--     the PERMISSION decides WHO is told · the PREFERENCE decides HOW
--
-- One row per person in `user_notify_prefs`; `channels` is a jsonb keyed by
-- the event — the same `kind` values `approval_requests` already carries, so
-- the queue itself is the central registry of events:
--
--     {"phonebook_edit": {"email": true, "push": true, "whatsapp": false},
--      "phonebook_new":  {"email": true, "push": true, "whatsapp": false}}
--
-- That is how "Paul validates the phonebook" stays separate from "Paul is
-- woken for every coop seller": each event carries its own three switches.
--
--   · email    → joins approval_recipients(kind), so the notify-approval
--                e-mail for that event reaches them
--   · push     → approval_enqueue() also pushes to their device, matched on
--                `phone` the way every other push in this portal is
--   · whatsapp → STORED ONLY. WhatsApp is not connected yet; the choice is
--                kept so connecting it later activates everyone who already
--                opted in, without a second round of setup.
--
-- A channel is only ever a channel: it never grants the decision. E-mail and
-- push reach a person only while user_has_perm(user, 'approvals_manage') says
-- they hold the key — losing the permission silences every channel with it,
-- with nothing to clean up.
--
-- Per the standing rule, setting these channels is its own permission —
-- `notify_prefs_edit` — with role defaults, a row on the user screen, and this
-- table's own policies asking the database the same question as the page.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 1 · the channels, one row per person ────────────────────────────────────
create table if not exists public.user_notify_prefs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  phone      text,                          -- +961… — the number the person's device is
                                            -- registered under (push_subscriptions.phone_norm),
                                            -- and the WhatsApp address the day it exists
  channels   jsonb not null default '{}'::jsonb,   -- {event: {email,push,whatsapp}}
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table public.user_notify_prefs enable row level security;

-- A person may see their own channels; changing anyone's takes the key.
drop policy if exists user_notify_prefs_read on public.user_notify_prefs;
create policy user_notify_prefs_read on public.user_notify_prefs
  for select to authenticated
  using (public.has_perm('notify_prefs_edit') or user_id = auth.uid());

drop policy if exists user_notify_prefs_insert on public.user_notify_prefs;
create policy user_notify_prefs_insert on public.user_notify_prefs
  for insert to authenticated
  with check (public.has_perm('notify_prefs_edit'));

drop policy if exists user_notify_prefs_update on public.user_notify_prefs;
create policy user_notify_prefs_update on public.user_notify_prefs
  for update to authenticated
  using (public.has_perm('notify_prefs_edit'))
  with check (public.has_perm('notify_prefs_edit'));

drop policy if exists user_notify_prefs_delete on public.user_notify_prefs;
create policy user_notify_prefs_delete on public.user_notify_prefs
  for delete to authenticated
  using (public.has_perm('notify_prefs_edit'));


-- ── 2 · the permission ───────────────────────────────────────────────────────
-- Deciding which channels reach an employee is user administration, not a
-- reuse of `users_edit`: super admin, رئيس البلدية and المدير by default,
-- grantable to one person from the user screen like every other key.
update public.role_permissions
   set perms = perms || '{"notify_prefs_edit":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"notify_prefs_edit":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');


-- ── 3 · who the e-mail reaches, per event ────────────────────────────────────
-- Same list as before — the settings row and the super admins — plus everyone
-- who holds `approvals_manage` and switched 📧 on for THIS event. A super
-- admin who explicitly switched an event's 📧 OFF is respected; one with no
-- row (or no entry for the event) keeps today's behaviour.
--
-- The zero-argument version from 27 is replaced by one that takes the kind;
-- called with null (or by anything not yet passing it) it answers exactly as
-- the old one did.
drop function if exists public.approval_recipients();
create or replace function public.approval_recipients(p_kind text default null)
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
      left join public.user_notify_prefs np on np.user_id = u.id
     where r.role = 'super_admin' and u.email is not null
       and coalesce((np.channels -> p_kind ->> 'email')::boolean, true)
    union
    select u.email
      from public.user_notify_prefs np
      join auth.users u on u.id = np.user_id
     where p_kind is not null and u.email is not null
       and coalesce((np.channels -> p_kind ->> 'email')::boolean, false)
       and public.user_has_perm(np.user_id, 'approvals_manage')
  ) t
  where e is not null and e <> '';
$fn$;

-- unchanged: only the notifier (service role) asks this
revoke execute on function public.approval_recipients(text) from public, anon, authenticated;
grant  execute on function public.approval_recipients(text) to service_role;


-- ── 4 · who the push reaches, per event ──────────────────────────────────────
-- Phones of everyone who holds the decision AND switched 🔔 on for this event
-- AND told us which number their device is linked under. Permission first: a
-- stale row belonging to somebody who lost `approvals_manage` selects nothing.
create or replace function public.approval_push_targets(p_kind text)
returns text[] language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(array_agg(distinct btrim(np.phone)), array[]::text[])
    from public.user_notify_prefs np
   where p_kind is not null
     and coalesce((np.channels -> p_kind ->> 'push')::boolean, false)
     and coalesce(btrim(np.phone), '') <> ''
     and public.user_has_perm(np.user_id, 'approvals_manage');
$fn$;
revoke execute on function public.approval_push_targets(text) from public, anon, authenticated;

-- One push per reviewer when a request enters the queue. Fired once, from
-- approval_enqueue — deliberately NOT from the retry sweep, which exists for
-- the e-mail's notified_at and would ring the same phones every quarter hour
-- for a request nobody has decided yet.
create or replace function public.approval_push_notify(p_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  r       public.approval_requests%rowtype;
  v_phone text;
  v_label text;
begin
  select * into r from public.approval_requests where id = p_id;
  if not found or r.status <> 'pending' then return; end if;

  v_label := case r.kind
    when 'coop_seller'    then '🛒 بائع جديد في التعاونية'
    when 'coop_agent'     then '🚚 عامل توصيل جديد'
    when 'phonebook_new'  then '📇 جهة جديدة في دليل البلدية'
    when 'phonebook_edit' then '✏️ تعديل مقترح على الدليل'
    when 'user_account'   then '👤 حساب جديد على البوابة'
    else '🔔 طلب ينتظر التحقق' end;

  foreach v_phone in array public.approval_push_targets(r.kind) loop
    perform public.push_notify(
      'approval_pending', v_label,
      r.title || ' — بانتظار قراركم.',
      'dashboard.html#approval=' || r.id::text,
      v_phone);
  end loop;
exception when others then
  -- a notification that cannot go out must never break the thing it reports
  raise warning 'approval_push_notify(%) failed: %', p_id, sqlerrm;
end;
$fn$;
revoke execute on function public.approval_push_notify(uuid) from public, anon, authenticated;


-- ── 5 · the queue tells both channels ────────────────────────────────────────
-- Same function as 27, one line added: after handing the e-mail to pg_net, the
-- push goes to the reviewers who asked for it. The same p_notify flag guards
-- both, so the silent backfill path stays silent.
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
  if p_notify then
    perform public.approval_notify(v_id);
    perform public.approval_push_notify(v_id);
  end if;
  return v_id;
exception when others then
  raise warning 'approval_enqueue(% %) failed: %', p_kind, p_ref_id, sqlerrm;
  return null;
end;
$fn$;
revoke execute on function public.approval_enqueue(text,text,text,text,jsonb,text,boolean)
  from public, anon, authenticated;
