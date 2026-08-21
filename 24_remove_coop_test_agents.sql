-- ═══════════════════════════════════════════════════════════════════════════
-- 24_remove_coop_test_agents.sql — applied to the live project on 2026-08-21
--
-- The two delivery agents in the cooperative were never real people.
--
--   name       phone      area      vehicle     deliveries  created
--   delivery   03649694   "dd"      motorcycle  0           2 Aug 2026
--   Beirut     03846526   "BEIRUT"  motorcycle  0           2 Aug 2026
--
-- Both created the same afternoon the delivery feature was built, both with a
-- placeholder area, both with zero completed deliveries, and both were on PIN
-- 1234 until it was rotated earlier today. They are the developer's own test
-- accounts. Left in place they are two working logins into the delivery queue,
-- where an agent sees a buyer's name, phone and address once an order is
-- claimed.
--
-- CHECKED BEFORE REMOVING
--   live orders assigned to either                      0  (coop_orders is empty)
--   archived orders assigned to either                  1  — one of the cleared
--                                                          test orders, which
--                                                          names "delivery"
--   open session tokens                                 0  (coop_sessions empty)
--   foreign keys pointing at the table    coop_orders.delivery_agent_id,
--                                         ON DELETE NO ACTION — and empty, so
--                                         nothing blocks or cascades
--
-- The rows are copied to _archive_coop_delivery_agents first, exactly as the
-- test orders and transactions were, so the one archived order that names an
-- agent can still be resolved to something. The archive has row-level security
-- on and no policies: nothing but the service role reads it.
--
-- The PIN hashes are NOT copied. There is no reason to keep a credential for
-- an account that is being deleted.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public._archive_coop_delivery_agents
  (like public.coop_delivery_agents including defaults);

alter table public._archive_coop_delivery_agents drop column if exists pin_hash;
alter table public._archive_coop_delivery_agents add column if not exists archived_at timestamptz not null default now();
alter table public._archive_coop_delivery_agents enable row level security;

comment on table public._archive_coop_delivery_agents is
  'Delivery agents removed from the cooperative, kept so archived orders that name one can still be resolved. RLS on, no policies — service role only. PIN hashes deliberately not carried over.';

insert into public._archive_coop_delivery_agents
  (id, name, phone, whatsapp, area, vehicle, notes, status,
   active_orders, total_deliveries, rating, created_at, updated_at)
select id, name, phone, whatsapp, area, vehicle, notes, status,
       active_orders, total_deliveries, rating, created_at, updated_at
  from public.coop_delivery_agents
 where id in ('547bb13b-ff5e-49e8-9235-a437b403e8ad',
              'e9cc0d4a-9f9c-4a9a-bb19-ca21fac3f017')
   and not exists (select 1 from public._archive_coop_delivery_agents a
                    where a.id = public.coop_delivery_agents.id);

delete from public.coop_sessions
 where kind = 'agent'
   and subject_id in ('547bb13b-ff5e-49e8-9235-a437b403e8ad',
                      'e9cc0d4a-9f9c-4a9a-bb19-ca21fac3f017');

delete from public.coop_delivery_agents
 where id in ('547bb13b-ff5e-49e8-9235-a437b403e8ad',
              'e9cc0d4a-9f9c-4a9a-bb19-ca21fac3f017');

-- Measured after applying:
--   coop_delivery_agents                     0   both removed
--   _archive_coop_delivery_agents            2   both recoverable, without PINs
--   coop_sellers / coop_admins / categories  3 / 1 / 10   untouched
--   baladieh_finance                       169   untouched
--
-- To put one back, if either turns out to have been real:
--   insert into public.coop_delivery_agents
--     (id,name,phone,whatsapp,area,vehicle,notes,status,active_orders,
--      total_deliveries,rating,created_at,updated_at)
--   select id,name,phone,whatsapp,area,vehicle,notes,status,active_orders,
--          total_deliveries,rating,created_at,updated_at
--     from public._archive_coop_delivery_agents where phone = '…';
--   -- then set a new PIN from the coop admin screen; the old one is gone.
