// notify-approval — one email to the municipality whenever something lands in
// `approval_requests`: a coop seller or delivery agent registering, a phonebook
// entry or edit awaiting review, or a new account.
//
// Called by public.approval_notify() through pg_net, from a database trigger —
// NOT from the browser. That is the whole point: coop.html used to fire the old
// notify-coop-registration itself, so closing the tab lost the notification.
//
// verify_jwt = false, because pg_net posts without a Supabase JWT. The function
// is safe to call by anyone: it accepts only an id, sends only for a row that is
// still pending and not yet notified, stamps notified_at before returning, and
// answers with nothing but {ok}. So the worst a stranger can do — with an id
// they would have to guess — is deliver the email the municipality wanted.
//
// Secrets used (all already configured for the other notifiers):
//   BREVO_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

const BREVO_URL    = "https://api.brevo.com/v3/smtp/email";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const BREVO_KEY    = Deno.env.get("BREVO_API_KEY") || "";

const SENDER = { email: "noreply@municipality-wadi-el-sitt.org", name: "بلدية وادي الست" };
const PORTAL = "https://app.municipality-wadi-el-sitt.org";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const KIND: Record<string, { emoji: string; label: string; blurb: string; screen: string }> = {
  coop_seller:    { emoji: "🛒", label: "بائع جديد في التعاونية",
                    blurb: "سجّل بائع جديد في تعاونية وادي الست وحسابه موقوف حتى موافقتكم.",
                    screen: "dashboard.html" },
  coop_agent:     { emoji: "🚚", label: "عامل توصيل جديد",
                    blurb: "تقدّم عامل توصيل جديد بطلب الانضمام إلى التعاونية وينتظر مراجعتكم.",
                    screen: "dashboard.html" },
  phonebook_new:  { emoji: "📇", label: "جهة جديدة في دليل البلدية",
                    blurb: "أُضيفت جهة جديدة إلى الدليل ولن تظهر للعامة قبل التحقق منها.",
                    screen: "dashboard.html" },
  phonebook_edit: { emoji: "✏️", label: "تعديل مقترح على الدليل",
                    blurb: "اقترح أحدهم تعديلاً على جهة في الدليل، ولن يُطبَّق قبل موافقتكم.",
                    screen: "dashboard.html" },
  user_account:   { emoji: "👤", label: "حساب جديد على البوابة",
                    blurb: "أُنشئ حساب جديد على بوابة البلدية — يُرجى التأكّد من صاحبه.",
                    screen: "dashboard.html" },
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, ch => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]!
  ));
}

async function rest(path: string, init: RequestInit = {}) {
  return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
}

