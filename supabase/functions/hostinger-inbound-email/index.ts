// supabase/functions/hostinger-inbound-email/index.ts
// Receives message.received webhooks from Hostinger Mail (any registered
// mailbox), triages, stores, pushes to admins, and sends a bilingual
// auto-acknowledgement from the same mailbox.
//
// Required Supabase secret:
//   HOSTINGER_MAILBOXES = JSON array; one entry per mailbox that has a
//   webhook pointing at this function. Each entry is:
//     { addr: string, id: string, apiToken: string, webhookSecret: string }
//   Example:
//     [
//       {"addr":"a@example.com","id":"AC...","apiToken":"e5c...","webhookSecret":"9805..."},
//       {"addr":"b@example.com","id":"AC...","apiToken":"42a...","webhookSecret":"b708..."}
//     ]
//
// Auto-provided:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy with verify_jwt: false so Hostinger can call it without a Supabase JWT.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const HOSTINGER_API = "https://api.mail.hostinger.com";
const MUN_ID = "00000000-0000-0000-0000-000000000001";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

type Addr = { name?: string; address: string };
type Message = {
  uid: number;
  path: string;
  date: string;
  flags: string[];
  size: number;
  subject: string | null;
  from: Addr | null;
  to: Addr[];
  cc: Addr[];
  bcc: Addr[];
  messageId: string | null;
  inReplyTo: string | null;
};

type Category = "water" | "coop" | "bus" | "mrs" | "general" | "internal";

const TRIAGE_RULES: Array<{ cat: Category; needles: string[] }> = [
  { cat: "water", needles: ["water", "irrigation", "irrig", "مياه", "ري", "سقاية"] },
  { cat: "coop",  needles: ["coop", "cooperative", "coopérative", "تعاونية", "تعاوني"] },
  { cat: "bus",   needles: ["bus", "trip", "trajet", "باص", "رحلة"] },
  { cat: "mrs",   needles: ["mrs", "mukallaf", "tax", "fee", "invoice", "receipt", "مكلف", "رسم", "ايصال", "فاتورة"] },
];

const AUTO_REPLY_FROM_PATTERNS = [
  /(^|[.<@])(no-?reply|donotreply|do-not-reply|mailer-daemon|postmaster|bounce|bounces|abuse|noreply)@/i,
];
const AUTO_REPLY_SUBJECT_PATTERNS = [
  /^(auto[:\s-]|automatic reply|out of office|delivery status notification|undelivered|undeliverable|mail delivery failed|bounce|failed delivery notification)/i,
];

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function triage(subject: string, from: string, mailboxAddr: string): Category {
  const domain = mailboxAddr.split("@")[1]?.toLowerCase() ?? "";
  if (domain && from.toLowerCase().endsWith("@" + domain)) return "internal";

  const hay = `${subject} ${from}`.toLowerCase();
  for (const rule of TRIAGE_RULES) {
    if (rule.needles.some((n) => hay.includes(n))) return rule.cat;
  }
  return "general";
}

function isAutoReply(subject: string, fromAddr: string): boolean {
  if (AUTO_REPLY_FROM_PATTERNS.some((r) => r.test(fromAddr))) return true;
  if (AUTO_REPLY_SUBJECT_PATTERNS.some((r) => r.test(subject))) return true;
  return false;
}

async function hostingerGet(path: string, apiToken: string): Promise<Response> {
  return fetch(`${HOSTINGER_API}${path}`, {
    headers: { Authorization: `Bearer ${apiToken}`, Accept: "application/json" },
  });
}

