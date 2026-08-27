-- Tiny Tummy — Supabase schema
-- Run this once in the Supabase SQL editor, then put your project URL and
-- anon key in js/supabase-config.js. dashboard.html manages everything after.

-- ── Products ────────────────────────────────────────────────────────────
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  handle      text not null unique,
  name        text not null,
  category    text not null check (category in ('purees','meals','cakes')),
  age         text,
  price       numeric(10,2),
  description text,
  image_url   text,
  available   boolean not null default true,
  sort        integer not null default 100,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.products enable row level security;

-- The public site reads only available products.
create policy "public read available products"
  on public.products for select
  using (available = true);

-- Signed-in staff (the dashboard) manage everything.
create policy "staff read all products"
  on public.products for select to authenticated using (true);
create policy "staff insert products"
  on public.products for insert to authenticated with check (true);
create policy "staff update products"
  on public.products for update to authenticated using (true);
create policy "staff delete products"
  on public.products for delete to authenticated using (true);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products
  for each row execute function public.touch_updated_at();

-- ── Orders (ready for when you outgrow WhatsApp ordering) ───────────────
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  customer     text not null,
  phone        text not null,
  address      text,
  items        jsonb not null default '[]',   -- [{handle, name, qty, price}]
  notes        text,
  status       text not null default 'new'
               check (status in ('new','confirmed','preparing','delivered','cancelled')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.orders enable row level security;

-- Anyone can place an order; only signed-in staff can see or manage them.
create policy "public place order"
  on public.orders for insert to anon, authenticated with check (true);
create policy "staff read orders"
  on public.orders for select to authenticated using (true);
create policy "staff update orders"
  on public.orders for update to authenticated using (true);

drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.touch_updated_at();

-- ── Seed the catalog (edit freely — matches js/products-data.js) ────────
insert into public.products (handle, name, category, age, price, description, sort) values
  ('puree-pack',     'Puree Pack',          'purees', '6M+',  null, 'A starter bundle of our four signature purees: Ratatouille, Milletflower, Heartbeet and Tropical Quinoa.', 10),
  ('ratatouille',    'Ratatouille',         'purees', '6M+',  null, 'A gentle garden-vegetable puree, cooked the slow way.', 20),
  ('milletflower',   'Milletflower',        'purees', '6M+',  null, 'Creamy millet blended with cauliflower for tiny first tastes.', 30),
  ('heartbeet',      'Heartbeet',           'purees', '6M+',  null, 'Sweet beetroot puree packed with color and iron.', 40),
  ('tropical-quinoa','Tropical Quinoa',     'purees', '6M+',  null, 'Quinoa with a sunny mix of tropical fruit.', 50),
  ('labneh',         'Labneh',              'meals',  '7M+',  null, 'Homestyle labneh made from full-fat cow''s milk.', 60),
  ('tiny-balls-24m', 'Tiny Balls (24M+)',   'meals',  '24M+', null, 'Bite-size energy balls with biscuits, walnuts, cocoa, carob molasses and real vanilla.', 70),
  ('cake',           'Baby-Friendly Cake',  'cakes',  '12M+', null, 'Celebration cakes made with baby-friendly ingredients — ask us about flavors.', 80)
on conflict (handle) do nothing;
