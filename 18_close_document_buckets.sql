-- ═══════════════════════════════════════════════════════════════════════════
-- 18 — the two document buckets were open to anyone
--
-- Probed as `anon`, with no session at all:
--
--   74 citizen documents listable   (case-documents)
--   59 cash-box attachments listable (sandouk-docs)
--
-- `case-documents` carried a policy named «Allow all storage» — cmd ALL, role
-- public — so an anonymous visitor could read, overwrite and **delete** every
-- document a resident had ever attached to a request. Paths are
-- `<case_id>/<timestamp>_n.jpg` and case ids are sequential, so the whole set
-- could be walked: probing `199/` returned its document.
--
-- `sandouk-docs` was a public bucket with a SELECT policy for `anon`, so every
-- receipt, invoice and signed voucher was readable by anyone who had — or
-- guessed — a URL.
--
-- Closing the anon read on the cash box was not enough on its own:
-- `sandouk_docs_auth_all` granted ALL to any authenticated account, so the
-- water-only account could still open all 59. The same "logged in, therefore
-- allowed" pattern this platform has been shedding all week.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── citizens' documents ────────────────────────────────────────────────────
drop policy if exists "Allow all storage"   on storage.objects;  -- ALL, public
drop policy if exists "Allow all 5pq0yj_0"  on storage.objects;  -- SELECT, public
drop policy if exists "allow public reads"  on storage.objects;  -- SELECT, anon
drop policy if exists "Allow all 5pq0yj_2"  on storage.objects;  -- UPDATE, public
drop policy if exists "Allow all 5pq0yj_3"  on storage.objects;  -- DELETE, public

-- Uploading stays open: a resident attaches documents when filing a request,
-- and writing costs nobody anything. («Allow all 5pq0yj_1» and «allow public
-- uploads» remain, both INSERT-only and both scoped to this bucket.)

create policy case_docs_staff_read on storage.objects
  for select to authenticated
  using (bucket_id = 'case-documents' and public.has_perm('cases_view'));

create policy case_docs_staff_write on storage.objects
  for update to authenticated
  using (bucket_id = 'case-documents' and public.has_perm('cases_edit'))
  with check (bucket_id = 'case-documents' and public.has_perm('cases_edit'));

create policy case_docs_staff_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'case-documents' and public.has_perm('cases_delete'));

-- ── cash-box attachments ───────────────────────────────────────────────────
drop policy if exists sandouk_docs_public_read on storage.objects;
drop policy if exists sandouk_docs_auth_all    on storage.objects;

create policy sandouk_docs_staff_read on storage.objects
  for select to authenticated
  using (bucket_id = 'sandouk-docs' and public.has_perm('sandouk_view'));

create policy sandouk_docs_staff_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'sandouk-docs'
              and (public.has_perm('sandouk_add') or public.has_perm('sandouk_edit')));

create policy sandouk_docs_staff_update on storage.objects
  for update to authenticated
  using (bucket_id = 'sandouk-docs' and public.has_perm('sandouk_edit'))
  with check (bucket_id = 'sandouk-docs' and public.has_perm('sandouk_edit'));

create policy sandouk_docs_staff_remove on storage.objects
  for delete to authenticated
  using (bucket_id = 'sandouk-docs'
         and (public.has_perm('sandouk_edit') or public.has_perm('sandouk_delete')));

update storage.buckets set public = false where id = 'sandouk-docs';

-- Verified after applying:
--
--   not signed in            0 documents of either kind
--   water-only account       0 cash-box attachments
--   cash-box clerk          59 cash-box attachments, 0 citizen documents
--   mayor                   59 cash-box attachments, 74 citizen documents
--   super admin             59 and 74
--   product photos          still public, 20 — a shop window is meant to be one
--
-- The pages sign a link at the moment it is clicked (`bfOpenDoc`,
-- `openCaseDoc`), for the person clicking it, expiring in five minutes. The
-- `url` stored on older documents is left in place as a record; it is no longer
-- what opens the file.
