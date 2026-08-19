-- ═══════════════════════════════════════════════════════════════════════════
-- 08_lock_down_policies.sql — step 4 of the access audit
-- Applied to the live project on 2026-08-19.
--
-- Before this file, most municipal tables were governed by a policy that read
-- "auth.uid() IS NOT NULL" — a test for "is logged in", not for "is allowed".
-- Any account, including a resident who registered on the public citizen page,
-- could read and write the cash box, rewrite any case file, or insert itself
-- into employees as a manager (which is the check the admin-user function
-- trusts before it will create or delete accounts).
--
-- Everything below decides through has_perm() / has_role() from
-- 07_roles_and_permissions.sql, so a page gate and a policy can no longer
-- disagree about the same person.
--
-- Tables belonging to the other application sharing this Supabase project
-- (inventory, production, invoices, machines, suppliers, …) are deliberately
-- left alone: they are not part of this repository and cannot be tested here.
-- ═══════════════════════════════════════════════════════════════════════════

-- mayor keeps editing irrigation; the audit only removed cash-box entry,
-- editing and deletion from that role
update public.role_permissions
   set perms = perms || '{"water_edit":true}'::jsonb, updated_at = now()
 where role = 'mayor';

-- ── صندوق البلدية ──────────────────────────────────────────────────────────
drop policy if exists auth_rw_baladieh_finance  on public.baladieh_finance;
drop policy if exists auth_ins_baladieh_finance on public.baladieh_finance;
drop policy if exists auth_upd_baladieh_finance on public.baladieh_finance;
drop policy if exists auth_del_baladieh_finance on public.baladieh_finance;

create policy bf_select on public.baladieh_finance
  for select to authenticated using (public.has_perm('sandouk_view'));
create policy bf_insert on public.baladieh_finance
  for insert to authenticated with check (public.has_perm('sandouk_add'));
create policy bf_update on public.baladieh_finance
  for update to authenticated
  using (public.has_perm('sandouk_edit')) with check (public.has_perm('sandouk_edit'));
create policy bf_delete on public.baladieh_finance
  for delete to authenticated using (public.has_perm('sandouk_delete'));

-- ── جداول الموظفين والمشرفين ───────────────────────────────────────────────
drop policy if exists emp_all                     on public.employees;
drop policy if exists employees_authenticated_all on public.employees;
drop policy if exists employees_read_all          on public.employees;
create policy emp_select on public.employees
  for select to authenticated using (auth.uid() is not null);
create policy emp_write on public.employees
  for all to authenticated
  using (public.has_role(array['admin'])) with check (public.has_role(array['admin']));

drop policy if exists allow_all_super_admins on public.super_admins;
drop policy if exists sa_all                 on public.super_admins;
create policy sa_select on public.super_admins
  for select to authenticated using (auth.uid() is not null);
create policy sa_write on public.super_admins
  for all to authenticated
  using (public.has_role(array['super_admin'])) with check (public.has_role(array['super_admin']));

-- ── مالية الري ─────────────────────────────────────────────────────────────
drop policy if exists wf_auth_all on public.water_finance;
create policy wf_select on public.water_finance
  for select to authenticated using (public.has_perm('water_view'));
create policy wf_write on public.water_finance
  for all to authenticated
  using (public.has_perm('water_edit')) with check (public.has_perm('water_edit'));

-- ── معاملات المواطنين ──────────────────────────────────────────────────────
-- The blanket policy allowed any signed-in account to delete a case, and an
-- anonymous UPDATE with condition true allowed any visitor to rewrite one. The
-- role-checked policies beside them never mattered, because policies OR together.
drop policy if exists "Public access"     on public.cases;
drop policy if exists public_update_cases on public.cases;
drop policy if exists public_select_cases on public.cases;   -- duplicate select

-- a citizen may correct the case they filed
create policy cases_owner_update on public.cases
  for update to authenticated
  using (coalesce(email,'') <> '' and email = (auth.jwt() ->> 'email'))
  with check (coalesce(email,'') <> '' and email = (auth.jwt() ->> 'email'));

-- the public form attaches the documents it just uploaded to the case it just
-- created: bounded to a ten-minute window (cases.id is a sequential bigint, so
-- "any row" would be trivially enumerable) and to two columns by the grant below
create policy cases_attach_docs on public.cases
  for update to anon
  using (created_at > now() - interval '10 minutes')
  with check (created_at > now() - interval '10 minutes');

