-- ═══════════════════════════════════════════════════════════════════════════
-- 07_roles_and_permissions.sql — one source of truth for who may do what
-- Applied to the live project on 2026-08-19 (access audit, steps 2 and part of 4).
--
-- Model
--   user_roles        which role(s) an account holds  (server-side, not editable
--                     from a browser — unlike user_metadata.role, which four
--                     pages used to trust)
--   role_permissions  the default permission set for each role
--   user_permissions  per-user overrides — the checkboxes on the user screen;
--                     only the keys present override the role default
--   has_role(text[])  true when ANY of the caller's roles matches; super_admin
--                     satisfies every check
--   has_perm(text)    per-user override → role default → false
--
-- Decisions recorded here (owner, 2026-08-19):
--   · mayor views and signs cash-box vouchers but does not add, edit or delete
--   · only super_admin and admin create accounts, delete accounts and edit roles
--   · an individual admin can be limited by ticking a permission off for them
-- ═══════════════════════════════════════════════════════════════════════════

-- ── role vocabulary ────────────────────────────────────────────────────────
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role = any (array[
    'citizen','viewer','officer','approver','admin','mayor','super_admin',
    'finance','sandouk','water_admin','water_only','staff','baladieh',
    'coop_admin','dalail_admin','coop_customer','water_owner'
  ])
);

-- ── has_role: ANY matching role, super_admin always ────────────────────────
create or replace function public.has_role(p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
      and (role = any(p_roles) or role = 'super_admin')
  );
$$;

-- ── current_user_role: highest-ranked role, deterministically ──────────────
-- Previously "select role from user_roles where user_id = auth.uid()" with no
-- ordering: an account with several roles got an arbitrary one, so role-checked
-- policies passed or failed at random.
create or replace function public.current_user_role()
returns text language sql stable security definer
set search_path = public, pg_temp as $$
  select r.role from public.user_roles r
  where r.user_id = auth.uid()
  order by array_position(
    array['super_admin','mayor','admin','approver','water_admin','finance','sandouk',
          'officer','staff','baladieh','coop_admin','dalail_admin','viewer',
          'water_only','coop_customer','water_owner','citizen'], r.role) nulls last
  limit 1;
$$;

