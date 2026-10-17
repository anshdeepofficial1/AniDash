const CACHE='anidash-stream-v14';
const scopePath=new URL(self.registration.scope).pathname.replace(/\/$/,'');
const BASE=scopePath==='/'?'':scopePath;
const pathFor=file=>BASE+`/${file}`;
const SHELL=[pathFor('index.html'),pathFor('styles.css'),pathFor('app.js'),pathFor('manifest.webmanifest')];

// Files that must never come from cache: the app shell itself (so a deploy is
// picked up on the first reload) and anything served by a serverless function.
const NETWORK_FIRST=new Set([
  pathFor(''),
  pathFor('index.html'),
  pathFor('styles.css'),
  pathFor('app.js'),
  pathFor('manifest.webmanifest'),
  pathFor('sw.js')
]);

const trimCache=async(name,limit)=>{
  const cache=await caches.open(name);
  const keys=await cache.keys();
  if(keys.length<=limit) return;
  await Promise.all(keys.slice(0,keys.length-limit).map(key=>cache.delete(key)));
};

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

  // Streaming, search, episode lists and any other API traffic is always live:
  // caching them would pin expired CDN tokens or stale metadata.
  if(url.origin!==self.location.origin||url.pathname.startsWith('/api/')) return;

  const isNavigation=request.mode==='navigate';
  const file=(url.pathname===BASE||url.pathname===BASE+'/'?pathFor('index.html'):url.pathname);
  const useNetworkFirst=isNavigation||NETWORK_FIRST.has(file);

  if(useNetworkFirst){
    event.respondWith(
      fetch(request)
        .then(response=>{
          if(response.ok&&response.clone){
            const copy=response.clone();
            caches.open(CACHE).then(cache=>cache.put(file,copy)).then(()=>trimCache(CACHE,24));
          }
          return response;
        })
        .catch(()=>caches.match(file,{ignoreSearch:isNavigation}).then(hit=>hit||caches.match(pathFor('index.html'))))
    );
    return;
  }

  if(!url.pathname.startsWith(BASE+'/')) return;

  event.respondWith(
    caches.match(request).then(cached=>{
      const network=fetch(request).then(response=>{
        if(response.ok){
          const copy=response.clone();
          caches.open(CACHE).then(cache=>cache.put(request,copy)).then(()=>trimCache(CACHE,60));
        }
        return response;
      });
      return cached||network;
    })
  );
});
