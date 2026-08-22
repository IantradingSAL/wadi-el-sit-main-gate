-- ═══════════════════════════════════════════════════════════════════════════
-- 29 — a decision taken anywhere closes the request everywhere
--
-- `approval_decide()` moves the queue row and the record together, so those two
-- can never disagree. But it is not the only way a decision gets taken:
--
--   · phonebook.html's own admin popup — ✅ تطبيق / ❌ رفض — updates
--     phonebook_pending_edits (and phonebook_entries) directly
--   · the coop admin panel approves a seller by setting coop_sellers.status
--
-- Both are legitimate, both predate the queue, and neither knew about it. So a
-- request decided from one of those screens stayed `pending` in
-- approval_requests: the 🔔 badge kept counting it, and the list kept offering
-- buttons for a decision already taken.
--
-- That matters more since migration 28, because the notification email now
-- sends the reviewer to exactly those screens for a directory item — the popup
-- is the destination, not the fallback.
--
-- The watchers already fire on `update of status`; they only ever looked at the
-- transition INTO 'pending'. Now they also look at the transition OUT of it and
-- mirror the outcome onto the queue row, attributing it honestly: "حُسم من
-- الشاشة الخاصة بالسجل".
--
-- Nothing changes for a decision taken in the queue itself — approval_decide()
-- sets `status` first, so by the time these triggers run the row is no longer
-- 'pending' and the sync is a no-op.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.approval_sync_resolution(p_kind text, p_ref_id text, p_status text)
returns void language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare v_final text;
begin
  v_final := case
    when p_status in ('rejected','declined') then 'rejected'
    when p_status in ('approved','applied','active') then 'approved'
    else null end;
  if v_final is null then return; end if;      -- suspended, draft, anything else: leave it

  update public.approval_requests
     set status        = v_final,
         decided_at    = coalesce(decided_at, now()),
         decided_by    = coalesce(decided_by, auth.uid()),
         decided_email = coalesce(decided_email, (select u.email from auth.users u where u.id = auth.uid())),
         note          = coalesce(note, 'حُسم من الشاشة الخاصة بالسجل')
   where kind = p_kind and ref_id = p_ref_id and status = 'pending';
exception when others then
  raise warning 'approval_sync_resolution(% %): %', p_kind, p_ref_id, sqlerrm;
end;
$fn$;
revoke execute on function public.approval_sync_resolution(text,text,text) from public, anon, authenticated;

-- ── the same four watchers, now listening in both directions ───────────────
-- (bodies identical to migration 28 apart from the new elsif branch)

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

  elsif tg_op = 'UPDATE' and coalesce(new.status,'') is distinct from coalesce(old.status,'') then
    perform public.approval_sync_resolution('phonebook_edit', new.id::text, new.status);
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

  elsif tg_op = 'UPDATE' and coalesce(new.status,'') is distinct from coalesce(old.status,'') then
    perform public.approval_sync_resolution('phonebook_new', new.id::text, new.status);
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_phonebook_entry: %', sqlerrm; return new;
end;
$fn$;

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

  elsif tg_op = 'UPDATE' and coalesce(new.status,'') is distinct from coalesce(old.status,'') then
    perform public.approval_sync_resolution('coop_seller', new.id::text, new.status);
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

  elsif tg_op = 'UPDATE' and coalesce(new.status,'') is distinct from coalesce(old.status,'') then
    perform public.approval_sync_resolution('coop_agent', new.id::text, new.status);
  end if;
  return new;
exception when others then
  raise warning 'approval_tg_coop_agent: %', sqlerrm; return new;
end;
$fn$;

-- Measured on the live project: a pending edit resolved with a plain
--   update phonebook_pending_edits set status='approved'
-- (exactly what the phonebook popup does) left its queue row reading
--   status = approved · note = «حُسم من الشاشة الخاصة بالسجل»
-- where before this migration it would still have read `pending`.
-- The test rows were removed afterwards.
