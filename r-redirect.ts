// supabase/functions/r/index.ts
// ═══════════════════════════════════════════════════════════════════════════
// Short-link redirect edge function for بلدية وادي الست (Wadi El Sit)
// ═══════════════════════════════════════════════════════════════════════════
//
// Deployed with `verify_jwt: false` — public endpoint.
//   GET /functions/v1/r/<code>  →  302 to short_links.url for that code
//
// Vercel rewrites `/r/<code>` on the app domain to this endpoint so the
// URLs sent to WhatsApp look like:
//     https://app.municipality-wadi-el-sitt.org/r/<caseId>-<idx>
//
// Rows in short_links are inserted by citizen.html when an emergency
// report with photos is submitted; the redirect target is the signed
// URL of the uploaded file in the private `case-documents` bucket.
// ═══════════════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const NOT_FOUND_HTML =
  `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">` +
  `<title>404</title><meta name="viewport" content="width=device-width,initial-scale=1">` +
  `<style>body{font-family:system-ui,'Tajawal',sans-serif;background:#f7f8fb;color:#1a1a2e;` +
  `display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;` +
  `text-align:center}div{max-width:420px}h1{font-size:64px;margin:0 0 8px;color:#dc2626}` +
  `p{font-size:15px;color:#555;line-height:1.6}</style></head><body><div><h1>404</h1>` +
  `<p>الرابط غير موجود أو انتهت صلاحيته.<br>The link is not found or has expired.</p>` +
  `</div></body></html>`;

Deno.serve(async (req: Request) => {
  try {
    const u = new URL(req.url);
    const parts = u.pathname.split("/").filter(Boolean);
    const code = parts.length ? parts[parts.length - 1] : "";
    if (!code) return notFound();

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false },
    });

    const { data, error } = await sb
      .from("short_links")
      .select("url, expires_at")
      .eq("code", code)
      .maybeSingle();

    if (error || !data || !data.url) return notFound();
    if (data.expires_at && new Date(data.expires_at) < new Date()) return notFound();

    return new Response(null, {
      status: 302,
      headers: {
        Location: data.url,
        "Cache-Control": "private, max-age=60",
      },
    });
  } catch (_e) {
    return notFound();
  }
});

function notFound(): Response {
  return new Response(NOT_FOUND_HTML, {
    status: 404,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
