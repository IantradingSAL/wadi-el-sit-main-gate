-- ═══════════════════════════════════════════════════════════════════════════
-- 23_phonebook_privacy_enforced.sql — applied to the live project on 2026-08-21
--
-- The directory's privacy switches start working.
--
-- WHAT WAS BROKEN
-- Every per-person control in the phonebook — «إخفاء الجهة بالكامل», the phone
-- mode (كلاهما / اتصال فقط / واتساب فقط / إخفاء الرقم) and «إخفاء العنوان» —
-- is stored in `phonebook_extras`. The page reads that table directly and
-- decides in JavaScript which buttons to draw. But the table's read policy is
--
--     extras_select_public   SELECT   TO anon, authenticated
--                            USING (auth.uid() IS NOT NULL)
--
-- Named "public"; allows nobody anonymous. So for an ordinary visitor — which
-- is every resident, the directory has no login — the overlay came back empty
-- and every flag evaluated to false. A person who had asked not to be called,
-- not to be messaged on WhatsApp, or not to appear at all got the call button,
-- the WhatsApp button and their row anyway. The switch in the admin screen
-- moved, the database recorded it, and the public page ignored it.
--
-- Migration 22 fixed exactly this for the 601-row registry: phonebook_public()
-- applies entry_hidden / phone_hidden / address_hidden in SQL. What it did not
-- do is return the REST of the settings — disable_call, disable_wa — or any of
-- the extras the page shows (occupation, photo, work details, map pin). So the
-- registry stopped leaking hidden people, but the finer controls, and several
-- legitimate features, still depended on a table the visitor cannot read.
--
-- The user-added half of the directory, `phonebook_entries`, was worse: anon
-- reads the table row by row, so `phone_hidden` was pure decoration there, and
-- two overlapping SELECT policies meant
--     entries_select_public   USING (status IN ('approved','pending'))
-- overrode the sibling policy that checked entry_hidden — permissive policies
-- are OR-ed. Hidden entries, and entries still waiting for review, were both
-- readable by anyone with curl.
--
-- WHAT THIS DOES
--   1. `phonebook_public()` now returns the whole public projection of a
--      registry person — the extras overlay included — with every mask applied
--      in SQL. The page no longer needs `phonebook_extras` to render.
--   2. `phonebook_added_public()` does the same for the user-added entries,
--      and the raw table stops being readable by anon.
--   3. `phonebook_entries_full()` gives the unmasked rows to staff holding
--      `phonebook_edit` — the admin queues and the un-hide screen.
--   4. `phonebook_submit_entry()` replaces the anon INSERT. It whitelists the
--      columns a visitor may set, forces status='pending' and
--      source='user_added', and returns the new id so the page can still show
--      «قيد المراجعة» to the person who submitted it.
--   5. `phonebook_extras` becomes staff-only to read, matching its write
--      policy. Nothing else needs it: everyone else gets the masked projection.
--
-- A NEW SWITCH: email_hidden
-- The controls covered the phone and the address but not the email, and the
-- resident who prompted this asked for exactly that — «لا أريد بريداً». It is a
-- sibling of phone_hidden and address_hidden on both tables, applied in the
-- same place, and it is offered to the person submitting their own entry
-- rather than only to an administrator.
--
-- TWO COLUMNS THAT WERE MISSING
-- `phonebook_entries` has no `father` / `mother`, but the add form sends them.
-- The insert failed on the unknown column, the page fell through its own
-- "older schema" retry ladder to a bare payload, and every submission silently
-- lost its occupation, email, address, work details and notes. The columns are
-- added here and the RPC writes the full payload.
--
-- WHAT IS DELIBERATELY NOT CHANGED
-- No row is deleted and no flag is flipped. The 601 registry rows, the 11
-- overlays and the 8 user-added entries are all untouched — this migration
-- changes who may read them, not what they say.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the missing columns ───────────────────────────────────────────────────
alter table public.phonebook_extras  add column if not exists email_hidden boolean not null default false;
alter table public.phonebook_entries add column if not exists email_hidden boolean not null default false;
alter table public.phonebook_entries add column if not exists father text;
alter table public.phonebook_entries add column if not exists mother text;

comment on column public.phonebook_extras.email_hidden is
  'The person asked not to be emailed. phonebook_public() returns an empty email when it is set.';
comment on column public.phonebook_entries.email_hidden is
  'The person asked not to be emailed. phonebook_added_public() returns an empty email when it is set.';