-- ── permission catalogue ───────────────────────────────────────────────────
create table if not exists public.role_permissions (
  role       text primary key,
  perms      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.user_permissions (
  user_id    uuid primary key,
  perms      jsonb not null default '{}'::jsonb,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table public.role_permissions enable row level security;
alter table public.user_permissions enable row level security;

drop policy if exists rp_read on public.role_permissions;
create policy rp_read on public.role_permissions for select to authenticated using (true);
drop policy if exists rp_write on public.role_permissions;
create policy rp_write on public.role_permissions for all to authenticated
  using (public.has_role(array['admin'])) with check (public.has_role(array['admin']));

drop policy if exists up_read on public.user_permissions;
create policy up_read on public.user_permissions for select to authenticated
  using (user_id = auth.uid() or public.has_role(array['admin','mayor']));
drop policy if exists up_write on public.user_permissions;
create policy up_write on public.user_permissions for all to authenticated
  using (public.has_role(array['admin'])) with check (public.has_role(array['admin']));

-- ── has_perm: override, then role default ──────────────────────────────────
create or replace function public.has_perm(p text)
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce(
    (select (up.perms ->> p)::boolean
       from public.user_permissions up
      where up.user_id = auth.uid() and up.perms ? p),
    (select bool_or((rp.perms ->> p)::boolean)
       from public.user_roles ur
       join public.role_permissions rp on rp.role = ur.role
      where ur.user_id = auth.uid() and rp.perms ? p),
    public.has_role(array['super_admin']),
    false);
$$;

-- ── role defaults ──────────────────────────────────────────────────────────
insert into public.role_permissions(role, perms) values
 ('super_admin', '{"sandouk_view":true,"sandouk_add":true,"sandouk_edit":true,"sandouk_delete":true,"sandouk_sign":true,
                   "cases_view":true,"cases_add":true,"cases_edit":true,"cases_delete":true,"cases_approve":true,
                   "water_view":true,"water_edit":true,"mrs_view":true,"mrs_edit":true,
                   "coop_view":true,"coop_edit":true,"phonebook_view":true,"phonebook_edit":true,
                   "news_publish":true,"push_send":true,"inbox_read":true,
                   "users_view":true,"users_create":true,"users_edit":true,"users_delete":true,
                   "roles_edit":true,"roles_delete":true,"settings_edit":true,"export_data":true,"audit_view":true}'::jsonb),
 ('mayor',       '{"sandouk_view":true,"sandouk_add":false,"sandouk_edit":false,"sandouk_delete":false,"sandouk_sign":true,
                   "cases_view":true,"cases_add":true,"cases_edit":true,"cases_delete":true,"cases_approve":true,
                   "water_view":true,"water_edit":false,"mrs_view":true,"mrs_edit":false,
                   "coop_view":true,"coop_edit":false,"phonebook_view":true,"phonebook_edit":true,
                   "news_publish":true,"push_send":true,"inbox_read":true,
                   "users_view":true,"users_create":false,"users_edit":false,"users_delete":false,
                   "roles_edit":false,"roles_delete":false,"settings_edit":true,"export_data":true,"audit_view":true}'::jsonb),
 ('admin',       '{"sandouk_view":true,"sandouk_add":false,"sandouk_edit":false,"sandouk_delete":false,"sandouk_sign":false,
                   "cases_view":true,"cases_add":true,"cases_edit":true,"cases_delete":true,"cases_approve":true,
                   "water_view":true,"water_edit":true,"mrs_view":true,"mrs_edit":false,
                   "coop_view":true,"coop_edit":true,"phonebook_view":true,"phonebook_edit":true,
                   "news_publish":true,"push_send":true,"inbox_read":true,
                   "users_view":true,"users_create":true,"users_edit":true,"users_delete":true,
                   "roles_edit":true,"roles_delete":true,"settings_edit":true,"export_data":true,"audit_view":true}'::jsonb),
 ('finance',     '{"sandouk_view":true,"sandouk_add":true,"sandouk_edit":true,"sandouk_delete":false,"sandouk_sign":true,
                   "mrs_view":true,"phonebook_view":true,"phonebook_edit":true,
                   "export_data":true,"audit_view":true}'::jsonb),
 ('sandouk',     '{"sandouk_view":true,"sandouk_add":true,"sandouk_edit":true,"sandouk_delete":false,"sandouk_sign":true,
                   "mrs_view":true,"phonebook_view":true,"phonebook_edit":true,
                   "export_data":true,"audit_view":true}'::jsonb),
 ('officer',     '{"cases_view":true,"cases_add":true,"cases_edit":true,"cases_delete":false,"cases_approve":false,
                   "water_view":true,"phonebook_view":true,"phonebook_edit":true,"export_data":false}'::jsonb),
 ('approver',    '{"cases_view":true,"cases_approve":true,"cases_add":false,"cases_edit":false,"cases_delete":false,
                   "phonebook_view":true}'::jsonb),
 ('water_admin', '{"water_view":true,"water_edit":true,"phonebook_view":true}'::jsonb),
 ('water_only',  '{"water_view":true,"water_edit":false}'::jsonb),
 ('viewer',      '{"cases_view":true,"phonebook_view":true}'::jsonb),
 ('citizen',     '{}'::jsonb)
on conflict (role) do update set perms = excluded.perms, updated_at = now();

-- ── mirror existing access into user_roles ─────────────────────────────────
-- The same access each account already had through user_metadata, moved to the
-- store that cannot be edited from a browser. Nothing granted, nothing removed.
insert into public.user_roles(user_id, role)
select u.id, u.raw_user_meta_data->>'role'
from auth.users u
where u.raw_user_meta_data->>'role' in
      ('mayor','admin','approver','officer','viewer','sandouk','finance','water_admin','water_only')
  and not exists (select 1 from public.user_roles r
                  where r.user_id = u.id and r.role = u.raw_user_meta_data->>'role');

-- ── every role-checked policy switches to has_role() ───────────────────────
-- current_user_role() = ANY(ARRAY[...]) fails for a super_admin whose array
-- lists only mayor/admin, and mis-fires for any multi-role account.
do $$
declare r record; q text; w text; stmt text;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname='public'
      and (qual like '%current_user_role()%' or with_check like '%current_user_role()%')
  loop
    q := replace(coalesce(r.qual,''),       'current_user_role() = ANY (ARRAY[', 'public.has_role(ARRAY[');
    w := replace(coalesce(r.with_check,''), 'current_user_role() = ANY (ARRAY[', 'public.has_role(ARRAY[');
    stmt := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if r.qual is not null and q <> ''       then stmt := stmt || format(' using (%s)', q); end if;
    if r.with_check is not null and w <> '' then stmt := stmt || format(' with check (%s)', w); end if;
    execute stmt;
  end loop;
end $$;
