-- ═══════════════════════════════════════════════════════════════════════════
-- 41 — الدفع الإلكتروني: الخدمات إعدادات، وإدارتها صلاحية باسمها
--
-- pay.html ships with its services hardcoded; from here they are CONFIG —
-- `settings.pay_services` — edited from the page's own ⚙️ sheet, exactly the
-- club_games precedent. Each service carries:
--   key      stable id (also the sanad category later, at launch)
--   label    what the citizen reads
--   icon     the emoji on the card
--   fee      fixed amount in USD, or null → the payer types the amount
--   prop     true → رقم العقار is mandatory for this service
--   active   false → hidden from the page without deleting the row
--
-- Per the standing rule, running the payment screen is its own permission —
-- `pay_manage` — with role defaults for every role, a row on the user screen,
-- and the database asking the same key: pay_set_config() is the only write
-- path and it refuses without has_perm('pay_manage'). The public read is
-- pay_config(), which returns only this one settings key.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 0 · config ──────────────────────────────────────────────────────────────
insert into public.settings (key, value)
values ('pay_services', jsonb_build_object(
  'services', jsonb_build_array(
    jsonb_build_object('key','jibaya', 'label','جباية ورسوم بلدية','icon','🏛️','fee',null,'prop',true, 'active',true),
    jsonb_build_object('key','nifayat','label','بدل نفايات',        'icon','🗑️','fee',null,'prop',true, 'active',true),
    jsonb_build_object('key','ta2jir', 'label','قيمة تأجيرية',       'icon','🏠','fee',null,'prop',true, 'active',true),
    jsonb_build_object('key','rukhas', 'label','رسوم رخص وإفادات',   'icon','📄','fee',null,'prop',false,'active',true),
    jsonb_build_object('key','gharama','label','غرامات',             'icon','⚖️','fee',null,'prop',false,'active',true))))
on conflict (key) do nothing;

create or replace function public.pay_config()
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce((select value from public.settings where key='pay_services'), '{}'::jsonb);
$fn$;
grant execute on function public.pay_config() to anon, authenticated;

create or replace function public.pay_set_config(p jsonb)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if not public.has_perm('pay_manage') then
    raise exception 'لا تملك صلاحية إدارة الدفع الإلكتروني';
  end if;
  update public.settings set value = value || p, updated_at = now() where key='pay_services';
  return public.pay_config();
end;
$fn$;
grant execute on function public.pay_set_config(jsonb) to authenticated;


-- ── 1 · the permission, for every role ──────────────────────────────────────
-- Configuring what the municipality collects online is its own authority.
update public.role_permissions
   set perms = perms || '{"pay_manage":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"pay_manage":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');
