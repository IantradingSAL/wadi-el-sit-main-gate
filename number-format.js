/* ═══════════════════════════════════════════════════════════════════
   Wadi El Sit — shared number formatting  (number-format.js)

   One rule for the whole portal: every number the user reads or types
   is grouped in thousands with Latin digits —

        156,000,000        not   156000000
        1,250.75           not   1250.75

   ── Display helpers ────────────────────────────────────────────────
     numGroup(v[, maxFrac])   156000000  → "156,000,000"
     numParse(v)              "156,000"  → 156000        (NaN if unparsable)
     numVal(v[, dflt])        same, but falls back to 0 / dflt

   ── Grouped inputs ─────────────────────────────────────────────────
   Mark any money/quantity field with `data-num` and it becomes a
   live-grouped field:

        <input class="fi" id="bf-i-amount" data-num min="0" step="0.01">

   The element is upgraded in place (type=number → text, because a
   native number input refuses to display separators) and its `value`
   property is re-wrapped so existing code keeps working untouched:

        el.value = 156000000        →  shows "156,000,000"
        parseFloat(el.value)        →  156000000   (plain, no commas)

   Fields added to the DOM later (modals rendered via innerHTML) are
   picked up automatically by a MutationObserver.
   ═══════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';
  if (global.numGroup) return;              // already loaded

  var AR_DIGITS = /[٠-٩۰-۹]/g;   // ٠-٩ and ۰-۹
  // Thin/regular spaces, commas (Latin + Arabic ٬), apostrophe groupers.
  var GROUPERS  = /[\s  ,٬’']/g;

  function toLatin(s) {
    return String(s).replace(AR_DIGITS, function (d) {
      var c = d.charCodeAt(0);
      return String(c >= 0x06F0 ? c - 0x06F0 : c - 0x0660);
    });
  }

  /* "١٥٦٬٠٠٠" | "156,000.5" | 156000.5  →  156000.5   (NaN when unparsable) */
  function numParse(v) {
    if (typeof v === 'number') return v;
    if (v == null) return NaN;
    var s = toLatin(v).replace(GROUPERS, '').replace(/٫/g, '.'); // ٫ → .
    if (s === '' || s === '-' || s === '.' || s === '-.') return NaN;
    return Number(s);
  }

  function numVal(v, dflt) {
    var n = numParse(v);
    return isFinite(n) ? n : (dflt === undefined ? 0 : dflt);
  }

  /* 156000000 → "156,000,000" */
  function numGroup(v, maxFrac) {
    var n = numParse(v);
    if (!isFinite(n)) return '';
    return n.toLocaleString('en-US', {
      maximumFractionDigits: (maxFrac == null ? 2 : maxFrac)
    });
  }

  /* Group a half-typed string, keeping a trailing "." and the decimals
     the user is still entering ("1234." → "1,234.", "1234.5" → "1,234.5"). */
  function groupTyped(raw) {
    var s = toLatin(raw).replace(/[^0-9.\-]/g, '');
    var neg = s.charAt(0) === '-';
    s = s.replace(/-/g, '');
    var dot = s.indexOf('.');
    var int = (dot < 0 ? s : s.slice(0, dot));
    var dec = (dot < 0 ? '' : s.slice(dot + 1).replace(/\./g, '').slice(0, 6));
    int = int.replace(/^0+(?=\d)/, '');
    var out = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    if (dot > -1) out += '.' + dec;
    if (neg && (out !== '')) out = '-' + out;
    return out;
  }

  /* ── input upgrade ──────────────────────────────────────────────── */

  var nativeValue = Object.getOwnPropertyDescriptor(
    global.HTMLInputElement ? global.HTMLInputElement.prototype : {}, 'value'
  );

  function rawOf(el)      { return nativeValue.get.call(el); }
  function setRaw(el, s)  { nativeValue.set.call(el, s); }

  /* Re-group the text while keeping the caret next to the same digit. */
  function reformat(el) {
    var before = rawOf(el);
    var caret;
    try { caret = el.selectionStart; } catch (e) { caret = null; }
    // How many digits/dots sit to the left of the caret right now?
    var kept = caret == null ? null
      : (before.slice(0, caret).match(/[0-9.]/g) || []).length;

    var after = groupTyped(before);
    if (after === before && caret == null) return;
    if (after !== before) setRaw(el, after);
    if (kept == null) return;

    // Walk the new text until we've passed `kept` digits/dots.
    var seen = 0, pos = after.length;
    for (var i = 0; i < after.length; i++) {
      if (seen >= kept) { pos = i; break; }
      if (/[0-9.]/.test(after.charAt(i))) seen++;
    }
    if (seen < kept) pos = after.length;
    try { el.setSelectionRange(pos, pos); } catch (e) {}
  }

  function enhance(el) {
    if (!el || el.__numFmt || !nativeValue || !nativeValue.get) return;
    el.__numFmt = true;

    // A native number input can never render "156,000,000".
    if (el.type === 'number') el.type = 'text';
    if (!el.getAttribute('inputmode')) el.setAttribute('inputmode', 'decimal');
    el.setAttribute('autocomplete', 'off');
    if (!el.style.direction) el.style.direction = 'ltr';

    setRaw(el, groupTyped(rawOf(el)));

    // `value` now speaks plain numbers outward and grouped text inward,
    // so every existing parseFloat(el.value) / el.value = n keeps working.
    Object.defineProperty(el, 'value', {
      configurable: true,
      enumerable: true,
      get: function () {
        var n = numParse(rawOf(this));
        return isFinite(n) ? String(n) : '';
      },
      set: function (v) {
        setRaw(this, (v === '' || v == null) ? '' : groupTyped(String(v)));
      }
    });

    // Backspace/Delete sitting on a separator should eat the digit next
    // to it, the way it would in a field without separators.
    el.addEventListener('keydown', function (ev) {
      if (ev.key !== 'Backspace' && ev.key !== 'Delete') return;
      var a, b;
      try { a = el.selectionStart; b = el.selectionEnd; } catch (e) { return; }
      if (a == null || a !== b) return;                 // a selection: leave it
      var txt = rawOf(el);
      if (ev.key === 'Backspace' && a > 0 && txt.charAt(a - 1) === ',') {
        ev.preventDefault();
        setRaw(el, txt.slice(0, a - 2) + txt.slice(a));
        try { el.setSelectionRange(a - 2, a - 2); } catch (e) {}
        reformat(el);
      } else if (ev.key === 'Delete' && txt.charAt(a) === ',') {
        ev.preventDefault();
        setRaw(el, txt.slice(0, a) + txt.slice(a + 2));
        try { el.setSelectionRange(a, a); } catch (e) {}
        reformat(el);
      }
    });

    el.addEventListener('input', function () { reformat(el); });
    el.addEventListener('blur', function () {
      var n = numParse(rawOf(el));
      setRaw(el, isFinite(n) ? numGroup(n) : '');
    });
  }

  function scan(root) {
    if (!root || !root.querySelectorAll) return;
    if (root.matches && root.matches('input[data-num]')) enhance(root);
    var list = root.querySelectorAll('input[data-num]');
    for (var i = 0; i < list.length; i++) enhance(list[i]);
    if (root.matches && root.matches('input[data-phone]')) phoneEnhance(root);
    var tel = root.querySelectorAll('input[data-phone]');
    for (var k = 0; k < tel.length; k++) phoneEnhance(tel[k]);
  }


  /* ═══════════════════════════════════════════════════════════════════
     ☎️  Lebanese phone numbers — one shape for the whole portal

       stored / typed            shown              wa.me / tel:
       03922209                  +961 3 922 209     9613922209
       +96103922209              +961 3 922 209     9613922209
       76 789 039                +961 76 789 039    96176789039
       ٠٣٩٢٢٢٠٩                  +961 3 922 209     9613922209

     Lebanon writes a number nationally with a trunk 0 — 03, 70, 71, 76,
     78, 79, 81 for mobiles, 01/04/05/06/07/08/09 for landlines — and that
     0 is DROPPED after the country code. Keeping it is what produced
     “+961 0 392 2209” in the directory: a number no phone can dial, wrongly
     grouped on top. The national significant number is 7 digits (3 XXXXXX,
     1 XXXXXX) or 8 (7X XXXXXX, 81 XXXXXX), and that length alone decides
     the grouping.

     A number that is plainly foreign (+33…, +971…) is left as it is.
     ══════════════════════════════════════════════════════════════════ */
  var LB_CC = '961';

  // → { ok, lb, cc, nsn, raw }   nsn carries no trunk 0
  function phoneParts(v) {
    var raw = toLatin(v == null ? '' : v).replace(/[\s\u00a0()\-\.\u2010-\u2015]/g, '').trim();
    if (!raw) return { ok: false, lb: false, cc: '', nsn: '', raw: '' };
    if (raw.slice(0, 2) === '00') raw = '+' + raw.slice(2);

    var rest;
    if (raw.charAt(0) === '+') {
      if (raw.slice(1, 4) === LB_CC) rest = raw.slice(4);
      else return { ok: false, lb: false, cc: '', nsn: '', raw: raw };   // foreign, hands off
    } else if (raw.slice(0, 3) === LB_CC && raw.replace(/\D/g, '').length >= 10) {
      rest = raw.slice(3);
    } else {
      rest = raw;
    }

    var nsn = rest.replace(/\D/g, '').replace(/^0+/, '');
    return { ok: nsn.length === 7 || nsn.length === 8, lb: true, cc: LB_CC, nsn: nsn, raw: raw };
  }

  // +9613922209 — what to store and what tel: should carry
  function phoneE164(v) {
    var p = phoneParts(v);
    if (!p.lb) return p.raw;
    if (!p.nsn) return '';
    return '+' + LB_CC + p.nsn;
  }

  // +961 3 922 209 — what a human reads
  function phoneDisplay(v) {
    var p = phoneParts(v);
    if (!p.lb) return p.raw;
    if (!p.nsn) return '';
    var head = p.nsn.length === 8 ? p.nsn.slice(0, 2) : p.nsn.slice(0, 1);
    var body = p.nsn.slice(head.length);
    var mid  = body.slice(0, 3), tail = body.slice(3);
    return '+' + LB_CC + ' ' + head + (mid ? ' ' + mid : '') + (tail ? ' ' + tail : '');
  }

  // 9613922209 — wa.me wants digits only, no plus
  function phoneWa(v) {
    var e = phoneE164(v);
    return e ? e.replace(/\D/g, '') : '';
  }

  // Is this a number we can actually dial?
  function phoneValid(v) {
    var p = phoneParts(v);
    return p.lb ? p.ok : /^\+?\d{7,15}$/.test(p.raw);
  }

  /* Inputs marked `data-phone` open with +961 already in them and settle into
     the display shape when the field is left. Formatting on blur rather than on
     every keystroke keeps the caret where the person put it. */
  var PH_PLACEHOLDER = '+961 3 000 000';
  function phoneEnhance(el) {
    if (!el || el.__phoneReady) return;
    el.__phoneReady = true;
    if (!el.getAttribute('placeholder')) el.setAttribute('placeholder', PH_PLACEHOLDER);
    if (!el.getAttribute('inputmode')) el.setAttribute('inputmode', 'tel');
    el.setAttribute('dir', 'ltr');
    if (el.value) el.value = phoneDisplay(el.value);

    el.addEventListener('focus', function () {
      if (!el.value.trim()) el.value = '+' + LB_CC + ' ';
      try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {}
    });
    el.addEventListener('blur', function () {
      var v = el.value.trim();
      if (!v || v === '+' + LB_CC || v === '+' + LB_CC + ' ') { el.value = ''; return; }
      var shown = phoneDisplay(v);
      if (shown) el.value = shown;
    });
  }

  function boot() {
    scan(document);
    if (!global.MutationObserver) return;
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var added = muts[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j].nodeType === 1) scan(added[j]);
        }
      }
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  global.numGroup   = numGroup;
  global.numParse   = numParse;
  global.numVal     = numVal;
  global.numEnhance = enhance;
  global.numScan    = scan;

  global.phoneParts   = phoneParts;
  global.phoneE164    = phoneE164;
  global.phoneDisplay = phoneDisplay;
  global.phoneWa      = phoneWa;
  global.phoneValid   = phoneValid;
  global.phoneEnhance = phoneEnhance;
  global.WadiPhone    = { parts: phoneParts, e164: phoneE164, display: phoneDisplay,
                          wa: phoneWa, valid: phoneValid, enhance: phoneEnhance, cc: LB_CC };
})(window);
