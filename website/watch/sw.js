const CACHE='anidash-stream-v9';
const SHELL=[
  '/watch',
  '/watch/index.html',
  '/watch/styles.css',
  '/watch/app.js',
  '/watch/manifest.webmanifest',
  '/assets/anidash_logo.png'
];

self.addEventListener('install',event=>{
  event.waitUntil(
    caches.open(CACHE)
      .then(cache=>cache.addAll(SHELL))
      .then(()=>self.skipWaiting())
  );
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET') return;

  const url=new URL(request.url);
  if(url.pathname.startsWith('/api/')) return;

  if(request.mode==='navigate'){
    event.respondWith(
      fetch(request)
        .then(response=>{
          const copy=response.clone();
          caches.open(CACHE).then(cache=>cache.put('/watch/index.html',copy));
          return response;
        })
        .catch(()=>caches.match('/watch/index.html'))
    );
    return;
  }

  if(url.origin!==self.location.origin) return;
  const isAppAsset=url.pathname.startsWith('/watch/')||url.pathname==='/assets/anidash_logo.png';
  if(!isAppAsset) return;

  event.respondWith(
    caches.match(request).then(cached=>{
      const network=fetch(request).then(response=>{
        if(response.ok){
          const copy=response.clone();
          caches.open(CACHE).then(cache=>cache.put(request,copy));
        }
        return response;
      });
      return cached||network;
    })
  );
});
