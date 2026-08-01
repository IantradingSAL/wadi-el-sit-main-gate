// ═══════════════════════════════════════════════════════════════════════════
// pwa-ios.js — Injects iOS-specific PWA enhancements into every page.
// Idempotent: safe to load alongside existing <meta> and <link> tags in the
// HTML — it checks for duplicates before inserting.
//
// Adds:
//   • apple-mobile-web-app-capable / status-bar / title meta tags
//   • theme-color meta (with light + dark variants)
//   • apple-touch-icon (180×180 — Apple's current preferred size)
//   • apple-touch-startup-image (splash) for iPhone + iPad, portrait + landscape
//   • Preloads the maskable icon so Add-to-Home-Screen has a smooth install
//
// Load AFTER pwa.js (or independently) with:
//   <script src="pwa-ios.js" defer></script>
// ═══════════════════════════════════════════════════════════════════════════

(function () {
  'use strict';

  var head = document.head || document.getElementsByTagName('head')[0];
  if (!head) return;

  // Resolve the app's base path so this works both at repo root and under
  // /wadi-el-sit-main-gate/ (GitHub Pages subpath). Uses <base href> if set,
  // otherwise the current script's directory.
  function baseHref() {
    var b = document.querySelector('base');
    if (b && b.href) return b.href.replace(/\/$/, '') + '/';
    var s = document.currentScript || (function () {
      var scripts = document.getElementsByTagName('script');
      for (var i = scripts.length - 1; i >= 0; i--) {
        if (/pwa-ios\.js(?:\?|$)/.test(scripts[i].src)) return scripts[i];
      }
      return null;
    })();
    if (s && s.src) return s.src.replace(/pwa-ios\.js.*$/, '');
    return './';
  }
  var BASE = baseHref();

  function ensureMeta(name, content) {
    if (document.querySelector('meta[name="' + name + '"]')) return;
    var m = document.createElement('meta');
    m.setAttribute('name', name);
    m.setAttribute('content', content);
    head.appendChild(m);
  }

  function ensureThemeColor(color, scheme) {
    var sel = 'meta[name="theme-color"]' + (scheme ? '[media*="' + scheme + '"]' : ':not([media])');
    if (document.querySelector(sel)) return;
    var m = document.createElement('meta');
    m.setAttribute('name', 'theme-color');
    m.setAttribute('content', color);
    if (scheme) m.setAttribute('media', '(prefers-color-scheme: ' + scheme + ')');
    head.appendChild(m);
  }

  function ensureLink(rel, href, extra) {
    var link = document.createElement('link');
    link.rel = rel;
    link.href = BASE + href;
    if (extra) {
      for (var k in extra) if (Object.prototype.hasOwnProperty.call(extra, k)) {
        link.setAttribute(k, extra[k]);
      }
    }
    head.appendChild(link);
    return link;
  }

  // ─── 1. Standalone / status bar / title ─────────────────────────────
  ensureMeta('apple-mobile-web-app-capable',       'yes');
  ensureMeta('mobile-web-app-capable',             'yes');
  ensureMeta('apple-mobile-web-app-status-bar-style', 'default');
  ensureMeta('apple-mobile-web-app-title',         'وادي الست');
  ensureMeta('application-name',                   'بلدية وادي الست');
  ensureMeta('format-detection',                   'telephone=no');

  // ─── 2. Theme color (light + dark) ─────────────────────────────────
  ensureThemeColor('#1a6eb5', 'light');
  ensureThemeColor('#0f4d82', 'dark');

  // ─── 3. Apple touch icons ─────────────────────────────────────────
  // Prefer the new iOS-tuned 180×180 asset; keep fallbacks.
  var appleIcons = [
    ['180x180', 'ios-assets/icons/AppIcon-60@3x-180.png'],
    ['167x167', 'ios-assets/icons/AppIcon-83.5@2x-167.png'],
    ['152x152', 'ios-assets/icons/AppIcon-76@2x-152.png'],
    ['120x120', 'ios-assets/icons/AppIcon-60@2x-120.png']
  ];
  appleIcons.forEach(function (spec) {
    // Skip if the page already has a same-size apple-touch-icon
    if (document.querySelector('link[rel="apple-touch-icon"][sizes="' + spec[0] + '"]')) return;
    ensureLink('apple-touch-icon', spec[1], { sizes: spec[0] });
  });

  // ─── 4. Apple splash screens (Add-to-Home-Screen launch) ─────────
  // Each entry: [device-width, device-height, dpr, filename]
  var IOS_SPLASH = [
    // iPhone
    [430, 932, 3, 'splash-iPhone-15-Pro-Max-1290x2796.png'],
    [393, 852, 3, 'splash-iPhone-15-Pro-1179x2556.png'],
    [428, 926, 3, 'splash-iPhone-14-Plus-1284x2778.png'],
    [390, 844, 3, 'splash-iPhone-14-1170x2532.png'],
    [375, 812, 3, 'splash-iPhone-13-mini-1125x2436.png'],
    [414, 896, 2, 'splash-iPhone-11-828x1792.png'],
    [375, 667, 2, 'splash-iPhone-8-750x1334.png'],
    // iPad
    [1024, 1366, 2, 'splash-iPad-Pro-12.9-2048x2732.png'],
    [834,  1194, 2, 'splash-iPad-Pro-11-1668x2388.png'],
    [820,  1180, 2, 'splash-iPad-Air-10.9-1640x2360.png'],
    [768,  1024, 2, 'splash-iPad-9.7-1536x2048.png']
  ];

  IOS_SPLASH.forEach(function (s) {
    var w = s[0], h = s[1], dpr = s[2], file = s[3];
    // Portrait
    ensureLink('apple-touch-startup-image', 'ios-assets/splash/' + file, {
      media: '(device-width: ' + w + 'px) and (device-height: ' + h + 'px) and ' +
             '(-webkit-device-pixel-ratio: ' + dpr + ') and (orientation: portrait)'
    });
    // Landscape (swap w/h in filename)
    var land = file.replace(/(\d+)x(\d+)\.png$/, function (_m, ww, hh) {
      return hh + 'x' + ww + '-landscape.png';
    });
    ensureLink('apple-touch-startup-image', 'ios-assets/splash/' + land, {
      media: '(device-width: ' + w + 'px) and (device-height: ' + h + 'px) and ' +
             '(-webkit-device-pixel-ratio: ' + dpr + ') and (orientation: landscape)'
    });
  });

  // ─── 5. Preload key icons for a smoother install prompt ─────────
  if (!document.querySelector('link[rel="preload"][as="image"][href*="icon-512"]')) {
    ensureLink('preload', 'icons/icon-512.png', { as: 'image' });
  }
})();
