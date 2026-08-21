// ═══════════════════════════════════════════════════════════════════════════
// wadi-shell.js — never show a resident a blank white page.
//
// WHY THIS FILE EXISTS
// Three pages — mrs.html, admin-push.html and news-admin.html — build every
// pixel from JavaScript after `window.supabase.createClient(...)`. When the
// Supabase CDN is slow or unreachable, that line throws, the whole inline
// script stops, and the page paints nothing at all: no header, no logo, no
// spinner, no message. Measured with the CDN blocked, those three rendered
// zero characters of visible text while every other page still drew its shell.
//
// A resident on a weak connection in the village does not conclude "the
// network is bad". They conclude the app is broken.
//
// WHAT IT DOES
// It watches. If, a few seconds after load, the page has painted essentially
// nothing, it puts up the municipality's own panel — logo, an explanation in
// Arabic, and a retry button. It never touches a page that rendered normally.
//
// It is deliberately not a fix for the underlying design. The real fix is for
// those pages to carry a static header in their HTML instead of building it
// from script. This makes sure that until they do, the failure is legible.
// ═══════════════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  var GRACE_MS = 4000;      // long enough for a slow village connection
  var shown = false;

  // Chrome the portal adds to every page. None of it is evidence that the
  // PAGE rendered: news-admin.html painted nothing but still measured 59
  // characters, because the install banner had appeared.
  var CHROME = ['pwa-install-banner', 'pwa-ios-modal', 'wadi-update-bar',
                'wadi-session-bar', 'toast'];

  function isChrome(el) {
    if (!el || el.nodeType !== 1) return true;
    if (el.id && CHROME.indexOf(el.id) !== -1) return true;
    if (el.classList && (el.classList.contains('wadi-gate') ||
                         el.classList.contains('toast'))) return true;
    if (el.getAttribute && el.getAttribute('role') === 'alert') return true;
    return false;
  }

  function pageLooksEmpty() {
    var body = document.body;
    if (!body) return false;          // nothing to attach to yet — try again later

    // Measure from body.innerText, not from each child. innerText on an element
    // that is NOT being rendered falls back to textContent — so summing the
    // children of a page whose panels are all display:none returns the entire
    // hidden markup and the page looks full when it is blank. body itself is
    // always rendered, so its innerText is exactly what a resident can read.
    var visible = (body.innerText || '').replace(/\s+/g, ' ').trim();

    // Whatever the portal itself put on screen is not evidence the PAGE
    // rendered: news-admin.html painted nothing but still measured 59
    // characters, because the install banner had appeared.
    var chrome = 0;
    var sel = CHROME.map(function (id) { return '#' + id; })
                    .concat(['.wadi-gate', '[role="alert"]', '.toast']).join(',');
    var nodes = document.querySelectorAll(sel);
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!el.getClientRects().length) continue;               // not on screen
      chrome += (el.innerText || '').replace(/\s+/g, ' ').trim().length;
    }

    return (visible.length - chrome) <= 40;
  }


  function show() {
    if (shown || !document.body) return;
    if (!pageLooksEmpty()) return;
    shown = true;

    var wrap = document.createElement('div');
    wrap.dir = 'rtl';
    wrap.setAttribute('role', 'alert');
    wrap.style.cssText =
      'position:fixed;inset:0;z-index:99998;background:#f5f7fa;color:#12212e;' +
      'display:flex;align-items:center;justify-content:center;padding:24px;' +
      'font-family:Tajawal,Tahoma,Arial,sans-serif;text-align:center';

    var card = document.createElement('div');
    card.style.cssText = 'max-width:360px;display:flex;flex-direction:column;' +
      'align-items:center;gap:14px';

    var logo = document.createElement('img');
    logo.src = 'icons/apple-touch-icon.png';
    logo.alt = '';
    logo.setAttribute('aria-hidden', 'true');
    logo.style.cssText = 'width:64px;height:64px;border-radius:50%;background:#fff;' +
      'object-fit:contain;box-shadow:0 4px 14px rgba(15,77,130,.2)';

    var h = document.createElement('div');
    h.textContent = 'تعذّر تحميل الصفحة';
    h.style.cssText = 'font-size:18px;font-weight:800;color:#0f4d82';

    var p = document.createElement('div');
    p.textContent = 'يبدو أنّ الاتصال بالإنترنت ضعيف أو منقطع. تحقّق من الاتصال ثم أعد المحاولة.';
    p.style.cssText = 'font-size:14px;line-height:1.7;color:#4a5866';

    var row = document.createElement('div');
    row.style.cssText = 'display:flex;gap:9px;flex-wrap:wrap;justify-content:center;margin-top:4px';

    var retry = document.createElement('button');
    retry.type = 'button';
    retry.textContent = '🔄 إعادة المحاولة';
    retry.style.cssText = 'padding:11px 20px;border:none;border-radius:10px;' +
      'background:linear-gradient(135deg,#0f4d82,#1a6eb5);color:#fff;' +
      'font-family:inherit;font-size:15px;font-weight:800;cursor:pointer';
    retry.onclick = function () { location.reload(); };

    var home = document.createElement('a');
    home.href = 'index.html';
    home.textContent = '🏛️ البوابة الرئيسية';
    home.style.cssText = 'padding:11px 20px;border-radius:10px;background:#fff;' +
      'border:1px solid #d5dee6;color:#0f4d82;text-decoration:none;' +
      'font-size:15px;font-weight:700';

    row.appendChild(retry);
    row.appendChild(home);
    [logo, h, p, row].forEach(function (el) { card.appendChild(el); });
    wrap.appendChild(card);
    document.body.appendChild(wrap);
  }

  function arm() {
    setTimeout(show, GRACE_MS);
    // A page whose script died before <body> was usable gets a second look.
    setTimeout(show, GRACE_MS + 2500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', arm);
  } else {
    arm();
  }

  // A script that dies before painting is exactly the case this exists for.
  window.addEventListener('error', function () { setTimeout(show, 1200); });
})();
