-- Tiny Tummy — operations schema (dashboard.html backend)
-- Run AFTER schema.sql. Creates the tt_* tables behind the Ops dashboard:
-- staff/roles/permissions, ingredients + lots (FEFO), BOM, orders pipeline,
-- delivery agents, requisitions, complaints/cases, chat, ISO 22000 checklist,
-- age programs, push devices + log.
--
-- Permission doctrine (same as the wadi-el-sitt municipality build):
-- one key per capability; has_perm() resolves per-user override → role
-- default → super_admin → false; every table's RLS asks the same key the
-- UI gates on, so the page and the database always agree.

-- ── staff, roles, permissions ───────────────────────────────────────────
create table if not exists public.tt_staff (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  role text not null default 'support'
    check (role in ('super_admin','manager','kitchen','delivery','support')),
  created_at timestamptz not null default now()
);

create table if not exists public.tt_role_perms (
  role text not null,
  key text not null,
  allowed boolean not null default false,
  primary key (role, key)
);

create table if not exists public.tt_user_perms (
  user_id uuid not null references public.tt_staff(id) on delete cascade,
  key text not null,
  allowed boolean not null,
  primary key (user_id, key)
);

create or replace function public.tt_has_perm(perm text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select up.allowed from tt_user_perms up where up.user_id = auth.uid() and up.key = perm),
    (select rp.allowed from tt_role_perms rp
       join tt_staff s on s.id = auth.uid() and rp.role = s.role
      where rp.key = perm),
    (select s.role = 'super_admin' from tt_staff s where s.id = auth.uid()),
    false);
$$;

-- Role defaults (explicit true/false for every role × key)
insert into public.tt_role_perms (role, key, allowed)
select r, k, case
    when r = 'super_admin' then true
    when r = 'manager' and k not in ('users_manage') then true
    when r = 'kitchen' and k in ('kitchen_manage','inventory_manage','chat_use') then true
    when r = 'delivery' and k in ('delivery_manage','chat_use') then true
    when r = 'support' and k in ('orders_manage','complaints_manage','chat_use') then true
    else false end
from unnest(array['super_admin','manager','kitchen','delivery','support']) r,
     unnest(array['orders_manage','kitchen_manage','inventory_manage','bom_manage',
                  'delivery_manage','suppliers_manage','iso_manage','complaints_manage',
                  'programs_manage','chat_use','push_send','reports_view','users_manage']) k
on conflict (role, key) do nothing;

-- ── ingredients, lots (FEFO), BOM ───────────────────────────────────────
-- Item master (Bloom inventory pattern): min/max levels, monthly use,
-- lead time and a per-item auto-requisition switch.
create table if not exists public.tt_ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'Other',
  unit text not null default 'kg',
  cost numeric(10,3) not null default 0,     -- cost per unit (latest purchase)
  min_level numeric(10,3) not null default 0,
  max_level numeric(10,3) not null default 0, -- auto-req refills up to this
  monthly_use numeric(10,3),
  lead_days int not null default 2,
  auto_req boolean not null default true,
  reorder_qty numeric(10,3) not null default 0
);

create table if not exists public.tt_lots (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references public.tt_ingredients(id) on delete cascade,
  lot_no text not null,
  qty numeric(10,3) not null default 0,
  expiry date not null,
  location text,                              -- Location / Shelf (Fridge A, Freezer, Dry store…)
  received_at date not null default current_date
);
create index if not exists tt_lots_fefo on public.tt_lots (ingredient_id, expiry); -- FEFO pick order

create table if not exists public.tt_bom (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  ingredient_id uuid not null references public.tt_ingredients(id) on delete cascade,
  qty_per_portion numeric(10,4) not null
);

-- ── orders pipeline ─────────────────────────────────────────────────────
-- Extends the public site's orders with the full production pipeline.
alter table public.orders add column if not exists code text unique;
alter table public.orders add column if not exists agent_id uuid;
alter table public.orders add column if not exists program_id uuid;
alter table public.orders add column if not exists kitchen_steps jsonb not null default '[]';
alter table public.orders add column if not exists history jsonb not null default '[]';
alter table public.orders add column if not exists ccp_records jsonb not null default '[]';   -- CCP temps: {step,value,pass,by,at}
alter table public.orders add column if not exists portioning jsonb;                          -- {planned,actual,target_g,avg_g,dev_pct,by,at,ok}
alter table public.orders add column if not exists batch_lot text;                            -- printed batch lot label
alter table public.orders add column if not exists track jsonb;                               -- {km,eta_min,promised,delayed,...}
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in
  ('new','confirmed','kitchen','portioning','qc','dispatch','delivering','delivered','cancelled'));

