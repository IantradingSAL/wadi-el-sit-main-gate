-- ═══════════════════════════════════════════════════════════════════════════
-- 20_close_unused_rpc_surface.sql — applied to the live project on 2026-08-21
--
-- Every SECURITY DEFINER function in `public` that `anon` may execute is a
-- door on the internet, because the anon key is printed in the source of every
-- page. There were 46 of them. Twenty-seven are doors the application actually
-- knocks on. The rest were left open by accident.
--
-- Two of them mattered:
--
--   coop_agent_verify_pin(phone, pin)
--     A delivery agent's PIN is four digits, hashed with a bare SHA-256 and
--     compared. This function checked a guess and returned the agent's identity
--     when the guess was right. No session, no rate limit, no lockout — ten
--     thousand guesses is minutes of work, and two agents are still on 1234.
--     Nothing in the application calls it: coop.html signs agents in through
--     coop_agent_login, which mints a session token. It is a leftover from
--     before that design and is dropped.
--
--   user_has_perm(user, permission)
--     Answered, to anyone holding the public key, whether a given account holds
--     a given permission. Only the admin-user edge function needs it, and that
--     runs as the service role.
--
-- The others are trigger bodies, internal helpers, one superseded order
-- function, and two functions belonging to the other application that shares
-- this project. None of them is meant to be reachable over PostgREST.
--
-- DELIBERATELY NOT REVOKED: has_perm(), has_role(), current_user_role() and
-- is_coop_admin(). They read as obvious candidates and they are not. Several
-- policies are written `FOR ALL TO public`, so an anonymous SELECT on
-- news_articles evaluates a USING clause that calls has_role(). Revoke EXECUTE
-- from anon and that clause raises instead of returning false — the public news
-- list stops loading for everyone. They return false for anon; leave them.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── two functions nothing calls, one of them a PIN oracle ──────────────────
drop function if exists public.coop_agent_verify_pin(text, text);
drop function if exists public.coop_seller_login(text, text);
drop function if exists public.place_coop_order(text, text, text, text, text, text, text, jsonb);

-- ── server-side only: the edge functions reach these as the service role ───
revoke execute on function public.user_has_perm(uuid, text)     from anon, authenticated;
revoke execute on function public.push_send_allowed(uuid, text) from anon, authenticated;

-- ── an anonymous write path into a table nothing reads, that nothing calls ─
revoke execute on function public.pwa_install_log(uuid, text, text, text, text, text, text, text, boolean)
  from anon, authenticated;

-- ── trigger bodies: nothing should reach them through /rest/v1/rpc ─────────
revoke execute on function public.handle_new_user()             from anon, authenticated;
revoke execute on function public.baladieh_finance_audit_fn()   from anon, authenticated;
revoke execute on function public._coop_auto_approve_seller()   from anon, authenticated;
revoke execute on function public._coop_auto_approve_agent()    from anon, authenticated;

-- ── internal helpers, called only from other definer functions ────────────
revoke execute on function public.coop_session_subject(uuid, text) from anon, authenticated;
revoke execute on function public.push_log_recipients(uuid)     from anon, authenticated;
revoke execute on function public.next_email_ticket_id()        from anon, authenticated;

-- ── belongs to the other application sharing this project ─────────────────
revoke execute on function public.generate_auto_requisitions()  from anon, authenticated;
revoke execute on function public.get_fefo_lot(uuid)            from anon, authenticated;
