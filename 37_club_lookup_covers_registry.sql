-- ═══════════════════════════════════════════════════════════════════════════
-- 37 — بحث البطولة يغطي الدليل كله
--
-- «الرقم موجود في الدليل، لماذا لا يظهر؟» — لأن 36 بحثت في phonebook_entries
-- فقط، وأكثر أهل الدليل من السجل (phonebook_registry). البحث الآن يسأل أيضاً
-- phonebook_public() — العرض العلني نفسه الذي يقرأه كل زائر — فيرث خصوصيته
-- حرفياً: الرقم المخفي يعود من الدالة فارغاً فلا يطابق شيئاً، والمقيد
-- entry_hidden لا يخرج منها أصلاً. البحث لا يرى إلا ما يراه أي زائر.
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

  -- الإضافات المعتمدة غير المخفية
  select coalesce(nullif(btrim(coalesce(e.name,'')),''),
                  btrim(coalesce(e.first,'')||' '||coalesce(e.family,'')))
    into v_name
    from public.phonebook_entries e
   where e.status = 'approved'
     and coalesce(e.entry_hidden, false) = false
     and coalesce(e.phone_hidden, false) = false
     and public.lb_phone_norm(e.phone) = n
   limit 1;

  -- أهل السجل، كما يعرضهم الدليل العلني حرفياً — رقم مخفي لا يطابق شيئاً
  if v_name is null or btrim(v_name) = '' then
    select coalesce(nullif(btrim(coalesce(p.name,'')),''),
                    btrim(coalesce(p.first,'')||' '||coalesce(p.family,'')))
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
