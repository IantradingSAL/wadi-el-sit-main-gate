-- ═══════════════════════════════════════════════════════════════════════════
-- 36 — التسجيل في البطولة يتعارف مع الدليل
--
-- On games.html, typing a phone number now asks the directory who this is:
--   · found → the name appears by itself (editable, but pre-filled).
--   · not found → the form asks «هل أنت من وادي الست؟». A YES queues a new
--     PENDING directory entry through the same pipeline every public addition
--     takes (approval_requests, the reviewers' channels, approval_decide) —
--     the tournament registration itself NEVER waits for that validation.
--     A NO adds nothing to the dalil at all: non-residents play, but are not
--     listed, and the directory is never even opened for them.
--
-- Privacy is the dalil's own: the lookup answers ONLY for entries the public
-- directory already shows — status approved, entry not hidden, phone not
-- hidden — and never touches the civil registry. Matching a hidden person's
-- phone reveals nothing.
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
  select coalesce(nullif(btrim(coalesce(e.name,'')),''),
                  btrim(coalesce(e.first,'')||' '||coalesce(e.family,'')))
    into v_name
    from public.phonebook_entries e
   where e.status = 'approved'
     and coalesce(e.entry_hidden, false) = false
     and coalesce(e.phone_hidden, false) = false
     and public.lb_phone_norm(e.phone) = n
   limit 1;
  if v_name is null or btrim(v_name) = '' then
    return jsonb_build_object('found', false);
  end if;
  return jsonb_build_object('found', true, 'name', v_name);
end;
$fn$;
grant execute on function public.club_phone_lookup(text) to anon, authenticated;

-- «من وادي الست» يقول نعم → يدخل الدليل معلَّقاً حتى يتحقق منه المراجعون،
-- عبر نفس مسار الإضافة العلنية: المُشغّل يملأ طابور التحقق ويُبلغ أصحابه.
create or replace function public.club_dalil_submit(p_name text, p_phone text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $fn$
declare
  n text := public.lb_phone_norm(p_phone);
begin
  if coalesce(btrim(p_name),'') = '' then return jsonb_build_object('queued', false); end if;
  if coalesce(n,'') = '' or length(n) < 7 then return jsonb_build_object('queued', false); end if;

  -- already known (approved or already waiting) → nothing to add
  if exists (select 1 from public.phonebook_entries e
              where e.status in ('approved','pending')
                and public.lb_phone_norm(e.phone) = n) then
    return jsonb_build_object('queued', false, 'reason', 'exists');
  end if;

  insert into public.phonebook_entries
    (mun_id, name, phone, submitter_name, submitter_phone, status, source, is_wadi_citizen)
  values
    ('00000000-0000-0000-0000-000000000001', btrim(p_name), btrim(p_phone),
     btrim(p_name), btrim(p_phone), 'pending', 'games', true);
  return jsonb_build_object('queued', true);
exception when others then
  -- the dalil must never break a tournament registration
  raise warning 'club_dalil_submit: %', sqlerrm;
  return jsonb_build_object('queued', false);
end;
$fn$;
grant execute on function public.club_dalil_submit(text,text) to anon, authenticated;
