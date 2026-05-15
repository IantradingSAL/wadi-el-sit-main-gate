// ════════════════════════════════════════════════════════════════════════════
// supabase/functions/notify-i18n/index.ts
//
// Multilingual notification Edge Function for Wadi El Sit Municipality.
// Sends EMAIL (Brevo) and WHATSAPP (Twilio) in the citizen's preferred language.
//
// NO Brevo templates needed — all email HTML is built inline here.
// To change copy: edit this file, redeploy.
//
// HOW TO DEPLOY:
//   1) Save this file at: supabase/functions/notify-i18n/index.ts
//   2) From your machine:
//        supabase functions deploy notify-i18n --project-ref onjbwhkmmtqnymhjnplw
//   3) In Supabase Dashboard → Functions → notify-i18n → Settings → Secrets:
//        BREVO_API_KEY=<your key>
//        MUNICIPALITY_EMAIL=noreply@wadi-elset.lb
//        TWILIO_ACCOUNT_SID=<your sid>          (optional)
//        TWILIO_AUTH_TOKEN=<your token>         (optional)
//        TWILIO_WHATSAPP_FROM=whatsapp:+14155238886   (optional)
//   4) In Supabase Dashboard → Database → Webhooks:
//        - Trigger on `cases` INSERT and UPDATE
//        - URL: https://onjbwhkmmtqnymhjnplw.supabase.co/functions/v1/notify-i18n
//        - Headers: Authorization: Bearer <SERVICE_ROLE_KEY>
//
// LANGUAGE SOURCE:
//   The `cases.lang` column (added by 02_lang_and_stock.sql).
//   Defaults to 'ar' if missing or invalid.
// ════════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const BREVO_API_KEY        = Deno.env.get("BREVO_API_KEY") ?? "";
const MUNICIPALITY_EMAIL   = Deno.env.get("MUNICIPALITY_EMAIL") ?? "noreply@wadi-elset.lb";
const TWILIO_ACCOUNT_SID   = Deno.env.get("TWILIO_ACCOUNT_SID") ?? "";
const TWILIO_AUTH_TOKEN    = Deno.env.get("TWILIO_AUTH_TOKEN") ?? "";
const TWILIO_WHATSAPP_FROM = Deno.env.get("TWILIO_WHATSAPP_FROM") ?? "whatsapp:+14155238886";
const PORTAL_URL           = "https://iantradingsal.github.io/wadi-el-sit-main-gate/citizen.html";

type Lang = "ar" | "en" | "fr";

