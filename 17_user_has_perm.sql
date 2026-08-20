-- ═══════════════════════════════════════════════════════════════════════════
-- 17 — let the edge functions ask the same permission question as everyone else
--
-- `admin-user` authorised on a row in `employees` with role 'manager'. That is
-- a different system from the one the pages and the row-level policies use, and
-- the two had drifted apart:
--
--   mmerhej@hotmail.com   role admin
--                         users_create / users_edit / users_delete → true
--                         employees manager row → none
--                         → shown user management, refused by the server
--                           with "Managers only"
--
-- One account in the whole municipality — the owner's — had a manager row, so
-- only the owner could ever create or delete a user, whatever the user screen
-- said.
--
-- has_perm() answers for whoever is calling; an edge function runs with the
-- service key and needs to ask *about* its caller. Same resolution, explicit
-- user: per-user override → role default → super_admin → false.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.user_has_perm(p_user uuid, p_perm text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce(
    (select (up.perms ->> p_perm)::boolean
       from public.user_permissions up
      where up.user_id = p_user and up.perms ? p_perm),
    (select bool_or((rp.perms ->> p_perm)::boolean)
       from public.user_roles ur
       join public.role_permissions rp on rp.role = ur.role
      where ur.user_id = p_user and rp.perms ? p_perm),
    (select exists (select 1 from public.user_roles ur
                     where ur.user_id = p_user and ur.role = 'super_admin')),
    false);
$fn$;

-- Only the service role asks this. From a browser, has_perm() is the way in —
-- nobody should be able to ask about another user.
revoke execute on function public.user_has_perm(uuid,text) from anon, authenticated;
grant  execute on function public.user_has_perm(uuid,text) to service_role;

-- Effect, measured before and after:
--
--   account                 users_create   manager row   before   after
--   imadaehn (super_admin)  true           yes           allowed  allowed
--   mmerhej  (admin)        true           no            REFUSED  allowed
--   darghamf (mayor)        false          no            refused  refused
--   eliac    (sandouk)      false          no            refused  refused
--   finance                 false          no            refused  refused
--   m.merhej (water_only)   false          no            refused  refused
--
-- One account gains what the user screen already promised it. Nobody else
-- gains anything.
