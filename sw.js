// ═══════════════════════════════════════════════════════════════════════════
// بلدية وادي الست — Service Worker (PWA + Push Notifications)
// ═══════════════════════════════════════════════════════════════════════════

const CACHE_NAME   = 'wadi-elsit-v4';
const RUNTIME_NAME = 'wadi-elsit-runtime-v1';

// Files to cache on install (the "shell" of the app)
const APP_SHELL = [
  './',
  './index.html',
  './phonebook.html',
  './citizen.html',
  './water.html',
  './dashboard.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon.png'
];

// ─── INSTALL: pre-cache the app shell ──────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      // addAll fails if any single resource is missing — use individual adds
      // and tolerate failures (e.g. citizen.html might not exist yet)
      return Promise.all(
        APP_SHELL.map(url =>
          cache.add(url).catch(err => console.warn('[SW] Failed to cache:', url, err))
        )
      );
    }).then(() => self.skipWaiting())
  );
});

// ─── ACTIVATE: clean up old caches ─────────────────────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter(k => k !== CACHE_NAME && k !== RUNTIME_NAME)
            .map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ─── FETCH: network-first for HTML, cache-first for assets ────────────────
self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Only handle GETs from same origin
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Network-first for HTML pages (always get fresh content if online)
  if (req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html')) {
    event.respondWith(
      fetch(req).then(resp => {
        const clone = resp.clone();
        caches.open(CACHE_NAME).then(c => c.put(req, clone));
        return resp;
      }).catch(() => caches.match(req).then(c => c || caches.match('./index.html')))
    );
    return;
  }

  // Cache-first for static assets (icons, manifest, etc.)
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then(resp => {
        if (resp && resp.status === 200) {
          const clone = resp.clone();
          caches.open(RUNTIME_NAME).then(c => c.put(req, clone));
        }
        return resp;
      }).catch(() => cached);
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// PUSH NOTIFICATIONS (will be activated when backend is set up)
// ═══════════════════════════════════════════════════════════════════════════

// ─── PUSH: receive notification from server ────────────────────────────────
self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'بلدية وادي الست', body: event.data ? event.data.text() : '' };
  }

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
    data: {
      url: data.url || './',
      ...data.data
    },
    actions: data.actions || []
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// ─── NOTIFICATION CLICK: open the app at the right page ───────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  // Smart URL resolution: if no specific URL, go to news.html (most likely relevant)
  let targetUrl = (event.notification.data && event.notification.data.url) || '';

  // If URL is empty, just '/', or just './' — fallback to news.html
  if (!targetUrl || targetUrl === '/' || targetUrl === './' || targetUrl === '#') {
    targetUrl = './news.html';
  }

  const fullUrl = new URL(targetUrl, self.location.origin).href;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // If the app is already open, focus it AND navigate to the target
      for (const client of clientList) {
        if (client.url.startsWith(self.location.origin) && 'focus' in client) {
          client.navigate(fullUrl).catch(() => {});
          return client.focus();
        }
      }
      // Otherwise open a new window
      if (self.clients.openWindow) {
        return self.clients.openWindow(fullUrl);
      }
    })
  );
});

// ─── PUSH SUBSCRIPTION CHANGE: re-subscribe automatically ──────────────────
self.addEventListener('pushsubscriptionchange', (event) => {
  console.log('[SW] Push subscription changed; client should re-subscribe.');
  // Optionally notify the server (handled in the page-side code)
});

// ─── MESSAGE: allow page to trigger SW actions (e.g. force update) ────────
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