// ─────────────────────────────────────────────────────────────────────────────
// Translation dictionary — all email/whatsapp strings in AR/EN/FR
// ─────────────────────────────────────────────────────────────────────────────
const T: Record<Lang, Record<string, string>> = {
  ar: {
    municipality: "بلدية وادي الست",
    district: "قضاء الشوف · محافظة جبل لبنان",
    dear: "السيد/ة",
    defaultName: "المواطن الكريم",
    caseLabel: "طلب رقم",
    trackBtn: "متابعة طلبك ←",
    footer: "بلدية وادي الست — نظام متابعة الطلبات · Powered by IanTrading SAL © 2026",
    autoSent: "هذه رسالة آلية — الرجاء عدم الرد عليها مباشرة.",
    // New case
    newSubject: "✅ تم استلام طلبك رقم #{id} — بلدية وادي الست",
    newBody: "<p>تم استلام طلبك بنجاح وسيتم معالجته في أقرب وقت.</p><p>رقم طلبك المرجعي: <strong>#{id}</strong> — احتفظ به لمتابعة طلبك.</p>",
    newWhatsApp: "🏛 *بلدية وادي الست*\n\nمرحباً {name}،\nتم استلام طلبك بنجاح ✅\n📌 رقم طلبك: *#{id}*\nاحتفظ بهذا الرقم لمتابعة طلبك.\n\nشكراً لتواصلك مع بلديتك 🤝",
    // Status changed
    statusSubject: "🔔 تحديث على طلبك #{id} — بلدية وادي الست",
    statusBody: '<p>تم تحديث حالة طلبك:</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;font-size:16px;font-weight:bold;color:#1e5429">الحالة الجديدة: {status}</div>{note}',
    statusNoteHtml: "<p><strong>رسالة من البلدية:</strong><br/>{note}</p>",
    statusWhatsApp: "🏛 *بلدية وادي الست*\n\nمرحباً {name}،\nتم تحديث طلبك رقم *#{id}*\n📋 الحالة الجديدة: *{status}*{noteBlock}\n\n🌐 تابع طلبك: {url}",
    statusNoteWaBlock: "\n\n💬 رسالة البلدية:\n{note}",
    // Public note added
    noteSubject: "💬 رسالة جديدة من بلدية وادي الست — طلب #{id}",
    noteBody: '<p>أضافت البلدية رداً جديداً على طلبك:</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;border-right:4px solid #2d7a3e;color:#1a4a2a">{note}</div>',
    noteWhatsApp: '🏛 *بلدية وادي الست*\n\nمرحباً {name}،\nرسالة جديدة من البلدية بخصوص طلبك *#{id}*:\n\n💬 "{note}"\n\n🌐 {url}',
    // New doc
    docSubject: "📎 تم إضافة مستند على طلبك #{id} — بلدية وادي الست",
    docBody: "<p>قامت البلدية بإضافة مستند جديد على طلبك.</p><p>يمكنك الاطلاع عليه من خلال متابعة طلبك على الموقع.</p>",
    docWhatsApp: "🏛 *بلدية وادي الست*\n\nمرحباً {name}،\nتم إضافة مستند جديد على طلبك *#{id}* 📎\n\n🌐 {url}",
    // Status labels
    s_new: "جديد",
    "s_in-progress": "قيد المعالجة",
    s_review: "مراجعة",
    "s_pending-approval": "ينتظر الموافقة",
    s_resolved: "منجز ✅",
    s_closed: "مغلق",
  },
  en: {
    municipality: "Wadi El Sit Municipality",
    district: "Chouf District · Mount Lebanon",
    dear: "Dear",
    defaultName: "Resident",
    caseLabel: "Request #",
    trackBtn: "Track your request →",
    footer: "Wadi El Sit Municipality — Request tracking · Powered by IanTrading SAL © 2026",
    autoSent: "This is an automated message — please do not reply directly.",
    newSubject: "✅ Your request #{id} has been received — Wadi El Sit Municipality",
    newBody: "<p>Your request has been received successfully and will be processed shortly.</p><p>Your reference number: <strong>#{id}</strong> — keep it to track your request.</p>",
    newWhatsApp: "🏛 *Wadi El Sit Municipality*\n\nHello {name},\nYour request was received successfully ✅\n📌 Reference number: *#{id}*\nKeep this number to track your request.\n\nThank you for contacting your municipality 🤝",
    statusSubject: "🔔 Update on your request #{id} — Wadi El Sit Municipality",
    statusBody: '<p>Your request status has been updated:</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;font-size:16px;font-weight:bold;color:#1e5429">New status: {status}</div>{note}',
    statusNoteHtml: "<p><strong>Message from the municipality:</strong><br/>{note}</p>",
    statusWhatsApp: "🏛 *Wadi El Sit Municipality*\n\nHello {name},\nYour request *#{id}* has been updated\n📋 New status: *{status}*{noteBlock}\n\n🌐 Track your request: {url}",
    statusNoteWaBlock: "\n\n💬 Municipality message:\n{note}",
    noteSubject: "💬 New message from Wadi El Sit Municipality — Request #{id}",
    noteBody: '<p>The municipality has added a new reply to your request:</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;border-left:4px solid #2d7a3e;color:#1a4a2a">{note}</div>',
    noteWhatsApp: '🏛 *Wadi El Sit Municipality*\n\nHello {name},\nNew message regarding your request *#{id}*:\n\n💬 "{note}"\n\n🌐 {url}',
    docSubject: "📎 Document added to your request #{id} — Wadi El Sit Municipality",
    docBody: "<p>The municipality has added a new document to your request.</p><p>You can view it by tracking your request on the website.</p>",
    docWhatsApp: "🏛 *Wadi El Sit Municipality*\n\nHello {name},\nA new document was added to your request *#{id}* 📎\n\n🌐 {url}",
    s_new: "New",
    "s_in-progress": "In progress",
    s_review: "Under review",
    "s_pending-approval": "Awaiting approval",
    s_resolved: "Resolved ✅",
    s_closed: "Closed",
  },
  fr: {
    municipality: "Municipalité de Wadi El Sit",
    district: "Caza du Chouf · Mont-Liban",
    dear: "Madame, Monsieur",
    defaultName: "Résident",
    caseLabel: "Demande n°",
    trackBtn: "Suivre votre demande →",
    footer: "Municipalité de Wadi El Sit — Suivi des demandes · Propulsé par IanTrading SAL © 2026",
    autoSent: "Ceci est un message automatique — merci de ne pas y répondre directement.",
    newSubject: "✅ Votre demande n°{id} a été reçue — Municipalité de Wadi El Sit",
    newBody: "<p>Votre demande a été reçue avec succès et sera traitée dans les plus brefs délais.</p><p>Numéro de référence : <strong>#{id}</strong> — gardez-le pour suivre votre demande.</p>",
    newWhatsApp: "🏛 *Municipalité de Wadi El Sit*\n\nBonjour {name},\nVotre demande a été reçue avec succès ✅\n📌 Numéro de référence : *#{id}*\nGardez ce numéro pour suivre votre demande.\n\nMerci d'avoir contacté votre municipalité 🤝",
    statusSubject: "🔔 Mise à jour de votre demande n°{id} — Municipalité de Wadi El Sit",
    statusBody: '<p>Le statut de votre demande a été mis à jour :</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;font-size:16px;font-weight:bold;color:#1e5429">Nouveau statut : {status}</div>{note}',
    statusNoteHtml: "<p><strong>Message de la municipalité :</strong><br/>{note}</p>",
    statusWhatsApp: "🏛 *Municipalité de Wadi El Sit*\n\nBonjour {name},\nVotre demande *#{id}* a été mise à jour\n📋 Nouveau statut : *{status}*{noteBlock}\n\n🌐 Suivre votre demande : {url}",
    statusNoteWaBlock: "\n\n💬 Message de la municipalité :\n{note}",
    noteSubject: "💬 Nouveau message de la Municipalité de Wadi El Sit — Demande n°{id}",
    noteBody: '<p>La municipalité a ajouté une nouvelle réponse à votre demande :</p><div style="background:#f0f8ea;border-radius:8px;padding:14px;margin:14px 0;border-left:4px solid #2d7a3e;color:#1a4a2a">{note}</div>',
    noteWhatsApp: '🏛 *Municipalité de Wadi El Sit*\n\nBonjour {name},\nNouveau message concernant votre demande *#{id}* :\n\n💬 "{note}"\n\n🌐 {url}',
    docSubject: "📎 Document ajouté à votre demande n°{id} — Municipalité de Wadi El Sit",
    docBody: "<p>La municipalité a ajouté un nouveau document à votre demande.</p><p>Vous pouvez le consulter en suivant votre demande sur le site.</p>",
    docWhatsApp: "🏛 *Municipalité de Wadi El Sit*\n\nBonjour {name},\nUn nouveau document a été ajouté à votre demande *#{id}* 📎\n\n🌐 {url}",
    s_new: "Nouvelle",
    "s_in-progress": "En cours",
    s_review: "En révision",
    "s_pending-approval": "En attente d'approbation",
    s_resolved: "Résolue ✅",
    s_closed: "Fermée",
  },
};

