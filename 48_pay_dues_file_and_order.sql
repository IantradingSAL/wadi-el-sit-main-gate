-- ═══════════════════════════════════════════════════════════════════════════
-- 48 — الجباية: ملف المكلّف، والدفع من الأقدم إلى الأحدث
--
-- Migration 47 keyed a due on رقم العقار alone. The real تكليف does not:
-- عقار 18 carries two مكلّفين (قسم ١ و٢، رقمان ٨٦ و٨٧), and عقار 54 carries
-- three. Keyed on the property alone, a lookup mixes two families' debts into
-- one list and one payment — the wrong name on the receipt, and each of them
-- reading the other's balance.
--
-- So a due now belongs to a **ملف مكلّف**: رقم العقار + رقم المكلّف. The key is
-- generated, never typed, so it cannot drift from the two columns it is made of.
--
--   unit         بلوك وطابق وشقة, as the تكليف prints it («/ ٠ / ١»)
--   taxpayer_no  رقم المكلّف — unique inside the property, not across the town
--   detail       ما يتألف منه المبلغ: «ر. قيمة تأجيرية ١٬٤٠٠٬٠٠٠ + ر. صيانة ٨٤٠٬٠٠٠»
--   file_key     generated: <taxpayer_no>@<property_number>
--
-- And the rule the municipality asked for: **الأقدم أولاً**. A citizen may pay
-- one year, or three, or all — but never 2026 while 2019 is still open. The
-- browser orders the list; this function is what actually refuses, because a
-- rule that lives only in the page is not a rule.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 0 · ملف المكلّف ─────────────────────────────────────────────────────────
alter table public.pay_dues add column if not exists unit        text;
alter table public.pay_dues add column if not exists taxpayer_no text;
alter table public.pay_dues add column if not exists detail      text;
alter table public.pay_dues
  add column if not exists file_key text
  generated always as (
    coalesce(nullif(btrim(taxpayer_no), ''), '-') || '@' || lower(btrim(property_number))
  ) stored;
create index if not exists pay_dues_file_idx on public.pay_dues(file_key, year);

-- ── 1 · نافذة المواطن — ملفات مرتّبة، وكل ملف سنواته من الأقدم ─────────────
-- Same three identifiers as before (عقار · هاتف · اسم); what changes is that
-- the answer is grouped, so the page can never put two مكلّفين in one basket.
create or replace function public.pay_dues_lookup(p_q text)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
declare
  v_q     text := btrim(coalesce(p_q,''));
  v_norm  text := public.lb_phone_norm(v_q);
  v_num   boolean := v_q ~ '^[0-9+ ()-]+$';
  v_files jsonb;
begin
  -- عقار «0» و«18» رقمان حقيقيان في هذا التكليف: شرط الأحرف الثلاثة كان
  -- يمنع خُمس البلدة من إيجاد جبايتها. الرقم يُطابَق تماماً فلا يكشف غيره؛
  -- الاسم وحده هو ما يبقى محتاجاً ثلاثة أحرف حتى لا يتحوّل البحث إلى جرد.
  if v_q = '' or (not v_num and length(v_q) < 3) then
    return jsonb_build_object('found', false);
  end if;

  with hit as (
    select d.*
      from public.pay_dues d
     where d.status = 'unpaid'
       and ( lower(d.property_number) = lower(v_q)
          or (v_norm <> '' and length(v_norm) >= 6 and d.phone_norm = v_norm)
          or (not v_num and d.owner_name ilike '%' || v_q || '%') )
  ), grouped as (
    select h.file_key,
           min(h.property_number) as property_number,
           min(h.owner_name)      as owner_name,
           min(h.taxpayer_no)     as taxpayer_no,
           min(h.unit)            as unit,
           min(h.currency)        as currency,
           sum(h.amount)          as total,
           min(h.year)            as oldest_year,
           jsonb_agg(jsonb_build_object(
             'id', h.id, 'year', h.year, 'label', h.label,
             'detail', h.detail, 'amount', h.amount, 'currency', h.currency)
             order by h.year, h.label) as dues
      from hit h
     group by h.file_key
  )
  select jsonb_agg(jsonb_build_object(
           'file_key', g.file_key, 'property_number', g.property_number,
           'owner_name', g.owner_name, 'taxpayer_no', g.taxpayer_no,
           'unit', g.unit, 'currency', g.currency, 'total', g.total,
           'dues', g.dues)
         order by g.property_number, g.taxpayer_no)
    into v_files
    from grouped g;

  if v_files is null then
    return jsonb_build_object('found', false);
  end if;
  -- 'dues' البنود مسطّحة أيضاً: نسخة 47 من الصفحة ما زالت تقرأها ولا تنكسر
  return jsonb_build_object(
    'found', true, 'files', v_files,
    'dues', (select jsonb_agg(d order by (d->>'year')::int)
               from jsonb_array_elements(v_files) f,
                    jsonb_array_elements(f->'dues') d));
