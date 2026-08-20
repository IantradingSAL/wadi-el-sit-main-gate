-- ═══════════════════════════════════════════════════════════════════════════
-- 14 — the cooperative's orders: let residents buy again, and stop publishing
--      their details
--
-- Two things were true of `coop_orders` at once, and both were wrong.
--
--   1. **Nobody could place an order.** Every INSERT policy carried
--      `auth.uid() IS NOT NULL`, and a buyer in the shop is anonymous. Probed
--      as `anon`: "new row violates row-level security policy". The last order
--      the shop took was 8 August. 10 of its 11 orders were placed inside the
--      last 30 days, so this is not a quiet shop — it is a shut one.
--
--   2. **Everyone could read every order.** Two SELECT policies were
--      `using (true)` for `anon`, so buyer name, phone and address were
--      downloadable by anyone with the public key. That is the exposure the
--      19 August audit recorded and could not close, because the seller and
--      agent order lists depended on it.
--
-- Migration 13 removed that dependency: sellers, agents and buyers now read
-- through security-definer functions scoped by a session token. So the reads
-- can close, and the shop can open.
--
-- The policy set is also just tidied: twelve policies, several of them exact
-- duplicates of each other, replaced by four that say what they mean.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── out with the pile ──────────────────────────────────────────────────────
drop policy if exists anon_all                          on public.coop_orders;
drop policy if exists anyone_can_read_orders            on public.coop_orders;
drop policy if exists coop_orders_delivery_public_read  on public.coop_orders;
drop policy if exists coop_orders_public_select         on public.coop_orders;
drop policy if exists anyone_can_insert_orders          on public.coop_orders;
drop policy if exists coop_orders_anon_insert           on public.coop_orders;
drop policy if exists pub_insert                        on public.coop_orders;
drop policy if exists anyone_can_update_orders          on public.coop_orders;
drop policy if exists coop_orders_delivery_claim        on public.coop_orders;
drop policy if exists coop_orders_seller_update         on public.coop_orders;
drop policy if exists sellers_can_update_own_orders     on public.coop_orders;

-- ── a resident may place an order ──────────────────────────────────────────
-- The shop is public, so this is the one thing `anon` must be able to do. It
-- is constrained: the order must name a seller who is actually approved, and
-- it may only start life as a pending order — a buyer cannot post an order
-- that is already "delivered", or one attached to a suspended seller.
create policy coop_orders_place on public.coop_orders
  for insert to anon, authenticated
  with check (
    seller_id in (select id from public.coop_sellers where status = 'approved')
    and coalesce(status, 'pending') = 'pending'
  );

-- ── reading is for staff; everyone else goes through a function ────────────
-- coop_seller_orders(), coop_agent_orders() and coop_buyer_orders() are
-- security definer, so they still work — each returns only the rows belonging
-- to the token (or the phone number) it was called with.
create policy coop_orders_staff_read on public.coop_orders
  for select to authenticated
  using (public.is_coop_admin() or public.has_perm('coop_view'));

create policy coop_orders_staff_write on public.coop_orders
  for update to authenticated
  using (public.is_coop_admin())
  with check (public.is_coop_admin());

-- (the existing coop_orders_admin_delete already covers DELETE)

-- ── the agent's actions, completed ─────────────────────────────────────────
-- 13 handled assigned / picked_up / delivered. The page also has «release» —
-- an agent handing a delivery back — and both pickup and delivery move the
-- order's own status alongside the delivery status, which 13 did not do.
create or replace function public.coop_order_set_status(
  p_token uuid, p_kind text, p_order uuid, p_status text)
returns boolean language plpgsql volatile security definer
set search_path = public, extensions, pg_temp as $fn$
declare v_subject uuid; v_n int;
begin
  v_subject := public.coop_session_subject(p_token, p_kind);
  if v_subject is null then return false; end if;

  if p_kind = 'seller' then
    if p_status not in ('pending','confirmed','out_for_delivery','delivered','cancelled') then
      return false;
    end if;
    update public.coop_orders
       set status = p_status,
           confirmed_at = case when p_status = 'confirmed' then now() else confirmed_at end,
           delivered_at = case when p_status = 'delivered' then now() else delivered_at end,
           cancelled_at = case when p_status = 'cancelled' then now() else cancelled_at end
     where id = p_order and seller_id = v_subject;
    get diagnostics v_n = row_count;
    return v_n > 0;

  elsif p_kind = 'agent' then
    if p_status = 'picked_up' then
      update public.coop_orders
         set delivery_status = 'picked_up', delivery_picked_up_at = now(),
             status = 'out_for_delivery', out_for_delivery_at = now()
       where id = p_order and delivery_agent_id = v_subject;

    elsif p_status = 'delivered' then
      update public.coop_orders
         set delivery_status = 'delivered', delivery_delivered_at = now(),
             status = 'delivered', delivered_at = now()
       where id = p_order and delivery_agent_id = v_subject;

    elsif p_status = 'unassigned' then
      -- handing it back: only the agent holding it may let it go
      update public.coop_orders
         set delivery_agent_id = null, delivery_status = 'unassigned',
             delivery_assigned_at = null
       where id = p_order and delivery_agent_id = v_subject;

    elsif p_status = 'assigned' then
      update public.coop_orders
         set delivery_status = 'assigned'
       where id = p_order and delivery_agent_id = v_subject;
    else
      return false;
    end if;
    get diagnostics v_n = row_count;
    return v_n > 0;
  end if;
  return false;
end;
$fn$;

grant execute on function public.coop_order_set_status(uuid,text,uuid,text) to anon, authenticated;
