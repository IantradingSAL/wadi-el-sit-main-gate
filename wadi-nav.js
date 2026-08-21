// ═══════════════════════════════════════════════════════════════════════════
// wadi-nav.js — one way back to the gate, on every page that needs one.
//
// WHY THIS FILE EXISTS
// The portal had four different return-to-home controls: `back-to-gate` (a
// round floating button on the cash box and irrigation admin), a gradient pill
// with text on the dashboard, `wadi-logo-link` inline in the header of the
// public pages, `hd-logo` on the bus trip page, and `wadi-logo-float` on the
// super-admin screen. Each carried its own copy of the CSS.
//
// Worse, four pages had no way home at all — the inbox, the 404, the password
// reset and the coop admin panel. In a browser the back button covers that.
// IN AN INSTALLED APP THERE IS NO BACK BUTTON, so a resident who opened a push
// notification and landed on one of those pages was simply stuck.
//
// HOW TO USE IT
//   <script src="wadi-nav.js" defer></script>
// and nothing else. The button injects itself, skips the home page, skips any
// page that already shows a logo linking home, and stays out of print output.
//
// Pages keeping their own header logo (news, coop, phonebook, citizen, water)
// are detected and left alone — a second control would be the duplicate the
// audit was trying to remove.
// ═══════════════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  var HOME = 'index.html';

  function fileName() {
    var p = (location.pathname || '').split('/').pop();
    return p || HOME;                       // "/" serves the gate
  }

  // Already home? Nothing to go back to.
  function isHome() {
    var f = fileName();
    return f === '' || f === HOME || f === 'index.htm';
  }

  // Does the page already show something that links to the gate?
  function alreadyHasAWayHome() {
    var links = document.querySelectorAll('a[href$="index.html"], a[href="/"], a[href="./"]');
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      // A link only counts if it is visible and carries a logo or an icon —
      // a text link buried in a footer is not a way home a thumb can find.
      if (a.classList.contains('back-to-gate')) return true;
      if (a.querySelector('img')) {
        var r = a.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) return true;
      }
    }
    return false;
  }

  var CSS =
    '.wadi-gate{position:fixed;top:10px;left:12px;z-index:99990;display:flex;' +
    'align-items:center;justify-content:center;width:44px;height:44px;' +
    'background:#fff;border-radius:50%;overflow:hidden;' +
    'text-decoration:none!important;box-shadow:0 4px 14px rgba(15,77,130,.3),' +
    '0 2px 6px rgba(0,0,0,.1);border:1.5px solid rgba(15,77,130,.15);' +
    'cursor:pointer;transition:transform .18s ease,box-shadow .18s ease}' +
    '.wadi-gate img{width:28px;height:28px;object-fit:contain;display:block}' +
    '.wadi-gate:hover,.wadi-gate:active{transform:translateY(-2px) scale(1.03);' +
    'box-shadow:0 8px 22px rgba(15,77,130,.45),0 4px 10px rgba(0,0,0,.12)}' +
    '.wadi-gate:focus-visible{outline:2px solid #1a6eb5;outline-offset:3px}' +
    // clear of the notch on an installed app
    '@supports(padding:max(0px)){.wadi-gate{top:max(10px,env(safe-area-inset-top));' +
    'left:max(12px,env(safe-area-inset-left))}}' +
    '@media(max-width:540px){.wadi-gate{width:38px;height:38px}' +
    '.wadi-gate img{width:23px;height:23px}}' +
    '@media print{.wadi-gate{display:none}}';

  function inject() {
    if (isHome()) return;
    if (document.querySelector('.wadi-gate')) return;
    if (alreadyHasAWayHome()) return;

    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    var a = document.createElement('a');
    a.href = HOME;
    a.className = 'wadi-gate';
    a.title = 'العودة للبوابة الرئيسية';
    a.setAttribute('aria-label', 'العودة للبوابة الرئيسية');

    var img = document.createElement('img');
    img.src = 'icons/apple-touch-icon.png';
    img.alt = '';                    // decorative: the link already has a label
    img.setAttribute('aria-hidden', 'true');
    a.appendChild(img);

    document.body.appendChild(a);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
