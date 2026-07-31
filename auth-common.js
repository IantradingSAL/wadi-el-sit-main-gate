/**
 * auth-common.js
 * ---------------------------------------------------------------
 * Adds a "نسيت كلمة المرور؟" (Forgot password?) link next to every
 * Supabase login form on the site, wired to send a password-reset
 * email that lands on reset-password.html.
 *
 * Include with:  <script src="auth-common.js" defer></script>
 * (must be loaded AFTER the @supabase/supabase-js CDN script)
 * ---------------------------------------------------------------
 */
(function () {
  var SUPABASE_URL = 'https://onjbwhkmmtqnymhjnplw.supabase.co';
  var SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uamJ3aGttbXRxbnltaGpucGx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MDY4MjUsImV4cCI6MjA5MDM4MjgyNX0.lhlsRdOqVHZuOXCJa0lCNuZkYJHhf1AZ_zOwqHHAeG4';
  var LINK_TEXT = 'نسيت كلمة المرور؟';
  var LINK_STYLE = 'display:block;margin-top:10px;color:#0f4d82;font-weight:700;font-size:12.5px;text-decoration:none;text-align:center;cursor:pointer';

  var _sb = null;
  function getClient() {
    if (_sb) return _sb;
    if (typeof window.supabase === 'undefined' || !window.supabase.createClient) return null;
    try {
      _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, { realtime: { enabled: false } });
    } catch (e) { return null; }
    return _sb;
  }

  function redirectTarget() {
    return location.origin
      + location.pathname.replace(/[^\/]+$/, '')
      + 'reset-password.html';
  }

  window.wadiSendPasswordReset = async function (email) {
    email = String(email || '').trim();
    if (!email) return { error: 'أدخل البريد الإلكتروني.' };
    var client = getClient();
    if (!client) return { error: 'مكتبة Supabase غير محمَّلة.' };
    try {
      var r = await client.auth.resetPasswordForEmail(email, { redirectTo: redirectTarget() });
      if (r && r.error) return { error: r.error.message };
      return { ok: true, email: email };
    } catch (e) {
      return { error: e.message || String(e) };
    }
  };

  async function handleClick(emailInput, feedbackTarget) {
    var em = emailInput ? String(emailInput.value || '').trim() : '';
    if (!em) {
      em = String(window.prompt('أدخل بريدك الإلكتروني لإرسال رابط إعادة تعيين كلمة المرور:') || '').trim();
      if (!em) return;
    }
    showFeedback(feedbackTarget, '⏳ جاري إرسال رابط إعادة التعيين…', 'info');
    var r = await window.wadiSendPasswordReset(em);
    if (r.error) showFeedback(feedbackTarget, '⚠️ ' + r.error, 'err');
    else showFeedback(feedbackTarget, '✅ تم إرسال رابط إعادة تعيين كلمة المرور إلى ' + r.email + '. تفقّد صندوق الوارد (وسلة الرسائل غير المرغوب فيها).', 'ok');
  }

  function showFeedback(target, text, kind) {
    if (!target) { window.alert(text); return; }
    target.textContent = text;
    var base = 'display:block;margin-top:10px;padding:9px 12px;border-radius:9px;font-size:12.5px;line-height:1.6;text-align:right;';
    if (kind === 'ok') target.style.cssText = base + 'background:#e6f4ea;color:#1e5429;border-right:4px solid #1e8e3e;';
    else if (kind === 'err') target.style.cssText = base + 'background:#fee2e2;color:#bf2424;border-right:4px solid #bf2424;';
    else target.style.cssText = base + 'background:#eef5fc;color:#0f4d82;border-right:4px solid #1a6eb5;';
  }

  function findEmailInput(scope, pwInput) {
    var candidates = scope.querySelectorAll(
      'input[type="email"], input[autocomplete="email"], input[autocomplete="username"], input[name*="mail" i], input[id*="mail" i], input[id*="em" i], input[placeholder*="mail" i], input[placeholder*="بريد" i]'
    );
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i] !== pwInput) return candidates[i];
    }
    var all = scope.querySelectorAll('input');
    for (var j = 0; j < all.length; j++) {
      var el = all[j];
      if (el === pwInput) return null;
      if (el.type === 'text' || el.type === 'email' || el.type === '') return el;
    }
    return null;
  }

  function inject() {
    var pws = document.querySelectorAll('input[type="password"]');
    for (var i = 0; i < pws.length; i++) {
      var pw = pws[i];
      if (pw.dataset.wadiForgot === '1') continue;
      if (pw.getAttribute('autocomplete') === 'new-password') continue;
      var scope = pw.closest('form') || pw.closest('.login-card') || pw.closest('.card') || pw.closest('#LOGIN_VIEW') || pw.parentElement && pw.parentElement.parentElement || document.body;
      var em = findEmailInput(scope, pw);
      if (!em) continue;
      pw.dataset.wadiForgot = '1';
      var link = document.createElement('a');
      link.href = '#';
      link.textContent = LINK_TEXT;
      link.className = 'wadi-forgot-link';
      link.setAttribute('style', LINK_STYLE);
      var fb = document.createElement('div');
      fb.className = 'wadi-forgot-feedback';
      fb.setAttribute('style', 'min-height:0');
      (function (emInput, feedback) {
        link.addEventListener('click', function (e) { e.preventDefault(); handleClick(emInput, feedback); });
      })(em, fb);
      var host = pw.closest('.fg') || pw.parentElement;
      if (host && host.parentNode) {
        host.parentNode.insertBefore(link, host.nextSibling);
        host.parentNode.insertBefore(fb, link.nextSibling);
      }
    }
  }

  function start() {
    inject();
    try {
      var mo = new MutationObserver(function () { inject(); });
      mo.observe(document.body, { childList: true, subtree: true });
    } catch (e) { /* ignore */ }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
