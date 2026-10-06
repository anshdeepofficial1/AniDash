const CACHE='anidash-stream-v11';
const scopePath=new URL(self.registration.scope).pathname.replace(/\/$/,'');
const BASE=scopePath==='/'?'':scopePath;
const pathFor=file=>BASE+`/${file}`;
const SHELL=[
  BASE||'/',
  pathFor('index.html'),
  pathFor('styles.css'),
  pathFor('app.js'),
  pathFor('manifest.webmanifest')
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
          if(response.ok){
            const copy=response.clone();
            caches.open(CACHE).then(cache=>cache.put(pathFor('index.html'),copy));
          }
          return response;
        })
        .catch(()=>caches.match(pathFor('index.html')))
    );
    return;
  }

  if(url.origin!==self.location.origin) return;
  const insideScope=BASE?url.pathname.startsWith(BASE+'/'):true;
  if(!insideScope) return;

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
