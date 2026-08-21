// ═══════════════════════════════════════════════════════════════════════════
// بلدية وادي الست — Service Worker v6
// FIXED: GitHub Pages subdirectory handling — notifications open correctly
// ═══════════════════════════════════════════════════════════════════════════

const CACHE_NAME   = 'wadi-elsit-v116';
const RUNTIME_NAME = 'wadi-elsit-runtime-v18';

// Push tracking config — used by notificationclick to mark opens.
const PUSH_SUPABASE_URL = 'https://onjbwhkmmtqnymhjnplw.supabase.co';
const PUSH_SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uamJ3aGttbXRxbnltaGpucGx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MDY4MjUsImV4cCI6MjA5MDM4MjgyNX0.lhlsRdOqVHZuOXCJa0lCNuZkYJHhf1AZ_zOwqHHAeG4';

// ★ KEY FIX: derive scope dynamically (handles /wadi-el-sit-main-gate/ subpath)
// self.registration.scope returns full URL like:
//   "https://iantradingsal.github.io/wadi-el-sit-main-gate/"
// We use this as the base for ALL navigation
const SCOPE_URL = self.registration.scope;

const APP_SHELL = [
  './',
  './index.html',
  './phonebook.html',
  './citizen.html',
  './water.html',
  './dashboard.html',
  './sandouk.html',
  './mrs.html',
  './mrs-update.html',
  './news.html',
  './news-detail.html',
  './coop.html',
  './bus-trip.html',
  './privacy.html',
  './404.html',
  './analytics.js',
  './number-format.js',
  // Every local script the pages above pull in. Without these the shell
  // loads from cache but its behaviour does not: auth-common and
  // wadi-perms decide who may see what, so a page that renders while they
  // are still fetching is a page with no permissions resolved.
  './auth-common.js',
  './wadi-perms.js',
  './wadi-nav.js',
  './wadi-shell.js',
  './wadi-dialogs.js',
  './wadi-municipality.js',
  './i18n.js',
  './wadi-strings.js',
  './wadi-help.css',
  './pwa.js',
  './pwa-ios.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png'
];

// ─── INSTALL ────────────────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  console.log('[SW v6] Installing. Scope:', SCOPE_URL);
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return Promise.all(
        APP_SHELL.map(url =>
          cache.add(url).catch(err => console.warn('[SW] cache miss:', url))
        )
      );
    })
    // No skipWaiting here on purpose. With no worker in control — a first
    // install — the browser activates this one immediately anyway. When a
    // worker IS in control, this one waits, and pwa.js offers the user
    // «نسخة جديدة متوفّرة» rather than swapping the app out from under
    // someone half-way through entering a sanad.
  );
});

