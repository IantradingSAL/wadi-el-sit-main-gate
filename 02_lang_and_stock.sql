-- ════════════════════════════════════════════════════════════════════════════
-- 02_lang_and_stock.sql
-- Adds language preference columns + safe stock decrement function
-- Run after 01_rls_and_roles.sql
-- ════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- LANGUAGE COLUMNS
-- These are the source of truth for which language to use in emails and push.
-- Populated by the client when the user submits a case / subscribes / orders.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) cases.lang — used by notify-i18n to pick email language
ALTER TABLE public.cases
  ADD COLUMN IF NOT EXISTS lang text NOT NULL DEFAULT 'ar';

ALTER TABLE public.cases
  DROP CONSTRAINT IF EXISTS cases_lang_check;
ALTER TABLE public.cases
  ADD CONSTRAINT cases_lang_check CHECK (lang IN ('ar','en','fr'));

-- 2) push_subscriptions.lang — used by send-push-i18n to pick push language
ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS lang text NOT NULL DEFAULT 'ar';

ALTER TABLE public.push_subscriptions
  DROP CONSTRAINT IF EXISTS push_subs_lang_check;
ALTER TABLE public.push_subscriptions
  ADD CONSTRAINT push_subs_lang_check CHECK (lang IN ('ar','en','fr'));

-- 3) push_subscriptions.user_phone — link a device to a citizen by phone
-- (already exists per memory, but ensure it's there)
ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS user_phone text;

-- 4) push_subscriptions.role — for role-targeted broadcasts (water_owner, citizen, etc.)
ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS role text;

-- 5) coop_orders.lang — used to send order notifications in the right language
ALTER TABLE public.coop_orders
  ADD COLUMN IF NOT EXISTS lang text NOT NULL DEFAULT 'ar';

ALTER TABLE public.coop_orders
  DROP CONSTRAINT IF EXISTS coop_orders_lang_check;
ALTER TABLE public.coop_orders
  ADD CONSTRAINT coop_orders_lang_check CHECK (lang IN ('ar','en','fr'));

-- Indices for fast lookups by the edge functions
CREATE INDEX IF NOT EXISTS idx_push_subs_user_phone ON public.push_subscriptions(user_phone);
CREATE INDEX IF NOT EXISTS idx_push_subs_role ON public.push_subscriptions(role);
CREATE INDEX IF NOT EXISTS idx_push_subs_active ON public.push_subscriptions(is_active) WHERE is_active = true;


-- ─────────────────────────────────────────────────────────────────────────────
-- ATOMIC STOCK DECREMENT + ORDER IDEMPOTENCY
-- Fixes M1: race condition where two simultaneous orders could both succeed
-- for the same last unit in stock.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) Add idempotency key to coop_orders
ALTER TABLE public.coop_orders
  ADD COLUMN IF NOT EXISTS idem_key text;

-- Unique index — prevents the same client from submitting the same order twice
-- (the client generates a random UUID per cart and reuses it on retries)
CREATE UNIQUE INDEX IF NOT EXISTS idx_coop_orders_idem
  ON public.coop_orders(idem_key)
  WHERE idem_key IS NOT NULL;

-- 2) Atomic place_order function: decrements stock and creates order in one transaction
-- If any item is out of stock, the whole order is rolled back.
CREATE OR REPLACE FUNCTION public.place_coop_order(
  p_idem_key text,
  p_buyer_name text,
  p_buyer_phone text,
  p_buyer_address text,
  p_delivery_method text,
  p_notes text,
  p_lang text,
  p_items jsonb  -- array of {product_id, qty, unit_price}
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id   bigint;
  v_existing   bigint;
  v_item       jsonb;
  v_total      numeric := 0;
  v_subtotal   numeric;
  v_product    record;
BEGIN
  -- Idempotency check: if this idem_key already exists, return the existing order
  IF p_idem_key IS NOT NULL THEN
    SELECT id INTO v_existing FROM public.coop_orders WHERE idem_key = p_idem_key;
    IF v_existing IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'order_id', v_existing, 'duplicate', true);
    END IF;
  END IF;

  -- Validate language
  IF p_lang NOT IN ('ar','en','fr') THEN p_lang := 'ar'; END IF;

  -- Lock each product row + check stock + decrement (all in one transaction)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT id, name, stock, price, seller_id
      INTO v_product
      FROM public.coop_products
     WHERE id = (v_item->>'product_id')::bigint
       FOR UPDATE;

    IF v_product IS NULL THEN
      RAISE EXCEPTION 'product_not_found:%', v_item->>'product_id';
    END IF;

    IF v_product.stock < (v_item->>'qty')::int THEN
      RAISE EXCEPTION 'out_of_stock:%:%', v_product.id, v_product.name;
    END IF;

    -- Decrement stock
    UPDATE public.coop_products
       SET stock = stock - (v_item->>'qty')::int
     WHERE id = v_product.id;

    -- Calculate subtotal at server-side prices (trust nothing from client)
    v_subtotal := v_product.price * (v_item->>'qty')::int;
    v_total := v_total + v_subtotal;
  END LOOP;

  -- Create the order
  INSERT INTO public.coop_orders
    (buyer_name, buyer_phone, buyer_address, delivery_method, notes,
     lang, idem_key, items, total, status, created_at)
  VALUES
    (p_buyer_name, p_buyer_phone, p_buyer_address, p_delivery_method, p_notes,
     p_lang, p_idem_key, p_items, v_total, 'pending', now())
  RETURNING id INTO v_order_id;

  RETURN jsonb_build_object('ok', true, 'order_id', v_order_id, 'total', v_total);

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_coop_order TO anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
-- After running this, check:
SELECT
  table_name,
  column_name,
  data_type,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name IN ('lang', 'user_phone', 'role', 'idem_key')
ORDER BY table_name, column_name;
-- You should see lang on cases, push_subscriptions, coop_orders.
