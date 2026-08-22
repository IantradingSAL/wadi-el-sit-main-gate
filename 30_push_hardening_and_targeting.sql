-- ═══════════════════════════════════════════════════════════════════════════
-- 30 — إصلاحات تدقيق الإشعارات (AUDIT-2026-08-22-push.md)
--
-- The audit found the push channel closed at both ends: broadcasts refused by
-- the server, municipal alerts matching no device. The client half of the fix
-- is in pwa.js / sw.js / dashboard.html / admin-push.html / news-admin.html;
-- this file is the database half.
--
--   1. one normalised key for phone targeting (`phone_norm`), because the same
--      number has been stored as 03…, 3… and +9613… over the life of the table
--      and the sender compared strings exactly — a silent miss every time
--   2. push_device_register / push_device_update: the only way a device may
--      write its own row, keyed on the endpoint it possesses
--   3. the open UPDATE and DELETE policies are dropped. They carried
--      USING (true) for `anon`, and the anon key is printed in every page: any
--      visitor could deactivate — or delete — every subscription in the
--      village with one request. INSERT stays open so a browser still running
--      a cached copy of pwa.js can register a new device.
--   4. push_log stops being readable by every signed-in account (it carries
--      message bodies and the recipient's phone number)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the matching key: digits, without 961, without the trunk 0 ────────────
create or replace function public.lb_phone_norm(p text)
returns text language sql immutable
set search_path = public, pg_temp as $fn$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          translate(coalesce(p,''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'),
        '[^0-9]', '', 'g'),
      '^961', ''),
    '^0+', ''), '');
$fn$;

alter table public.push_subscriptions
  add column if not exists phone_norm text
  generated always as (
    nullif(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            translate(coalesce(user_phone,''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'),
          '[^0-9]', '', 'g'),
        '^961', ''),
      '^0+', ''), '')
  ) stored;

create index if not exists push_subs_phone_norm_idx on public.push_subscriptions(phone_norm);
create index if not exists push_subs_role_idx on public.push_subscriptions(user_role) where is_active;

-- ── the device registers itself, and the server normalises what it stores ──
create or replace function public.push_device_register(
  p_endpoint text, p_p256dh text, p_auth text,
  p_mun_id uuid default '00000000-0000-0000-0000-000000000001',
  p_topics text[] default array['general'],
  p_lang text default 'ar', p_user_phone text default null,
  p_user_name text default null, p_user_role text default null,
  p_user_agent text default null)
returns boolean language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(btrim(p_endpoint),'') = '' or coalesce(btrim(p_p256dh),'') = ''
     or coalesce(btrim(p_auth),'') = '' then
    return false;
  end if;

  insert into public.push_subscriptions
    (mun_id, endpoint, p256dh, auth, topics, lang, user_phone, user_name, user_role,
     user_agent, is_active, failed_count)
  values (p_mun_id, p_endpoint, p_p256dh, p_auth,
          coalesce(p_topics, array['general']), coalesce(p_lang,'ar'),
          nullif(btrim(coalesce(p_user_phone,'')),''),
          nullif(btrim(coalesce(p_user_name,'')),''),
          nullif(btrim(coalesce(p_user_role,'')),''),
          left(coalesce(p_user_agent,''), 200), true, 0)
  on conflict (endpoint) do update
    set p256dh     = excluded.p256dh,
        auth       = excluded.auth,
        topics     = excluded.topics,
        lang       = coalesce(excluded.lang, public.push_subscriptions.lang),
        -- an identity already on the row is never erased by a later anonymous
        -- re-subscribe; it is only ever added to or replaced by a real value
        user_phone = coalesce(excluded.user_phone, public.push_subscriptions.user_phone),
        user_name  = coalesce(excluded.user_name,  public.push_subscriptions.user_name),
        user_role  = coalesce(excluded.user_role,  public.push_subscriptions.user_role),
        user_agent = coalesce(excluded.user_agent, public.push_subscriptions.user_agent),
        is_active  = true,
        failed_count = 0;
  return true;
exception when others then
  raise warning 'push_device_register: %', sqlerrm;
  return false;
end;
$fn$;

-- ── and updates only the row whose endpoint it can name ───────────────────
-- The endpoint is the device's own long unguessable URL: knowing it is what
-- proves the caller is that device. Null arguments leave a field untouched, so
-- one function serves topics, language, identity, deactivation and last_used_at.
create or replace function public.push_device_update(
  p_endpoint text,
  p_topics text[] default null,
  p_lang text default null,
  p_user_phone text default null,
  p_user_name text default null,
  p_user_role text default null,
  p_is_active boolean default null,
  p_touch boolean default false)
returns boolean language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare n integer;
begin
  if coalesce(btrim(p_endpoint),'') = '' then return false; end if;

  update public.push_subscriptions s
     set topics       = coalesce(p_topics, s.topics),
         lang         = coalesce(p_lang, s.lang),
         user_phone   = coalesce(nullif(btrim(coalesce(p_user_phone,'')),''), s.user_phone),
         user_name    = coalesce(nullif(btrim(coalesce(p_user_name,'')),''),  s.user_name),
         user_role    = coalesce(nullif(btrim(coalesce(p_user_role,'')),''),  s.user_role),
         is_active    = coalesce(p_is_active, s.is_active),
         last_used_at = case when p_touch then now() else s.last_used_at end
   where s.endpoint = p_endpoint;
  get diagnostics n = row_count;
  return n > 0;
exception when others then
  raise warning 'push_device_update: %', sqlerrm;
  return false;
end;
$fn$;

grant execute on function public.push_device_register(text,text,text,uuid,text[],text,text,text,text,text) to anon, authenticated;
grant execute on function public.push_device_update(text,text[],text,text,text,text,boolean,boolean) to anon, authenticated;

-- ── close the open doors ──────────────────────────────────────────────────
drop policy if exists ps_device_update on public.push_subscriptions;
drop policy if exists ps_device_delete on public.push_subscriptions;

-- ── the log is municipal ──────────────────────────────────────────────────
drop policy if exists pl_select_authenticated on public.push_log;
drop policy if exists pl_insert_anyone on public.push_log;
drop policy if exists push_log_read_staff on public.push_log;
create policy push_log_read_staff on public.push_log
  for select to authenticated
  using (public.has_perm('push_send') or public.has_role(array['mayor','admin','officer']));

-- Measured on the live project after applying, using the published anon key:
--
--   PATCH  /push_subscriptions?is_active=eq.true   → 401 permission denied
--   DELETE /push_subscriptions?is_active=eq.true   → 401 permission denied
--   POST   /rpc/push_device_update {endpoint,touch}→ 200 true (that row only)
--   POST   /rpc/push_device_register {…}           → 200 true, stored with
--                                                    user_role='staff'
--   phone_norm('+961 3 649 694') matches the device stored as '03649694'
--   active subscriptions before and after: 10 — nothing was lost
--
-- The `role` column is left in place on purpose: a browser still serving a
-- cached pwa.js posts it on registration, and dropping it would make those
-- inserts fail. Nothing reads it. Remove it once the caches have rotated.