-- ── the public projection of a registry person ────────────────────────────
-- The overlay is applied from an APPROVED extras row only; the masks are
-- applied from any extras row whatever its status. Hiding early is safe,
-- publishing early is not.
drop function if exists public.phonebook_public();
create function public.phonebook_public()
returns table (
  id int, name text, first text, family text, father text, mother text,
  phone text, wa text, cc text, address text,
  occupation text, email text, image text, lat numeric, lng numeric,
  work_phone text, work_address text, work_lat numeric, work_lng numeric,
  phone_hidden boolean, address_hidden boolean, email_hidden boolean,
  disable_call boolean, disable_wa boolean
)
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  with j as (
    select r.*,
           coalesce(x.phone_hidden,   false) as f_phone_hidden,
           coalesce(x.address_hidden, false) as f_address_hidden,
           coalesce(x.email_hidden,   false) as f_email_hidden,
           coalesce(x.disable_call,   false) as f_disable_call,
           coalesce(x.disable_wa,     false) as f_disable_wa,
           case when coalesce(x.status,'approved') = 'approved' then x end as ok
      from public.phonebook_registry r
      left join public.phonebook_extras x on x.ref_id = r.id
     where not coalesce(x.entry_hidden,     false)
       and not coalesce(x.deleted_by_admin, false)
  )
  select j.id, j.name, j.first, j.family, j.father, j.mother,
         case when j.f_phone_hidden then '' else coalesce((j.ok).phone, j.phone) end,
         case when j.f_phone_hidden or j.f_disable_wa then '' else j.wa end,
         j.cc,
         case when j.f_address_hidden then '' else coalesce((j.ok).address, j.address) end,
         (j.ok).occupation,
         case when j.f_email_hidden then '' else (j.ok).email end,
         (j.ok).image,
         case when j.f_address_hidden then null else (j.ok).lat end,
         case when j.f_address_hidden then null else (j.ok).lng end,
         (j.ok).work_phone, (j.ok).work_address, (j.ok).work_lat, (j.ok).work_lng,
         j.f_phone_hidden, j.f_address_hidden, j.f_email_hidden,
         j.f_disable_call, j.f_disable_wa
    from j;
$$;

-- ── the public projection of a user-added entry ───────────────────────────
drop function if exists public.phonebook_added_public();
create function public.phonebook_added_public()
returns table (
  id uuid, name text, first text, family text, father text, mother text,
  phone text, wa text, cc text, address text,
  occupation text, email text, image text, lat numeric, lng numeric, notes text,
  work_phone text, work_address text, work_lat numeric, work_lng numeric,
  phone_hidden boolean, address_hidden boolean, email_hidden boolean,
  disable_call boolean, disable_wa boolean,
  is_wadi_citizen boolean, status text, created_at timestamptz
)
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  select e.id, e.name, e.first, e.family, e.father, e.mother,
         case when coalesce(e.phone_hidden,false) then '' else e.phone end,
         case when coalesce(e.phone_hidden,false) or coalesce(e.disable_wa,false) then '' else e.wa end,
         e.cc,
         case when coalesce(e.address_hidden,false) then '' else e.address end,
         e.occupation,
         case when coalesce(e.email_hidden,false) then '' else e.email end,
         e.image,
         case when coalesce(e.address_hidden,false) then null else e.lat end,
         case when coalesce(e.address_hidden,false) then null else e.lng end,
         e.notes,
         e.work_phone, e.work_address, e.work_lat, e.work_lng,
         coalesce(e.phone_hidden,false), coalesce(e.address_hidden,false),
         coalesce(e.email_hidden,false),
         coalesce(e.disable_call,false), coalesce(e.disable_wa,false),
         coalesce(e.is_wadi_citizen,false), e.status, e.created_at
    from public.phonebook_entries e
   where e.status = 'approved'
     and not coalesce(e.entry_hidden, false);
$$;

-- ── the unmasked rows, for staff who administer the directory ─────────────
create or replace function public.phonebook_entries_full()
returns setof public.phonebook_entries
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  select e.* from public.phonebook_entries e
   where public.has_perm('phonebook_edit');
$$;

