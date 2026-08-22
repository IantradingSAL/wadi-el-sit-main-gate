// supabase/functions/send-push-i18n/index.ts — v7
// Multilingual sender: templates in ar/en/fr, one push per subscriber in the
// language that subscriber chose.
//
// v6 (2026-08-22 push audit):
//   · AUTHORISATION. This function had none — verify_jwt off and no check of
//     its own — so anyone who knew the URL could push to every resident, which
//     is exactly the hole migration 19 closed on its sibling `send-push`. It
//     now asks the same question: the service key (the database trigger that
//     calls it) passes, an inward alert to a municipal role passes, and an
//     outward send requires push_send resolved from the caller's own JWT.
//   · to_role matched `role`, a dead column that is NULL on every row — so
//     role targeting through this function could never match anyone. It reads
//     `user_role`, the column send-push and the admin screen use.
//   · phone matching used a list of spelling variants; it now uses the
//     generated `phone_norm` (digits, no 961, no trunk 0), so 03…, 3… and
//     +9613… are one key.
//
// v7 (migration 31 — receipts):
//   · the push_log row is written BEFORE the sends, because its id has to ride
//     inside every payload as `logId`; the counts are filled in afterwards.
//   · one push_receipts row per device, and the service worker stamps
//     delivered_at / opened_at on it. Without this, a case notification — the
//     most common notification the portal sends — would be the one thing
//     📬 سجل الإشعارات could not tell you the fate of.
//   · the send carries an `event`, so the log can be read by cause rather than
//     by wording: case_received, case_status, water_turn_soon…

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as webpush from "https://esm.sh/web-push@3.6.7";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const MUN_ID_DEFAULT = "00000000-0000-0000-0000-000000000001";

// roles that belong to the municipality itself — notifying these is "inward"
const MUNICIPAL_ROLES = new Set([
  "staff", "baladieh", "officer", "admin", "mayor", "super_admin",
  "sandouk", "finance", "approver", "water_admin"
]);

type Lang = "ar" | "en" | "fr";
type MLString = string | Partial<Record<Lang, string>>;

const TEMPLATES: Record<string, { title: Record<Lang, string>; body: Record<Lang, string> }> = {
  case_received: {
    title: { ar: "✅ تم استلام طلبك", en: "✅ Request received", fr: "✅ Demande reçue" },
    body: { ar: "رقم طلبك #{case_id} — احتفظ به للمتابعة.", en: "Your reference #{case_id} — keep it for tracking.", fr: "Référence #{case_id} — gardez-la pour le suivi." },
  },
  case_status: {
    title: { ar: "🔔 تحديث على طلبك #{case_id}", en: "🔔 Update on your request #{case_id}", fr: "🔔 Mise à jour de votre demande #{case_id}" },
    body: { ar: "الحالة الجديدة: {status}", en: "New status: {status}", fr: "Nouveau statut : {status}" },
  },
  water_turn_today: {
    title: { ar: "💧 دورة الري اليوم", en: "💧 Your irrigation turn today", fr: "💧 Votre tour d'irrigation aujourd'hui" },
    body: { ar: "دورتك من {start} إلى {end} — {hours} ساعة", en: "Your turn is from {start} to {end} — {hours} hours", fr: "Votre tour est de {start} à {end} — {hours} heures" },
  },
  water_turn_tomorrow: {
    title: { ar: "🔔 دورة الري غداً", en: "🔔 Irrigation turn tomorrow", fr: "🔔 Tour d'irrigation demain" },
    body: { ar: "غداً {start} — {hours} ساعة. استعدّ.", en: "Tomorrow at {start} — {hours} hours. Get ready.", fr: "Demain à {start} — {hours} heures. Préparez-vous." },
  },
  water_turn_soon: {
    title: { ar: "⏰ دورة الري بعد ساعة", en: "⏰ Irrigation turn in 1 hour", fr: "⏰ Tour d'irrigation dans 1 heure" },
    body: { ar: "دورتك تبدأ {start}", en: "Your turn starts at {start}", fr: "Votre tour commence à {start}" },
  },
  coop_order_received: {
    title: { ar: "🛒 طلبك في التعاونية", en: "🛒 Your cooperative order", fr: "🛒 Votre commande à la coopérative" },
    body: { ar: "تم إرسال طلبك #{order_id} للبائع — سيتواصل معك قريباً.", en: "Order #{order_id} sent to the seller — they will contact you soon.", fr: "Commande n°{order_id} envoyée au vendeur — il vous contactera bientôt." },
  },
  coop_new_order: {
    title: { ar: "🔔 طلب جديد", en: "🔔 New order", fr: "🔔 Nouvelle commande" },
    body: { ar: "طلب جديد من {buyer_name} — {total} ل.ل.", en: "New order from {buyer_name} — {total} LBP", fr: "Nouvelle commande de {buyer_name} — {total} LL" },
  },
  news_alert: {
    title: { ar: "📰 خبر من البلدية", en: "📰 Municipality news", fr: "📰 Actualité de la municipalité" },
    body: { ar: "{message}", en: "{message}", fr: "{message}" },
  },
};

