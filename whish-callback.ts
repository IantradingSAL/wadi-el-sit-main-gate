// ═══════════════════════════════════════════════════════════════════════════
// whish-callback — Supabase Edge Function
//
// Whish calls this when a payment settles. The notification itself is NEVER
// trusted: whoever calls this, for whatever externalId, the function turns
// around and asks Whish directly (POST /payment/collect/status, authenticated
// with the merchant secret) and only that answer decides. A forged "paid"
// therefore cannot book a receipt — at worst it makes us re-check a pending
// order.
//
//   verify with Whish → pay_orders.status = paid → pay_book_receipt()
//
// pay_book_receipt() issues the سند قبض from the sandouk series under its
// advisory lock and is idempotent, so Whish retrying the callback (or calling
// it for both legs) books exactly one receipt.
//
// Deploy: supabase functions deploy whish-callback --no-verify-jwt
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  // ── which order? accept the id from query or body, GET or POST ────────────
  const url = new URL(req.url);
  let ext = url.searchParams.get("externalId") ?? url.searchParams.get("external_id");
  if (!ext && req.method === "POST") {
    const b = await req.json().catch(() => null) as Record<string, unknown> | null;
    const v = b?.externalId ?? b?.external_id;
    if (v !== undefined && v !== null) ext = String(v);
  }
  const externalId = Number(ext);
  if (!externalId || !Number.isFinite(externalId)) {
    return new Response("externalId?", { status: 400 });
  }

  const { data: cfgRow } = await admin
    .from("settings").select("value").eq("key", "pay_whish").single();
  const cfg = (cfgRow?.value ?? {}) as {
    api_url?: string; channel?: string; secret?: string; website?: string; enabled?: boolean;
  };
  if (!cfg.enabled || !cfg.api_url || !cfg.secret) {
    return new Response("not live", { status: 503 });
  }

  const { data: order } = await admin
    .from("pay_orders").select("*").eq("external_id", externalId).single();
  if (!order) return new Response("unknown order", { status: 404 });
  if (order.status === "paid" && order.receipt_no) {
    return new Response("ok (already booked)", { status: 200 });
  }

  // ── the only voice we trust: Whish itself, asked with the secret ──────────
  let statusBody:
    | { status?: boolean; data?: { collectStatus?: string } }
    | null = null;
  try {
    const resp = await fetch(`${cfg.api_url}/payment/collect/status`, {
      method: "POST",
      headers: {
        channel: cfg.channel!,
        secret: cfg.secret!,
        websiteurl: cfg.website ?? "app.municipality-wadi-el-sitt.org",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        externalId,
        currency: order.currency,
        amount: Number(order.amount),
      }),
    });
    statusBody = await resp.json().catch(() => null);
    console.log("whish status", externalId, resp.status, JSON.stringify(statusBody));
  } catch (e) {
    console.error("status check failed", externalId, e);
    return new Response("verification unavailable", { status: 502 });
  }
  const collectStatus = statusBody?.data?.collectStatus;

  if (collectStatus === "success") {
    if (order.status !== "paid") {
      await admin.from("pay_orders")
        .update({ status: "paid", paid_at: new Date().toISOString() })
        .eq("id", order.id).eq("status", "pending");
    }
    const { data: receipt, error } = await admin.rpc("pay_book_receipt", { p_order: order.id });
    if (error) {
      console.error("booking failed", order.id, error.message);
      return new Response("paid, booking failed", { status: 500 });
    }
    console.log("booked", externalId, receipt);
    return new Response("ok " + receipt, { status: 200 });
  }

  if (collectStatus === "failed" && order.status === "pending") {
    await admin.from("pay_orders")
      .update({ status: "failed" }).eq("id", order.id).eq("status", "pending");
    return new Response("marked failed", { status: 200 });
  }

  return new Response("status: " + (collectStatus ?? "unknown"), { status: 200 });
});