revoke update on public.cases from anon;
grant  update (documents, timeline) on public.cases to anon;

-- ── الأخبار ────────────────────────────────────────────────────────────────
drop policy if exists news_insert_admin on public.news_articles;
drop policy if exists news_update_admin on public.news_articles;
drop policy if exists news_delete_admin on public.news_articles;

-- ── إعدادات النظام ─────────────────────────────────────────────────────────
drop policy if exists "allow all" on public.settings;
drop policy if exists allow_all   on public.settings;

-- ── سجل أصحاب حقوق الري وإعداداته ──────────────────────────────────────────
-- public read stays: water.html is a public page built on this table
drop policy if exists auth_write             on public.irr_owners;
drop policy if exists auth_update            on public.irr_owners;
drop policy if exists auth_delete            on public.irr_owners;
drop policy if exists irr_all                on public.irr_owners;
drop policy if exists allow_all_irr_owners   on public.irr_owners;
drop policy if exists pub_read               on public.irr_owners;   -- duplicate read
drop policy if exists irr_owners_admin_write on public.irr_owners;
create policy irr_owners_write on public.irr_owners
  for all to authenticated
  using (public.has_perm('water_edit')) with check (public.has_perm('water_edit'));

drop policy if exists allow_all_irr_config   on public.irr_config;
drop policy if exists irr_cfg_all            on public.irr_config;
drop policy if exists auth_write             on public.irr_config;
drop policy if exists auth_update            on public.irr_config;
drop policy if exists irr_config_admin_write on public.irr_config;
create policy irr_config_admin_write on public.irr_config
  for all to authenticated
  using (public.has_perm('water_edit')) with check (public.has_perm('water_edit'));

-- ── الدليل ─────────────────────────────────────────────────────────────────
-- residents keep submitting entries and corrections; editing the directory
-- follows the directory permission
drop policy if exists entries_admin_all    on public.phonebook_entries;
drop policy if exists phonebook_admin_full on public.phonebook_entries;
create policy phonebook_staff_write on public.phonebook_entries
  for all to authenticated
  using (public.has_perm('phonebook_edit')) with check (public.has_perm('phonebook_edit'));

drop policy if exists extras_admin_all           on public.phonebook_extras;
drop policy if exists phonebook_extras_staff_all on public.phonebook_extras;
create policy phonebook_extras_staff_write on public.phonebook_extras
  for all to authenticated
  using (public.has_perm('phonebook_edit')) with check (public.has_perm('phonebook_edit'));

drop policy if exists pe_admin_all on public.phonebook_pending_edits;
create policy pe_staff_write on public.phonebook_pending_edits
  for all to authenticated
  using (public.has_perm('phonebook_edit')) with check (public.has_perm('phonebook_edit'));

drop policy if exists corrections_admin_all on public.phonebook_corrections;
create policy corrections_staff_write on public.phonebook_corrections
  for all to authenticated
  using (public.has_perm('phonebook_edit')) with check (public.has_perm('phonebook_edit'));

-- ── قوالب الإشعارات وبيانات البلدية ────────────────────────────────────────
drop policy if exists pt_admin_all on public.push_templates;

drop policy if exists allow_all_municipalities on public.municipalities;
create policy municipalities_read on public.municipalities
  for select to anon, authenticated using (true);
create policy municipalities_write on public.municipalities
  for all to authenticated
  using (public.has_role(array['admin','mayor'])) with check (public.has_role(array['admin','mayor']));

-- ── الأرشيف المالي MRS (36 جدولاً) ─────────────────────────────────────────
-- writing was tied to one hard-coded email address; it now follows mrs_edit,
-- which the super admin holds by definition
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'mrs\_%'
  loop
    execute format('drop policy if exists %I on public.%I', 'imp_ins_'||t.tablename, t.tablename);
    execute format('drop policy if exists %I on public.%I', 'imp_del_'||t.tablename, t.tablename);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_perm(''mrs_edit''))',
                   'mrs_ins_'||t.tablename, t.tablename);
    execute format('create policy %I on public.%I for delete to authenticated using (public.has_perm(''mrs_edit''))',
                   'mrs_del_'||t.tablename, t.tablename);
  end loop;
end $$;
