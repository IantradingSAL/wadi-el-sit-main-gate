-- ═══════════════════════════════════════════════════════════════════════════
-- 28 — the notification says WHOSE record, and WHAT changes
--
-- The first version of the email named the person who *submitted* the request:
--
--     تعديل مقترح على جهة في الدليل — من IMAD
--     هاتفه: 03649694 · نوع الهدف: registry · الحقول المقترَحة: occupation
--
-- which tells a reviewer almost nothing. Whose record is it? What is being
-- corrected, from what to what? All of it was sitting one query away, and the
-- phonebook's own review panel was already showing it (المهنة (قديم) → جديد).
--
-- So the trigger now resolves the subject of the change and puts the whole
-- answer in the notice:
--
--     تعديل بيانات: ايلي حارس ابي شهلا (سجل #311)
--     صاحب السجل: ايلي حارس ابي شهلا · هاتفه المسجَّل: +961 71 610 031
--     المطلوب تعديله: المهنة
--     ✏️ المهنة:  —  ←  موظف
--
-- and stores a link straight to that person's card in the directory, so the
-- email lands on the record rather than on a queue.
--
-- Phone numbers in every notice follow the same Lebanese rule the browser uses
-- (number-format.js): the national trunk 0 is dropped after +961 and the rest
-- is grouped by its real length.
-- ═══════════════════════════════════════════════════════════════════════════

-- ☎️ the same rule as number-format.js, in SQL
create or replace function public.lb_phone_display(p text)
returns text language plpgsql immutable
set search_path = public, pg_temp as $fn$
declare d text; nsn text; head text; body text;
begin
  if coalesce(btrim(p),'') = '' then return null; end if;
  d := translate(p, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  if left(btrim(d),1) = '+' and left(regexp_replace(btrim(d),'[^0-9]','','g'),3) <> '961' then
    return btrim(d);                          -- a genuinely foreign number, untouched
  end if;
  d := regexp_replace(d, '[^0-9]', '', 'g');
  nsn := regexp_replace(regexp_replace(d, '^00', ''), '^961', '');
  nsn := regexp_replace(nsn, '^0+', '');
  if length(nsn) not in (7,8) then return btrim(p); end if;
  head := case when length(nsn) = 8 then left(nsn,2) else left(nsn,1) end;
  body := substr(nsn, length(head)+1);
  return '+961 ' || head || ' ' || left(body,3) || ' ' || substr(body,4);
end;
$fn$;

-- الأسماء العربية للحقول، كي يقرأ البريد كجملة لا كأعمدة قاعدة بيانات
create or replace function public.approval_field_label(p text)
returns text language sql immutable
set search_path = public, pg_temp as $fn$
  select coalesce(
    (case p
      when 'name' then 'الاسم'            when 'first' then 'الاسم الأول'
      when 'family' then 'العائلة'         when 'father' then 'اسم الأب'
      when 'mother' then 'اسم الأم'        when 'phone' then 'الهاتف'
      when 'wa' then 'واتساب'              when 'email' then 'البريد الإلكتروني'
      when 'occupation' then 'المهنة'      when 'address' then 'العنوان'
      when 'work_phone' then 'هاتف العمل'  when 'work_address' then 'عنوان العمل'
      when 'notes' then 'ملاحظات'          when 'image' then 'الصورة'
      when 'lat' then 'خط العرض'           when 'lng' then 'خط الطول'
      when 'work_lat' then 'خط عرض العمل'  when 'work_lng' then 'خط طول العمل'
      when 'phone_hidden' then 'إخفاء الهاتف'     when 'address_hidden' then 'إخفاء العنوان'
      when 'email_hidden' then 'إخفاء البريد'      when 'entry_hidden' then 'إخفاء الجهة'
      when 'disable_call' then 'تعطيل الاتصال'     when 'disable_wa' then 'تعطيل واتساب'
      when 'bdate' then 'تاريخ الولادة'
      else null end), p);
$fn$;

-- من هو صاحب السجل، وأين تُفتح بطاقته
create or replace function public.approval_pb_person(
  p_target_type text, p_ref_id integer, p_entry uuid,
  out person_name text, out person_phone text, out person_link text)
language plpgsql stable security definer
set search_path = public, pg_temp as $fn$
begin
  if p_target_type = 'registry' then
    select r.name, r.phone into person_name, person_phone
      from public.phonebook_registry r where r.id = p_ref_id;
    person_link := 'phonebook.html#contact=' || coalesce(p_ref_id::text,'');
  else
    select e.name, e.phone into person_name, person_phone
      from public.phonebook_entries e where e.id = p_entry;
    person_link := 'phonebook.html#contact=' || coalesce(p_entry::text,'');
  end if;
end;
$fn$;

-- قديم ← جديد، حقلاً حقلاً، بأسماء عربية وأرقام هاتف مُنسّقة
create or replace function public.approval_changes(p_original jsonb, p_proposed jsonb)
returns jsonb language sql stable
set search_path = public, pg_temp as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'field', public.approval_field_label(k),
           'from',  case when k in ('phone','wa','work_phone')
                         then coalesce(public.lb_phone_display(coalesce(p_original->>k,'')), '—')
                         else coalesce(nullif(btrim(coalesce(p_original->>k,'')),''), '—') end,
           'to',    case when k in ('phone','wa','work_phone')
                         then coalesce(public.lb_phone_display(coalesce(p_proposed->>k,'')), '—')
                         else coalesce(nullif(btrim(coalesce(p_proposed->>k,'')),''), '—') end)
           order by k), '[]'::jsonb)
  from jsonb_object_keys(coalesce(p_proposed,'{}'::jsonb)) k
  where coalesce(p_original->>k,'') is distinct from coalesce(p_proposed->>k,'');
