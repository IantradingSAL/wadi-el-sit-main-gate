-- ═══════════════════════════════════════════════════════════════════════════
-- 42 — ربط Whish إعدادات: يوم تصل بيانات التاجر تُلصق في ⚙️ ولا يُكتب سطر كود
--
-- `settings.pay_whish` carries the merchant connection — the API URL, the
-- channel (merchant) id, the secret, sandbox/live, and the on/off switch.
-- Both directions go through guarded RPCs and NOTHING here is public:
--   pay_whish_get() / pay_whish_set()  →  has_perm('pay_manage') or refuse.
-- pay_config() stays the page's only public read, and from here it also
-- answers `live` — the boolean alone, never a credential — so the page can
-- drop its «قريباً» face the day the switch turns on, without a deploy.
--
-- The checkout edge functions (whish-checkout / whish-callback) will read
-- this same key server-side; the browser never touches the secret.
-- ═══════════════════════════════════════════════════════════════════════════

insert into public.settings (key, value)
values ('pay_whish', jsonb_build_object(
  'api_url','', 'channel','', 'secret','', 'mode','sandbox', 'enabled',false))
on conflict (key) do nothing;

create or replace function public.pay_whish_get()
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
begin
  if not public.has_perm('pay_manage') then
    raise exception 'لا تملك صلاحية إدارة الدفع الإلكتروني';
  end if;
  return coalesce((select value from public.settings where key='pay_whish'), '{}'::jsonb);
end;
$fn$;
grant execute on function public.pay_whish_get() to authenticated;

create or replace function public.pay_whish_set(p jsonb)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if not public.has_perm('pay_manage') then
    raise exception 'لا تملك صلاحية إدارة الدفع الإلكتروني';
  end if;
  update public.settings set value = value || p, updated_at = now() where key='pay_whish';
  return public.pay_whish_get();
end;
$fn$;
grant execute on function public.pay_whish_set(jsonb) to authenticated;

-- the public read gains the flag only — credentials never leave pay_whish_get
create or replace function public.pay_config()
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $fn$
  select coalesce((select value from public.settings where key='pay_services'), '{}'::jsonb)
      || jsonb_build_object('live',
           coalesce(((select value from public.settings where key='pay_whish')->>'enabled')::boolean, false));
$fn$;
