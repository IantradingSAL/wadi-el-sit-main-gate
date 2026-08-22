// send-push — إشعار Push
// ══════════════════════════════════════════════════════════════════════════════
// This function runs with verify_jwt off, and it has to: a resident filing a
// request calls it to tell the municipality, and that resident has no session.
//
// It used to carry no authorisation of its own either. Anyone who knew the URL
// could POST a title and a body and have it arrive on every resident's phone,
// looking exactly like the municipality — mun_id is in the page source, and
// nothing else was needed.
//
// Now the request is classified and the database decides:
//
//   internal — the request carries `x-wadi-push-token`, the secret held in this
//              project's vault and known only to `push_notify()`. That is the
//              database itself reporting an event it just recorded: a directory
//              entry approved, an order confirmed, an irrigation turn due.
//              Trusted, and deliberately NOT the service-role key — a caller
//              that leaks this token can send notifications and nothing else.
//   inward   — telling the municipality something (to_role: a municipal role).
//              Open, as it must be. The worst it can do is bother the staff.
//   outward  — everyone, a topic, a non-municipal role, or one resident's
//              phone. Requires push_send, resolved from the caller's own JWT.
//              NOTE for callers: send the SIGNED-IN USER'S access token, not
//              the anon key. The anon key resolves to no user, so an outward
//              send with it is refused with 403 — which is exactly how the
//              admin screens silently stopped broadcasting.
//
// Phone targeting matches on push_subscriptions.phone_norm (digits, without
// 961, without the trunk 0) rather than on the raw string, because the same
// number has been stored as 03…, 3…, and +9613… over the life of the table.
//
// Every send now leaves a trail in two places, not one:
//
//   push_log      — one row per send: what was said, to whom it was addressed,
//                   under which `event`, and how many devices it reached.
//   push_receipts — one row per device: whether the push service accepted it,
//                   and then — filled in by the service worker — when the phone
//                   actually received it and when the person opened it.
//
// The log id travels inside the payload as `logId`, which is what lets the
// service worker report back against the right send.
//
// Deploy:  supabase functions deploy send-push --no-verify-jwt
// ══════════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as webpush from "https://esm.sh/web-push@3.6.7";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-wadi-push-token",
};

// roles that belong to the municipality itself — notifying these is "inward"
const MUNICIPAL_ROLES = new Set([
  "staff", "baladieh", "officer", "admin", "mayor", "super_admin",
  "sandouk", "finance", "approver", "water_admin"
]);