async function hostingerPost(path: string, apiToken: string, body: unknown): Promise<Response> {
  return fetch(`${HOSTINGER_API}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiToken}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function buildAutoReply(opts: {
  ticketId: string;
  originalSubject: string;
  fromName: string;
  fromAddr: string;
  category: Category;
  mailboxAddr: string;
}): { subject: string; text: string; html: string; displayName: string } {
  const salutation = opts.fromName || opts.fromAddr;
  const subject = `Re: ${opts.originalSubject || "(no subject)"} — ${opts.ticketId}`;

  const text =
    `مرحباً ${salutation}،\n\n` +
    `شكراً لتواصلكم مع بلدية وادي الست. تم تسجيل رسالتكم برقم المرجع: ${opts.ticketId}.\n` +
    `سيتم الرد عليكم في أقرب فرصة ممكنة.\n\n` +
    `— بلدية وادي الست\n\n` +
    `----\n\n` +
    `Hello ${salutation},\n\n` +
    `Thank you for contacting the Wadi El Sit Municipality. Your message has been logged under reference: ${opts.ticketId}.\n` +
    `We will get back to you as soon as possible.\n\n` +
    `— Municipality of Wadi El Sit`;

  const html =
    `<div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;font-size:14px;line-height:1.6">` +
    `<p>مرحباً ${escapeHtml(salutation)}،</p>` +
    `<p>شكراً لتواصلكم مع <strong>بلدية وادي الست</strong>. تم تسجيل رسالتكم برقم المرجع: <strong>${opts.ticketId}</strong>.</p>` +
    `<p>سيتم الرد عليكم في أقرب فرصة ممكنة.</p>` +
    `<p>— بلدية وادي الست</p>` +
    `</div>` +
    `<hr>` +
    `<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.6">` +
    `<p>Hello ${escapeHtml(salutation)},</p>` +
    `<p>Thank you for contacting the <strong>Wadi El Sit Municipality</strong>. Your message has been logged under reference: <strong>${opts.ticketId}</strong>.</p>` +
    `<p>We will get back to you as soon as possible.</p>` +
    `<p>— Municipality of Wadi El Sit</p>` +
    `</div>`;

  return { subject, text, html, displayName: "Wadi El Sit Municipality" };
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => (
    c === "&" ? "&amp;" :
    c === "<" ? "&lt;" :
    c === ">" ? "&gt;" :
    c === '"' ? "&quot;" : "&#39;"
  ));
}

type MailboxConfig = {
  addr: string;
  id: string;
  apiToken: string;
  webhookSecret: string;
};

