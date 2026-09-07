// ═══════════════════════════════════════════════════════════════════════════
// whish-checkout — Supabase Edge Function
//
// The browser hands over an order it created through pay_create_order(); this
// function is the only thing that talks to Whish outward, because the merchant
// credentials live in settings.pay_whish and never reach a client. It asks
// Whish for a collect URL (POST /payment/whish, headers channel/secret/
// websiteurl) and returns it for the redirect. Amount and services were
// validated and priced by the database — nothing from the browser is trusted
// beyond the order id.
//
// Deploy: supabase functions deploy whish-checkout --no-verify-jwt
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const SITE = "https://app.municipality-wadi-el-sitt.org";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  // ── merchant config — server-side only ────────────────────────────────────
  const { data: cfgRow } = await admin
    .from("settings").select("value").eq("key", "pay_whish").single();
  const cfg = (cfgRow?.value ?? {}) as {
    api_url?: string; channel?: string; secret?: string;
    website?: string; mode?: string; enabled?: boolean;
  };
  if (!cfg.enabled || !cfg.api_url || !cfg.secret || !cfg.channel) {
    return json(503, { live: false, error: "الدفع الإلكتروني غير مفعّل بعد" });
  }

  let orderId: string | undefined;
  try { ({ order_id: orderId } = await req.json()); } catch (_) { /* below */ }
  if (!orderId) return json(400, { error: "order_id مطلوب" });

  const { data: order, error } = await admin
    .from("pay_orders").select("*").eq("id", orderId).single();
  if (error || !order) return json(404, { error: "الطلب غير موجود" });
  if (order.status !== "pending") {
    return json(409, { error: "الطلب ليس بانتظار الدفع", status: order.status });
  }

  // ── create the collect request at Whish ───────────────────────────────────
  const cb = `${Deno.env.get("SUPABASE_URL")}/functions/v1/whish-callback` +
    `?externalId=${order.external_id}`;
  const payload = {
    amount: Number(order.amount),
    currency: order.currency,
    invoice: `رسوم بلدية وادي الست — طلب ${order.external_id}`,
    externalId: order.external_id,
    successCallbackUrl: `${cb}&r=success`,
    failureCallbackUrl: `${cb}&r=failure`,
    successRedirectUrl: `${SITE}/pay.html#paid=${order.external_id}`,
    failureRedirectUrl: `${SITE}/pay.html#payfail=${order.external_id}`,
  };
  let resp: Response;
  try {
    resp = await fetch(`${cfg.api_url}/payment/whish`, {
      method: "POST",
      headers: {
        channel: cfg.channel!,
        secret: cfg.secret!,
        websiteurl: cfg.website ?? "app.municipality-wadi-el-sitt.org",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.error("whish unreachable", e);
    return json(502, { error: "تعذّر الوصول إلى Whish — حاول بعد قليل" });
  }
  const body = await resp.json().catch(() => null) as
    { status?: boolean; code?: string | null; data?: { collectUrl?: string } } | null;
  console.log("whish create", order.external_id, resp.status, JSON.stringify(body));
  if (!resp.ok || !body?.status || !body?.data?.collectUrl) {
    return json(502, {
      error: "رفض Whish إنشاء الدفعة" + (body?.code ? ` (${body.code})` : ""),
    });
  }

  return json(200, { live: true, redirect_url: body.data.collectUrl });
});
