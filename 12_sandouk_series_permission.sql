-- ═══════════════════════════════════════════════════════════════════════════
-- 12 — ترقيم السندات becomes a permission of its own
--
-- Setting the sanad prefix and the number a year's series starts from decides
-- what every future receipt is called. It rode in on `settings_edit`, which
-- mayor and admin both hold; the municipality wants it with the super admin
-- alone, grantable per person from the user screen like everything else.
--
--   sandouk_series   super_admin → true, every other role → false
--
-- The page gate is not the real gate — a page can be bypassed — so the
-- `settings` write policy decides it too. Only the `sandouk_series` key moves;
-- every other setting keeps the mayor/admin rule it already had.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the role defaults ──────────────────────────────────────────────────────
update public.role_permissions
   set perms = perms || '{"sandouk_series":true}'::jsonb,
       updated_at = now()
 where role = 'super_admin';

update public.role_permissions
   set perms = perms || '{"sandouk_series":false}'::jsonb,
       updated_at = now()
 where role <> 'super_admin';

-- ── the policy ─────────────────────────────────────────────────────────────
-- has_perm() resolves per-user override → role default → super_admin → false,
-- so granting one person ترقيم السندات from the user screen is enough, and
-- nothing else needs to change here.
drop policy if exists settings_admin_write on public.settings;
create policy settings_admin_write on public.settings
  for all
  using (
    case when key = 'sandouk_series'
         then public.has_perm('sandouk_series')
         else public.has_role(array['mayor','admin'])
    end)
  with check (
    case when key = 'sandouk_series'
         then public.has_perm('sandouk_series')
         else public.has_role(array['mayor','admin'])
    end);