// ─────────────────────────────────────────────────────────────────────────────
function fmt(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? ""));
}

function pickLang(raw: unknown): Lang {
  if (raw === "en" || raw === "fr" || raw === "ar") return raw;
  return "ar";
}

function buildEmail(lang: Lang, name: string, caseId: number, content: string): string {
  const t = T[lang];
  const dir = lang === "ar" ? "rtl" : "ltr";
  const startSide = lang === "ar" ? "right" : "left";
  return `<!DOCTYPE html>
<html dir="${dir}" lang="${lang}">
<head><meta charset="UTF-8"><style>
  body{font-family:${lang === "ar" ? "Tahoma,Arial" : "'Inter',Arial"},sans-serif;background:#f0f2f7;margin:0;padding:20px;direction:${dir}}
  .card{background:#fff;border-radius:16px;max-width:560px;margin:0 auto;overflow:hidden}
  .hdr{background:linear-gradient(120deg,#0f4d82,#1a6eb5);color:#fff;padding:22px 28px;text-align:center}
  .hdr h1{margin:0;font-size:20px;font-weight:800}
  .hdr p{margin:5px 0 0;opacity:.75;font-size:13px}
  .body{padding:22px 28px;font-size:15px;line-height:1.8;color:#333;text-align:${startSide}}
  .badge{display:inline-block;background:#daeaf8;color:#0f4d82;padding:8px 20px;border-radius:8px;font-weight:800;font-size:18px;margin:10px 0}
  .ftr{background:#f8f9fb;padding:14px 28px;font-size:12px;color:#8d93a6;text-align:center;border-top:1px solid #eee}
  .auto{font-size:11px;color:#bbb;margin-top:8px}
  a.btn{display:inline-block;background:#1a6eb5;color:#fff;padding:11px 26px;border-radius:10px;text-decoration:none;font-weight:700;margin-top:14px}
</style></head>
<body>
<div class="card">
  <div class="hdr">
    <h1>🏛 ${t.municipality}</h1>
    <p>${t.district}</p>
  </div>
  <div class="body">
    <p>${t.dear} <strong>${escapeHtml(name)}</strong>,</p>
    ${content}
    <div><span class="badge">${t.caseLabel} #${caseId}</span></div>
    <a class="btn" href="${PORTAL_URL}">${t.trackBtn}</a>
  </div>
  <div class="ftr">
    ${t.footer}
    <div class="auto">${t.autoSent}</div>
  </div>
</div>
</body></html>`;
}