-- Portioning settings live on the product (BOM editor edits them)
alter table public.products add column if not exists portion_g numeric(8,1);
alter table public.products add column if not exists batch_portions int not null default 1;

create table if not exists public.tt_agents (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  active boolean not null default true
);

-- Live map tracking: the agent's phone posts GPS pings while delivering;
-- the dashboard map reads the latest ping per agent and recomputes the ETA
-- (road distance / city speed). A delay past the promised time triggers the
-- customer push with the new estimate.
create table if not exists public.tt_agent_pings (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.tt_agents(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  lat double precision not null,
  lng double precision not null,
  at timestamptz not null default now()
);
create index if not exists tt_pings_latest on public.tt_agent_pings (agent_id, at desc);

-- FEFO consumption: called when an order is sent to the kitchen.
-- Deducts each BOM ingredient from lots in earliest-expiry order and opens
-- an auto-requisition for anything that lands below its minimum.
create or replace function public.tt_consume_fefo(p_order uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  r record; l record; needed numeric; take numeric; picked text[] := '{}';
begin
  if not tt_has_perm('kitchen_manage') then raise exception 'kitchen_manage required'; end if;
  for r in
    select b.ingredient_id, sum(b.qty_per_portion * (i->>'qty')::numeric) as qty
    from orders o, jsonb_array_elements(o.items) i
    join tt_bom b on b.product_id = (i->>'product_id')::uuid
    where o.id = p_order group by b.ingredient_id
  loop
    needed := r.qty;
    for l in select * from tt_lots where ingredient_id = r.ingredient_id and qty > 0
             order by expiry asc for update
    loop
      exit when needed <= 0;
      take := least(l.qty, needed);
      update tt_lots set qty = qty - take where id = l.id;
      needed := needed - take;
      picked := picked || (take || ' from lot ' || l.lot_no);
    end loop;
    if needed > 0 then picked := picked || ('SHORT ' || needed || ' of ingredient ' || r.ingredient_id); end if;
    -- auto-requisition when below minimum and none open
    insert into tt_requisitions (ingredient_id, qty, reason, note)
    select g.id, g.reorder_qty, 'auto', g.name || ' below minimum after order'
    from tt_ingredients g
    where g.id = r.ingredient_id
      and (select coalesce(sum(qty),0) from tt_lots where ingredient_id = g.id) < g.min_level
      and not exists (select 1 from tt_requisitions q where q.ingredient_id = g.id and q.status in ('pending','approved'));
  end loop;
  return picked;
end $$;

create table if not exists public.tt_requisitions (
  id uuid primary key default gen_random_uuid(),
  ingredient_id uuid not null references public.tt_ingredients(id) on delete cascade,
  qty numeric(10,3) not null,
  reason text not null default 'manual' check (reason in ('auto','manual')),
  -- Bloom workflow: pending → approved (by a manager) → received; or cancelled
  status text not null default 'pending' check (status in ('pending','approved','received','cancelled')),
  note text,
  created_at timestamptz not null default now()
);

-- ── suppliers & payables ────────────────────────────────────────────────
-- Providers cover goods suppliers AND employees as service providers, in
-- one payables book. Posting a goods invoice through tt_invoice_post()
-- automatically receives every line into stock as a lot (FEFO-ready),
-- refreshes the ingredient's latest cost, and closes its open requisitions.
create table if not exists public.tt_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null default 'supplier' check (type in ('supplier','employee')),
  category text,
  phone text,
  terms_days int not null default 30,
  staff_id uuid references public.tt_staff(id),   -- set when the provider is an employee
  created_at timestamptz not null default now()
);

create table if not exists public.tt_sup_invoices (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  provider_id uuid not null references public.tt_providers(id) on delete restrict,
  kind text not null default 'goods' check (kind in ('goods','service')),
  invoice_date date not null default current_date,
  due_date date not null,
  status text not null default 'unpaid' check (status in ('unpaid','paid')),
  paid_at date,
  lines jsonb not null default '[]',
  -- goods line: {ingredient_id, qty, cost, lot_no, expiry}
  -- service line: {desc, amount}
  total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists tt_sup_inv_aging on public.tt_sup_invoices (status, due_date);

create or replace function public.tt_invoice_post(p_invoice uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v record; l jsonb;
begin
  if not tt_has_perm('suppliers_manage') then raise exception 'suppliers_manage required'; end if;
  select * into v from tt_sup_invoices where id = p_invoice;
  if v.kind <> 'goods' then return; end if;
  for l in select * from jsonb_array_elements(v.lines) loop
    insert into tt_lots (ingredient_id, lot_no, qty, expiry)
    values ((l->>'ingredient_id')::uuid, l->>'lot_no', (l->>'qty')::numeric, (l->>'expiry')::date);
    update tt_ingredients set cost = coalesce((l->>'cost')::numeric, cost)
      where id = (l->>'ingredient_id')::uuid and (l->>'cost') is not null;
    update tt_requisitions set status = 'received'
      where ingredient_id = (l->>'ingredient_id')::uuid and status in ('pending','approved');
  end loop;
end $$;

alter table public.tt_providers enable row level security;
alter table public.tt_sup_invoices enable row level security;
create policy "providers read" on public.tt_providers for select to authenticated
  using (public.tt_has_perm('suppliers_manage'));
create policy "providers write" on public.tt_providers for all to authenticated
  using (public.tt_has_perm('suppliers_manage')) with check (public.tt_has_perm('suppliers_manage'));
create policy "sup invoices read" on public.tt_sup_invoices for select to authenticated
  using (public.tt_has_perm('suppliers_manage'));
create policy "sup invoices write" on public.tt_sup_invoices for all to authenticated
  using (public.tt_has_perm('suppliers_manage')) with check (public.tt_has_perm('suppliers_manage'));

-- ── complaints / cases with escalation ──────────────────────────────────
create table if not exists public.tt_cases (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  order_code text,
  customer text not null,
  phone text,
  summary text not null,
  severity text not null default 'medium' check (severity in ('low','medium','high')),
  status text not null default 'open' check (status in ('open','investigating','escalated','resolved')),
  assigned_to uuid references public.tt_staff(id),
  escalated_to uuid references public.tt_staff(id),
  sla_date date,
  log jsonb not null default '[]',
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- ── team chat ───────────────────────────────────────────────────────────
create table if not exists public.tt_chat (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('kitchen','delivery','management')),
  sender_id uuid not null references public.tt_staff(id),
  text text not null,
  created_at timestamptz not null default now()
);

-- ── ISO 22000 checklist ────────────────────────────────────────────────
-- Working summary items in our own words; certification work follows the
-- official standard text. Same rows as tinytummy/iso22000-checklist.csv.
create table if not exists public.tt_iso (
  id uuid primary key default gen_random_uuid(),
  clause text not null,
  item text not null,
  status text not null default 'todo' check (status in ('done','progress','todo')),
  owner text,
  evidence text,
  updated_at timestamptz not null default now()
);

-- ── age programs ────────────────────────────────────────────────────────
create table if not exists public.tt_programs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  age_band text not null,
  description text,
  weekly_menu text,
  price_month numeric(10,2) not null default 0,
  enrolled int not null default 0
);

-- ── push: device registry + send log (municipality doctrine) ───────────
-- Sent, delivered and opened are three different facts; a send with no
-- audience must be refused by the edge function. Wire the same way as the
-- municipality: send-push edge function + VAPID keys + service worker that
-- stamps delivered/opened receipts back per device.
create table if not exists public.tt_push_devices (
  id uuid primary key default gen_random_uuid(),
  endpoint text not null unique,
  keys jsonb not null,
  user_role text,
  phone_norm text,
  program_id uuid references public.tt_programs(id),
  created_at timestamptz not null default now()
);

create table if not exists public.tt_push_log (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  audience text not null,
  sent_at timestamptz not null default now(),
  delivered_at timestamptz,
  opened_at timestamptz
);

-- ── RLS: every table asks the same key the UI gates on ─────────────────
alter table public.tt_staff enable row level security;
alter table public.tt_role_perms enable row level security;
alter table public.tt_user_perms enable row level security;
alter table public.tt_ingredients enable row level security;
alter table public.tt_lots enable row level security;
alter table public.tt_bom enable row level security;
alter table public.tt_agents enable row level security;
alter table public.tt_requisitions enable row level security;
alter table public.tt_cases enable row level security;
alter table public.tt_chat enable row level security;
alter table public.tt_iso enable row level security;
alter table public.tt_programs enable row level security;
alter table public.tt_push_devices enable row level security;
alter table public.tt_push_log enable row level security;

create policy "staff read own profile" on public.tt_staff for select to authenticated using (true);
create policy "users_manage writes staff" on public.tt_staff for all to authenticated
  using (public.tt_has_perm('users_manage')) with check (public.tt_has_perm('users_manage'));

create policy "read role perms" on public.tt_role_perms for select to authenticated using (true);
create policy "users_manage writes role perms" on public.tt_role_perms for all to authenticated
  using (public.tt_has_perm('users_manage')) with check (public.tt_has_perm('users_manage'));
create policy "read own user perms" on public.tt_user_perms for select to authenticated using (true);
create policy "users_manage writes user perms" on public.tt_user_perms for all to authenticated
  using (public.tt_has_perm('users_manage')) with check (public.tt_has_perm('users_manage'));

create policy "inventory read" on public.tt_ingredients for select to authenticated using (true);
create policy "inventory write" on public.tt_ingredients for all to authenticated
  using (public.tt_has_perm('inventory_manage')) with check (public.tt_has_perm('inventory_manage'));
create policy "lots read" on public.tt_lots for select to authenticated using (true);
create policy "lots write" on public.tt_lots for all to authenticated
  using (public.tt_has_perm('inventory_manage')) with check (public.tt_has_perm('inventory_manage'));

create policy "bom read" on public.tt_bom for select to authenticated using (true);
create policy "bom write" on public.tt_bom for all to authenticated
  using (public.tt_has_perm('bom_manage')) with check (public.tt_has_perm('bom_manage'));

create policy "agents read" on public.tt_agents for select to authenticated using (true);
create policy "agents write" on public.tt_agents for all to authenticated
  using (public.tt_has_perm('delivery_manage')) with check (public.tt_has_perm('delivery_manage'));

alter table public.tt_agent_pings enable row level security;
create policy "pings write" on public.tt_agent_pings for insert to authenticated
  with check (public.tt_has_perm('delivery_manage'));
create policy "pings read" on public.tt_agent_pings for select to authenticated
  using (public.tt_has_perm('delivery_manage') or public.tt_has_perm('orders_manage'));

create policy "reqs read" on public.tt_requisitions for select to authenticated using (true);
create policy "reqs write" on public.tt_requisitions for all to authenticated
  using (public.tt_has_perm('inventory_manage')) with check (public.tt_has_perm('inventory_manage'));

create policy "cases read" on public.tt_cases for select to authenticated
  using (public.tt_has_perm('complaints_manage'));
create policy "cases write" on public.tt_cases for all to authenticated
  using (public.tt_has_perm('complaints_manage')) with check (public.tt_has_perm('complaints_manage'));

create policy "chat read" on public.tt_chat for select to authenticated
  using (public.tt_has_perm('chat_use'));
create policy "chat write own" on public.tt_chat for insert to authenticated
  with check (public.tt_has_perm('chat_use') and sender_id = auth.uid());

create policy "iso read" on public.tt_iso for select to authenticated using (true);
create policy "iso write" on public.tt_iso for all to authenticated
  using (public.tt_has_perm('iso_manage')) with check (public.tt_has_perm('iso_manage'));

create policy "programs public read" on public.tt_programs for select using (true);
create policy "programs write" on public.tt_programs for all to authenticated
  using (public.tt_has_perm('programs_manage')) with check (public.tt_has_perm('programs_manage'));

-- Devices register from the public site (anon), like the municipality's
-- push_device_register: keyed on the device's own endpoint, no anon UPDATE/DELETE.
create policy "device register" on public.tt_push_devices for insert to anon, authenticated with check (true);
create policy "device read" on public.tt_push_devices for select to authenticated
  using (public.tt_has_perm('push_send'));
create policy "push log read" on public.tt_push_log for select to authenticated
  using (public.tt_has_perm('push_send'));
create policy "push log write" on public.tt_push_log for insert to authenticated
  with check (public.tt_has_perm('push_send'));

-- ── seed: ISO 22000 checklist (matches iso22000-checklist.csv) ─────────
insert into public.tt_iso (clause, item, status) values
 ('4 · Context','Scope of the food safety management system defined and written down','todo'),
 ('4 · Context','Interested parties and their requirements listed (parents, MoPH, suppliers)','todo'),
 ('5 · Leadership','Food safety policy written, signed and displayed in the kitchen','todo'),
 ('5 · Leadership','Roles and responsibilities for food safety assigned','todo'),
 ('6 · Planning','Risks and opportunities for the FSMS assessed with actions','todo'),
 ('6 · Planning','Food safety objectives set and tracked (complaints, temp logs)','todo'),
 ('7 · Support','Team trained on hygiene and allergen handling; records kept','todo'),
 ('7 · Support','Calibrated thermometers for fridges, freezers and blast chiller','todo'),
 ('7 · Support','Documented information controlled (versions, who can edit)','todo'),
 ('8 · Operation · PRPs','Cleaning & sanitation schedule per area, signed daily','todo'),
 ('8 · Operation · PRPs','Pest control contract and inspection log','todo'),
 ('8 · Operation · PRPs','Supplier approval list with certificates for every ingredient','todo'),
 ('8 · Operation · PRPs','Personal hygiene rules: uniforms, handwash stations, illness policy','todo'),
 ('8 · Operation · PRPs','Water potability tested and recorded','todo'),
 ('8 · Operation · HACCP','Flow diagram for each product family (puree / finger food / cake)','todo'),
 ('8 · Operation · HACCP','Hazard analysis per step (biological, chemical, physical, allergen)','todo'),
 ('8 · Operation · HACCP','CCPs set with critical limits (cook core temp, chill time, cold chain)','todo'),
 ('8 · Operation · HACCP','Monitoring records for each CCP with corrective actions','todo'),
 ('8 · Operation','Full lot traceability: ingredient lot → batch → order','todo'),
 ('8 · Operation','FEFO stock rotation enforced at picking (earliest expiry first)','todo'),
 ('8 · Operation','Allergen labelling on every pack; nut-aware age programs flagged','todo'),
 ('8 · Operation','Recall / withdrawal procedure written and tested once','todo'),
 ('8 · Operation','Cold-chain delivery: insulated boxes, max transit time defined','todo'),
 ('9 · Evaluation','Customer complaints reviewed weekly and linked to lots','todo'),
 ('9 · Evaluation','Internal audit plan — at least one full audit per year','todo'),
 ('9 · Evaluation','Management review meeting with minutes','todo'),
 ('10 · Improvement','Corrective actions tracked to closure with root cause','todo'),
 ('10 · Improvement','FSMS updated when menu, suppliers or process change','todo')
on conflict do nothing;

-- ── seed: age programs ─────────────────────────────────────────────────
insert into public.tt_programs (name, age_band, description, weekly_menu, price_month) values
 ('First Tastes','6–7 months','Single-vegetable smooth purees, one new taste every 3 days.','Mon Ratatouille · Wed Heartbeet · Fri Milletflower',79),
 ('Little Explorers','7–12 months','Thicker textures + first finger food, iron-rich mix.','Mon Milletflower · Wed Labneh + veg sticks · Fri Tropical Quinoa',89),
 ('Toddler Table','12–24 months','Family-style small meals, self-feeding portions.','Mon mini meals · Wed Labneh bowl · Fri surprise + fruit',95),
 ('Big Kids Club','2–5 years','Lunchbox program for nursery days, nut-aware options.','Daily lunchbox · Tiny Balls snack twice a week',99)
on conflict do nothing;
