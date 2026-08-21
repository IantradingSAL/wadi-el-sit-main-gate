-- ═══════════════════════════════════════════════════════════════════════════
-- 25_remove_bloomaligner.sql — applied to the live project on 2026-08-21
--
-- The second application leaves the municipality's database.
--
-- CLAUDE.md has always described this project as "a Supabase project shared
-- with one other, unrelated application". This removes that application. The
-- owner owns both and asked for it to go.
--
-- WHAT IT WAS
-- An aligner manufacturing system: inventory with lots and expiry dates,
-- purchase invoices and payments, a bill of materials, production and quality
-- records, machines, suppliers. 28 tables and one view, sharing a database with
-- the municipality's cash box, citizen registry and tax records — same
-- `public` schema, same API surface, same service-role key.
--
-- 355 rows in total, last written 5 August 2026. Eleven tables held data:
--
--   inventory_lots            107      invoices                  50
--   invoice_lines              76      inventory_items           46
--   inventory_stock_history    31      payments                  26
--   machines                    7      suppliers                  4
--   bom                         3      inventory_locations        3
--   yield_rules                 2
--
-- HOW THE 28 WERE IDENTIFIED
-- Every table in `public` was checked against the municipality's own pages: a
-- literal search for each table name across every .html and .js file in this
-- repository. These 28 are referenced by none of them. Tables with generic
-- names that DO belong to the municipality were kept, and it is worth naming
-- them so nobody removes them by pattern-matching later:
--
--   profiles           coop.html, citizen.html
--   employees          the legacy auth table; its own separate cleanup
--   currency_settings  incoming_emails  audit_log  short_links  webhook_debug
--
-- `payments` went with the manufacturing set: its only foreign key is
-- `invoice_id`, and the municipality's money lives in `baladieh_finance`.
--
-- BEFORE DROPPING
--   • every row copied to schema `bloom_archive_20260821`, verified table by
--     table: 28 tables, 355 rows, zero mismatches
--   • the schema is not exposed through the API — only `public` is — and both
--     anon and authenticated were revoked from it explicitly
--   • no foreign key from any remaining table pointed into the set
--   • one view depended on them, `inventory_lots_enriched_view`, also the other
--     application's; its definition is kept in the external backup file
--
-- AFTER
--   bloom tables in public                            0
--   tables in bloom_archive_20260821                 28
--   baladieh_finance                                169   untouched
--   phonebook_registry                              601   untouched
--   cases 39 · news 55 · mrs_takleefat 3595          all untouched
--
-- TO RESTORE, if this turns out to have been wrong:
--   create table public.<t> (like bloom_archive_20260821.<t> including all);
--   insert into public.<t> select * from bloom_archive_20260821.<t>;
--
-- STILL TO BE DONE BY HAND — the Supabase API cannot delete an edge function,
-- so these seven remain and must be deleted from the dashboard:
--   bloom-webhook · bloom-sync · bloom-fetch-one · bloom-aligners-full
--   bloom-backfill-aligners · bloom-test-endpoint · get-inventory-items
-- All six bloom-* ones were already reduced to 410 stubs on 20 August and hold
-- no tokens; deleting them is tidiness, not security. `gh-upload` is different:
-- it still holds the GitHub token in its source and writes to the other
-- application's repository. It goes when that token is rotated.
--
-- The api.bloomaligner.fr token cannot be rotated from here. It has to be done
-- with the provider.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. the archive ────────────────────────────────────────────────────────
create schema if not exists bloom_archive_20260821;

comment on schema bloom_archive_20260821 is
  'Snapshot of the 28 tables belonging to the bloomaligner application, taken 21 August 2026 immediately before they were dropped from public. Not exposed through the API: only the public schema is.';

do $$
declare t text;
begin
  foreach t in array array[
    'bloom_imports','bom','customer_feedback','inventory_items','inventory_locations',
    'inventory_lots','inventory_requisitions','inventory_stock_history','invoice_lines','invoices',
    'machine_consumable_loads','machine_lot_assignments','machines','material_consumption_log',
    'material_yield_rules','non_conformity_reports','notification_log','notification_settings',
    'order_step_tracking','payments','production_entries','production_lots','production_records',
    'production_reminders','quality_controls','suppliers','time_sessions','yield_rules']
  loop
    execute format(
      'create table if not exists bloom_archive_20260821.%I (like public.%I including defaults including constraints including indexes)', t, t);
    execute format('insert into bloom_archive_20260821.%I select * from public.%I', t, t);
  end loop;
end $$;

revoke all on schema bloom_archive_20260821 from anon, authenticated;
revoke all on all tables in schema bloom_archive_20260821 from anon, authenticated;

-- ── 2. the removal ────────────────────────────────────────────────────────
drop view if exists public.inventory_lots_enriched_view;

do $$
declare t text;
begin
  foreach t in array array[
    'bloom_imports','bom','customer_feedback','inventory_items','inventory_locations',
    'inventory_lots','inventory_requisitions','inventory_stock_history','invoice_lines','invoices',
    'machine_consumable_loads','machine_lot_assignments','machines','material_consumption_log',
    'material_yield_rules','non_conformity_reports','notification_log','notification_settings',
    'order_step_tracking','payments','production_entries','production_lots','production_records',
    'production_reminders','quality_controls','suppliers','time_sessions','yield_rules']
  loop
    execute format('drop table if exists public.%I cascade', t);
  end loop;
end $$;
