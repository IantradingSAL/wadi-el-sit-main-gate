// ═══════════════════════════════════════════════════════════════════════════
// pwa.js — يُلصق في كلّ صفحة لتفعيل ميزات PWA
// ═══════════════════════════════════════════════════════════════════════════
(function () {
/* i18n helper — translates an English key using window.I18N if loaded,
   otherwise falls back to the Arabic original string passed as second arg. */
function _t(key, ar){
  try {
    if(window.I18N && typeof window.I18N.L === 'function'){
      var d = window.I18N.L();
      if(d && d[key] !== undefined) return d[key];
    }
  } catch(e){}
  return ar;
}


  'use strict';

  // ─── PUSH CONFIG (Wadi El Sit) ───────────────────────────────────────────
  const VAPID_PUBLIC_KEY = 'BOPoaz8fSF5yefbNZvqADxVB_ENHmkkZwYjyTyuiZp215QpzxKr2eEhkp8LxEUhWWe6Of7Yxmis9zWO-DrlhMnM';
  const SUPABASE_URL  = 'https://onjbwhkmmtqnymhjnplw.supabase.co';
  const SUPABASE_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uamJ3aGttbXRxbnltaGpucGx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MDY4MjUsImV4cCI6MjA5MDM4MjgyNX0.lhlsRdOqVHZuOXCJa0lCNuZkYJHhf1AZ_zOwqHHAeG4';
  const MUN_ID        = '00000000-0000-0000-0000-000000000001';

  // ─── 1. Register service worker ─────────────────────────────────────────
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js').then((reg) => {
        console.log('[PWA] Service worker registered.');
        // Check for updates every hour while page is open
        setInterval(() => reg.update().catch(() => {}), 60 * 60 * 1000);
      }).catch((err) => console.warn('[PWA] SW registration failed:', err));

      // 🔄 AUTO-LINK push subscription with stored identity (every page load)
      // Wait 2.5s for SW + supabase to settle, then sync identity
      setTimeout(() => {
        if (window.PWA && window.PWA.autoLink) {
          window.PWA.autoLink().catch(e => console.warn('[PWA] autoLink failed:', e));
        }
      }, 2500);
    });
  }

  // ─── 2. Install prompt handling ─────────────────────────────────────────
  let deferredPrompt = null;
  const INSTALL_KEY = 'pwa_install_dismissed_at';
  const DISMISS_DAYS = 7;  // re-show banner after 7 days if dismissed

  function shouldShowInstallBanner() {
    // Don't show if already installed (running in standalone mode)
    if (window.matchMedia('(display-mode: standalone)').matches) return false;
    if (window.navigator.standalone === true) return false;  // iOS
    // Don't re-show within 7 days of dismissal
    const last = parseInt(localStorage.getItem(INSTALL_KEY) || '0', 10);
    if (last && (Date.now() - last) < DISMISS_DAYS * 86400 * 1000) return false;
    return true;
  }

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferr
