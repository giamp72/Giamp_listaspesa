const CACHE_NAME = 'lista-spesa-v2';
const APP_SHELL = [
  new URL('./index.html', self.registration.scope).href,
  new URL('./manifest.webmanifest', self.registration.scope).href,
  new URL('./icons/icon.svg', self.registration.scope).href
];
const SUPABASE_CLIENT = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    try {
      const response = await fetch(SUPABASE_CLIENT);
      if (!response.ok && response.type !== 'opaque') throw new Error(`HTTP ${response.status}`);
      await cache.put(SUPABASE_CLIENT, response);
    } catch (error) {
      console.error('Impossibile memorizzare la libreria Supabase per l’uso offline:', error);
    }
  })());
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const {request} = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;

  if (url.href === SUPABASE_CLIENT) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok || response.type === 'opaque') await cache.put(request, response.clone());
      return response;
    })());
    return;
  }

  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        const cache = await caches.open(CACHE_NAME);
        await cache.put(APP_SHELL[0], response.clone());
        return response;
      } catch {
        return (await caches.match(request)) || (await caches.match(APP_SHELL[0]));
      }
    })());
    return;
  }

  if (APP_SHELL.includes(url.href)) {
    event.respondWith(caches.match(request).then(response => response || fetch(request)));
  }
});