// digits, Arabic-Indic included, without 961 and without the national 0
const AR_DIGITS: Record<string, string> = {
  "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
  "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
};
function phoneKey(v: unknown): string {
  return String(v ?? "")
    .replace(/[٠-٩۰-۹]/g, (d) => AR_DIGITS[d] ?? d)
    .replace(/[^0-9]/g, "")
    .replace(/^961/, "")
    .replace(/^0+/, "");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json();
    const {
      mun_id, title, body: msgBody, url, topics, sent_by, image, tag,
      to_user_phone, to_role, template_id, event
    } = body;

    if (!mun_id || !title || !msgBody) {
      return json({ error: "Missing mun_id, title, or body" }, 400);
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // ─── who is asking, and for what ─────────────────────────────────────
    // The database's own token first: push_notify() sends it on every trigger
    // and on the irrigation sweep, and those have no session to speak of.
    const internalToken = (req.headers.get("x-wadi-push-token") || "").trim();
    let internal = false;
    if (internalToken) {
      const chk = await fetch(`${SUPABASE_URL}/rest/v1/rpc/push_internal_auth`, {
        method: "POST",
        headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`,
                   "Content-Type": "application/json" },
        body: JSON.stringify({ p_token: internalToken })
      });
      internal = chk.ok ? (await chk.json().catch(() => false)) === true : false;
      if (!internal) {
        console.log("[send-push] internal token presented but not recognised");
        return json({ error: "غير مسموح", scope: "internal" }, 403);
      }
    }

    const scope = internal ? "internal" :
      ((to_role && MUNICIPAL_ROLES.has(String(to_role)) && !to_user_phone &&
        !(Array.isArray(topics) && topics.length))
        ? "inward" : "outward");

    if (!internal) {
      let callerId: string | null = null;
      const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
      if (jwt) {
        // The anon key is a JWT too; /auth/v1/user simply returns no user for it.
        const meRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
          headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` }
        });
        if (meRes.ok) {
          const me = await meRes.json().catch(() => null);
          callerId = me?.id ?? null;
        }
      }

      const allowRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/push_send_allowed`, {
        method: "POST",
        headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`,
                   "Content-Type": "application/json" },
        body: JSON.stringify({ p_user: callerId, p_scope: scope })
      });
      const allowed = allowRes.ok ? await allowRes.json().catch(() => false) : false;
      if (allowed !== true) {
        console.log("[send-push] refused", { scope, callerId, to_role, topics, to_user_phone });
        return json({
          error: scope === "outward"
            ? "إرسال إشعار للمقيمين يتطلّب صلاحية push_send — أرسل رمز جلسة المستخدم لا مفتاح anon"
            : "غير مسموح",
          scope
        }, 403);
      }
    }

    const VAPID_PUBLIC  = Deno.env.get("VAPID_PUBLIC_KEY")  ?? "";
    const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
    const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT")     ?? "mailto:admin@example.com";
    if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
      return json({ error: "VAPID keys not configured" }, 500);
    }
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

    const sb = createClient(SUPABASE_URL, SERVICE_KEY);

    // ─── Build target query ─────────────────────────────────────────
    let q = sb.from("push_subscriptions").select("*").eq("mun_id", mun_id).eq("is_active", true);

    if (to_user_phone) {
      const key = phoneKey(to_user_phone);
      if (!key) return json({ error: "to_user_phone is not a usable number" }, 400);
      q = q.eq("phone_norm", key);
    } else if (to_role) {
      q = q.eq("user_role", to_role);
    } else if (topics && Array.isArray(topics) && topics.length > 0) {
      q = q.overlaps("topics", topics);
    }

    const { data: subs, error } = await q;
    if (error) return json({ error: error.message }, 500);

    // ─── the log row comes first: the payload has to carry its id ────────
    const logRow = {
      mun_id, title, body: msgBody, url,
      topics: topics || (to_role ? [to_role] : ['general']),
      recipients_count: subs?.length ?? 0,
      success_count: 0, failed_count: 0,
      sent_by: sent_by || "system",
      to_user_phone: to_user_phone || null,
      to_role: to_role || null,
      template_id: template_id || null,
      event: event || null
    };
    const { data: logged } = await sb.from("push_log").insert(logRow).select("id").single();
    const logId: string | null = logged?.id ?? null;

    if (!subs || subs.length === 0) {
      return json({ log_id: logId, recipients_count: 0, success_count: 0, failed_count: 0,
                    message: "No matching subscribers" });
    }

    const payload = JSON.stringify({
      title, body: msgBody,
      url: url && url.trim() && url !== "/" ? url : "news.html",
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-72.png",
      image,
      tag: tag || "wadi-news",
      logId,
      event: event || null,
      timestamp: Date.now()
    });

    let successCount = 0;
    let failedCount = 0;
    const receipts: any[] = [];

    await Promise.all(subs.map(async (sub: any) => {
      const subscription = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth }
      };
      const receipt: any = {
        log_id: logId, endpoint: sub.endpoint,
        user_phone: sub.user_phone ?? null,
        user_name: sub.user_name ?? null,
        user_role: sub.user_role ?? null,
        sent_ok: false, error: null
      };
      try {
        await webpush.sendNotification(subscription, payload, { TTL: 86400 });
        successCount++;
        receipt.sent_ok = true;
        sb.from("push_subscriptions")
          .update({ last_used_at: new Date().toISOString(), failed_count: 0 })
          .eq("id", sub.id).then();
      } catch (err: any) {
        failedCount++;
        const status = err.statusCode || 0;
        receipt.error = String(status || err?.message || "send failed").slice(0, 200);
        if (status === 404 || status === 410) {
          await sb.from("push_subscriptions").update({ is_active: false }).eq("id", sub.id);
        } else {
          const newFails = (sub.failed_count || 0) + 1;
          await sb.from("push_subscriptions")
            .update({ failed_count: newFails, is_active: newFails < 5 })
            .eq("id", sub.id);
        }
      }
      receipts.push(receipt);
    }));

    if (logId) {
      // one row per device — this is what 📬 سجل الإشعارات reads, and what the
      // service worker stamps `delivered_at` / `opened_at` on afterwards
      if (receipts.length) {
        const { error: rErr } = await sb.from("push_receipts").insert(receipts);
        if (rErr) console.log("[send-push] receipts:", rErr.message);
      }
      await sb.from("push_log")
        .update({ success_count: successCount, failed_count: failedCount })
        .eq("id", logId);
    }

    if (template_id) {
      sb.rpc('increment_template_usage', { tpl_id: template_id }).then().catch(() => {});
    }

    return json({
      log_id: logId,
      recipients_count: subs.length,
      success_count: successCount,
      failed_count: failedCount
    });

  } catch (e: any) {
    console.error(e);
    return json({ error: e.message || "Internal error" }, 500);
  }
});

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" }
  });
}
