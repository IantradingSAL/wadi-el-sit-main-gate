-- ═══════════════════════════════════════════════════════════════════════════
-- 38 — البحث يعيد الاسم الثلاثي
--
-- «Imad» وحدها لا تكفي بطاقة بطولة ولا جدول شاشة: المطلوب الاسم الثلاثي —
-- الاسم واسم الأب والعائلة — متى كانت الأجزاء موجودة في الدليل، والاسم
-- المخزون كما هو حين لا تكون. نفس مصادر 37 ونفس خصوصيتها حرفياً.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.club_phone_lookup(p_phone text)
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
declare
  n text := public.lb_phone_norm(p_phone);
  v_name text;
begin
  if coalesce(n,'') = '' or length(n) < 7 then
    return jsonb_build_object('found', false);
  end if;

  -- الإضافات المعتمدة غير المخفية — الاسم الثلاثي إن وُجدت أجزاؤه
  select case
           when coalesce(btrim(e.first),'') <> '' and coalesce(btrim(e.family),'') <> ''
           then btrim(concat_ws(' ', nullif(btrim(e.first),''), nullif(btrim(e.father),''), nullif(btrim(e.family),'')))
           else nullif(btrim(coalesce(e.name,'')),'')
         end
    into v_name
    from public.phonebook_entries e
   where e.status = 'approved'
     and coalesce(e.entry_hidden, false) = false
     and coalesce(e.phone_hidden, false) = false
     and public.lb_phone_norm(e.phone) = n
   limit 1;

  -- أهل السجل، من العرض العلني نفسه — بالثلاثي أيضاً
  if v_name is null or btrim(v_name) = '' then
    select case
             when coalesce(btrim(p.first),'') <> '' and coalesce(btrim(p.family),'') <> ''
             then btrim(concat_ws(' ', nullif(btrim(p.first),''), nullif(btrim(p.father),''), nullif(btrim(p.family),'')))
             else nullif(btrim(coalesce(p.name,'')),'')
           end
      into v_name
      from public.phonebook_public() p
     where public.lb_phone_norm(p.phone) = n
        or public.lb_phone_norm(p.wa) = n
     limit 1;
  end if;

  if v_name is null or btrim(v_name) = '' then
    return jsonb_build_object('found', false);
  end if;
  return jsonb_build_object('found', true, 'name', v_name);
end;
$fn$;
grant execute on function public.club_phone_lookup(text) to anon, authenticated;