function pickLang(raw: unknown): Lang {
  if (raw === "en" || raw === "fr" || raw === "ar") return raw;
  return "ar";
}
function pickString(field: MLString | undefined, lang: Lang): string {
  if (!field) return "";
  if (typeof field === "string") return field;
  return field[lang] ?? field.ar ?? field.en ?? field.fr ?? "";
}
function fmt(template: string, vars: Record<string, unknown>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
}

// digits, Arabic-Indic included, without 961 and without the national 0 —
// the same key the generated column push_subscriptions.phone_norm holds
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

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const VAPID_PUBLIC  = Deno.env.get("VAPID_PUBLIC_KEY")  ?? "";
    const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
    const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT")     ?? "mailto:admin@example.com";
    if (!VAPID_PUBLIC || !VAPID_PRIVATE) return json({ error: "VAPID keys not configured" }, 500);
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

    const sb = createClient(SUPABASE_URL, SERVICE_KEY);

    const payload = await req.json();
    const { template, vars = {}, title: customTitle, body: customBody,
            url: clickUrl, to_endpoint, to_user_phone, to_role, to_topic,
            mun_id, event } = payload ?? {};
    const munId = mun_id || MUN_ID_DEFAULT;

    // ─── who is asking, and for what ─────────────────────────────────────
    // The database trigger calls this with the service key; that is the
    // trusted server path. Everything else is classified like send-push.
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    const isService = !!SERVICE_KEY && jwt === SERVICE_KEY;

    if (!isService) {
      const scope =
        (to_role && MUNICIPAL_ROLES.has(String(to_role)) && !to_user_phone && !to_topic && !to_endpoint)
          ? "inward" : "outward";

      let callerId: string | null = null;
      if (jwt) {
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
        console.log("[send-push-i18n] refused", { scope, callerId, to_role, to_topic, to_user_phone });
        return json({
          ok: false,
          error: scope === "outward"
            ? "إرسال إشعار للمقيمين يتطلّب صلاحية push_send — أرسل رمز جلسة المستخدم لا مفتاح anon"
            : "غير مسموح",
          scope
        }, 403);
      }
    }

    // Resolve title/body per language
    let titleByLang: Record<Lang, string>;
    let bodyByLang:  Record<Lang, string>;

    if (template && TEMPLATES[template]) {
      const tpl = TEMPLATES[template];
      titleByLang = { ar: fmt(tpl.title.ar, vars), en: fmt(tpl.title.en, vars), fr: fmt(tpl.title.fr, vars) };
      bodyByLang  = { ar: fmt(tpl.body.ar, vars),  en: fmt(tpl.body.en, vars),  fr: fmt(tpl.body.fr, vars)  };
    } else if (customTitle && customBody) {
      titleByLang = { ar: pickString(customTitle, "ar"), en: pickString(customTitle, "en"), fr: pickString(customTitle, "fr") };
      bodyByLang  = { ar: pickString(customBody, "ar"),  en: pickString(customBody, "en"),  fr: pickString(customBody, "fr")  };
    } else {
      return json({ ok: false, error: "Must provide either `template` + `vars`, or `title` + `body`" }, 400);
    }

    // Build target query
    let q = sb.from("push_subscriptions")
      .select("id,endpoint,p256dh,auth,lang,user_phone,user_name,user_role,topics,failed_count")
      .eq("mun_id", munId)
      .eq("is_active", true);

    let targeted = "";
    if (to_endpoint) {
      q = q.eq("endpoint", to_endpoint); targeted = "endpoint";
    } else if (to_user_phone) {
      const key = phoneKey(to_user_phone);
      if (!key) return json({ ok: false, error: "to_user_phone is not a usable number" }, 400);
      q = q.eq("phone_norm", key); targeted = "phone:" + key;
    } else if (to_role) {
      q = q.eq("user_role", to_role); targeted = "role:" + to_role;
    } else if (to_topic) {
      q = q.overlaps("topics", [to_topic]); targeted = "topic:" + to_topic;
    }

    const { data: subs, error: subsErr } = await q;
    if (subsErr) return json({ ok: false, error: "subs_fetch_failed", detail: subsErr.message }, 500);

    // ─── the log row comes first: its id rides inside every payload ───────
    const logRow = {
      mun_id: munId,
      title: titleByLang.ar, body: bodyByLang.ar,
      url: clickUrl || null, topics: to_topic ? [to_topic] : [],
      recipients_count: subs?.length ?? 0,
      success_count: 0, failed_count: 0,
      sent_by: "system:notify-i18n",
      to_user_phone: to_user_phone || null,
      to_role: to_role || null,
      event: event || template || null,
    };
    const { data: logged } = await sb.from("push_log").insert(logRow).select("id").single();
    const logId: string | null = logged?.id ?? null;

    if (!subs || subs.length === 0) {
      return json({ ok: true, sent: 0, log_id: logId, note: "no matching subscriptions", targeted });
    }

    // Send pushes — each subscriber in the language they chose
    let successCount = 0, failedCount = 0;
    const errors: string[] = [];
    const deadIds: string[] = [];
    const receipts: any[] = [];

    await Promise.all(subs.map(async (sub: any) => {
      const lang = pickLang(sub.lang);
      const pushPayload = JSON.stringify({
        title: titleByLang[lang], body: bodyByLang[lang],
        url: clickUrl || "/", icon: "/icons/icon-192.png", badge: "/icons/icon-72.png",
        lang, dir: lang === "ar" ? "rtl" : "ltr",
        logId, event: event || template || null,
        tag: template || "wadi-push", timestamp: Date.now()
      });
      const receipt: any = {
        log_id: logId, endpoint: sub.endpoint,
        user_phone: sub.user_phone ?? null,
        user_name: sub.user_name ?? null,
        user_role: sub.user_role ?? null,
        sent_ok: false, error: null
      };
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          pushPayload,
          { TTL: 86400 }
        );
        successCount++;
        receipt.sent_ok = true;
      } catch (e: any) {
        failedCount++;
        const status = e?.statusCode ?? 0;
        receipt.error = String(status || e?.message || "send failed").slice(0, 200);
        errors.push(`...${String(sub.endpoint).slice(-15)}: ${status} ${e?.message ?? ""}`.slice(0, 200));
        if (status === 404 || status === 410) deadIds.push(sub.id);
      }
      receipts.push(receipt);
    }));

    if (deadIds.length) {
      await sb.from("push_subscriptions").update({ is_active: false }).in("id", deadIds);
    }

    if (logId) {
      if (receipts.length) {
        const { error: rErr } = await sb.from("push_receipts").insert(receipts);
        if (rErr) console.log("[send-push-i18n] receipts:", rErr.message);
      }
      await sb.from("push_log")
        .update({ success_count: successCount, failed_count: failedCount })
        .eq("id", logId);
    }

    return json({
      ok: true, sent: successCount, failed: failedCount, total: subs.length,
      log_id: logId, cleaned: deadIds.length, errors: errors.slice(0, 5), targeted,
    });

  } catch (err: any) {
    console.error("send-push-i18n error:", err);
    return json({ ok: false, error: err?.message || String(err) }, 500);
  }
});