$fn$;

-- ── the phonebook watchers, now saying WHO and WHAT ────────────────────────
create or replace function public.approval_tg_phonebook_edit()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_name text; v_phone text; v_link text; v_title text;
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then

    select person_name, person_phone, person_link
      into v_name, v_phone, v_link
      from public.approval_pb_person(new.target_type, new.ref_id, new.target_entry_id);

    v_title := 'تعديل بيانات: ' || coalesce(nullif(btrim(coalesce(v_name,'')),''), 'جهة في الدليل')
               || case when new.target_type = 'registry' and new.ref_id is not null
                       then ' (سجل #' || new.ref_id || ')' else '' end;

    perform public.approval_enqueue(
      'phonebook_edit', 'phonebook_pending_edits', new.id::text,
      v_title,
      jsonb_strip_nulls(jsonb_build_object(
        'صاحب السجل', v_name,
        'هاتفه المسجَّل', public.lb_phone_display(v_phone),
        'المطلوب تعديله', (select string_agg(public.approval_field_label(k), '، ' order by k)
                             from jsonb_object_keys(coalesce(new.proposed,'{}'::jsonb)) k),
        'مقدّم الطلب', new.submitter_name,
        'هاتف مقدّم الطلب', public.lb_phone_display(new.submitter_phone),
        'السبب', new.reason,
        '__changes', nullif(public.approval_changes(new.original, new.proposed), '[]'::jsonb))),
      v_link);
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_phonebook_edit: %', sqlerrm; return new;
end;
$fn$;

create or replace function public.approval_tg_phonebook_entry()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'phonebook_new', 'phonebook_entries', new.id::text,
      'جهة جديدة: ' || coalesce(nullif(btrim(coalesce(new.name,'')),''),
                                btrim(coalesce(new.first,'')||' '||coalesce(new.family,''))),
      jsonb_strip_nulls(jsonb_build_object(
        'الاسم', new.name, 'العائلة', new.family,
        'الهاتف', public.lb_phone_display(new.phone),
        'المهنة', new.occupation, 'العنوان', new.address,
        'هاتف العمل', public.lb_phone_display(new.work_phone),
        'عنوان العمل', new.work_address,
        'البريد الإلكتروني', new.email,
        'أضافها', new.submitter_name,
        'هاتف المُضيف', public.lb_phone_display(new.submitter_phone),
        'المصدر', new.source)),
      'phonebook.html#contact=' || new.id::text);
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_phonebook_entry: %', sqlerrm; return new;
end;
$fn$;

-- الأرقام في تبليغات التعاونية والحسابات تتبع الصيغة نفسها
create or replace function public.approval_tg_coop_seller()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'coop_seller', 'coop_sellers', new.id::text,
      coalesce(new.display_name, new.username, new.phone, 'بائع جديد'),
      jsonb_strip_nulls(jsonb_build_object(
        'اسم العرض', new.display_name, 'اسم المستخدم', new.username,
        'الهاتف', public.lb_phone_display(new.phone),
        'واتساب', public.lb_phone_display(new.whatsapp),
        'المنطقة', new.area, 'النشاط', new.bio, 'البريد', new.email)),
      'coop.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_coop_seller: %', sqlerrm; return new;
end;
$fn$;

create or replace function public.approval_tg_coop_agent()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  if coalesce(new.status,'pending') = 'pending'
     and (tg_op = 'INSERT' or coalesce(old.status,'') is distinct from 'pending') then
    perform public.approval_enqueue(
      'coop_agent', 'coop_delivery_agents', new.id::text,
      coalesce(new.name, new.phone, 'عامل توصيل جديد'),
      jsonb_strip_nulls(jsonb_build_object(
        'الاسم', new.name,
        'الهاتف', public.lb_phone_display(new.phone),
        'واتساب', public.lb_phone_display(new.whatsapp),
        'المنطقة', new.area, 'وسيلة النقل', new.vehicle, 'ملاحظات', new.notes)),
      'coop.html');
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_coop_agent: %', sqlerrm; return new;
end;
$fn$;

-- الحساب الجديد يُعرَّف باسم صاحبه إن وُجد، لا ببريده وحده
create or replace function public.approval_tg_new_user()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $fn$
begin
  perform public.approval_enqueue(
    'user_account', 'auth.users', new.id::text,
    coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', new.email, 'حساب جديد'),
    jsonb_strip_nulls(jsonb_build_object(
      'البريد', new.email,
      'الاسم', coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name'),
      'الهاتف', public.lb_phone_display(new.raw_user_meta_data->>'phone'),
      'طريقة التسجيل', coalesce(new.raw_app_meta_data->>'provider', 'email'))),
    'dashboard.html');
  return new;
exception when others then
  raise warning 'approval_tg_new_user: %', sqlerrm; return new;
end;
$fn$;

-- Measured on the live project before committing:
--
--   approval_pb_person('registry', 311, null)
--     → ايلي حارس ابي شهلا · +96171610031 · phonebook.html#contact=311
--   lb_phone_display('03649694')            → +961 3 649 694
--   approval_changes(occupation ''→'موظف',
--                    phone '03649694'→'70123456')
--     → [{المهنة: — ← موظف}, {الهاتف: +961 3 649 694 ← +961 70 123 456}]
