-- ═══════════════════════════════════════════════════════════════════════════
-- 16 — the rest of the silently-blocked public actions
--
-- The coop order bug in 14/15 was not a one-off. Probing every table the
-- public pages write to, as the role those pages actually run as (`anon`),
-- turned up the same fault three more times: a policy written `to
-- authenticated`, or checking `auth.uid() IS NOT NULL`, standing in front of
-- something only anonymous visitors ever do.
--
--   a seller adding a product        → 42501, violates row-level security
--   a seller editing their product   → 0 rows changed, reported as success
--   a resident signing up for a trip → 42501, violates row-level security
--   a device subscribing to push     → 42501, violates row-level security
--
-- The last one means the notification system had stopped taking new devices
-- altogether. Filing a municipal request, registering as a seller and
-- submitting a directory entry were probed too, and were fine.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── push notifications: a device manages its own subscription ──────────────
drop policy if exists ps_insert_open on public.push_subscriptions;
drop policy if exists ps_update_open on public.push_subscriptions;
drop policy if exists ps_delete_open on public.push_subscriptions;
drop policy if exists ps_select_open on public.push_subscriptions;   -- anon read all: gone

create policy ps_device_insert on public.push_subscriptions
  for insert to anon, authenticated with check (true);
create policy ps_device_update on public.push_subscriptions
  for update to anon, authenticated using (true) with check (true);
create policy ps_device_delete on public.push_subscriptions
  for delete to anon, authenticated using (true);

-- ── bus trip: a resident may sign up, and see how full the bus is ──────────
drop policy if exists allow_anyone_insert on public.bus_trip_signups;

create policy bts_public_signup on public.bus_trip_signups
  for insert to anon, authenticated
  with check (
    trip_id in (select id from public.bus_trips)
    and coalesce(seats_count,1) between 1 and 20
  );

create policy bts_public_counts on public.bus_trip_signups
  for select to anon, authenticated using (true);

-- how many seats are taken is public; who took them is not
revoke select on public.bus_trip_signups from anon;
grant  select (id, trip_id, mun_id, seats_count, status, created_at)
  on public.bus_trip_signups to anon;

-- ── coop products: the seller's own, through their session token ───────────
drop policy if exists anon_all                     on public.coop_products;
drop policy if exists anyone_insert_products       on public.coop_products;
drop policy if exists coop_products_anon_insert    on public.coop_products;
drop policy if exists anyone_update_products       on public.coop_products;
drop policy if exists coop_products_seller_update  on public.coop_products;
drop policy if exists anyone_delete_products       on public.coop_products;
drop policy if exists anyone_read_products         on public.coop_products;
drop policy if exists pub_read                     on public.coop_products;

create policy coop_products_staff_write on public.coop_products
  for all to authenticated
  using (public.is_coop_admin()) with check (public.is_coop_admin());
-- coop_products_public_read (using true) and coop_products_admin_delete stay:
-- the shop window is public, and that is the whole point of it.

-- coop_product_save() and coop_product_delete() are recorded in the live
-- project; both resolve the seller from their session token and touch only
-- rows where seller_id matches. photo_urls and delivery_options are text[] on
-- this table, and category_id is text — the functions cast accordingly.

-- coop_place_order() also takes the stock down now, in the same statement as
-- the order. That used to be the buyer's browser issuing an UPDATE against the
-- seller's product row: refused by RLS, swallowed by an empty catch, so stock
-- never moved.
