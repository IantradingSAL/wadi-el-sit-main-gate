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
      em = String(await window.wadiPrompt('أدخل بريدك الإلكتروني لإرسال رابط إعادة تعيين كلمة المرور:',
                    { title: '🔑 إعادة تعيين كلمة المرور', type: 'email', dir: 'ltr' }) || '').trim();
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
      // Always insert the link inside the password input's own parent so it
      // stays in the same container as the input. Anchoring higher (e.g. the
      // outer .fg) risked landing outside the login card on pages where the
      // input sits directly inside a flex-centered card, leaving the link
      // floating in mid-air next to the card.
      if (pw.parentNode) {
        pw.parentNode.insertBefore(link, pw.nextSibling);
        pw.parentNode.insertBefore(fb, link.nextSibling);
      }
    }
  }

  /* ── Masked password prompt ────────────────────────────────────────────
   * Both password paths used prompt(), which shows what is typed in clear
   * text — including the one where an administrator sets someone else's
   * password, in an office, in plain view. This is the same question asked
   * properly: masked, confirmed twice, Enter to submit, Escape to cancel.
   *
   *   var pw = await wadiAskPassword({title:'…', note:'…'});   // null = cancelled
   */
  window.wadiAskPassword = function (opts) {
    opts = opts || {};
    var MIN = opts.min || 8;
    return new Promise(function (resolve) {
      var ov = document.createElement('div');
      ov.dir = 'rtl';
      ov.style.cssText = 'position:fixed;inset:0;z-index:100000;background:rgba(12,18,26,.55);'
        + 'display:flex;align-items:center;justify-content:center;padding:16px;'
        + 'font-family:Tajawal,Tahoma,sans-serif';
      var box = document.createElement('div');
      box.style.cssText = 'background:#fff;color:#1a1a2e;border-radius:14px;padding:18px;'
        + 'width:100%;max-width:380px;box-shadow:0 18px 48px rgba(0,0,0,.35);'
        + 'display:flex;flex-direction:column;gap:10px';
      var h = document.createElement('div');
      h.textContent = opts.title || '🔑 كلمة مرور جديدة';
      h.style.cssText = 'font-size:16px;font-weight:800;color:#0f4d82';
      var note = document.createElement('div');
      note.textContent = opts.note || ('لا تقل عن ' + MIN + ' أحرف');
      note.style.cssText = 'font-size:12.5px;color:#8a95a3';
      var f1 = field('كلمة المرور الجديدة');
      var f2 = field('أعِد إدخالها للتأكيد');
      var err = document.createElement('div');
      err.style.cssText = 'font-size:12.5px;color:#c22;font-weight:700;min-height:16px';
      var row = document.createElement('div');
      row.style.cssText = 'display:flex;gap:8px;margin-top:2px';
      var ok = button('✓ حفظ', 'flex:1;background:linear-gradient(135deg,#1f7a45,#2a9c5a);color:#fff');
      var no = button('إلغاء', 'flex:1;background:#eef1f5;color:#5c6a72');
      row.appendChild(ok); row.appendChild(no);
      box.appendChild(h); box.appendChild(note);
      box.appendChild(f1.wrap); box.appendChild(f2.wrap);
      box.appendChild(err); box.appendChild(row);
      ov.appendChild(box);

      function field(label) {
        var wrap = document.createElement('label');
        wrap.style.cssText = 'display:flex;flex-direction:column;gap:4px;font-size:12.5px;font-weight:700;color:#5c6a72';
        var t = document.createElement('span'); t.textContent = label;
        var i = document.createElement('input');
        i.type = 'password';
        i.autocomplete = 'new-password';
        i.style.cssText = 'border:1.5px solid #d5dfec;border-radius:9px;padding:9px 11px;font-size:15px;'
          + 'font-family:inherit;direction:ltr;text-align:left;background:#f8fbfe';
        wrap.appendChild(t); wrap.appendChild(i);
        return { wrap: wrap, input: i };
      }
      function button(text, css) {
        var b = document.createElement('button');
        b.type = 'button'; b.textContent = text;
        b.style.cssText = 'border:none;border-radius:9px;padding:9px 12px;font-weight:800;'
          + 'font-size:14px;cursor:pointer;font-family:inherit;' + css;
        return b;
      }
      function done(v) {
        document.removeEventListener('keydown', onKey, true);
        ov.remove();
        resolve(v);
      }
      function submit() {
        var a = f1.input.value, b = f2.input.value;
        if (!a || a.length < MIN) { err.textContent = '⚠️ كلمة المرور يجب أن تكون ' + MIN + ' أحرف على الأقل'; f1.input.focus(); return; }
        if (a !== b) { err.textContent = '⚠️ كلمتا المرور غير متطابقتين'; f2.input.value = ''; f2.input.focus(); return; }
        done(a);
      }
      function onKey(e) {
        if (e.key === 'Escape') { e.preventDefault(); done(null); }
        else if (e.key === 'Enter') { e.preventDefault(); submit(); }
      }
      ok.addEventListener('click', submit);
      no.addEventListener('click', function () { done(null); });
      ov.addEventListener('click', function (e) { if (e.target === ov) done(null); });
      document.addEventListener('keydown', onKey, true);
      document.body.appendChild(ov);
      f1.input.focus();
    });
  };

  /* ── Session expiry ────────────────────────────────────────────────────
   * A token refresh can fail — a phone asleep for a day, a revoked session,
   * no signal — and every call after that returns 401. Pages used to show a
   * raw error, or nothing at all, and the clerk kept typing into a form that
   * could no longer save. One watcher, attached to whichever client the page
   * built, says so plainly instead.
   *
   * Attaches to window.sb (what nearly every page names its client) or to a
   * client passed to wadiWatchSession(). Opt out with
   * window.__wadiNoSessionWatch = true before this script loads.
   */
  var _watched = false;

  window.wadiWatchSession = function (client) {
    if (_watched || window.__wadiNoSessionWatch) return false;
    if (!client || !client.auth || typeof client.auth.onAuthStateChange !== 'function') return false;
    _watched = true;
    var hadSession = false;
    try {
      client.auth.getSession().then(function (r) {
        hadSession = !!(r && r.data && r.data.session);
      }).catch(function () {});
    } catch (e) { /* older client shapes */ }
    client.auth.onAuthStateChange(function (event, session) {
      if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') { hadSession = true; return; }
      if (event !== 'SIGNED_OUT' || !hadSession || session) return;
      hadSession = false;
      showSessionEnded();
    });
    return true;
  };

  function showSessionEnded() {
    if (document.getElementById('wadi-session-bar')) return;
    var bar = document.createElement('div');
    bar.id = 'wadi-session-bar';
    bar.dir = 'rtl';
    bar.setAttribute('role', 'alert');
    bar.style.cssText = 'position:fixed;left:12px;right:12px;top:12px;z-index:99999;max-width:560px;'
      + 'margin:0 auto;display:flex;gap:10px;align-items:center;justify-content:space-between;'
      + 'flex-wrap:wrap;background:#8a2b28;color:#fff;border-radius:12px;padding:11px 14px;'
      + 'font-family:Tajawal,Tahoma,sans-serif;font-size:14px;font-weight:700;'
      + 'box-shadow:0 6px 24px rgba(0,0,0,.3)';
    var msg = document.createElement('span');
    msg.textContent = '🔒 انتهت الجلسة — لن يُحفظ أي تعديل قبل تسجيل الدخول من جديد';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = 'تسجيل الدخول';
    btn.style.cssText = 'background:#fff;color:#8a2b28;border:none;border-radius:8px;padding:7px 14px;'
      + 'font-weight:800;font-size:13.5px;cursor:pointer;font-family:inherit';
    btn.addEventListener('click', function () { location.reload(); });
    bar.appendChild(msg); bar.appendChild(btn);
    document.body.appendChild(bar);
  }

  function watchWindowClient() {
    // The page builds its client after this script runs, so look a few times
    // rather than once, then stop.
    var tries = 0;
    var t = setInterval(function () {
      if (window.wadiWatchSession(window.sb) || ++tries > 20) clearInterval(t);
    }, 500);
  }

  function start() {
    inject();
    watchWindowClient();
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
