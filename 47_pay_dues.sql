-- ═══════════════════════════════════════════════════════════════════════════
-- 47 — المتوجبات البلدية (الجباية): ما يتوجب على كل عقار، سنةً بسنة، يُدفع عبر Whish
--
-- The cash box records what WAS paid; this table records what is OWED.
-- One row per (property, year, item): جباية 2025، رسم تأخير 2025، جباية 2026…
-- A citizen finds their dues with ANY identifier they know — رقم العقار,
-- their name, or their phone — and pays the rows they select; the payment
-- rides the exact Whish pipeline of migration 46 and books the same official
-- Q-YYYY-NNN receipt, which is then stamped back onto the dues rows.
--
--   pay_dues                  the ledger of dues. No anon access; staff read
--                             and write behind pay_dues_manage (its own key).
--   pay_dues_lookup(q)        the citizen's window: answers unpaid dues for a
--                             property number (exact), a phone (normalised,
--                             the same digits-minus-961-minus-0 rule as every
--                             other lookup) or a name (whole-word-ish match,
--                             3+ letters). Returns only what the due itself
--                             says: property, owner, year, item, amount.
--   pay_dues_create_order(ids) the only way from dues to a payment: reprices
--                             from the rows themselves (never the browser),
--                             refuses paid/foreign mixes, creates the
--                             pay_orders row and links the dues to it.
--   pay_book_receipt          (recreated) now speaks the order's currency in
--                             the ledger description — «2,300,000 ل.ل», not a
--                             dollar sign on a lira amount — and, having
--                             booked, marks the order's dues rows paid with
--                             the receipt number. Idempotence unchanged.
--
-- pay_dues_manage follows the standing four-part rule: its own key, defaults
-- for every role, a row on the user screen (dashboard.html), and RLS below
-- asking the very same key.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0 · دفتر المتوجبات ──────────────────────────────────────────────────────
create table if not exists public.pay_dues (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  property_number text not null,
  owner_name      text not null,
  phone           text,
  phone_norm      text,                    -- stamped by trigger from phone
  year            int  not null check (year between 2000 and 2100),
  label           text not null,           -- «جباية ورسوم بلدية»، «رسم تأخير»…
  amount          numeric(14,2) not null check (amount > 0),
  currency        text not null default 'LBP' check (currency in ('LBP','USD')),
  status          text not null default 'unpaid'
                  check (status in ('unpaid','paid','cancelled')),
  order_id        uuid references public.pay_orders(id),
  receipt_no      text,
  paid_at         timestamptz
);
create index if not exists pay_dues_prop_idx  on public.pay_dues(lower(property_number), year);
create index if not exists pay_dues_norm_idx  on public.pay_dues(phone_norm);
create index if not exists pay_dues_order_idx on public.pay_dues(order_id);

create or replace function public.pay_dues_norm_tg()
returns trigger language plpgsql as $fn$
begin
  new.phone_norm := nullif(public.lb_phone_norm(coalesce(new.phone,'')), '');
  return new;
end;
$fn$;
drop trigger if exists pay_dues_norm on public.pay_dues;
create trigger pay_dues_norm before insert or update of phone
  on public.pay_dues for each row execute function public.pay_dues_norm_tg();

alter table public.pay_dues enable row level security;
drop policy if exists pay_dues_read  on public.pay_dues;
drop policy if exists pay_dues_write on public.pay_dues;
create policy pay_dues_read on public.pay_dues
  for select to authenticated using (public.has_perm('pay_dues_manage'));
create policy pay_dues_write on public.pay_dues
  for all to authenticated
  using (public.has_perm('pay_dues_manage'))
  with check (public.has_perm('pay_dues_manage'));
-- citizens never touch the table: they go through the two functions below.

-- ── 1 · نافذة المواطن — أي معرّف يعرفه يوصله ────────────────────────────────
create or replace function public.pay_dues_lookup(p_q text)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
declare
  v_q    text := btrim(coalesce(p_q,''));
  v_norm text := public.lb_phone_norm(v_q);
  v_rows jsonb;