function escapeHtml(s: string): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// ─────────────────────────────────────────────────────────────────────────────
serve(async (req) => {
  try {
    const { type, record, old_record } = await req.json();
    if (type !== "UPDATE" && type !== "INSERT") {
      return new Response("ok", { status: 200 });
    }

    const c = record;
    const lang = pickLang(c.lang);
    const t = T[lang];

    const citizenEmail = c.email;
    const citizenPhone = c.phone;
    const caseId       = c.id;
    const name         = c.name?.trim() || t.defaultName;

    const statusChanged    = old_record && old_record.status !== c.status;
    const publicNoteChanged = old_record && old_record.public_note !== c.public_note && c.public_note;
    const newDocAdded      = old_record && (c.documents || []).length > (old_record.documents || []).length;
    const isNew            = type === "INSERT";

    let subject = "", htmlBody = "", whatsappMsg = "";

    if (isNew) {
      subject     = fmt(t.newSubject, { id: caseId });
      htmlBody    = buildEmail(lang, name, caseId, fmt(t.newBody, { id: caseId }));
      whatsappMsg = fmt(t.newWhatsApp, { name, id: caseId });

    } else if (statusChanged) {
      const statusKey = `s_${c.status}`;
      const statusLabel = t[statusKey] ?? c.status;
      const noteHtml = c.public_note ? fmt(t.statusNoteHtml, { note: escapeHtml(c.public_note) }) : "";
      const noteWa = c.public_note ? fmt(t.statusNoteWaBlock, { note: c.public_note }) : "";
      subject     = fmt(t.statusSubject, { id: caseId });
      htmlBody    = buildEmail(lang, name, caseId, fmt(t.statusBody, { status: statusLabel, note: noteHtml }));
      whatsappMsg = fmt(t.statusWhatsApp, { name, id: caseId, status: statusLabel, noteBlock: noteWa, url: PORTAL_URL });

    } else if (publicNoteChanged) {
      subject     = fmt(t.noteSubject, { id: caseId });
      htmlBody    = buildEmail(lang, name, caseId, fmt(t.noteBody, { note: escapeHtml(c.public_note) }));
      whatsappMsg = fmt(t.noteWhatsApp, { name, id: caseId, note: c.public_note, url: PORTAL_URL });

    } else if (newDocAdded) {
      subject     = fmt(t.docSubject, { id: caseId });
      htmlBody    = buildEmail(lang, name, caseId, t.docBody);
      whatsappMsg = fmt(t.docWhatsApp, { name, id: caseId, url: PORTAL_URL });

    } else {
      return new Response("no notification needed", { status: 200 });
    }

    const results: string[] = [];

    // ── EMAIL via Brevo ──
    if (citizenEmail && BREVO_API_KEY && htmlBody) {
      const res = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
          "api-key": BREVO_API_KEY,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify({
          sender:    { name: t.municipality, email: MUNICIPALITY_EMAIL },
          to:        [{ email: citizenEmail, name }],
          subject,
          htmlContent: htmlBody,
          // Help Brevo classify properly
          tags:      ["wadi-elset", `lang-${lang}`, isNew ? "new-case" : "case-update"],
        }),
      });
      const data = await res.json().catch(() => ({}));
      results.push(`email[${lang}]: ${res.ok ? "sent ✅" : "failed ❌ " + JSON.stringify(data).slice(0, 200)}`);
    } else if (!citizenEmail) {
      results.push("email: skipped (no citizen email on case)");
    } else if (!BREVO_API_KEY) {
      results.push("email: skipped (BREVO_API_KEY not configured)");
    }

    // ── WhatsApp via Twilio ──
    if (citizenPhone && TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN && whatsappMsg) {
      let phone = String(citizenPhone).replace(/[^0-9+]/g, "");
      if (!phone.startsWith("+")) phone = "+961" + phone.replace(/^0/, "");
      const res = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
        {
          method: "POST",
          headers: {
            "Authorization": "Basic " + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({
            From: TWILIO_WHATSAPP_FROM,
            To:   `whatsapp:${phone}`,
            Body: whatsappMsg,
          }),
        },
      );
      const data = await res.json().catch(() => ({}));
      results.push(`whatsapp[${lang}]: ${res.ok ? "sent ✅" : "failed ❌ " + (data.message ?? "")}`);
    }

    return new Response(JSON.stringify({ ok: true, lang, results }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), { status: 500 });
  }
});