-- ── a visitor submitting themselves ───────────────────────────────────────
-- Replaces the anon INSERT policy, which let anyone write any column: status,
-- source, approved_by and is_wadi_citizen included. This whitelists the fields
-- a person may set about themselves, and returns the id so the page can keep
-- showing them their own submission while it waits for review.
create or replace function public.phonebook_submit_entry(p jsonb)
returns uuid
language plpgsql security definer
set search_path to 'public','pg_temp'
as $$
declare v_id uuid;
begin
  if coalesce(btrim(p->>'name'), '') = '' then
    raise exception 'الاسم مطلوب';
  end if;
  if coalesce(btrim(p->>'phone'), '') = '' then
    raise exception 'رقم الهاتف مطلوب';
  end if;

  insert into public.phonebook_entries (
    mun_id, name, first, family, father, mother,
    phone, wa, cc, email, occupation, address, lat, lng, image, notes,
    work_phone, work_address, work_lat, work_lng,
    submitter_name, submitter_phone,
    phone_hidden, address_hidden, email_hidden, disable_call, disable_wa,
    status, source
  ) values (
    coalesce(nullif(p->>'mun_id','')::uuid, '00000000-0000-0000-0000-000000000001'::uuid),
    left(btrim(p->>'name'), 160),
    left(p->>'first', 80),        left(p->>'family', 80),
    left(p->>'father', 80),       left(p->>'mother', 80),
    left(btrim(p->>'phone'), 32), left(p->>'wa', 32), left(p->>'cc', 8),
    left(p->>'email', 160),       left(p->>'occupation', 120),
    left(p->>'address', 240),
    nullif(p->>'lat','')::numeric, nullif(p->>'lng','')::numeric,
    left(p->>'image', 400),       left(p->>'notes', 600),
    left(p->>'work_phone', 32),   left(p->>'work_address', 240),
    nullif(p->>'work_lat','')::numeric, nullif(p->>'work_lng','')::numeric,
    left(p->>'submitter_name', 120), left(p->>'submitter_phone', 32),
    coalesce((p->>'phone_hidden')::boolean,   false),
    coalesce((p->>'address_hidden')::boolean, false),
    coalesce((p->>'email_hidden')::boolean,   false),
    coalesce((p->>'disable_call')::boolean,   false),
    coalesce((p->>'disable_wa')::boolean,     false),
    'pending', 'user_added'
  ) returning id into v_id;

  return v_id;
end;
$$;

-- ── who may read the tables themselves ────────────────────────────────────
-- phonebook_extras: staff only, matching its own write policy. The masked
-- projection above is what everyone else gets.
drop policy if exists extras_select_public on public.phonebook_extras;
drop policy if exists extras_select_staff  on public.phonebook_extras;
create policy extras_select_staff on public.phonebook_extras
  for select to authenticated
  using (public.has_perm('phonebook_edit'));

-- phonebook_entries: the two overlapping anon policies go. Permissive policies
-- are OR-ed, so the one that checked entry_hidden was cancelled out by the one
-- that did not.
drop policy if exists entries_select_public   on public.phonebook_entries;
drop policy if exists phonebook_public_read   on public.phonebook_entries;
drop policy if exists entries_insert_public   on public.phonebook_entries;
drop policy if exists entries_select_staff    on public.phonebook_entries;
create policy entries_select_staff on public.phonebook_entries
  for select to authenticated
  using (public.has_perm('phonebook_edit'));

-- ── grants ────────────────────────────────────────────────────────────────
-- Supabase grants every newly created function to anon by default, so the
-- revoke has to name anon explicitly, not only PUBLIC. Migration 22 learned
-- this the hard way with phonebook_registry_full().
revoke execute on function public.phonebook_public()          from public;
revoke execute on function public.phonebook_added_public()    from public;
revoke execute on function public.phonebook_entries_full()    from public, anon;
revoke execute on function public.phonebook_submit_entry(jsonb) from public;

grant  execute on function public.phonebook_public()          to anon, authenticated;
grant  execute on function public.phonebook_added_public()    to anon, authenticated;
grant  execute on function public.phonebook_entries_full()    to authenticated;
grant  execute on function public.phonebook_submit_entry(jsonb) to anon, authenticated;

-- Measured after applying.
--
-- As anon (`set role anon`):
--   phonebook_extras   direct select                 0 rows — staff-only now,
--                                                    rather than a policy that
--                                                    named nobody
--   phonebook_entries  direct select                 0 rows
--   phonebook_registry direct select                 0 rows
--   phonebook_public()                             601 rows
--   phonebook_added_public()                         7 of the 8 entries — the
--                                                    eighth is the person who
--                                                    had asked to be hidden and
--                                                    was being served anyway
--
-- Masking, proved on three throwaway rows inside a transaction that was rolled
-- back (601 / 11 / 8 before and after, nothing written):
--   phone_hidden   → phone '', wa '', flag true
--   address_hidden → address '', lat and lng null
--   email_hidden   → email ''
--   disable_wa     → wa '', flag true, the row otherwise intact
--   entry_hidden   → the row is not returned at all
--
-- Every real account simulated against its own JWT — nobody lost a screen:
--   mayor, admin, sandouk, finance, super_admin   extras 11, entries_full 8,
--                                                 registry_full 601
--   water_only, and an account with no role       extras 0, entries_full 0,
--                                                 added_public 7, public 601
-- The water_only account is the one that matters: it is the person who uses the
-- irrigation screen, it holds neither phonebook_edit nor phonebook_registry,
-- and both its payer pickers still fill.