function whenAr(iso: string | null): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("ar-LB", { timeZone: "Asia/Beirut" });
  } catch { return String(iso); }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST")    return json({ error: "POST only" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return json({ error: "service creds missing" }, 500);
  if (!BREVO_KEY)                    return json({ error: "BREVO_API_KEY not configured" }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const id = body?.id;
  if (!id || typeof id !== "string") return json({ error: "body must include id" }, 400);

  // ── the request itself ──
  const r = await rest(`approval_requests?id=eq.${encodeURIComponent(id)}&select=*`);
  if (!r.ok) return json({ error: "lookup failed" }, 502);
  const rows = await r.json();
  const row = Array.isArray(rows) && rows.length ? rows[0] : null;
  if (!row) return json({ ok: true, skipped: "not found" });
  if (row.status !== "pending") return json({ ok: true, skipped: "not pending" });
  if (row.notified_at)          return json({ ok: true, skipped: "already notified" });

  // ── who to tell ──
  const rp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/approval_recipients`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: "{}",
  });
  const emails: string[] = rp.ok ? (await rp.json() ?? []) : [];
  if (!emails.length) {
    await rest(`approval_requests?id=eq.${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ notify_note: "لا مستلمين مضبوطين" }),
    });
    return json({ ok: false, error: "no recipients configured" }, 200);
  }

  const k = KIND[row.kind] ?? { emoji: "🔔", label: row.kind, blurb: "طلب ينتظر التحقق.", screen: "dashboard.html" };
  const subject = `${k.emoji} ${k.label} بانتظار التحقق — ${row.title}`;

  const summary = (row.summary && typeof row.summary === "object") ? row.summary : {};
  const detailRows = Object.entries(summary)
    .filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== "")
    .map(([key, v]) =>
      `<tr><td style="padding:7px 12px;color:#64748b;white-space:nowrap;border-bottom:1px solid #eef2f7">${esc(key)}</td>` +
      `<td style="padding:7px 12px;font-weight:700;border-bottom:1px solid #eef2f7">${esc(v)}</td></tr>`)
    .join("") ||
    `<tr><td style="padding:7px 12px;color:#94a3b8">لا تفاصيل إضافية</td></tr>`;

  // The link must land ON THE RECORD, not on a list to hunt through:
  // dashboard.html#approval=<id> opens that one request with its decision
  // buttons. For a directory row we can go one hop further and name the record
  // inside the phonebook's own review panel.
  const link = `${PORTAL}/dashboard.html#approval=${encodeURIComponent(row.id)}`;
  const deep =
    (row.kind === "phonebook_new" || row.kind === "phonebook_edit")
      ? `${PORTAL}/phonebook.html#review=${encodeURIComponent(row.ref_id)}`
      : "";
  const htmlContent = `<!doctype html><html dir="rtl" lang="ar"><body style="margin:0;background:#f1f5f9;padding:24px;font-family:Tahoma,Arial,sans-serif">
<div style="max-width:560px;margin:auto;background:#fff;border:1px solid #e2e8f0;border-radius:14px;overflow:hidden">
  <div style="background:#0f4d82;color:#fff;padding:16px 18px">
    <div style="font-size:16px;font-weight:800">${k.emoji} ${esc(k.label)}</div>
    <div style="font-size:12px;opacity:.85;margin-top:3px">بلدية وادي الست — قضاء الشوف · جبل لبنان</div>
  </div>
  <div style="padding:18px">
    <p style="margin:0 0 6px;font-size:14px;color:#334155;line-height:1.7">${esc(k.blurb)}</p>
    <p style="margin:0 0 14px;font-size:15px;font-weight:800;color:#0f4d82">${esc(row.title)}</p>
    <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #eef2f7;border-radius:8px">${detailRows}</table>
    <p style="margin:14px 0 4px;font-size:12px;color:#94a3b8">وصل الطلب: ${esc(whenAr(row.requested_at))}</p>
    <div style="margin-top:18px;text-align:center">
      <a href="${link}" style="display:inline-block;background:#0f4d82;color:#fff;text-decoration:none;font-weight:800;font-size:14px;padding:12px 22px;border-radius:10px">🎯 فتح هذا السجل للتحقق</a>
      ${deep ? `<div style="margin-top:10px"><a href="${deep}" style="color:#0f4d82;font-size:12.5px;font-weight:700">أو افتحه في شاشة الدليل ←</a></div>` : ""}
    </div>
    <p style="margin:16px 0 0;font-size:11.5px;color:#94a3b8;line-height:1.7">
      يفتح الزرّ أعلاه هذا الطلب بعينه في لوحة البلدية، بأزرار الموافقة والرفض. هذه رسالة آلية — لا حاجة للرد عليها.
    </p>
  </div>
</div>
</body></html>`;

  let sent = false, note = "";
  try {
    const br = await fetch(BREVO_URL, {
      method: "POST",
      headers: { "api-key": BREVO_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        sender: SENDER,
        to: emails.map(e => ({ email: e })),
        subject,
        htmlContent,
      }),
    });
    sent = br.ok;
    note = sent ? `أُرسل إلى ${emails.length} عنوان` : `Brevo ${br.status}: ${(await br.text()).slice(0, 300)}`;
  } catch (e) {
    note = `send failed: ${String(e).slice(0, 300)}`;
  }

  // notified_at is stamped only on success, so the pg_cron sweep retries a
  // failure instead of leaving the municipality unaware.
  await rest(`approval_requests?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify(sent ? { notified_at: new Date().toISOString(), notify_note: note }
                              : { notify_note: note }),
  });

  return json({ ok: sent });
});
