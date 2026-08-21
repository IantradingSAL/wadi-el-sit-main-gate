-- ═══════════════════════════════════════════════════════════════════════════
-- 22_phonebook_registry.sql — applied to the live project on 2026-08-21
--
-- The citizen registry stops being a file on the internet.
--
-- WHAT IT WAS
-- `contacts-registry.js` sat in the web root. GitHub Pages served it to anyone
-- who typed the URL — no login, no key — and the service worker precached it
-- into every visitor's browser. Row-level security could not reach it, because
-- it was not in the database. It carried 601 residents with name, parents,
-- phone, WhatsApp, address and birth date. Until earlier today it also carried
-- every resident's religious sect and gender, which no page ever displayed.
--
-- THE PART THAT WAS WORSE THAN A LEAK
-- The directory has a per-person opt-out: `phonebook_extras.entry_hidden`, plus
-- phone_hidden and address_hidden. It was enforced in JavaScript, at
-- phonebook.html line 1370, over an array loaded from that public file. So a
-- resident who asked to be taken out of the directory got a «🚫 مخفية» badge
-- in the UI and stayed completely readable to anyone with curl. The opt-out was
-- decoration. Nobody had used it yet — 0 rows hidden — so no one was harmed,
-- but it would have failed the first person who asked.
--
-- WHAT IT IS NOW
-- `public.phonebook_registry`, with row-level security on and NO SELECT policy
-- for any role. Every read goes through one of two functions, so the database
-- decides the projection rather than whichever page is asking:
--
--   phonebook_public()          anon + authenticated. The public directory.
--                               entry_hidden rows are dropped, phone_hidden and
--                               address_hidden fields blanked — in SQL. Returns
--                               no birth year.
--
--   phonebook_registry_full()   authenticated, and only with the new
--                               `phonebook_registry` permission. The whole
--                               table, unmasked, including the mother's name
--                               and the birth year, for the payer pickers in
--                               sandouk.html and water-admin.html, and so a
--                               phonebook admin can still see a hidden person
--                               in order to un-hide them.
--
-- WHY phonebook_public() STILL RETURNS THE MOTHER'S NAME
-- Because the public directory already shows it — «اسم الأم» on the detail
-- card, in the share text and in the vCard export. Removing it is a one-line
-- change here whenever the municipality decides to, but it is a visible change
-- to what residents see, so it is not being made silently in a security fix.
-- The birth year is different: nothing public displays it, so it does not go.
--
-- THE STANDING RULE (CLAUDE.md), all four parts
--   1. a permission key of its own       phonebook_registry
--   2. a role default for every role     six true, five explicit false
--   3. a row on the user screen          WP_GROUPS in dashboard.html
--   4. the database enforcing that key   has_perm() inside the function and in
--                                        the table's write policy
--
-- HOW THE 601 ROWS GOT IN
-- The `http` extension was installed, used to have Postgres fetch the file
-- directly from the repository, and dropped again in the same migration — so
-- 601 residents' personal data never travelled through an agent's context or
-- an intermediate file. Re-running this needs a URL the database can reach.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.phonebook_registry (
  id       integer primary key,
  name     text not null,
  first    text,
  family   text,
  father   text,
  mother   text,
  phone    text,
  wa       text,
  cc       text,
  address  text,
  bdate    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.phonebook_registry enable row level security;

comment on table public.phonebook_registry is
  'The municipal citizen registry. Previously contacts-registry.js, a static file in the web root that GitHub Pages served to anyone. No role may SELECT it directly: phonebook_public() returns the public projection with the per-person opt-out applied, and phonebook_registry_full() returns everything to a caller holding phonebook_registry.';

-- No SELECT policy, deliberately. Reads go through the functions below.
drop policy if exists registry_staff_write on public.phonebook_registry;
create policy registry_staff_write on public.phonebook_registry
  for all to authenticated
  using (public.has_perm('phonebook_registry'))
  with check (public.has_perm('phonebook_registry'));

-- ── the import, run once ───────────────────────────────────────────────────
-- create extension if not exists http with schema extensions;
-- do $$
-- declare v_body text; v_start int; v_stop int; v_json jsonb;
-- begin
--   select content into v_body from extensions.http_get('<raw url of contacts-registry.js>');
--   v_start := position('[' in v_body);
--   v_stop  := length(v_body) - strpos(reverse(v_body), ']') + 1;
--   v_json  := substring(v_body from v_start for v_stop - v_start + 1)::jsonb;
--   insert into public.phonebook_registry
--     (id,name,first,family,father,mother,phone,wa,cc,address,bdate)
--   select (r->>'id')::int, r->>'name', r->>'first', r->>'family', r->>'father',
--          r->>'mother', r->>'phone', r->>'wa', r->>'cc', r->>'address', r->>'bdate'
--     from jsonb_array_elements(v_json) r
--   on conflict (id) do update set
--     name=excluded.name, first=excluded.first, family=excluded.family,
--     father=excluded.father, mother=excluded.mother, phone=excluded.phone,
--     wa=excluded.wa, cc=excluded.cc, address=excluded.address,
--     bdate=excluded.bdate, updated_at=now();
-- end $$;
-- drop extension if exists http;

-- ── what a visitor to the public directory may see ────────────────────────
drop function if exists public.phonebook_public();
create function public.phonebook_public()
returns table (
  id int, name text, first text, family text, father text, mother text,
  phone text, wa text, cc text, address text
)
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  select r.id, r.name, r.first, r.family, r.father, r.mother,
         case when coalesce(x.phone_hidden,false)   then '' else coalesce(x.phone,   r.phone)   end,
         case when coalesce(x.phone_hidden,false)   then '' else r.wa end,
         r.cc,
         case when coalesce(x.address_hidden,false) then '' else coalesce(x.address, r.address) end
    from public.phonebook_registry r
    left join public.phonebook_extras x on x.ref_id = r.id
   where not coalesce(x.entry_hidden,     false)
     and not coalesce(x.deleted_by_admin, false);
$$;

-- ── what a member of staff holding the key may see ────────────────────────
create or replace function public.phonebook_registry_full()
returns setof public.phonebook_registry
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  select r.* from public.phonebook_registry r
   where public.has_perm('phonebook_registry');
$$;

revoke execute on function public.phonebook_public()        from public;
revoke execute on function public.phonebook_registry_full() from public;
grant  execute on function public.phonebook_public()        to anon, authenticated;
grant  execute on function public.phonebook_registry_full() to authenticated;

-- Supabase's default privileges hand every newly created function to anon, so
-- revoking from PUBLIC is not enough — anon keeps an explicit grant of its own,
-- and the first run of this migration left the full registry callable by anon.
-- It returned nothing (has_perm is false for anon) but the door was open.
revoke execute on function public.phonebook_registry_full() from anon;

-- ── the role defaults, explicit for every role ────────────────────────────
-- true for the roles that pick a payer or administer the directory; false, in
-- writing, for the rest. has_perm() resolves per-user override → role default →
-- super_admin → false, so granting one person from the user screen still works.
update public.role_permissions
   set perms = perms || '{"phonebook_registry":true}'::jsonb, updated_at = now()
 where role in ('super_admin','admin','mayor','sandouk','finance','water_admin');

update public.role_permissions
   set perms = perms || '{"phonebook_registry":false}'::jsonb, updated_at = now()
 where role not in ('super_admin','admin','mayor','sandouk','finance','water_admin');

-- Measured after applying:
--   rows imported                              601   (matches the file exactly)
--   anon SELECT on phonebook_registry            0   RLS, no policy
--   anon phonebook_public()                    601
--   anon phonebook_registry_full()          denied   no EXECUTE
--   one person marked entry_hidden → public    600   the opt-out finally works
