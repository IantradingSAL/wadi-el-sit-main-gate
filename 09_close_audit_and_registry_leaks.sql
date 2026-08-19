-- ═══════════════════════════════════════════════════════════════════════════
-- 09 — close the reads that 07/08 left open
--
-- 07/08 locked the money tables behind has_perm(): baladieh_finance needs
-- sandouk_view, water_finance needs water_view. Verified working — an
-- ordinary logged-in user reads 0 rows from both.
--
-- What they missed is everything *beside* those tables:
--
--   baladieh_finance_audit   select using (true)  → any logged-in user.
--                            168 of its 173 rows carry `amount` and 166
--                            carry `person` in the snapshot, so the cash
--                            box leaked in full through its own audit
--                            trail while the table itself stayed shut.
--
--   mrs_* (28 tables)        select using (true)  → any logged-in user
--                            reads the taxpayer registry, 209 names.
--
--   audit_log                select using (true)  → any logged-in user
--                            reads all 1,727 system activity rows.
--
-- Anyone able to create an account — a coop seller, for instance — held
-- all three. Each policy is replaced with the has_perm() the matching
-- page already requires, so no legitimate user loses access.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the cash-box audit trail: same gate as the cash box ────────────────────
drop policy if exists bfa_read_auth on public.baladieh_finance_audit;
create policy bfa_read_auth on public.baladieh_finance_audit
  for select to authenticated
  using (has_perm('sandouk_view'));

-- ── the taxpayer registry: same gate as the MRS page ───────────────────────
do $$
declare t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname='public' and tablename like 'mrs\_%'
  loop
    execute format('drop policy if exists %I on public.%I', 'ro_'||t, t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (has_perm(''mrs_view''))',
      'ro_'||t, t);
  end loop;
end $$;

-- ── the system activity log: readable with audit_view, not by everyone ─────
drop policy if exists audit_log_read_auth on public.audit_log;
create policy audit_log_read_auth on public.audit_log
  for select to authenticated
  using (has_perm('audit_view'));

-- Writing the log stays open to any signed-in user (the pages log their own
-- actions), but no longer to anonymous visitors, who were able to forge
-- entries into it.
drop policy if exists audit_log_insert_anyone on public.audit_log;
create policy audit_log_insert_auth on public.audit_log
  for insert to authenticated
  with check (true);

-- ── short links may only point back at this project's own storage ──────────
-- The redirect function 302s to whatever url the row holds, and anonymous
-- visitors may insert rows, so the municipality's domain could be used to
-- bounce people anywhere. All 8 existing rows already satisfy this.
alter table public.short_links drop constraint if exists short_links_url_self_only;
alter table public.short_links add constraint short_links_url_self_only
  check (url like 'https://onjbwhkmmtqnymhjnplw.supabase.co/%');

-- ── privileges PostgREST never uses and anon should never hold ─────────────
revoke truncate, references, trigger on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke delete, update on public.baladieh_finance, public.audit_log,
                          public.user_roles, public.profiles from anon;
