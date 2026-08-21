// ═══════════════════════════════════════════════════════════════════════════
// wadi-dialogs.js — the portal asks in its own voice.
//
// WHY THIS FILE EXISTS
// The portal made 105 native dialog calls: 32 alert(), 52 confirm(), 21
// prompt(). In a browser those are merely ugly. In a wrapped app — which is
// what this is becoming — every one of them renders as a system dialog stamped
// with the website's domain, in the system font, in the system's language
// direction. It is the clearest possible signal to a resident that they are
// not in an app but on a web page.
//
// They also cannot be styled, cannot be translated, and on iOS a prompt() in a
// standalone PWA is unreliable.
//
// WHAT IT PROVIDES
//   await wadiConfirm(message, opts)  → Promise<boolean>
//   await wadiAlert(message, opts)    → Promise<void>
//
// and it replaces window.alert with the styled version. alert() returns
// nothing and no caller reads its result, so that swap is safe. confirm() and
// prompt() are NOT replaced silently: both are synchronous, and quietly
// returning a promise where code expects a boolean would make every
// `if (!confirm(...))` guard pass — deleting municipal records without asking.
// Those call sites are converted explicitly, one at a time, to await.
//
// wadiAskPassword() in auth-common.js already covers the masked-input case.
// ═══════════════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  var Z = 100001;   // above wadiAskPassword's overlay

  function el(tag, css, text) {
    var n = document.createElement(tag);
    if (css) n.style.cssText = css;
    if (text != null) n.textContent = text;
    return n;
  }

  function open(opts) {
    return new Promise(function (resolve) {
      var ov = el('div', 'position:fixed;inset:0;z-index:' + Z + ';' +
        'background:rgba(12,18,26,.55);display:flex;align-items:center;' +
        'justify-content:center;padding:16px;font-family:Tajawal,Tahoma,Arial,sans-serif');
      ov.dir = 'rtl';
      ov.setAttribute('role', 'dialog');
      ov.setAttribute('aria-modal', 'true');

      var box = el('div', 'background:#fff;color:#12212e;border-radius:14px;' +
        'padding:20px;width:100%;max-width:390px;box-shadow:0 18px 48px rgba(0,0,0,.35);' +
        'display:flex;flex-direction:column;gap:12px');

      if (opts.title) {
        var h = el('div', 'font-size:16px;font-weight:800;color:#0f4d82', opts.title);
        box.appendChild(h);
      }

      var msg = el('div', 'font-size:14.5px;line-height:1.75;color:#4a5866;' +
        'white-space:pre-wrap;word-break:break-word', String(opts.message == null ? '' : opts.message));
      box.appendChild(msg);

      var row = el('div', 'display:flex;gap:9px;margin-top:4px');

      function close(value) {
        document.removeEventListener('keydown', onKey, true);
        if (ov.parentNode) ov.parentNode.removeChild(ov);
        resolve(value);
      }

      var ok = el('button', 'flex:1;padding:12px;border:none;border-radius:10px;' +
        'background:' + (opts.danger ? '#9e2420' : 'linear-gradient(135deg,#0f4d82,#1a6eb5)') +
        ';color:#fff;font-family:inherit;font-size:15px;font-weight:800;cursor:pointer',
        opts.okText || 'موافق');
      ok.type = 'button';
      ok.onclick = function () { close(true); };

      if (opts.kind === 'confirm') {
        var no = el('button', 'flex:1;padding:12px;border:1px solid #d5dee6;' +
          'border-radius:10px;background:#fff;color:#4a5866;font-family:inherit;' +
          'font-size:15px;font-weight:700;cursor:pointer', opts.cancelText || 'إلغاء');
        no.type = 'button';
        no.onclick = function () { close(false); };
        row.appendChild(no);
      }
      row.appendChild(ok);
      box.appendChild(row);
      ov.appendChild(box);

      function onKey(e) {
        if (e.key === 'Escape') { e.preventDefault(); close(opts.kind === 'confirm' ? false : undefined); }
        else if (e.key === 'Enter') { e.preventDefault(); close(true); }
      }
      document.addEventListener('keydown', onKey, true);

      // clicking the backdrop is a cancel, never a confirm
      ov.addEventListener('click', function (e) {
        if (e.target === ov) close(opts.kind === 'confirm' ? false : undefined);
      });

      (document.body || document.documentElement).appendChild(ov);
      setTimeout(function () { ok.focus(); }, 30);
    });
  }

  window.wadiConfirm = function (message, opts) {
    opts = opts || {};
    return open({
      kind: 'confirm', message: message,
      title: opts.title || 'تأكيد',
      okText: opts.okText || 'تأكيد',
      cancelText: opts.cancelText || 'إلغاء',
      danger: opts.danger
    });
  };

  window.wadiAlert = function (message, opts) {
    opts = opts || {};
    return open({ kind: 'alert', message: message, title: opts.title || 'تنبيه',
                  okText: opts.okText || 'حسناً' });
  };

  // ── text input, and the multi-field version ────────────────────────────
  // prompt() chained three times — which is how a new payee was collected on
  // the irrigation screen — is miserable on a phone: three system dialogs, no
  // way back, and on iOS in a standalone PWA it is unreliable. wadiForm asks
  // once.
  function openForm(opts) {
    return new Promise(function (resolve) {
      var ov = el('div', 'position:fixed;inset:0;z-index:' + Z + ';' +
        'background:rgba(12,18,26,.55);display:flex;align-items:center;' +
        'justify-content:center;padding:16px;font-family:Tajawal,Tahoma,Arial,sans-serif');
      ov.dir = 'rtl';
      ov.setAttribute('role', 'dialog');
      ov.setAttribute('aria-modal', 'true');

      var box = el('div', 'background:#fff;color:#12212e;border-radius:14px;' +
        'padding:20px;width:100%;max-width:390px;box-shadow:0 18px 48px rgba(0,0,0,.35);' +
        'display:flex;flex-direction:column;gap:11px;max-height:88vh;overflow:auto');

      if (opts.title) box.appendChild(el('div',
        'font-size:16px;font-weight:800;color:#0f4d82', opts.title));
      if (opts.note) box.appendChild(el('div',
        'font-size:12.5px;color:#7a8894;line-height:1.6', opts.note));

      var inputs = [];
      opts.fields.forEach(function (f) {
        var wrap = el('div', 'display:flex;flex-direction:column;gap:4px');
        wrap.appendChild(el('label', 'font-size:12.5px;font-weight:700;color:#4a5866', f.label));
        var i;
        if (f.type === 'checkbox') {
          var row = el('label', 'display:flex;align-items:center;gap:8px;cursor:pointer;font-size:14px');
          i = document.createElement('input');
          i.type = 'checkbox';
          i.checked = !!f.value;
          i.style.cssText = 'width:20px;height:20px;accent-color:#1a6eb5';
          row.appendChild(i);
          row.appendChild(el('span', 'color:#4a5866', f.label));
          wrap.innerHTML = '';
          wrap.appendChild(row);
        } else {
          i = document.createElement('input');
          i.type = f.type || 'text';
          i.value = f.value == null ? '' : f.value;
          if (f.placeholder) i.placeholder = f.placeholder;
          if (f.inputmode) i.setAttribute('inputmode', f.inputmode);
          if (f.dir) i.dir = f.dir;
          // 16px or iOS zooms the page when the field takes focus
          i.style.cssText = 'padding:11px 12px;border:1px solid #d5dee6;border-radius:9px;' +
            'font-family:inherit;font-size:16px;width:100%;box-sizing:border-box';
          wrap.appendChild(i);
        }
        inputs.push({ key: f.key, el: i, type: f.type });
        box.appendChild(wrap);
      });

      var err = el('div', 'font-size:12.5px;color:#9e2420;min-height:16px');
      box.appendChild(err);

      var row2 = el('div', 'display:flex;gap:9px');
      function close(v) {
        document.removeEventListener('keydown', onKey, true);
        if (ov.parentNode) ov.parentNode.removeChild(ov);
        resolve(v);
      }
      var cancel = el('button', 'flex:1;padding:12px;border:1px solid #d5dee6;border-radius:10px;' +
        'background:#fff;color:#4a5866;font-family:inherit;font-size:15px;font-weight:700;cursor:pointer',
        opts.cancelText || 'إلغاء');
      cancel.type = 'button';
      cancel.onclick = function () { close(null); };

      var save = el('button', 'flex:1;padding:12px;border:none;border-radius:10px;' +
        'background:linear-gradient(135deg,#0f4d82,#1a6eb5);color:#fff;font-family:inherit;' +
        'font-size:15px;font-weight:800;cursor:pointer', opts.okText || 'حفظ');
      save.type = 'button';
      save.onclick = function () {
        var out = {};
        for (var i = 0; i < inputs.length; i++) {
          var f = opts.fields[i];
          var v = inputs[i].type === 'checkbox' ? inputs[i].el.checked : inputs[i].el.value.trim();
          if (f.required && !v) { err.textContent = 'هذا الحقل مطلوب: ' + f.label; inputs[i].el.focus(); return; }
          out[inputs[i].key] = v;
        }
        close(out);
      };
      row2.appendChild(cancel);
      row2.appendChild(save);
      box.appendChild(row2);
      ov.appendChild(box);

      function onKey(e) {
        if (e.key === 'Escape') { e.preventDefault(); close(null); }
        else if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'checkbox') {
          e.preventDefault(); save.click();
        }
      }
      document.addEventListener('keydown', onKey, true);
      ov.addEventListener('click', function (e) { if (e.target === ov) close(null); });

      (document.body || document.documentElement).appendChild(ov);
      setTimeout(function () { if (inputs[0]) inputs[0].el.focus(); }, 30);
    });
  }

  window.wadiForm = openForm;

  window.wadiPrompt = function (message, opts) {
    opts = opts || {};
    return openForm({
      title: opts.title || 'إدخال',
      note: opts.note,
      okText: opts.okText || 'موافق',
      fields: [{ key: 'v', label: message, value: opts.value, type: opts.type || 'text',
                 placeholder: opts.placeholder, inputmode: opts.inputmode, dir: opts.dir,
                 required: opts.required !== false }]
    }).then(function (r) { return r ? r.v : null; });
  };

  // Safe to swap: alert() returns undefined and nothing reads it.
  // NOT done for confirm() or prompt() — see the note at the top of this file.
  var nativeAlert = window.alert;
  window.alert = function (m) {
    try { window.wadiAlert(m); }
    catch (e) { nativeAlert.call(window, m); }
  };
})();