function loadMailboxes(): MailboxConfig[] {
  const raw = Deno.env.get("HOSTINGER_MAILBOXES") ?? "";
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((m) =>
      m && typeof m.addr === "string" && typeof m.id === "string" &&
      typeof m.apiToken === "string" && typeof m.webhookSecret === "string"
    );
  } catch {
    return [];
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const mailboxes = loadMailboxes();
  if (mailboxes.length === 0) {
    return json({ error: "HOSTINGER_MAILBOXES not configured" }, 500);
  }

  const auth = req.headers.get("authorization") ?? "";
  const mb = mailboxes.find((m) => constantTimeEqual(auth, `Bearer ${m.webhookSecret}`));
  if (!mb) {
    return json({ error: "unauthorized" }, 401);
  }
  const { addr: mailboxAddr, id: mailboxId, apiToken } = mb;

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  // Debug: capture every real Hostinger payload so we can learn its shape.
  const sbEarly = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const headersObj: Record<string, string> = {};
  req.headers.forEach((v, k) => { headersObj[k] = v; });
  await sbEarly.from("webhook_debug").insert({
    mailbox: mailboxAddr,
    payload,
    headers: headersObj,
  });

  // Hostinger's real payload puts everything under `data` — no `uid` field.
  const data = payload?.data ?? {};
  const eventType: string = payload?.event ?? payload?.type ?? "message.received";

  if (eventType !== "message.received") {
    return json({ ok: true, skipped: `event ${eventType}` });
  }

  const messageId = String(data.messageId ?? data["message-id"] ?? "").trim();
  if (!messageId) {
    return json({ ok: true, skipped: "no messageId in payload" });
  }

  // Skip Hostinger's built-in test-delivery payload — otherwise we'd try to
  // auto-reply to sender@example.com on every /test call.
  if (messageId.includes("test-message-id@example.com")) {
    return json({ ok: true, skipped: "hostinger test payload" });
  }

  // Parse "Name <email@x>" or a bare email into name + address.
  const rawFrom = String(data.from ?? "").trim();
  let fromName = "", fromAddr = "unknown@unknown";
  const nameEmail = rawFrom.match(/^\s*(.*?)\s*<\s*([^>]+)\s*>\s*$/);
  if (nameEmail) {
    fromName = nameEmail[1].replace(/^"|"$/g, "").trim();
    fromAddr = nameEmail[2].trim();
  } else if (rawFrom.includes("@")) {
    fromAddr = rawFrom;
  }

  const toAddrs: string[] = Array.isArray(data.to)
    ? data.to.map((v: unknown) => String(v))
    : (typeof data.to === "string" ? [data.to] : []);
  const subject: string = String(data.subject ?? "");
  const receivedAt: string = data.date
    ? new Date(String(data.date)).toISOString()
    : new Date().toISOString();
  const plainBody: string = String(data.plainBody ?? "");
  const snippet = plainBody.replace(/\s+/g, " ").trim().slice(0, 280);
  const folder = "INBOX";
  // Use messageId as our unique key (guaranteed unique per email by RFC 5322).
  const uidKey = messageId;

  const autoReply = isAutoReply(subject, fromAddr);
  const category = triage(subject, fromAddr, mailboxAddr);

  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Reserve a ticket id (skip for auto-replies, they don't get an ack).
  let ticketId: string | null = null;
  if (!autoReply) {
    const { data: t, error: tErr } = await sb.rpc("next_email_ticket_id");
    if (!tErr && typeof t === "string") ticketId = t;
  }

  // Store the email. Unique on (mailbox, folder, message_uid) — dupes silently ignored.
  const { error: insErr } = await sb
    .from("incoming_emails")
    .insert({
      mun_id: MUN_ID,
      mailbox: mailboxAddr,
      folder,
      message_uid: uidKey,
      message_id: messageId,
      from_email: fromAddr,
      from_name: fromName,
      to_emails: toAddrs,
      subject,
      snippet,
      received_at: receivedAt,
      category,
      ticket_id: ticketId,
      is_auto_reply: autoReply,
    });

  // Ignore unique-violation (duplicate delivery) — everything else is a real error.
  if (insErr && !String(insErr.message).includes("duplicate key")) {
    return json({ error: "db insert failed", detail: insErr.message }, 500);
  }

  // Nothing more to do for auto-replies / bounces.
  if (autoReply) {
    return json({ ok: true, messageId, category, action: "logged_as_auto_reply" });
  }

  // Fire push to admins (best-effort).
  const pushPayload = {
    template: "news_alert",
    vars: { message: `📧 ${category.toUpperCase()} · ${subject || "(no subject)"} — ${fromAddr}` },
    to_role: "admin",
    mun_id: MUN_ID,
    url: `/admin-panel.html#inbox/${ticketId ?? ""}`,
  };
  try {
    await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push-i18n`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
      },
      body: JSON.stringify(pushPayload),
    });
  } catch (_) { /* push failure is non-fatal */ }

  // Send bilingual auto-ack via Hostinger, threaded via inReplyTo.
  if (ticketId) {
    const reply = buildAutoReply({
      ticketId,
      originalSubject: subject,
      fromName,
      fromAddr,
      category,
      mailboxAddr,
    });

    try {
      // Threading via inReplyTo requires a UID we don't have from the webhook,
      // so we send a fresh reply (still shows as "Re:" thanks to subject).
      const sendRes = await hostingerPost(
        `/api/v1/mailboxes/${encodeURIComponent(mailboxId)}/send`,
        apiToken,
        {
          to: [fromAddr],
          subject: reply.subject,
          text: reply.text,
          html: reply.html,
          displayName: reply.displayName,
        },
      );
      if (sendRes.ok || sendRes.status === 204) {
        await sb.from("incoming_emails")
          .update({ replied: true })
          .eq("mailbox", mailboxAddr)
          .eq("folder", folder)
          .eq("message_uid", uidKey);
      }
    } catch (_) { /* auto-reply failure is non-fatal */ }
  }

  return json({ ok: true, messageId, category, ticket: ticketId });
});

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
