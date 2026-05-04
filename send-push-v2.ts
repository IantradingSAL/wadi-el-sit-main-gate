// supabase/functions/send-push/index.ts
// ═══════════════════════════════════════════════════════════════════════════
// إشعار Push — Supabase Edge Function v2 (يدعم استهداف المستخدم بالهاتف)
// ═══════════════════════════════════════════════════════════════════════════
//
// إعادة النشر:
//   supabase functions deploy send-push --no-verify-jwt
//
// أنماط الاستدعاء:
//   1) للجميع:                  { mun_id, title, body, topics: ['general'] }
//   2) لمستخدم محدّد بالهاتف:    { mun_id, title, body, to_user_phone: '76789039' }
//   3) لكل المستخدمين بدور معين: { mun_id, title, body, to_role: 'staff' }
//   4) للمشتركين بمواضيع معيّنة: { mun_id, title, body, topics: ['water'] }
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as webpush from "https://esm.sh/web-push@3.6.7";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json();
    const {
      mun_id, title, body: msgBody, url, topics, sent_by, image, tag,
      to_user_phone, to_role, template_id
    } = body;

    if (!mun_id || !title || !msgBody) {
      return json({ error: "Missing mun_id, title, or body" }, 400);
    }

    const VAPID_PUBLIC  = Deno.env.get("VAPID_PUBLIC_KEY")  ?? "";
    const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
    const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT")     ?? "mailto:admin@example.com";
    if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
      return json({ error: "VAPID keys not configured" }, 500);
    }
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

    const sb = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ─── Build target query ──────────────────────────────────────────────
    let q = sb.from("push_subscriptions").select("*").eq("mun_id", mun_id).eq("is_active", true);

    if (to_user_phone) {
      // Targeting a specific user by phone — most specific
      const phoneNorm = to_user_phone.toString().replace(/[^\d+]/g, "");
      // Match phone in any common format (digits-only or with +)
      q = q.or(`user_phone.eq.${phoneNorm},user_phone.eq.+${phoneNorm.replace(/^\+/,'')}`);
    } else if (to_role) {
      // Targeting a role (staff, citizen, water_owner, seller, etc.)
      q = q.eq("user_role", to_role);
    } else if (topics && Array.isArray(topics) && topics.length > 0) {
      // Targeting subscribers of specific topics
      q = q.overlaps("topics", topics);
    }
    // else: send to ALL active subscribers under mun_id

    const { data: subs, error } = await q;
    if (error) return json({ error: error.message }, 500);

    if (!subs || subs.length === 0) {
      // Log even with zero recipients (so admin sees it was attempted)
      await sb.from("push_log").insert({
        mun_id, title, body: msgBody, url,
        topics: topics || (to_role ? [to_role] : ['general']),
        recipients_count: 0, success_count: 0, failed_count: 0,
        sent_by: sent_by || "system",
        to_user_phone: to_user_phone || null,
        to_role: to_role || null,
        template_id: template_id || null
      });
      return json({ recipients_count: 0, success_count: 0, failed_count: 0, message: "No matching subscribers" });
    }

    // ─── Build push payload ──────────────────────────────────────────────
    const payload = JSON.stringify({
      title, body: msgBody,
      url: url || "/",
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-72.png",
      image,
      tag: tag || "wadi-news",
      timestamp: Date.now()
    });

    // ─── Dispatch concurrently ───────────────────────────────────────────
    let successCount = 0;
    let failedCount = 0;

    await Promise.all(subs.map(async (sub: any) => {
      const subscription = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth }
      };
      try {
        await webpush.sendNotification(subscription, payload, { TTL: 86400 });
        successCount++;
        sb.from("push_subscriptions")
          .update({ last_used_at: new Date().toISOString(), failed_count: 0 })
          .eq("id", sub.id).then();
      } catch (err: any) {
        failedCount++;
        const status = err.statusCode || 0;
        if (status === 404 || status === 410) {
          await sb.from("push_subscriptions").update({ is_active: false }).eq("id", sub.id);
        } else {
          const newFails = (sub.failed_count || 0) + 1;
          await sb.from("push_subscriptions")
            .update({ failed_count: newFails, is_active: newFails < 5 })
            .eq("id", sub.id);
        }
      }
    }));

    // ─── Log ─────────────────────────────────────────────────────────────
    await sb.from("push_log").insert({
      mun_id, title, body: msgBody, url,
      topics: topics || (to_role ? [to_role] : ['general']),
      recipients_count: subs.length,
      success_count: successCount,
      failed_count: failedCount,
      sent_by: sent_by || "system",
      to_user_phone: to_user_phone || null,
      to_role: to_role || null,
      template_id: template_id || null
    });

    // Update template usage counter
    if (template_id) {
      sb.rpc('increment_template_usage', { tpl_id: template_id }).then().catch(() => {});
    }

    return json({
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
