-- ═══════════════════════════════════════════════════════════════════════════
-- 45 — الدفع الإلكتروني: طلب الدفع يُبنى ويُدقَّق في القاعدة قبل أن يلمس Whish
--
-- The order pipeline that the Whish checkout will ride on, built BEFORE the
-- API documentation arrives so that wiring Whish in later touches only the
-- two edge functions (whish-checkout / whish-callback), nothing here.
--
--   pay_orders            one row per payment attempt. No anon access at all;
--                         staff read behind pay_view (its own key, below).
--   pay_create_order()    the only way in. Verifies, server-side, everything
--                         the page promises: the phone is in the dalil (the
--                         same answer the tournament form gets), every service
--                         is an ACTIVE entry of settings.pay_services with its
--                         fee respected, and رقم العقار present where required.
--                         The total is computed here — never trusted from the
--                         browser.
--   pay_view              reading who paid what is its own power, distinct
--                         from configuring the services (pay_manage) — the
--                         push_log_view precedent. Role defaults for all
--                         roles, row on the user screen, RLS asks the key.
--
-- The edge functions will use the service role to move an order to paid and
-- book the Q-2026-NNN receipt; no UPDATE policy exists on purpose.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0 · the orders ──────────────────────────────────────────────────────────
create table if not exists public.pay_orders (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  phone           text not null,
  phone_norm      text not null,
  payer_name      text not null,
  services        jsonb not null,          -- [{key,label,amount}] — validated & repriced server-side
  property_number text,
  amount          numeric(12,2) not null check (amount > 0),
  currency        text not null default 'USD' check (currency in ('USD','LBP')),
  status          text not null default 'pending'
                  check (status in ('pending','paid','failed','cancelled','expired')),
  whish_ref       text,                    -- Whish's transaction reference, set by the callback
  paid_at         timestamptz,
  receipt_no      text                     -- the sanad (Q-2026-NNN) booked for it
);
create index if not exists pay_orders_norm_idx   on public.pay_orders(phone_norm, created_at desc);
create index if not exists pay_orders_status_idx on public.pay_orders(status, created_at desc);

alter table public.pay_orders enable row level security;
drop policy if exists pay_orders_read on public.pay_orders;
create policy pay_orders_read on public.pay_orders
  for select to authenticated using (public.has_perm('pay_view'));
-- writes: INSERT only through pay_create_order (security definer); the edge
-- functions update through the service role. No anon path exists.

-- ── 1 · the only way in ─────────────────────────────────────────────────────
create or replace function public.pay_create_order(
  p_phone text, p_name text, p_services jsonb, p_property text default null)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_norm   text := public.lb_phone_norm(p_phone);
  v_name   text := nullif(btrim(coalesce(p_name,'')),'');
  v_prop   text := nullif(btrim(coalesce(p_property,'')),'');
  v_cfg    jsonb;
  v_sel    jsonb := '[]'::jsonb;
  v_item   jsonb;
  v_svc    jsonb;
  v_amount numeric := 0;
  v_fee    numeric;
  v_need_prop boolean := false;
  v_id     uuid;
begin
  if v_norm = '' then
    raise exception 'رقم الهاتف غير صالح';
  end if;
  if v_name is null then
    raise exception 'الاسم مطلوب';
  end if;
  -- الدفع لأهل وادي الست المسجّلين — الدليل يجيب بالجواب نفسه الذي يجيب به
  -- نموذج البطولة (الخصوصية نفسها: الرقم المخفي لا يطابق شيئاً)
  if not coalesce((public.club_phone_lookup(p_phone)->>'found')::boolean, false) then
    raise exception 'الرقم غير مسجّل في دليل البلدية — التسجيل في الدليل شرط للدفع الإلكتروني';
  end if;

  select value into v_cfg from public.settings where key='pay_services';
  if v_cfg is null or jsonb_typeof(v_cfg->'services') <> 'array' then
    raise exception 'خدمات الدفع غير مهيأة';
  end if;
  if jsonb_typeof(p_services) <> 'array' or jsonb_array_length(p_services) = 0 then
    raise exception 'اختر خدمة واحدة على الأقل';
  end if;

  for v_item in select * from jsonb_array_elements(p_services) loop
    select s into v_svc from jsonb_array_elements(v_cfg->'services') s
     where s->>'key' = v_item->>'key' and coalesce((s->>'active')::boolean, true);
    if v_svc is null then
      raise exception 'خدمة غير معتمدة: %', coalesce(v_item->>'key','؟');
    end if;
    -- الرسم الثابت يفرض نفسه؛ الرسم الحر يقبل ما كتبه الدافع بشرط أن يكون موجباً
    v_fee := case when v_svc->>'fee' is not null
                  then (v_svc->>'fee')::numeric
                  else (v_item->>'amount')::numeric end;
    if v_fee is null or v_fee <= 0 then
      raise exception 'مبلغ غير صالح للخدمة: %', v_svc->>'label';
    end if;
    if coalesce((v_svc->>'prop')::boolean, false) then
      v_need_prop := true;
    end if;
    v_amount := v_amount + v_fee;
    v_sel := v_sel || jsonb_build_object('key', v_svc->>'key', 'label', v_svc->>'label', 'amount', v_fee);
  end loop;

  if v_need_prop and v_prop is null then
    raise exception 'رقم العقار إلزامي لإحدى الخدمات المختارة';
  end if;

  insert into public.pay_orders (phone, phone_norm, payer_name, services, property_number, amount)
  values (public.lb_phone_display(p_phone), v_norm, v_name, v_sel, v_prop, v_amount)
  returning id into v_id;

  return jsonb_build_object('order_id', v_id, 'amount', v_amount, 'currency', 'USD');
end;
$fn$;
grant execute on function public.pay_create_order(text, text, jsonb, text) to anon, authenticated;

-- ── 2 · pay_view — لكل دور قيمته ────────────────────────────────────────────
update public.role_permissions
   set perms = perms || '{"pay_view":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"pay_view":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');