begin
  if length(v_q) < 3 then
    return jsonb_build_object('found', false);
  end if;
  select jsonb_agg(jsonb_build_object(
           'id', d.id, 'property_number', d.property_number,
           'owner_name', d.owner_name, 'year', d.year, 'label', d.label,
           'amount', d.amount, 'currency', d.currency)
         order by d.year, d.label)
    into v_rows
    from public.pay_dues d
   where d.status = 'unpaid'
     and ( lower(d.property_number) = lower(v_q)
        or (v_norm <> '' and d.phone_norm = v_norm)
        or (v_q !~ '^[0-9+ ()-]+$' and d.owner_name ilike '%' || v_q || '%') );
  if v_rows is null then
    return jsonb_build_object('found', false);
  end if;
  return jsonb_build_object('found', true, 'dues', v_rows);
end;
$fn$;
grant execute on function public.pay_dues_lookup(text) to anon, authenticated;

-- ── 2 · من المتوجب إلى الطلب — التسعير من الصفوف نفسها ──────────────────────
create or replace function public.pay_dues_create_order(p_ids uuid[])
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_n        int;
  v_amount   numeric;
  v_currency text;
  v_prop     text;
  v_owner    text;
  v_phone    text;
  v_sel      jsonb;
  v_id       uuid;
begin
  if p_ids is null or array_length(p_ids,1) is null then
    raise exception 'اختر بنداً واحداً على الأقل';
  end if;

  select count(*), sum(d.amount),
         jsonb_agg(jsonb_build_object(
           'key', 'due-' || d.year, 'due_id', d.id,
           'label', d.label || ' ' || d.year, 'amount', d.amount)
           order by d.year, d.label)
    into v_n, v_amount, v_sel
    from public.pay_dues d
   where d.id = any(p_ids) and d.status = 'unpaid'
     and (d.order_id is null
          or exists (select 1 from public.pay_orders o
                      where o.id = d.order_id
                        and o.status in ('failed','cancelled','expired')));
  if v_n is distinct from array_length(p_ids,1) then
    raise exception 'أحد البنود مدفوع أو قيد الدفع — حدّث الاستعلام وأعد المحاولة';
  end if;
  -- عملة واحدة وعقار واحد لكل دفعة: إيصال واحد نظيف في دفتر الصندوق
  if (select count(distinct d.currency) from public.pay_dues d where d.id = any(p_ids)) > 1 then
    raise exception 'لا يمكن جمع عملتين في دفعة واحدة';
  end if;
  if (select count(distinct lower(d.property_number)) from public.pay_dues d where d.id = any(p_ids)) > 1 then
    raise exception 'البنود المختارة تعود لأكثر من عقار — ادفع كل عقار على حدة';
  end if;
  select d.property_number, d.owner_name, d.phone, d.currency
    into v_prop, v_owner, v_phone, v_currency
    from public.pay_dues d where d.id = any(p_ids) limit 1;

  insert into public.pay_orders
    (phone, phone_norm, payer_name, services, property_number, amount, currency)
  values
    (coalesce(v_phone, '—'), coalesce(public.lb_phone_norm(coalesce(v_phone,'')), ''),
     v_owner, v_sel, v_prop, v_amount, v_currency)
  returning id into v_id;

  update public.pay_dues set order_id = v_id where id = any(p_ids);

  return jsonb_build_object('order_id', v_id, 'amount', v_amount, 'currency', v_currency);
end;
$fn$;
grant execute on function public.pay_dues_create_order(uuid[]) to anon, authenticated;

-- ── 3 · pay_book_receipt: العملة بلسانها، والمتوجب يُختم بالإيصال ───────────
create or replace function public.pay_book_receipt(p_order uuid)
returns text language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  v_o      public.pay_orders%rowtype;
  v_year   text;
  v_prefix text := 'Q';
  v_start  int  := 0;
  v_cfg    jsonb;
  v_pre    text;
  v_next   int;
  v_no     text;
  v_cat    text;
  v_desc   text;
