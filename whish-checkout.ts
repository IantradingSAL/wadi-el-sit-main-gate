// ═══════════════════════════════════════════════════════════════════════════
// whish-checkout — Supabase Edge Function (SCAFFOLD, awaiting the Whish API doc)
//
// The browser calls this with an order built by pay_create_order(); this
// function is the only place that talks to Whish outward, because the merchant
// credentials live in settings.pay_whish and must never reach a client.
//
// What is already real here: config loading, the enabled/live gate, and order
// verification. What awaits Whish's REST documentation is ONE block, marked
// TODO(whish): the exact endpoint, auth header shape and payload of "create a
// collection request", and what to hand back for the redirect.
//
// Deploy (after filling the TODO): supabase functions deploy whish-checkout
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

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

  // ── merchant config — read server-side, never exposed ─────────────────────
  const { data: cfgRow } = await admin
    .from("settings").select("value").eq("key", "pay_whish").single();
  const cfg = (cfgRow?.value ?? {}) as {
    api_url?: string; channel?: string; secret?: string;
    mode?: string; enabled?: boolean;
  };
  if (!cfg.enabled || !cfg.api_url || !cfg.secret) {
    // the page shows «قريباً» while this returns not-live — flipping the ⚙️
    // switch after the integration ships is what turns payments on
    return json(503, { live: false, error: "الدفع الإلكتروني غير مفعّل بعد" });
  }

  // ── the order — created and priced by pay_create_order(), re-checked here ─
  let orderId: string | undefined;
  try {
    ({ order_id: orderId } = await req.json());
  } catch (_) { /* fall through */ }
  if (!orderId) return json(400, { error: "order_id مطلوب" });

  const { data: order, error } = await admin
    .from("pay_orders").select("*").eq("id", orderId).single();
  if (error || !order) return json(404, { error: "الطلب غير موجود" });
  if (order.status !== "pending") {
    return json(409, { error: "الطلب ليس بانتظار الدفع", status: order.status });
  }

  // ── TODO(whish): create the collection request ────────────────────────────
  // Per the Whish Pay REST documentation (sandbox first — cfg.mode):
  //   const resp = await fetch(`${cfg.api_url}/…create-payment…`, {
  //     method: "POST",
  //     headers: { /* auth per doc: cfg.channel + cfg.secret */ },
  //     body: JSON.stringify({
  //       amount: order.amount, currency: order.currency,
  //       reference: order.id,               // travels to the callback
  //       callbackUrl: `${Deno.env.get("SUPABASE_URL")}/functions/v1/whish-callback`,
  //       // success/failure redirect URLs back to pay.html
  //     }),
  //   });
  //   → return json(200, { live: true, redirect_url: …, whish_ref: … });
  return json(501, {
    live: true,
    error: "تكامل Whish قيد الإنجاز — بانتظار توثيق الـ API",
  });
});
