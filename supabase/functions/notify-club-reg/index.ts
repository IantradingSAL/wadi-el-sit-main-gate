// notify-club-reg — one e-mail to the club's organizers whenever somebody
// registers for the tournament (games.html). Called by the club_reg_tg trigger
// through pg_net — never by the browser, same shape as notify-approval.
//
// Recipients are resolved live by club_reg_recipients(): everyone who holds
// `club_games_manage` AND switched 📧 on for the `club_game_reg` event in the
// notification matrix. No recipients configured → nothing to send, and that is
// fine: the push channel and the admin sheet still tell the story.
//
// verify_jwt = false, because pg_net posts without a JWT. Safe by the same
// argument as notify-approval: the function accepts only an id it looks up
// itself, and the worst a stranger can trigger is the e-mail the organizers
// asked for.

const BREVO_URL    = "https://api.brevo.com/v3/smtp/email";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const BREVO_KEY    = Deno.env.get("BREVO_API_KEY") || "";

const SENDER = { email: "noreply@municipality-wadi-el-sitt.org", name: "وادي الست" };
const PORTAL = "https://app.municipality-wadi-el-sitt.org";

const GAME: Record<string, string> = {
  frangieh:  "🎲 طاولة — فرنجية",
  mahbouseh: "🎲 طاولة — محبوسة",
  tarneeb:   "♠️ ورق — طرنيب",
  arbaamie:  "♥️ ورق — أربعمية (400)",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { "Content-Type": "application/json" },
  });
}
function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, ch => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]!
  ));
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY || !BREVO_KEY) return json({ error: "creds missing" }, 500);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }
  const id = body?.id;
  if (!id || typeof id !== "string") return json({ error: "body must include id" }, 400);

  const r = await fetch(`${SUPABASE_URL}/rest/v1/club_game_regs?id=eq.${encodeURIComponent(id)}&select=*`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!r.ok) return json({ error: "lookup failed" }, 502);
  const rows = await r.json();
  const reg = Array.isArray(rows) && rows.length ? rows[0] : null;
  if (!reg) return json({ ok: true, skipped: "not found" });

  const rp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/club_reg_recipients`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: "{}",
  });
  const emails: string[] = rp.ok ? (await rp.json() ?? []) : [];
  if (!emails.length) return json({ ok: true, skipped: "no recipients opted in" });

  const g = GAME[reg.game] ?? reg.game;
  const who = reg.team_name
    ? `${reg.team_name} (${reg.p1_name} + ${reg.p2_name})`
    : reg.p1_name + (reg.p2_name ? ` + ${reg.p2_name}` : "");
  const subject = `🎲 تسجيل جديد في البطولة — ${who}`;

  const rows2 = [
    ["اللعبة", g],
    ["المشارك", who],
    ["الهاتف", reg.p1_phone + (reg.p2_phone ? ` · ${reg.p2_phone}` : "")],
    ["الطاولة", reg.table_label],
    ["الرسم", `${reg.fee}$` + (reg.own_board ? " (أحضر طاولته — 5$)" : "")],
    ["الصورة", (reg.p1_photo || reg.p2_photo) ? "📸 أرفق صورة" : "—"],
  ].map(([k, v]) =>
    `<tr><td style="padding:7px 12px;color:#64748b;white-space:nowrap;border-bottom:1px solid #eef2f7">${esc(k)}</td>` +
    `<td style="padding:7px 12px;font-weight:700;border-bottom:1px solid #eef2f7">${esc(v)}</td></tr>`).join("");

  const htmlContent = `<!doctype html><html dir="rtl" lang="ar"><body style="margin:0;background:#f1f5f9;padding:24px;font-family:Tahoma,Arial,sans-serif">
<div style="max-width:560px;margin:auto;background:#fff;border:1px solid #e2e8f0;border-radius:14px;overflow:hidden">
  <div style="background:#0f4d82;color:#fff;padding:16px 18px">
    <div style="font-size:16px;font-weight:800">🎲 تسجيل جديد — بطولة وادي الست</div>
    <div style="font-size:12px;opacity:.85;margin-top:3px">الطاولة والورق · وادي الست</div>
  </div>
  <div style="padding:18px">
    <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #eef2f7;border-radius:8px">${rows2}</table>
    <div style="margin-top:18px;text-align:center">
      <a href="${PORTAL}/games.html" style="display:inline-block;background:#0f4d82;color:#fff;text-decoration:none;font-weight:800;font-size:14px;padding:12px 22px;border-radius:10px">🎯 فتح شاشة البطولة</a>
    </div>
    <p style="margin:16px 0 0;font-size:11.5px;color:#94a3b8;line-height:1.7">رسالة آلية — تصلك لأنك فعّلت 📧 لحدث «تسجيل في البطولة».</p>
  </div>
</div>
</body></html>`;

  let sent = false, note = "";
  try {
    const br = await fetch(BREVO_URL, {
      method: "POST",
      headers: { "api-key": BREVO_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ sender: SENDER, to: emails.map(e => ({ email: e })), subject, htmlContent }),
    });
    sent = br.ok;
    note = sent ? `sent to ${emails.length}` : `Brevo ${br.status}`;
  } catch (e) { note = String(e).slice(0, 200); }

  return json({ ok: sent, note });
});