// ─── ACTIVATE ───────────────────────────────────────────────────────────────
self.addEventListener('activate', (event) => {
  console.log('[SW v6] Activating');
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter(k => k !== CACHE_NAME && k !== RUNTIME_NAME)
            .map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ─── FETCH ──────────────────────────────────────────────────────────────────
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html')) {
    event.respondWith(
      fetch(req, { cache: 'no-store' }).then(resp => {
        const clone = resp.clone();
        caches.open(CACHE_NAME).then(c => c.put(req, clone));
        return resp;
      }).catch(() => caches.match(req).then(r => r || caches.match('./index.html')))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(resp => {
        if (resp.ok) {
          const clone = resp.clone();
          caches.open(RUNTIME_NAME).then(c => c.put(req, clone));
        }
        return resp;
      }).catch(() => caches.match('./index.html'));
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// PUSH NOTIFICATIONS — Bulletproof URL handling with SCOPE awareness
// ═══════════════════════════════════════════════════════════════════════════

/**
 * ★ THE CRITICAL FIX:
 * Resolves notification URLs against the SW SCOPE (not origin).
 * This handles GitHub Pages subdirectories correctly:
 *   scope = "https://iantradingsal.github.io/wadi-el-sit-main-gate/"
 *   "news.html"           → "https://iantradingsal.github.io/wadi-el-sit-main-gate/news.html"
 *   "/news.html"          → "https://iantradingsal.github.io/wadi-el-sit-main-gate/news.html"
 *   "./news.html"         → "https://iantradingsal.github.io/wadi-el-sit-main-gate/news.html"
 *   "news-detail.html?id=42" → ".../wadi-el-sit-main-gate/news-detail.html?id=42"
 */
function resolveNotificationUrl(url) {
  // Empty/invalid → news landing page
  if (!url || typeof url !== 'string') return new URL('./news.html', SCOPE_URL).href;

  const trimmed = url.trim();
  if (!trimmed || trimmed === '/' || trimmed === './' || trimmed === '#' ||
      trimmed === 'undefined' || trimmed === 'null') {
    return new URL('./news.html', SCOPE_URL).href;
  }

  // Already absolute URL?
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    try {
      const u = new URL(trimmed);
      if (u.origin === self.location.origin) {
        return trimmed; // Same origin, use as-is
      }
      // Different origin → fallback to safe page
      return new URL('./news.html', SCOPE_URL).href;
    } catch {
      return new URL('./news.html', SCOPE_URL).href;
    }
  }

  // Relative URL: resolve against SCOPE (not origin!)
  // This handles "/news.html" → ".../wadi-el-sit-main-gate/news.html"
  let cleaned = trimmed;

  // Strip leading slashes — they would cause resolution against origin
  while (cleaned.startsWith('/')) cleaned = cleaned.substring(1);

  // Strip leading "./" if present
  if (cleaned.startsWith('./')) cleaned = cleaned.substring(2);

  try {
    return new URL(cleaned, SCOPE_URL).href;
  } catch {
    return new URL('./news.html', SCOPE_URL).href;
  }
}

// ─── PUSH ───────────────────────────────────────────────────────────────────
self.addEventListener('push', (event) => {
  console.log('[SW v6] Push received');
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'بلدية وادي الست', body: event.data ? event.data.text() : '' };
  }

  console.log('[SW v6] Push data:', JSON.stringify(data));
  const resolvedUrl = resolveNotificationUrl(data.url);
  console.log('[SW v6] Resolved URL:', resolvedUrl);

  const title = data.title || 'بلدية وادي الست';
  const options = {
    body: data.body || '',
    icon: data.icon || './icons/icon-192.png',
    badge: data.badge || './icons/icon-72.png',
    image: data.image,
    tag: data.tag || 'general',
    renotify: !!data.renotify,
    requireInteraction: !!data.requireInteraction,
    silent: !!data.silent,
    timestamp: data.timestamp || Date.now(),
    dir: 'rtl',
    lang: 'ar',
    data: { url: resolvedUrl, originalUrl: data.url, ...data.data },
    actions: data.actions || []
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// ─── NOTIFICATION CLICK ────────────────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  console.log('[SW v6] Notification clicked');
  event.notification.close();

  let targetUrl = '';
  if (event.notification.data) {
    targetUrl = event.notification.data.url || event.notification.data.originalUrl || '';
  }

  // ★ Re-resolve! The cached `data.url` from old SW versions might be wrong (no scope)
  // Re-running resolveNotificationUrl ensures correctness even for old notifications
  const fullUrl = resolveNotificationUrl(targetUrl);
  console.log('[SW v6] Opening:', fullUrl);

  // 👁️ Mark the notification as "opened" for admin analytics: bump
  // last_used_at on this device's push_subscriptions row so it becomes
  // >= the notification's sent_at. Fire-and-forget; never blocks navigation.
  const markOpened = self.registration.pushManager.getSubscription()
    .then((sub) => {
      if (!sub || !sub.endpoint) return;
      return fetch(
        PUSH_SUPABASE_URL + '/rest/v1/push_subscriptions?endpoint=eq.' + encodeURIComponent(sub.endpoint),
        {
          method: 'PATCH',
          headers: {
            'apikey': PUSH_SUPABASE_KEY,
            'Authorization': 'Bearer ' + PUSH_SUPABASE_KEY,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
          },
          body: JSON.stringify({ last_used_at: new Date().toISOString() })
        }
      ).catch(() => {});
    })
    .catch(() => {});

  const openWindowTask = self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
    for (const client of clientList) {
      if (client.url.startsWith(self.location.origin) && 'focus' in client) {
        return client.focus().then(c => {
          if (c && 'navigate' in c) return c.navigate(fullUrl).catch(() => {});
        });
      }
    }
    if (self.clients.openWindow) return self.clients.openWindow(fullUrl);
  });

  event.waitUntil(Promise.all([markOpened, openWindowTask]));
});

self.addEventListener('pushsubscriptionchange', (event) => {
  console.log('[SW v6] Subscription changed');
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

console.log('[SW v6] Loaded. Scope:', SCOPE_URL);