begin
  select * into v_o from public.pay_orders where id = p_order for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if v_o.receipt_no is not null then return v_o.receipt_no; end if;   -- idempotent
  if v_o.status <> 'paid' then raise exception 'لا إيصال لطلب غير مدفوع'; end if;

  -- قفل سلسلة القبض — القاعدة نفسها منذ اليوم الأول: الرقم لا يصدر مرتين
  perform pg_advisory_xact_lock(hashtext('sandouk_series_income'));

  v_year := to_char((now() at time zone 'Asia/Beirut')::date, 'YYYY');
  select value into v_cfg from public.settings where key = 'sandouk_series';
  if v_cfg is not null then
    v_prefix := coalesce(nullif(btrim(coalesce(
                  v_cfg->'income'->'years'->v_year->>'prefix',
                  v_cfg->'income'->>'prefix')), ''), 'Q');
    v_start  := coalesce((v_cfg->'income'->'years'->v_year->>'start')::int, 0);
  end if;
  v_pre := v_prefix || '-' || v_year || '-';

  select coalesce(max((substring(receipt_no from length(v_pre)+1))::int), 0)
    into v_next
    from public.baladieh_finance
   where entry_type = 'income'
     and receipt_no like v_pre || '%'
     and substring(receipt_no from length(v_pre)+1) ~ '^[0-9]+$';
  v_next := greatest(v_next + 1, greatest(v_start, 1));
  v_no := v_pre || lpad(v_next::text, 3, '0');

  select case when jsonb_array_length(v_o.services) = 1
              then v_o.services->0->>'label'
              else 'جباية ورسوم بلدية' end
    into v_cat;
  select 'دفع إلكتروني عبر Whish — '
         || string_agg((s->>'label') || ' ('
              || case when v_o.currency = 'LBP'
                      then to_char((s->>'amount')::numeric, 'FM999,999,999,999') || ' ل.ل'
                      else '$' || (s->>'amount') end
              || ')', ' + ')
    into v_desc
    from jsonb_array_elements(v_o.services) s;

  insert into public.baladieh_finance
    (entry_date, entry_type, category, description, amount, stamp_value,
     currency, payment_method, person, receipt_no, property_number,
     notes, created_by)
  values
    ((now() at time zone 'Asia/Beirut')::date, 'income', v_cat, v_desc,
     v_o.amount, 0, v_o.currency, 'whish', v_o.payer_name, v_no,
     v_o.property_number,
     'Whish externalId ' || v_o.external_id
       || coalesce(' · ref ' || v_o.whish_ref, ''),
     'whish-pay');

  update public.pay_orders set receipt_no = v_no where id = p_order;
  -- المتوجب الذي دُفع يُختم بإيصاله — فلا يظهر مستحقاً مرة ثانية
  update public.pay_dues
     set status = 'paid', receipt_no = v_no, paid_at = now()
   where order_id = p_order and status = 'unpaid';
  return v_no;
end;
$fn$;
revoke execute on function public.pay_book_receipt(uuid) from public, anon, authenticated;

-- ── 4 · pay_dues_manage — لكل دور قيمته ─────────────────────────────────────
update public.role_permissions
   set perms = perms || '{"pay_dues_manage":true}'::jsonb, updated_at = now()
 where role in ('super_admin','mayor','admin');
update public.role_permissions
   set perms = perms || '{"pay_dues_manage":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','mayor','admin');

-- ── 5 · بذور التجربة (sandbox) — عقار «dummy» على 03649694 ─────────────────
-- Test rows for the sandbox phase, requested for the record; cleared with the
-- rest of the test data before go-live.
insert into public.pay_dues (property_number, owner_name, phone, year, label, amount, currency)
select 'dummy', 'imad', '+9613649694', y.year, y.label, y.amount, 'LBP'
  from (values (2025, 'جباية ورسوم بلدية', 2300000::numeric),
               (2025, 'رسم تأخير',          100000::numeric),
               (2026, 'جباية ورسوم بلدية', 2300000::numeric)) y(year, label, amount)
 where not exists (select 1 from public.pay_dues where property_number = 'dummy');
