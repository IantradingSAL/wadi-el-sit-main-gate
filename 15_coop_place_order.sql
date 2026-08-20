-- ═══════════════════════════════════════════════════════════════════════════
-- 15 — placing an order, and a seller assigning a delivery
--
-- 14 let `anon` insert an order again. That was not enough on its own: the
-- page calls `.insert(orders).select()`, and PostgREST turns `.select()` into
-- a RETURNING clause. RETURNING needs to *read* the new row, and there is no
-- SELECT policy for anon any more — deliberately, because that policy is what
-- published every buyer's name, phone and address.
--
-- Probed to be sure which half was failing:
--
--   anon INSERT without RETURNING  → inserted 1 row
--   anon INSERT with RETURNING     → 42501, violates row-level security
--
-- So the insert goes through a function, exactly as `citizen_track_case` does
-- for municipal requests: security definer, returns the rows it just created,
-- and enforces the same guarantees the policy does — a real, approved seller,
-- and an order that can only start life pending.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.coop_place_order(p_orders jsonb)
returns setof public.coop_orders
language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $fn$
declare v_order jsonb; v_row public.coop_orders%rowtype; v_ids uuid[] := '{}';
begin
  if jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'no orders supplied';
  end if;
  if jsonb_array_length(p_orders) > 20 then
    raise exception 'too many orders in one basket';
  end if;

  for v_order in select * from jsonb_array_elements(p_orders) loop
    if not exists (select 1 from public.coop_sellers
                    where id = (v_order->>'seller_id')::uuid and status = 'approved') then
      raise exception 'unknown or unapproved seller';
    end if;

    insert into public.coop_orders(
        seller_id, customer_name, customer_phone, customer_address, items, total,
        delivery_method, delivery_fee_lbp, delivery_status, status, notes, lang)
    values (
        (v_order->>'seller_id')::uuid,
        nullif(btrim(coalesce(v_order->>'customer_name','')), ''),
        nullif(btrim(coalesce(v_order->>'customer_phone','')), ''),
        nullif(btrim(coalesce(v_order->>'customer_address','')), ''),
        coalesce(v_order->'items', '[]'::jsonb),
        coalesce((v_order->>'total')::numeric, 0),
        coalesce(v_order->>'delivery_method','pickup'),
        coalesce((v_order->>'delivery_fee_lbp')::numeric, 0),
        nullif(v_order->>'delivery_status',''),
        'pending',                                   -- never what the caller says
        nullif(btrim(coalesce(v_order->>'notes','')), ''),
        coalesce(nullif(v_order->>'lang',''),'ar'))
    returning * into v_row;

    v_ids := v_ids || v_row.id;
  end loop;

  return query select o.* from public.coop_orders o where o.id = any(v_ids);
end;
$fn$;

-- A seller handing one of their own orders to a named delivery agent. Scoped
-- by the seller's session token: their own order, and a real agent.
create or replace function public.coop_order_assign_agent(
  p_token uuid, p_order uuid, p_agent uuid)
returns boolean language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $fn$
declare v_seller uuid; v_n int;
begin
  v_seller := public.coop_session_subject(p_token, 'seller');
  if v_seller is null then return false; end if;
  if not exists (select 1 from public.coop_delivery_agents where id = p_agent) then
    return false;
  end if;
  update public.coop_orders
     set delivery_agent_id = p_agent,
         delivery_status = 'assigned',
         delivery_assigned_at = now()
   where id = p_order and seller_id = v_seller and delivery_method = 'delivery';
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$fn$;

grant execute on function public.coop_place_order(jsonb)                      to anon, authenticated;
grant execute on function public.coop_order_assign_agent(uuid,uuid,uuid)      to anon, authenticated;
