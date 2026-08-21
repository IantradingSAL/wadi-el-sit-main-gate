-- ═══════════════════════════════════════════════════════════════════════════
-- 26 — 📊 تتبع نشاط الموظفين stops being a per-browser note to self
--
-- The screen read `localStorage['wadi_user_activity_v1']`, which is one
-- browser's private storage. So it showed the municipality zero activity, zero
-- active staff and an empty list — not because nobody worked, but because
-- whatever any employee did was written on their own device and never left it.
-- A supervisor opening the screen was reading their own browser, and clearing
-- site data erased the record.
--
-- Activity belongs in a table, like everything else that must outlive one
-- device. There is already a `public.audit_log` on this project — it belongs to
-- the *other* application sharing it (its pages are inventory, suppliers,
-- invoices, employees, all from 5–11 August), so the municipality gets its own
-- table rather than a screen that mixes two organisations' work together.
--
-- Append-only for clients, exactly like baladieh_finance_audit (migration 06):
-- INSERT is allowed only for the caller's own rows, SELECT is gated on the new
-- permission, and there is no UPDATE or DELETE policy at all.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.app_activity (
  id          uuid primary key default gen_random_uuid(),
  at          timestamptz not null default now(),
  actor_id    uuid not null default auth.uid(),
  actor_email text,
  role        text,                 -- the role the page was acting under
  page        text,                 -- dashboard | sandouk | water | coop …
  action      text not null,        -- Arabic label as shown on the screen
  target      text,                 -- what it acted on (رقم طلب، اسم مستخدم…)
  detail      text
);

create index if not exists app_activity_at_idx    on public.app_activity(at desc);
create index if not exists app_activity_actor_idx on public.app_activity(actor_email);
create index if not exists app_activity_page_idx  on public.app_activity(page);

alter table public.app_activity enable row level security;

-- Anyone signed in records their own activity; nobody records anybody else's.
drop policy if exists app_activity_insert_self on public.app_activity;
create policy app_activity_insert_self on public.app_activity
  for insert to authenticated
  with check (actor_id = auth.uid());

-- Reading is the supervisory act, and it has its own key.
drop policy if exists app_activity_read_perm on public.app_activity;
create policy app_activity_read_perm on public.app_activity
  for select to authenticated
  using (public.has_perm('activity_view'));

-- No update, no delete: a log that can be edited is not a log.

-- ── the permission: activity_view ──────────────────────────────────────────
-- It rode on the page's own ROLE_CFG table before, which is JavaScript and
-- therefore not a gate. Watching what every employee does is supervision, so it
-- goes to the three roles that supervise — and to anyone the super admin ticks
-- it on for from the user screen, which is what has_perm() resolves first.
update public.role_permissions
   set perms = perms || '{"activity_view":true}'::jsonb,
       updated_at = now()
 where role in ('super_admin','mayor','admin');

update public.role_permissions
   set perms = perms || '{"activity_view":false}'::jsonb,
       updated_at = now()
 where role not in ('super_admin','mayor','admin');

-- Effect:
--
--   role          activity_view   sees نشاط الموظفين
--   super_admin   true            yes
--   mayor         true            yes
--   admin         true            yes
--   approver      false           no
--   citizen       false           no
--   finance       false           no
--   officer       false           no
--   sandouk       false           no
--   viewer        false           no
--   water_admin   false           no
--   water_only    false           no
--
-- The page gate (WadiPerms.can('activity_view')) and the read policy now ask
-- the same question about the same person.