end;
$fn$;
grant execute on function public.pay_dues_lookup(text) to anon, authenticated;

-- ── 2 · من المتوجب إلى الطلب — ملف واحد، ومن الأقدم ─────────────────────────
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
  v_file     text;
  v_maxyear  int;
  v_older    record;
  v_sel      jsonb;
  v_id       uuid;
begin
  if p_ids is null or array_length(p_ids,1) is null then
    raise exception 'اختر بنداً واحداً على الأقل';
  end if;

  select count(*), sum(d.amount), max(d.year),
         jsonb_agg(jsonb_build_object(
           'key', 'due-' || d.year, 'due_id', d.id,
           'label', d.label || ' ' || d.year, 'amount', d.amount)
           order by d.year, d.label)
    into v_n, v_amount, v_maxyear, v_sel
    from public.pay_dues d
   where d.id = any(p_ids) and d.status = 'unpaid'
     and (d.order_id is null
          or exists (select 1 from public.pay_orders o
                      where o.id = d.order_id
                        and o.status in ('failed','cancelled','expired')));
  if v_n is distinct from array_length(p_ids,1) then
    raise exception 'أحد البنود مدفوع أو قيد الدفع — حدّث الاستعلام وأعد المحاولة';
  end if;
  if (select count(distinct d.currency) from public.pay_dues d where d.id = any(p_ids)) > 1 then
    raise exception 'لا يمكن جمع عملتين في دفعة واحدة';
  end if;
  -- ملف واحد لكل دفعة: إيصال باسم صاحبه، لا باسم جاره على العقار نفسه
  if (select count(distinct d.file_key) from public.pay_dues d where d.id = any(p_ids)) > 1 then
    raise exception 'البنود المختارة تعود لأكثر من مكلّف — ادفع كل مكلّف على حدة';
  end if;
  select d.file_key into v_file
    from public.pay_dues d where d.id = any(p_ids) limit 1;

  -- الأقدم أولاً: لا تُدفع سنة وتُترك سنة أقدم منها معلّقة
  select d.year, d.label into v_older
    from public.pay_dues d
   where d.file_key = v_file
     and d.status = 'unpaid'
     and d.year < v_maxyear
     and not (d.id = any(p_ids))
   order by d.year
   limit 1;
  if found then
    raise exception 'يجب تسديد % % أولاً — الدفع يبدأ من أقدم سنة مستحقة',
      v_older.label, v_older.year;
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

-- ── 3 · شاشة الجباية في الصندوق تقرأ المجاميع من القاعدة ────────────────────
-- One row per ملف مكلّف for 💰 الجباية in sandouk.html: what is owed, what was
-- collected, and the oldest year still open — the column the collector works by.
create or replace function public.pay_dues_files()
returns table (
  file_key text, property_number text, taxpayer_no text, unit text,
  owner_name text, phone text, currency text,
  years_unpaid int, oldest_year int, newest_year int,
  due_total numeric, paid_total numeric, last_receipt text
) language sql stable security definer
set search_path = public, pg_temp as $fn$
  select d.file_key,
         min(d.property_number), min(d.taxpayer_no), min(d.unit),
         min(d.owner_name), min(d.phone), min(d.currency),
         count(*) filter (where d.status = 'unpaid')::int,
         min(d.year) filter (where d.status = 'unpaid'),
         max(d.year) filter (where d.status = 'unpaid'),
         coalesce(sum(d.amount) filter (where d.status = 'unpaid'), 0),
         coalesce(sum(d.amount) filter (where d.status = 'paid'), 0),
         (array_agg(d.receipt_no order by d.paid_at desc nulls last)
            filter (where d.receipt_no is not null))[1]
    from public.pay_dues d
   where public.has_perm('pay_dues_manage')     -- نفس مفتاح الجدول، لا نافذة جانبية
     and d.status <> 'cancelled'
   group by d.file_key
$fn$;
revoke execute on function public.pay_dues_files() from public, anon;
grant execute on function public.pay_dues_files() to authenticated;
