const CACHE_NAME = "anidash-watch-shell-v1";
const BASE = new URL(self.registration.scope).pathname.replace(/\/$/, "");
const SHELL = [BASE + "/", BASE + "/index.html", BASE + "/styles.css", BASE + "/app.js", BASE + "/manifest.webmanifest"];

self.addEventListener("install", event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith("/api/")) return;
  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match(BASE + "/index.html")));
    return;
  }
  if (![BASE + "/styles.css", BASE + "/app.js", BASE + "/manifest.webmanifest"].includes(url.pathname)) return;
  event.respondWith(fetch(request).then(response => {
    if (response.ok) caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone()));
    return response;
  }).catch(() => caches.match(request)));
});
