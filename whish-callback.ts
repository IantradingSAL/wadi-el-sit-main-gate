// ═══════════════════════════════════════════════════════════════════════════
// whish-callback — Supabase Edge Function (SCAFFOLD, awaiting the Whish API doc)
//
// Whish calls this when a payment settles. The chain it must complete, in one
// place and only after VERIFYING the notification came from Whish:
//
//   verify signature → pay_orders.status = paid → book the sanad → notify
//
// The receipt is booked into the cash box through the sandouk numbering series
// (Q-YYYY-NNN) under its advisory lock — the same rule as the paper book: a
// number is never issued twice. The row carries the payer, the services as the
// البيان, رقم العقار, and payment_method «Whish», so 📊 التقارير and the CSV
// see an online payment like any counter payment.
//
// TODO(whish) blocks: the signature/authentication scheme of the callback and
// the payload field names — both come from the API documentation.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });

  const { data: cfgRow } = await admin
    .from("settings").select("value").eq("key", "pay_whish").single();
  const cfg = (cfgRow?.value ?? {}) as { secret?: string; enabled?: boolean };
  if (!cfg.enabled || !cfg.secret) return new Response("not live", { status: 503 });

  // ── TODO(whish): verify this call really came from Whish ──────────────────
  // Per the API doc: HMAC over the body with cfg.secret, a signature header,
  // or a server-to-server confirmation call — whichever the doc specifies.
  // An unverifiable notification is dropped with 401; a forged "paid" must
  // never be able to book a receipt.
  return new Response("callback verification pending Whish API documentation", {
    status: 501,
  });

  // ── After verification (the shape of what follows) ────────────────────────
  // const { reference: orderId, transactionId } = payload;   // names per doc
  // 1. load the order; ignore if already paid (callbacks can repeat)
  // 2. update pay_orders: status='paid', paid_at=now(), whish_ref=transactionId
  // 3. book the receipt in the sandouk series (advisory lock, next Q number),
  //    with category per service, البيان from order.services, الجهة the payer,
  //    property_number, payment_method 'Whish' — then stamp receipt_no back
  //    onto the order
  // 4. push to the payer (push_notify via its own token) + the pay/sandouk
  //    staff per the notify matrix
});
