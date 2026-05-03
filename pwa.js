// ═══════════════════════════════════════════════════════════════════════════
// pwa.js — يُلصق في كلّ صفحة لتفعيل ميزات PWA
// ═══════════════════════════════════════════════════════════════════════════
(function () {
  'use strict';

  // ─── PUSH CONFIG (Wadi El Sit) ───────────────────────────────────────────
  const VAPID_PUBLIC_KEY = 'BJjyBXyjL0fkAxlgyu715TXCkqDfTqCFwahiodJsBVtWpQ4fa3ouup8wu89sDyeWrgd5i-wirk-EfQPNzWG1-NQ';
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
    deferredPrompt = e;
    if (shouldShowInstallBanner()) showInstallBanner();
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    hideInstallBanner();
    console.log('[PWA] App installed.');
  });

  function showInstallBanner() {
    if (document.getElementById('pwa-install-banner')) return;
    const banner = document.createElement('div');
    banner.id = 'pwa-install-banner';
    banner.innerHTML = `
      <style>
        #pwa-install-banner{position:fixed;left:50%;bottom:max(16px,env(safe-area-inset-bottom));transform:translateX(-50%);width:calc(100% - 32px);max-width:420px;background:linear-gradient(135deg,#1a6eb5,#0f4d82);color:#fff;border-radius:18px;padding:14px 16px;box-shadow:0 12px 32px rgba(15,77,130,.4),0 4px 10px rgba(0,0,0,.12);z-index:99998;display:flex;align-items:center;gap:11px;font-family:'Tajawal',sans-serif;direction:rtl;animation:pwaSlideUp .35s cubic-bezier(.16,1,.3,1)}
        @keyframes pwaSlideUp{from{transform:translateX(-50%) translateY(120%);opacity:0}to{transform:translateX(-50%) translateY(0);opacity:1}}
        #pwa-install-banner .pwa-i{width:42px;height:42px;border-radius:12px;background:rgba(255,255,255,.18);display:flex;align-items:center;justify-content:center;font-size:22px;flex-shrink:0}
        #pwa-install-banner .pwa-text{flex:1;min-width:0}
        #pwa-install-banner .pwa-t{font-size:14px;font-weight:800;line-height:1.3;margin-bottom:2px}
        #pwa-install-banner .pwa-s{font-size:11.5px;opacity:.85;line-height:1.4}
        #pwa-install-banner .pwa-btns{display:flex;gap:6px;flex-shrink:0}
        #pwa-install-banner .pwa-btn{background:#fff;color:#0f4d82;border:none;border-radius:10px;padding:8px 14px;font-family:inherit;font-size:12.5px;font-weight:800;cursor:pointer}
        #pwa-install-banner .pwa-btn:active{transform:scale(.96)}
        #pwa-install-banner .pwa-x{background:rgba(255,255,255,.15);color:#fff;border:none;border-radius:10px;width:32px;height:32px;cursor:pointer;font-size:14px;font-weight:700}
      </style>
      <div class="pwa-i">📱</div>
      <div class="pwa-text">
        <div class="pwa-t">ثبّت تطبيق وادي الست</div>
        <div class="pwa-s">لوصول أسرع وعمل بدون إنترنت</div>
      </div>
      <div class="pwa-btns">
        <button class="pwa-btn" id="pwa-install-yes">تثبيت</button>
        <button class="pwa-x" id="pwa-install-no" aria-label="إغلاق">✕</button>
      </div>
    `;
    document.body.appendChild(banner);
    document.getElementById('pwa-install-yes').onclick = installApp;
    document.getElementById('pwa-install-no').onclick = dismissInstall;
  }

  function hideInstallBanner() {
    const b = document.getElementById('pwa-install-banner');
    if (b) b.remove();
  }

  function installApp() {
    if (!deferredPrompt) {
      // iOS Safari path: show manual install instructions
      showIosInstructions();
      return;
    }
    deferredPrompt.prompt();
    deferredPrompt.userChoice.then(() => {
      deferredPrompt = null;
      hideInstallBanner();
    });
  }

  function dismissInstall() {
    localStorage.setItem(INSTALL_KEY, Date.now().toString());
    hideInstallBanner();
  }

  function showIosInstructions() {
    hideInstallBanner();
    const m = document.createElement('div');
    m.id = 'pwa-ios-modal';
    m.innerHTML = `
      <style>
        #pwa-ios-modal{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:99999;display:flex;align-items:flex-end;justify-content:center;padding:0;direction:rtl;font-family:'Tajawal',sans-serif;animation:pwaFade .25s ease}
        @keyframes pwaFade{from{opacity:0}to{opacity:1}}
        #pwa-ios-modal .ios-card{background:#fff;border-radius:20px 20px 0 0;width:100%;max-width:480px;padding:18px 18px max(18px,env(safe-area-inset-bottom));animation:pwaSlideUp .35s cubic-bezier(.16,1,.3,1)}
        #pwa-ios-modal h3{font-size:17px;font-weight:800;color:#0f4d82;margin-bottom:6px}
        #pwa-ios-modal p{font-size:13px;color:#555;line-height:1.7;margin-bottom:13px}
        #pwa-ios-modal ol{padding-right:22px;font-size:13.5px;line-height:2.1;color:#333}
        #pwa-ios-modal ol li b{color:#0f4d82}
        #pwa-ios-modal .close-btn{width:100%;margin-top:14px;background:#0f4d82;color:#fff;border:none;border-radius:12px;padding:13px;font-family:inherit;font-size:14px;font-weight:800;cursor:pointer}
      </style>
      <div class="ios-card">
        <h3>📱 ثبّت التطبيق على iPhone</h3>
        <p>على iOS، التثبيت يتمّ بـ ٣ خطوات بسيطة من Safari:</p>
        <ol>
          <li>اضغط زرّ <b>المشاركة</b> ⎯ <b>📤</b> في أسفل Safari</li>
          <li>مرّر للأسفل واضغط <b>"إضافة إلى الشاشة الرئيسية"</b></li>
          <li>اضغط <b>"إضافة"</b> أعلى اليمين</li>
        </ol>
        <button class="close-btn" onclick="document.getElementById('pwa-ios-modal').remove()">حسناً، فهمت</button>
      </div>
    `;
    m.addEventListener('click', (e) => { if (e.target === m) m.remove(); });
    document.body.appendChild(m);
  }

  // ─── 3. iOS detection: show banner manually since iOS doesn't fire beforeinstallprompt ───
  const isIos = /iPhone|iPad|iPod/i.test(navigator.userAgent) && !window.MSStream;
  const isIosStandalone = window.navigator.standalone === true;
  if (isIos && !isIosStandalone && shouldShowInstallBanner()) {
    setTimeout(() => {
      if (!document.getElementById('pwa-install-banner') && !deferredPrompt) {
        showInstallBanner();
      }
    }, 4000);
  }

  // ─── 4. Push notification API (full Supabase integration) ─────────────
  window.PWA = {
    isInstalled: () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true,

    canPush: () => 'Notification' in window && 'serviceWorker' in navigator && 'PushManager' in window,

    showInstallPrompt: () => {
      if (deferredPrompt) installApp();
      else if (isIos) showIosInstructions();
      else alert('يمكنك تثبيت التطبيق من قائمة المتصفّح (الثلاث نقاط).');
    },

    // Returns the current subscription status: 'subscribed', 'denied', 'unsupported', 'pending'
    pushStatus: async () => {
      if (!window.PWA.canPush()) return 'unsupported';
      if (Notification.permission === 'denied') return 'denied';
      if (Notification.permission === 'default') return 'pending';
      try {
        const reg = await navigator.serviceWorker.ready;
        const sub = await reg.pushManager.getSubscription();
        return sub ? 'subscribed' : 'pending';
      } catch (e) { return 'pending'; }
    },

    // Enable push: ask permission, subscribe, save to Supabase
    enablePush: async (topics = ['general']) => {
      if (!window.PWA.canPush()) {
        throw new Error('متصفّحك لا يدعم الإشعارات. تأكّد من iOS 16.4+ أو Android Chrome حديث.');
      }

      // Wait for service worker to be ready
      const reg = await navigator.serviceWorker.ready;

      // Request permission
      const permission = await Notification.requestPermission();
      if (permission === 'denied') {
        throw new Error('رفضتَ السماح بالإشعارات. لتفعيلها، اذهب إلى إعدادات المتصفّح/الموقع.');
      }
      if (permission !== 'granted') {
        throw new Error('لم يتمّ منح الإذن.');
      }

      // Subscribe to push
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
        });
      }

      // Save to Supabase
      const subJson = sub.toJSON();
      const payload = {
        mun_id: MUN_ID,
        endpoint: subJson.endpoint,
        p256dh: subJson.keys.p256dh,
        auth: subJson.keys.auth,
        user_agent: navigator.userAgent.slice(0, 200),
        topics: topics,
        is_active: true
      };

      const resp = await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?on_conflict=endpoint`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=minimal'
        },
        body: JSON.stringify(payload)
      });

      if (!resp.ok && resp.status !== 201 && resp.status !== 204) {
        const text = await resp.text();
        console.error('Push save failed:', resp.status, text);
        throw new Error(`تعذّر حفظ الاشتراك (${resp.status}): ${text.slice(0,100)}`);
      }

      return sub;
    },

    // Disable push: unsubscribe + remove from Supabase
    disablePush: async () => {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) return false;

      const endpoint = sub.endpoint;

      // Unsubscribe locally
      await sub.unsubscribe();

      // Mark inactive in Supabase
      try {
        await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(endpoint)}`, {
          method: 'PATCH',
          headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify({ is_active: false })
        });
      } catch (e) { console.warn('Failed to mark sub inactive:', e); }

      return true;
    },

    getCurrentSubscription: async () => {
      if (!('serviceWorker' in navigator)) return null;
      const reg = await navigator.serviceWorker.ready;
      return await reg.pushManager.getSubscription();
    },

    // Update topics for an existing subscription
    updateTopics: async (topics) => {
      const sub = await window.PWA.getCurrentSubscription();
      if (!sub) throw new Error('غير مشترك حالياً');
      await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(sub.endpoint)}`, {
        method: 'PATCH',
        headers: {
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        },
        body: JSON.stringify({ topics })
      });
    }
  };

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; ++i) out[i] = raw.charCodeAt(i);
    return out;
  }
})();
