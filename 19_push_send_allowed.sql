-- ═══════════════════════════════════════════════════════════════════════════
-- 19 — who may push a notification to the village
--
-- `send-push` runs with verify_jwt off — it has to, because a resident filing
-- a request calls it to tell the municipality, and that resident has no
-- session. It carried no authorisation of its own either.
--
-- So anyone who knew the URL could POST a title and a body and have it arrive
-- on every resident's phone, looking exactly like the municipality. `mun_id`
-- is in the page source; nothing else was needed.
--
-- The decision lives here rather than inside the function so it can be tested,
-- and so it answers the same way as every other permission on the platform.
--
--   inward   — telling the municipality something (to_role: a municipal role).
--              Anyone may: it is what the citizen page does when a request is
--              filed, and the worst it can do is bother the staff.
--   outward  — everyone, a topic, a non-municipal role, or one resident's
--              phone. Requires push_send.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.push_send_allowed(p_user uuid, p_scope text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $fn$
  select case
    when p_scope = 'inward' then true
    when p_user is null     then false
    else public.user_has_perm(p_user, 'push_send')
  end;
$fn$;

revoke execute on function public.push_send_allowed(uuid,text) from anon, authenticated;
grant  execute on function public.push_send_allowed(uuid,text) to service_role;

-- Measured after applying:
--
--   caller                                     scope     allowed
--   the anon key (what an attacker holds)      outward   false
--   the anon key                               inward    true
--   a resident filing a request                inward    true
--   sandouk clerk                              outward   false
--   water-only                                 outward   false
--   finance                                    outward   false
--   mayor                                      outward   true
--   admin                                      outward   true
--   super admin                                outward   true
