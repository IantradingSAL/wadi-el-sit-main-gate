/**
 * بلدية وادي الست — Service Worker
 * 
 * Strategy: Network-first with cache fallback
 * This ensures users see the LATEST content from GitHub Pages
 * while having offline access to previously loaded pages.
 */

const CACHE_NAME = 'baladiye-v1';
const CACHE_VERSION = 1;

// Files that are always cached for offline use
const STATIC_ASSETS = [
  './',
  './index.html',
  './manifest.json'
];

// ====== INSTALL: Cache the app shell ======
self.addEventListener('install', (event) => {
  console.log('[SW] Installing v' + CACHE_VERSION);
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('[SW] Caching app shell');
        return cache.addAll(STATIC_ASSETS);
      })
      .then(() => self.skipWaiting()) // Activate immediately
  );
});

// ====== ACTIVATE: Clean up old caches ======
self.addEventListener('activate', (event) => {
  console.log('[SW] Activating v' + CACHE_VERSION);
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME)
          .map((name) => {
            console.log('[SW] Deleting old cache:', name);
            return caches.delete(name);
          })
      );
    }).then(() => self.clients.claim()) // Take control of all pages
  );
});

// ====== FETCH: Network-first strategy ======
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Don't cache Supabase API calls (always need fresh data)
  if (url.hostname.includes('supabase')) {
    return; // Let browser handle normally
  }

  // Don't cache POST requests
  if (request.method !== 'GET') {
    return;
  }

  // Network-first strategy for everything else
  event.respondWith(
    fetch(request)
      .then((response) => {
        // Only cache successful responses
        if (response && response.status === 200 && response.type === 'basic') {
          const responseClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseClone);
          });
        }
        return response;
      })
      .catch(() => {
        // Network failed, try cache
        return caches.match(request).then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          // If requesting an HTML page and nothing cached, show offline fallback
          if (request.headers.get('accept')?.includes('text/html')) {
            return caches.match('./index.html');
          }
        });
      })
  );
});

// ====== MESSAGE: Handle update notifications ======
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
