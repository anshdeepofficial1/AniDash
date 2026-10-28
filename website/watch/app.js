const $=s=>document.querySelector(s);
const $$=s=>[...document.querySelectorAll(s)];

const state={
  current:null,
  episodes:[],
  hls:null,
  home:[],
  homeData:null,
  searchTimer:null,
  mangaTimer:null,
  spotlightTimer:null,
  spotlightIndex:0,
  hindiLoaded:false,
  hindiCurrent:null,
  libraryStatus:'watching',
  browseFilter:'all',
  lastMainPage:'homePage',
  pageHistory:[],
  aiConversation:[],
  newsLoaded:false,
  playingEpisode:null,
  lastProgressSave:0
};

const DEFAULT_WEB_SETTINGS={
  theme:'dark',
  amoled:false,
  compactCards:false,
  spotlightAutoPlay:true,
  showAdult:false,
  incognito:false,
  preferredAudio:'sub',
  preferredQuality:'Auto',
  nav:{browse:true,manga:true,watchlist:true}
};

const hindiApi=async(params,{timeout=18000}={})=>{
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),timeout);
  try{
    const response=await fetch('/api/hindi?'+new URLSearchParams(params),{signal:controller.signal});
    const payload=await response.json().catch(()=>({}));
    if(!response.ok) throw Error(payload.error||'Hindi source is temporarily unavailable');
    return payload;
  }catch(error){
    if(error?.name==='AbortError') throw Error('Hindi source took too long to respond. Please retry.');
    throw error;
  }finally{clearTimeout(timer)}
};

function loadWebSettings(){
  try{
    const saved=JSON.parse(localStorage.getItem('anidash-web-settings')||'{}');
    return {
      ...DEFAULT_WEB_SETTINGS,
      ...saved,
      nav:{...DEFAULT_WEB_SETTINGS.nav,...(saved.nav||{})}
    };
  }catch(_){
    return JSON.parse(JSON.stringify(DEFAULT_WEB_SETTINGS));
  }
}

let webSettings=loadWebSettings();

function mediaVisible(item){
  return webSettings.showAdult||item?.isAdult!==true;
}

function applyWebSettings(){
  const root=document.documentElement;
  if(webSettings.theme==='system') delete root.dataset.theme;
  else root.dataset.theme=webSettings.theme;
  root.dataset.amoled=webSettings.amoled?'true':'false';
  root.classList.toggle('compact-cards',!!webSettings.compactCards);

  const visibility={
    browsePage:webSettings.nav.browse,
    mangaPage:webSettings.nav.manga,
    watchlistPage:webSettings.nav.watchlist
  };
  $$('[data-page]').forEach(button=>{
    if(button.dataset.page==='homePage') button.hidden=false;
    else if(Object.prototype.hasOwnProperty.call(visibility,button.dataset.page)) button.hidden=!visibility[button.dataset.page];
  });

  const audio=$('#audio');
  if(audio) audio.value=webSettings.preferredAudio;

  const systemDark=window.matchMedia?.('(prefers-color-scheme: dark)').matches;
  const dark=webSettings.theme==='dark'||(webSettings.theme==='system'&&systemDark);
  const themeColor=dark?(webSettings.amoled?'#000000':'#090d0a'):'#f8faf7';
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content',themeColor);
  const themeUse=$('#macThemeButton use');
  if(themeUse) themeUse.setAttribute('href',dark?'#i-moon':'#i-sun');
}

function saveWebSettings(){
  localStorage.setItem('anidash-web-settings',JSON.stringify(webSettings));
  applyWebSettings();
  syncSettingsControls();
}

function syncSettingsControls(){
  const values={
    settingIncognito:webSettings.incognito,
    settingAdult:webSettings.showAdult,
    settingAmoled:webSettings.amoled,
    settingCompact:webSettings.compactCards,
    settingSpotlight:webSettings.spotlightAutoPlay,
    settingNavBrowse:webSettings.nav.browse,
    settingNavManga:webSettings.nav.manga,
    settingNavWatchlist:webSettings.nav.watchlist
  };
  for(const [id,value] of Object.entries(values)){
    const el=$('#'+id);
    if(el) el.checked=!!value;
  }
  if($('#settingAudio')) $('#settingAudio').value=webSettings.preferredAudio;
  if($('#settingQuality')) $('#settingQuality').value=webSettings.preferredQuality;
  $$('#themeSegments [data-theme-value]').forEach(button=>{
    button.classList.toggle('active',button.dataset.themeValue===webSettings.theme);
  });
  updateNotificationPermissionStatus();
  const installed=window.matchMedia('(display-mode: standalone)').matches||window.navigator.standalone===true;
  if($('#installStatus')) $('#installStatus').textContent=installed?'Installed and running as an app':'Open in Safari and add AniDash to your Home Screen';
}

function updateNotificationPermissionStatus(){
  const label=$('#notificationPermissionStatus');
  if(!label) return;
  if(!('Notification' in window)){
    label.textContent='Not supported by this browser';
    return;
  }
  const permission=Notification.permission;
  label.textContent=permission==='granted'?'Allowed':permission==='denied'?'Blocked in browser settings':'Tap to request permission';
}

const anilist=async(query,variables={})=>{
  const r=await fetch('https://graphql.anilist.co',{
    method:'POST',
    headers:{'Content-Type':'application/json','Accept':'application/json'},
    body:JSON.stringify({query,variables})
  });
  if(!r.ok) throw Error('Could not load AniList');
  const payload=await r.json();
  if(payload.errors?.length) throw Error(payload.errors[0].message||'AniList request failed');
  return payload.data;
};

const api=async(params,{timeout=20000}={})=>{
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),timeout);
  try{
    const r=await fetch('/api/anidash?'+new URLSearchParams(params),{signal:controller.signal});
    const x=await r.json().catch(()=>({}));
    if(!r.ok) throw Error(x.error||'Could not load');
    return x;
  }catch(error){
    if(error?.name==='AbortError') throw Error('Episode source took too long to respond. Please retry.');
    throw error;
  }finally{
    clearTimeout(timer);
  }
};

const titleOf=x=>x?.title?.english||x?.title?.romaji||x?.title?.native||x?.name||x?.title||'Untitled';
const imageOf=x=>x?.coverImage?.extraLarge||x?.coverImage?.large||x?.cover||x?.poster||'';
const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const mediaFields=`id title{english romaji native} synonyms coverImage{extraLarge large} bannerImage seasonYear episodes duration format averageScore status description(asHtml:false) genres isAdult nextAiringEpisode{episode timeUntilAiring}`;
const mangaFields=`id title{english romaji native} synonyms coverImage{extraLarge large} bannerImage seasonYear chapters volumes format averageScore status description(asHtml:false) genres isAdult`;

function seasonBadge(x){
  const format=(x?.format||'').toUpperCase();
  if(format==='MOVIE') return 'M';
  if(format==='MUSIC') return '';
  if(format==='OVA') return 'OVA';
  const titles=[titleOf(x),...(x?.synonyms||[])].join(' ');
  if(format==='SPECIAL'||/special|chibi/i.test(titles)) return 'SP';
  const match=titles.match(/(?:season|series)\s*(\d+)|\b(\d+)(?:st|nd|rd|th)\s+season\b/i);
  const part=titles.match(/(?:part|cour)\s*(\d+)/i);
  if(match){
    const season=Number(match[1]||match[2]||1);
    const partNo=Number(part?.[1]||1);
    return partNo>1?`S${season}-${partNo}`:`S${season}`;
  }
  if(part&&Number(part[1])>1) return `S1-${part[1]}`;
  if(/\bii\b|season\s*2|2nd\s*season/i.test(titles)) return 'S2';
  return 'S1';
}

function formatWatchClock(seconds){
  const safe=Math.max(0,Math.floor(Number(seconds)||0));
  const minutes=Math.floor(safe/60);
  const remainder=safe%60;
  if(minutes===0) return `${remainder}s`;
  return `${minutes}:${String(remainder).padStart(2,'0')}`;
}

function card(x,wide=false,type='anime'){
  const title=titleOf(x);
  const baseImage=imageOf(x);
  const image=wide?(x.bannerImage||baseImage):baseImage;
  const meta=type==='manga'
    ? (x.chapters?`${x.chapters} CHAPTERS`:(x.format||'MANGA'))
    : (x.format==='MOVIE'?'MOVIE':(x.episodes?`${x.episodes} EPS`:(x.nextAiringEpisode?.episode>1?`${x.nextAiringEpisode.episode-1}+ EPS`:'? EPS')));
  const badge=type==='manga'?(x.format==='NOVEL'?'LN':'M'):seasonBadge(x);
  const watched=Number(x.progressSeconds)||0;
  const duration=Number(x.durationSeconds)||0;
  const progress=duration>0?Math.max(0,Math.min(1,watched/duration)):0;
  const remaining=duration>watched?duration-watched:0;
  const continueMeta=wide
    ? `<small class="continue-episode">E${esc(x.episode||1)} · ${esc(x.episodeTitle||'Continue watching')}</small>`+
      (duration>0?`<small class="continue-time">${esc(formatWatchClock(watched))} watched · ${esc(formatWatchClock(remaining))} left</small>`:'')
    : `<small>${esc(meta)}</small>`;

  return `<button class="anime-card" data-id="${esc(x.id)}" data-title="${encodeURIComponent(title)}" data-image="${encodeURIComponent(baseImage)}" data-type="${type}">
    <div class="cover">
      <img src="${esc(image)}" loading="lazy" alt="">
      ${badge?`<span class="corner">${esc(badge)}</span>`:''}
      ${x.averageScore?`<span class="rating">★ ${(x.averageScore/10).toFixed(1)}</span>`:''}
      ${wide?'<span class="play-fab">▶</span>':''}
      ${wide?`<span class="progress"><i style="width:${(progress*100).toFixed(1)}%"></i></span>`:''}
    </div>
    <strong>${esc(title)}</strong>
    ${continueMeta}
  </button>`;
}
function rail(title,items,homeKey,browseFilter='all'){
  return `<section class="home-block" data-home-section="${esc(homeKey)}">
    <div class="section-title"><h2>${esc(title)}</h2><button class="section-more" data-filter="${esc(browseFilter)}" aria-label="Open ${esc(title)}">›</button></div>
    <div class="rail">${items.map(x=>card(x)).join('')}</div>
  </section>`;
}

function bindCards(root=document){
  root.querySelectorAll('.anime-card[data-type="anime"]').forEach(b=>{
    b.onclick=()=>openDetails({
      id:+b.dataset.id,
      title:decodeURIComponent(b.dataset.title),
      cover:decodeURIComponent(b.dataset.image)
    });
  });
}

function bindMangaCards(root=document){
  root.querySelectorAll('.anime-card[data-type="manga"]').forEach(b=>{
    b.onclick=()=>openMangaDetails({
      id:+b.dataset.id,
      title:decodeURIComponent(b.dataset.title),
      cover:decodeURIComponent(b.dataset.image)
    });
  });
}

function renderSpotlight(items){
  clearInterval(state.spotlightTimer);
  state.spotlightIndex=0;
  const rail=$('#spotlightRail');
  const heroes=items.slice(0,Math.min(8,items.length));
  rail.classList.remove('skeleton');
  rail.innerHTML=heroes.map(hero=>{
    const status=String(hero.status||'').toUpperCase()==='RELEASING'?'Ongoing':String(hero.status||'').replaceAll('_',' ');
    const description=String(hero.description||'').replace(/<[^>]+>/g,' ').replace(/\s+/g,' ').trim();
    return `
      <button class="spotlight-slide" data-id="${hero.id}" data-title="${encodeURIComponent(titleOf(hero))}" data-image="${encodeURIComponent(imageOf(hero))}" style="background-image:url('${esc(hero.bannerImage||imageOf(hero))}')">
        ${hero.averageScore?`<span class="score">★ ${(hero.averageScore/10).toFixed(1)}</span>`:''}
        <div class="spotlight-content">
          <h1>${esc(titleOf(hero))}</h1>
          ${description?`<p class="spotlight-description">${esc(description)}</p>`:''}
          <div class="spotlight-meta">
            ${status?`<span class="badge">${esc(status)}</span>`:''}
            ${hero.format?`<span class="badge">${esc(hero.format)}</span>`:''}
            ${hero.duration?`<span class="badge">${esc(hero.duration)} min</span>`:''}
          </div>
        </div>
      </button>`;
  }).join('');

  rail.querySelectorAll('.spotlight-slide').forEach(b=>b.onclick=()=>openDetails({
    id:+b.dataset.id,
    title:decodeURIComponent(b.dataset.title),
    cover:decodeURIComponent(b.dataset.image)
  }));

  if(heroes.length>1&&webSettings.spotlightAutoPlay){
    state.spotlightTimer=setInterval(()=>{
      if(document.hidden) return;
      state.spotlightIndex=(state.spotlightIndex+1)%heroes.length;
      const slide=rail.children[state.spotlightIndex];
      if(slide) rail.scrollTo({left:Math.max(0,slide.offsetLeft-(rail.clientWidth-slide.clientWidth)/2),behavior:'smooth'});
    },5000);
  }
}
async function loadHome(){
  try{
    const q=`query{
      trending:Page(page:1,perPage:25){media(type:ANIME,sort:TRENDING_DESC){${mediaFields}}}
      popular:Page(page:1,perPage:20){media(type:ANIME,sort:POPULARITY_DESC){${mediaFields}}}
      favorite:Page(page:1,perPage:20){media(type:ANIME,sort:FAVOURITES_DESC){${mediaFields}}}
      updated:Page(page:1,perPage:20){media(type:ANIME,sort:UPDATED_AT_DESC,status:RELEASING){${mediaFields}}}
      upcoming:Page(page:1,perPage:20){media(type:ANIME,sort:START_DATE,status:NOT_YET_RELEASED){${mediaFields}}}
    }`;
    const d=await anilist(q);
    const clean={
      trending:{...d.trending,media:d.trending.media.filter(mediaVisible)},
      popular:{...d.popular,media:d.popular.media.filter(mediaVisible)},
      favorite:{...d.favorite,media:d.favorite.media.filter(mediaVisible)},
      updated:{...d.updated,media:d.updated.media.filter(mediaVisible)},
      upcoming:{...d.upcoming,media:d.upcoming.media.filter(mediaVisible)}
    };
    state.homeData=clean;
    state.home=clean.trending.media;
    renderSpotlight(state.home);
    $('#homeSections').innerHTML=
      rail('Trending Anime',clean.trending.media,'trending','all')+
      rail('Popular Anime',clean.popular.media,'popular','popular')+
      rail('Most Favorite',clean.favorite.media,'favorite','popular')+
      rail('Recently Updated',clean.updated.media,'updated','airing')+
      rail('Upcoming Anime',clean.upcoming.media,'upcoming','all');
    renderContinue();
    bindCards($('#homePage'));
    $$('.section-more').forEach(b=>b.onclick=()=>{
      state.browseFilter=b.dataset.filter||'all';
      openPage('browsePage');
      setBrowseFilter(state.browseFilter);
    });
    if(!$('#searchInput').value.trim()) renderBrowseLanding(state.browseFilter);
  }catch(e){
    $('#spotlightRail').classList.remove('skeleton');
    $('#spotlightRail').innerHTML=`<div class="empty-state"><h2>Could not load Home</h2><p>${esc(e.message)}</p></div>`;
  }
}

function renderContinue(){
  const saved=JSON.parse(localStorage.getItem('anidash-progress')||'[]')
    .filter(item=>{
      const progress=Number(item.progressSeconds)||0;
      const duration=Number(item.durationSeconds)||0;
      return !(duration>0&&progress/duration>=0.92);
    })
    .sort((a,b)=>b.time-a.time);
  const section=$('#continueSection');
  if(!saved.length){section.hidden=true;return}
  section.hidden=false;
  $('#continueRail').innerHTML=saved.map(x=>card({...x,id:x.id,episode:x.episode,episodeTitle:x.episodeTitle},true)).join('');
  bindCards($('#continueRail'));
}

async function openDetails(media){
  state.current=media;
  state.episodes=[];
  const dlg=$('#detailsDialog');
  if(!dlg.open) dlg.showModal();
  $('#detailsContent').innerHTML=`<div class="detail-hero skeleton" style="background-image:url('${esc(media.cover)}')"><div class="detail-title"><h1>${esc(media.title)}</h1><p>Loading details…</p></div></div>`;
  try{
    const d=await anilist(`query($id:Int){Media(id:$id,type:ANIME){${mediaFields} characters(sort:ROLE,perPage:18){nodes{id name{full}image{large}}}}}`,{id:media.id});
    const m=d.Media;
    state.current={...media,...m,title:titleOf(m),cover:imageOf(m)};
    const tracked=getLibrary().some(x=>String(x.id)===String(m.id));
    $('#detailsContent').innerHTML=`
      <div class="detail-hero" style="background-image:url('${esc(m.bannerImage||imageOf(m))}')">
        <div class="detail-title">
          <div><span class="badge">${esc(m.format||'TV')}</span> <span class="badge">★ ${m.averageScore?(m.averageScore/10).toFixed(1):'—'}</span></div>
          <h1>${esc(titleOf(m))}</h1>
          <p>${m.seasonYear||''} · ${m.episodes||'?'} episodes · ${esc(m.status?.replaceAll('_',' ')||'')}</p>
        </div>
      </div>
      <div class="detail-body">
        <div class="detail-actions">
          <button class="primary" id="playFirst">▶ Play</button>
          <button class="secondary" id="trackAnime">${tracked?'✓ Tracked':'＋ Track'}</button>
        </div>
        <div class="detail-tabs"><button data-tab="about" class="active">About</button><button data-tab="episodes">Episodes</button><button data-tab="characters">Characters</button></div>
        <div id="tabContent"></div>
      </div>`;
    const about=`<section class="tab-pane"><h2>Synopsis</h2><p>${esc(m.description||'No synopsis available.')}</p><h3>Available languages</h3><div class="chips"><button>Japanese · SUB</button><button>English · DUB</button></div><h3>Genres</h3><div class="chips">${(m.genres||[]).map(g=>`<button>${esc(g)}</button>`).join('')}</div></section>`;
    const chars=`<div class="poster-grid">${(m.characters?.nodes||[]).map(c=>`<div class="anime-card"><div class="cover"><img src="${esc(c.image.large)}" alt=""></div><strong>${esc(c.name.full)}</strong></div>`).join('')}</div>`;
    $('#tabContent').innerHTML=about;
    $$('.detail-tabs button').forEach(b=>b.onclick=async()=>{
      $$('.detail-tabs button').forEach(x=>x.classList.toggle('active',x===b));
      if(b.dataset.tab==='about') $('#tabContent').innerHTML=about;
      if(b.dataset.tab==='characters') $('#tabContent').innerHTML=chars;
      if(b.dataset.tab==='episodes') await showEpisodes();
    });
    $('#playFirst').onclick=async()=>{await ensureEpisodes();if(state.episodes.length) playEpisode(state.episodes[0])};
    $('#trackAnime').onclick=()=>{
      let list=getLibrary();
      const idx=list.findIndex(x=>String(x.id)===String(m.id));
      if(idx>=0){
        list.splice(idx,1);
        $('#trackAnime').textContent='＋ Track';
      }else{
        list.unshift({id:m.id,title:titleOf(m),cover:imageOf(m),format:m.format,episodes:m.episodes,status:'watching',favorite:false});
        $('#trackAnime').textContent='✓ Tracked';
      }
      setLibrary(list);
      renderLibrary();
    };
  }catch(e){
    $('#detailsContent').innerHTML+=`<div class="detail-body"><p>${esc(e.message)}</p></div>`;
  }
}

async function openMangaDetails(media){
  state.current=media;
  const dlg=$('#detailsDialog');
  if(!dlg.open) dlg.showModal();
  $('#detailsContent').innerHTML=`<div class="detail-hero skeleton" style="background-image:url('${esc(media.cover)}')"><div class="detail-title"><h1>${esc(media.title)}</h1><p>Loading manga…</p></div></div>`;
  try{
    const d=await anilist(`query($id:Int){Media(id:$id,type:MANGA){${mangaFields} staff(perPage:8){nodes{id name{full}}}}}`,{id:media.id});
    const m=d.Media;
    $('#detailsContent').innerHTML=`
      <div class="detail-hero" style="background-image:url('${esc(m.bannerImage||imageOf(m))}')"><div class="detail-title"><div><span class="badge">${esc(m.format||'MANGA')}</span> <span class="badge">★ ${m.averageScore?(m.averageScore/10).toFixed(1):'—'}</span></div><h1>${esc(titleOf(m))}</h1><p>${m.seasonYear||''} · ${m.chapters||'?'} chapters · ${esc(m.status?.replaceAll('_',' ')||'')}</p></div></div>
      <div class="detail-body"><div class="detail-tabs"><button class="active">About</button></div><section class="tab-pane"><h2>Synopsis</h2><p>${esc(m.description||'No synopsis available.')}</p><h3>Genres</h3><div class="chips">${(m.genres||[]).map(g=>`<button>${esc(g)}</button>`).join('')}</div><h3>Web reader</h3><p>Manga discovery is available here. Extension-based reading remains a native AniDash feature.</p></section></div>`;
  }catch(e){
    $('#detailsContent').innerHTML+=`<div class="detail-body"><p>${esc(e.message)}</p></div>`;
  }
}

function normalizeEpisodePages(payload){
  const direct=Number(payload?.totalPages);
  if(Number.isFinite(direct)&&direct>0) return direct;
  const pageInfo=Number(payload?.pageInfo?.lastPage);
  if(Number.isFinite(pageInfo)&&pageInfo>0) return pageInfo;
  const pagination=Number(payload?.pagination?.totalPages||payload?.pagination?.lastPage);
  if(Number.isFinite(pagination)&&pagination>0) return pagination;
  return 1;
}

function mergeEpisodes(items){
  const byNumber=new Map(state.episodes.map(ep=>[String(ep.number),ep]));
  for(const ep of items||[]){
    if(ep?.number===undefined||ep?.number===null) continue;
    byNumber.set(String(ep.number),ep);
  }
  state.episodes=[...byNumber.values()].sort((a,b)=>Number(a.number)-Number(b.number));
}

function synthesizeEpisodesFromAniList(){
  const count=Number(
    state.current?.episodes||
    (state.current?.nextAiringEpisode?.episode?state.current.nextAiringEpisode.episode-1:0)
  );
  if(!Number.isFinite(count)||count<=0) return false;
  state.episodes=Array.from({length:count},(_,i)=>({
    number:i+1,
    title:`Episode ${i+1}`,
    image:state.current?.bannerImage||state.current?.cover||''
  }));
  return true;
}

async function ensureEpisodes(onProgress){
  if(state.episodes.length) return;

  let first;
  try{
    first=await api({action:'episodes',id:state.current.id,page:1},{timeout:18000});
  }catch(error){
    if(synthesizeEpisodesFromAniList()) return;
    throw error;
  }

  mergeEpisodes(first.episodes||[]);
  const totalPages=Math.min(50,normalizeEpisodePages(first));
  onProgress?.({loadedPages:1,totalPages,episodes:state.episodes.length});

  // Remaining pages are pulled in the background through a small worker pool.
  // Long series expose up to 50 pages (5 000+ episodes); firing them all at
  // once stalled the episode tab and hammered the upstream API.
  loadRemainingEpisodes({
    id:state.current.id,
    totalPages,
    inferred:(first.episodes||[]).length>=100,
    onProgress
  });

  if(!state.episodes.length) synthesizeEpisodesFromAniList();
}

let episodeLoader=null;

function loadRemainingEpisodes({id,totalPages,inferred=false,onProgress}){
  const key=String(id);
  if(episodeLoader?.id===key) return;

  const queue=inferred
    ? Array.from({length:24},(_,index)=>index+2)
    : Array.from({length:Math.max(0,totalPages-1)},(_,index)=>index+2);
  if(!queue.length) return;

  const loader={id:key};
  episodeLoader=loader;
  const stillCurrent=()=>String(state.current?.id)===key;
  let completed=1;

  const worker=async()=>{
    while(queue.length){
      if(!stillCurrent()) return;
      const page=queue.shift();
      let payload=null;
      try{
        payload=await api({action:'episodes',id,page},{timeout:18000});
      }catch(_){}
      if(!stillCurrent()) return;

      const items=payload?.episodes||[];
      if(payload&&items.length) mergeEpisodes(items);
      completed++;
      onProgress?.({
        loadedPages:completed,
        totalPages:totalPages||null,
        episodes:state.episodes.length
      });

      if(payload&&!items.length) return;
      if(inferred&&items.length<100) return;
    }
  };

  const width=Math.min(3,queue.length);
  Promise.all(Array.from({length:width},()=>worker())).finally(()=>{
    if(episodeLoader===loader) episodeLoader=null;
    if(!stillCurrent()) return;
    onProgress?.({
      loadedPages:completed,
      totalPages:totalPages||null,
      episodes:state.episodes.length,
      done:true
    });
  });
}

function renderEpisodeButtons(box,loadingText=''){
  if(!state.episodes.length){
    box.innerHTML='<p>No episodes are available from this source.</p>';
    return;
  }
  const current=String(state.playingEpisode?.number??'');
  box.innerHTML=`${loadingText?`<p class="episode-loading-note">${esc(loadingText)}</p>`:''}<div class="episode-list">${state.episodes.map(ep=>`<button class="episode${String(ep.number)===current?' is-current':''}" data-episode="${esc(ep.number)}"><img src="${esc(ep.image||state.current.cover)}" loading="lazy" alt=""><span><strong>E${esc(ep.number)} — ${esc(ep.title||'Episode '+ep.number)}</strong><small>${ep.filler?'Filler episode':'Tap to watch'}</small></span></button>`).join('')}</div>`;
  box.querySelectorAll('.episode').forEach((b,i)=>b.onclick=()=>{
    const next=state.episodes[i];
    if(!next) return;
    if(String(next.number)===String(state.playingEpisode?.number)) return;
    playEpisode(next);
  });
}

async function showEpisodes(){
  const box=$('#tabContent');
  box.innerHTML='<p>Fetching episodes…</p>';
  try{
    await ensureEpisodes(progress=>{
      const suffix=progress.totalPages
        ? `Loading episodes… ${progress.loadedPages}/${progress.totalPages} pages`
        : `Loading episodes… ${progress.episodes} found`;
      if(state.episodes.length) renderEpisodeButtons(box,suffix);
      else box.innerHTML=`<p>${esc(suffix)}</p>`;
    });
    renderEpisodeButtons(box);
  }catch(e){
    box.innerHTML=`<div class="episode-load-error"><p>${esc(e.message)}</p><button class="primary" id="retryEpisodes">Retry</button></div>`;
    $('#retryEpisodes')?.addEventListener('click',()=>{
      state.episodes=[];
      showEpisodes();
    });
  }
}

/* ============================== Playback engine ==============================
 * Everything below owns the <video> element: stream lifecycle, candidate
 * failover, and the reactive state the control bar renders from.
 * ======================================================================== */

const player={
  sources:[],          // candidate streams for the open episode
  index:-1,            // candidate currently attached
  source:null,
  subtitles:[],        // {label, lang, kind, proxiedUrl}
  subtitleIndex:-1,    // -1 == off
  levels:[],           // HLS rendition levels (hls.js only)
  levelIndex:-1,       // -1 == auto
  token:0,             // invalidates overlapping playEpisode() calls
  retries:0,
  intro:null,
  outro:null,
  controlsTimer:null,
  scrubbing:false,
  lastVolume:1,
  pendingServer:'',    // explicit server chosen by the viewer
  fatal:false
};

function destroyStream(){
  if(state.hls){
    try{state.hls.destroy()}catch(_){}
    state.hls=null;
  }
  player.source=null;
  player.levels=[];
  player.levelIndex=-1;
}

function resetVideoElement(video){
  destroyStream();
  const frame=$('#externalPlayerFrame');
  if(frame){frame.hidden=true;frame.src='about:blank'}
  $('#playerStage')?.classList.remove('external-embed-active');
  video.hidden=false;
  try{video.pause()}catch(_){}
  video.removeAttribute('src');
  try{video.load()}catch(_){}
  player.fatal=false;
}

function streamLabel(source){
  return [source?.server,source?.quality].filter(Boolean).join(' · ')||'stream';
}

function uniqueBy(list,keyFn){
  const seen=new Set();
  const out=[];
  for(const item of list||[]){
    const key=keyFn(item);
    if(!key||seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

function orderedStreamCandidates(sources){
  const preferred=String(webSettings.preferredQuality||'Auto').toLowerCase();
  const wanted=preferred==='auto'?null:preferred.replace('p','');
  const serverRank={'Momo':0,'Zoko':1,'Gigi':2,'Neko':3};

  const seen=new Set();
  return [...(sources||[])]
    .filter(source=>source?.url&&!seen.has(source.url)&&(seen.add(source.url),true))
    .sort((a,b)=>{
      const serverDiff=(serverRank[a.server]??99)-(serverRank[b.server]??99);
      if(serverDiff!==0) return serverDiff;
      const aq=wanted&&String(a.quality||'').toLowerCase().replace('p','').includes(wanted)?0:1;
      const bq=wanted&&String(b.quality||'').toLowerCase().replace('p','').includes(wanted)?0:1;
      return aq-bq;
    });
}

const STREAM_TIMEOUT_MS=12000;
const CONFIRM_TIMEOUT_MS=8000;
// Upper bound on how long playEpisode will cycle through candidates before
// giving up, so a run of dead servers still produces feedback in reasonable time.
const FAILOVER_BUDGET_MS=45000;

async function tryNativeStream(video,source){
  return new Promise((resolve,reject)=>{
    let settled=false;
    const finish=(error)=>{
      if(settled) return;
      settled=true;
      clearTimeout(timer);
      video.removeEventListener('loadedmetadata',ready);
      video.removeEventListener('canplay',ready);
      video.removeEventListener('error',failed);
      if(!error) player.source=source;
      error?reject(error):resolve();
    };
    const ready=()=>finish();
    const failed=()=>finish(Error(
      video.error?.code===4
        ? 'This stream format is not supported by this browser'
        : 'This stream could not be decoded'
    ));
    const timer=setTimeout(()=>finish(Error('This stream timed out')),STREAM_TIMEOUT_MS);
    video.preload='auto';
    video.addEventListener('loadedmetadata',ready);
    video.addEventListener('canplay',ready);
    video.addEventListener('error',failed);
    video.src=source.url;
    video.load();
  });
}

async function tryHlsStream(video,source){
  if(!globalThis.Hls||!Hls.isSupported()){
    throw Error('HLS playback library is unavailable');
  }

  return new Promise((resolve,reject)=>{
    let settled=false;
    let mediaRecoveries=0;
    let networkRecoveries=0;
    let timer;

    const hls=new Hls({
      enableWorker:true,
      lowLatencyMode:false,
      backBufferLength:60,
      maxBufferLength:60,
      maxMaxBufferLength:240,
      maxBufferSize:64*1000*1000,
      startLevel:-1,
      capLevelToPlayerSize:false,
      manifestLoadingTimeOut:12000,
      manifestLoadingMaxRetry:3,
      manifestLoadingRetryDelay:600,
      levelLoadingTimeOut:12000,
      levelLoadingMaxRetry:3,
      levelLoadingRetryDelay:600,
      fragLoadingTimeOut:20000,
      fragLoadingMaxRetry:6,
      fragLoadingRetryDelay:500,
      nudgeMaxRetry:6,
      nudgeOffset:0.2,
      maxFragLookUpTolerance:0.3,
    });
    state.hls=hls;

    const finish=(error)=>{
      if(settled) return;
      settled=true;
      clearTimeout(timer);
      if(error){
        try{hls.destroy()}catch(_){}
        if(state.hls===hls) state.hls=null;
        reject(error);
        return;
      }
      player.source=source;
      resolve();
    };

    timer=setTimeout(()=>finish(Error('Video stream timed out')),STREAM_TIMEOUT_MS+5000);

    const syncLevels=()=>{
      if(state.hls!==hls) return;
      player.levels=(hls.levels||[]).map((level,index)=>({
        index,
        height:Number(level.height)||0,
        bitrate:Number(level.bitrate)||0,
        label:level.height
          ? `${level.height}p`
          : `${Math.round((Number(level.bitrate)||0)/1000)} kbps`
      }));
      renderQualityMenu();
    };

    hls.on(Hls.Events.MANIFEST_PARSED,syncLevels);
    hls.on(Hls.Events.LEVELS_UPDATED,syncLevels);
    hls.on(Hls.Events.AUDIO_TRACKS_UPDATED,()=>{
      if(state.hls===hls) renderAudioMenu();
    });
    hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED,(_,data)=>{
      if(state.hls===hls) mergeHlsSubtitles(data?.subtitleTracks||[]);
    });

    hls.on(Hls.Events.ERROR,(_,data)=>{
      if(!data?.fatal) return;

      if(data.type===Hls.ErrorTypes.MEDIA_ERROR&&mediaRecoveries<2){
        mediaRecoveries++;
        try{
          hls.recoverMediaError();
          return;
        }catch(_){}
      }

      if(data.type===Hls.ErrorTypes.NETWORK_ERROR&&networkRecoveries<3){
        networkRecoveries++;
        try{
          hls.startLoad();
        }catch(_){}
        if(!settled){
          clearTimeout(timer);
          timer=setTimeout(
            ()=>finish(Error('Stream network request failed')),
            8000
          );
        }else{
          setPlayerStatus(`Reconnecting (${networkRecoveries}/3)…`);
        }
        return;
      }

      const message=data.type===Hls.ErrorTypes.NETWORK_ERROR
        ? 'Stream network request failed'
        : 'Stream format could not be decoded';

      if(!settled) finish(Error(message));
      else showPlaybackError(message);
    });

    hls.loadSource(source.url);
    hls.attachMedia(video);
  });
}

async function startAndConfirmPlayback(video){
  const start=Number(video.currentTime||0);

  try{
    await video.play();
  }catch(error){
    if(error?.name==='NotAllowedError'){
      return {needsTap:true};
    }
    throw error;
  }

  if(Number(video.currentTime||0)>start+0.05){
    return {needsTap:false};
  }

  return new Promise((resolve,reject)=>{
    let settled=false;

    const finish=(error)=>{
      if(settled) return;
      settled=true;
      clearTimeout(timer);
      video.removeEventListener('timeupdate',advanced);
      video.removeEventListener('playing',playing);
      video.removeEventListener('error',failed);
      error?reject(error):resolve({needsTap:false});
    };

    const advanced=()=>{
      if(Number(video.currentTime||0)>start+0.05) finish();
    };
    const playing=()=>{
      setTimeout(advanced,250);
    };
    const failed=()=>finish(Error('This stream could not be decoded'));
    const timer=setTimeout(()=>finish(Error('Video started but no frame was decoded')),CONFIRM_TIMEOUT_MS);

    video.addEventListener('timeupdate',advanced);
    video.addEventListener('playing',playing);
    video.addEventListener('error',failed,{once:true});
  });
}

function savedProgressFor(ep){
  try{
    const list=JSON.parse(localStorage.getItem('anidash-progress')||'[]');
    return list.find(item=>
      String(item.id)===String(state.current?.id)&&
      Number(item.episode)===Number(ep?.number)
    )||null;
  }catch(_){
    return null;
  }
}

async function restoreResumePosition(video,ep){
  const saved=savedProgressFor(ep);
  const position=Number(saved?.progressSeconds)||0;
  if(position<=1) return;

  if(video.readyState<1){
    await Promise.race([
      new Promise(resolve=>video.addEventListener('loadedmetadata',resolve,{once:true})),
      new Promise(resolve=>setTimeout(resolve,3000))
    ]);
  }

  const duration=Number(video.duration)||Number(saved?.durationSeconds)||0;
  if(duration>0&&position>=duration*0.92) return;
  try{video.currentTime=position}catch(_){}
}

function persistPlaybackProgress(ep,video,{force=false}={}){
  if(webSettings.incognito||!ep||!state.current) return;
  const now=Date.now();
  if(!force&&now-state.lastProgressSave<4500) return;
  state.lastProgressSave=now;

  let list=[];
  try{list=JSON.parse(localStorage.getItem('anidash-progress')||'[]')}catch(_){}
  const previous=list.find(item=>String(item.id)===String(state.current.id));
  list=list.filter(item=>String(item.id)!==String(state.current.id));

  const progressSeconds=Math.max(0,Math.floor(Number(video?.currentTime)||Number(previous?.progressSeconds)||0));
  const mediaDuration=Number(video?.duration);
  const durationSeconds=Number.isFinite(mediaDuration)&&mediaDuration>0
    ? Math.floor(mediaDuration)
    : Math.max(0,Math.floor(Number(previous?.durationSeconds)||0));

  list.unshift({
    ...previous,
    id:state.current.id,
    title:state.current.title||titleOf(state.current),
    cover:ep.image||state.current.bannerImage||state.current.cover||imageOf(state.current),
    bannerImage:ep.image||state.current.bannerImage,
    episode:+ep.number,
    episodeTitle:ep.title||`Episode ${ep.number}`,
    episodes:state.current.episodes,
    format:state.current.format,
    progressSeconds,
    durationSeconds,
    time:now
  });

  localStorage.setItem('anidash-progress',JSON.stringify(list.slice(0,30)));
  renderContinue();
  renderHistoryPage();
}

/* ---- episode source retrieval (cached, retried, server aware) ------------- */

const SOURCE_CACHE_TTL=30*60*1000;

function sourceCacheKey(id,episode,audio,server){
  return `anidash-src:${id}:${episode}:${audio}:${server||'auto'}`;
}

function readSourceCache(key){
  try{
    const cached=JSON.parse(sessionStorage.getItem(key)||'null');
    if(cached?.payload?.sources?.length&&Date.now()-cached.time<SOURCE_CACHE_TTL){
      return cached.payload;
    }
  }catch(_){}
  return null;
}

function proxyMediaUrl(url,headers){
  const params=new URLSearchParams();
  params.set('url',url);
  params.set('headers',JSON.stringify(headers||{}));
  return '/api/media?'+params.toString();
}

/**
 * Resolve a playable source for one episode.
 * Successful responses are remembered for the tab session so a retry after a
 * decoder hiccup does not pay the upstream round-trip again; an explicit
 * `server` choice always bypasses the cache.
 */
function fetchEpisodeSource(id,episode,audio,server=''){
  const key=sourceCacheKey(id,episode,audio,server);
  const cached=server?null:readSourceCache(key);
  if(cached) return Promise.resolve(cached);

  return api({
    action:'source',
    id,
    episode,
    audio,
    ...(server?{server}:{})
  },{timeout:22000}).then(payload=>{
    if(payload?.sources?.length&&!server){
      try{
        sessionStorage.setItem(key,JSON.stringify({time:Date.now(),payload}));
      }catch(_){}
    }
    return payload;
  }).catch(error=>{
    const stale=server?null:readSourceCache(key);
    if(stale) return stale;
    throw error;
  });
}

function normalizeSubtitles(list){
  return uniqueBy(
    (list||[]).map(track=>{
      const raw=String(track?.url||track?.file||'').trim();
      if(!raw) return null;
      const url=/^https?:\/\//i.test(raw)?proxyMediaUrl(raw,track.headers||{}):raw;
      return {
        label:String(track?.label||track?.lang||track?.language||'Subtitle'),
        lang:String(track?.lang||track?.language||'en'),
        kind:track?.kind==='subtitles'?'subtitles':'captions',
        url
      };
    }).filter(Boolean),
    item=>item.url
  );
}

async function playEpisode(ep,{server=''}={}){
  const dlg=$('#playerDialog'),video=$('#video'),loading=$('#playerLoading');
  if(!dlg.open) dlg.showModal();

  if(state.playingEpisode&&state.playingEpisode!==ep&&state.current?.sourceProvider!=='toonstream'){
    persistPlaybackProgress(state.playingEpisode,video,{force:true});
  }

  const token=++player.token;
  const series=state.current;
  player.episode=ep;
  state.playingEpisode=null;
  player.subtitleIndex=-1;
  player.retries=0;
  player.intro=null;
  player.outro=null;
  player.pendingServer=server||'';
  player.fatal=false;

  closePlayerMenus();
  hidePlaybackError();
  hidePlayerChips();
  if(ep?.image) video.poster=ep.image;

  updatePlayerTitle(ep,series);
  setPlayerStatus('Loading episode…');
  $('#playerLoadingText').textContent='Starting video…';
  loading.hidden=false;
  showControls(true);
  resetVideoElement(video);

  try{
    const audio=webSettings.preferredAudio==='dub'?'dub':'sub';
    const select=$('#audio');
    if(select) select.value=audio;

    if(series?.sourceProvider==='toonstream'){
      const payload=await hindiApi({action:'source',url:ep.url},{timeout:22000});
      if(token!==player.token) return;
      const chosen=(payload.sources||[])[0];
      if(!chosen?.url) throw Error('No browser-compatible Hindi player was returned for this episode.');
      if(chosen.kind==='video'){
        const frame=$('#externalPlayerFrame');
        frame.hidden=true;
        frame.src='about:blank';
        $('#playerStage').classList.remove('external-embed-active');
        video.hidden=false;
        const directSource={
          url:chosen.url,
          server:'Toonstream',
          type:'Hindi',
          quality:chosen.label||'Auto',
          isM3U8:/\.m3u8(?:$|\?)/i.test(chosen.url)
        };
        if(directSource.isM3U8&&globalThis.Hls&&Hls.isSupported()){
          await tryHlsStream(video,directSource);
        }else if(directSource.isM3U8&&video.canPlayType('application/vnd.apple.mpegurl')){
          await tryNativeStream(video,directSource);
        }else if(directSource.isM3U8){
          throw Error('This browser cannot play the Hindi HLS stream directly.');
        }else{
          await tryNativeStream(video,directSource);
        }
        await startAndConfirmPlayback(video);
      }else{
        const frame=$('#externalPlayerFrame');
        frame.src=chosen.url;
        frame.hidden=false;
        video.hidden=true;
        $('#playerStage').classList.add('external-embed-active');
        setPlayerStatus('Hindi · '+(chosen.label||'embedded player'));
      }
      loading.hidden=true;
      state.playingEpisode=ep;
      return;
    }

    const payload=await fetchEpisodeSource(series?.id,ep.number,audio,server);
    if(token!==player.token) return;

    const candidates=orderedStreamCandidates(payload.sources||[]);
    if(!candidates.length){
      throw Error(
        audio==='dub'
          ? 'English dub is not available for this episode.'
          : 'No playable source was found for this episode.'
      );
    }

    player.sources=candidates;
    player.subtitles=normalizeSubtitles(payload.subtitles);
    player.intro=payload.intro||null;
    player.outro=payload.outro||null;
    player.index=-1;

    renderSubtitleMenu();
    renderQualityMenu();
    renderAudioMenu();
    renderEpisodeDrawer(ep);

    let lastError=null;
    let chosen=null;
    let needsTap=false;
    const failoverStart=Date.now();

    for(let index=0;index<candidates.length;index++){
      if(token!==player.token) return;
      if(Date.now()-failoverStart>FAILOVER_BUDGET_MS){
        break;
      }
      const source=candidates[index];
      player.index=index;
      setPlayerStatus(
        candidates.length>1
          ? `Trying ${streamLabel(source)} (${index+1}/${candidates.length})…`
          : `Loading ${streamLabel(source)}…`
      );

      resetVideoElement(video);

      try{
        if(source.isM3U8){
          // Chrome reports "maybe" for apple-mpegurl but cannot actually play
          // it, so the native path is only valid where hls.js is unavailable
          // (Safari). Where hls.js works we always use it.
          if(globalThis.Hls&&Hls.isSupported()){
            await tryHlsStream(video,source);
          }else if(video.canPlayType('application/vnd.apple.mpegurl')){
            await tryNativeStream(video,source);
          }else{
            throw Error('This browser cannot play HLS streams');
          }
        }else{
          await tryNativeStream(video,source);
        }

        if(token!==player.token) return;
        await restoreResumePosition(video,ep);
        const result=await startAndConfirmPlayback(video);
        if(token!==player.token) return;
        needsTap=result.needsTap;
        chosen=source;
        break;
      }catch(error){
        lastError=error;
        resetVideoElement(video);
      }
    }

    if(token!==player.token) return;
    if(!chosen) throw lastError||Error('No browser-compatible stream server was found.');

    loading.hidden=true;
    player.fatal=false;
    state.playingEpisode=ep;
    persistPlaybackProgress(ep,video,{force:true});
    renderEpisodeDrawer(ep);
    syncQualityMenuSelection();
    syncSubtitleSelection();
    updatePlayerChrome();

    if(needsTap){
      setPlayerStatus('Tap play to start');
      $('#playerDialog').classList.add('needs-tap');
      showControls(true);
    }else{
      setPlayerStatus('');
      showControls();
    }
  }catch(error){
    if(token!==player.token) return;
    loading.hidden=true;
    resetVideoElement(video);
    showPlaybackError(
      error?.message||'Playback failed. Try another server or audio track.'
    );
  }
}

function getLibrary(){
  try{return JSON.parse(localStorage.getItem('anidash-library')||'[]')}catch(_){return[]}
}
function setLibrary(list){localStorage.setItem('anidash-library',JSON.stringify(list))}
function renderLibrary(){
  const list=getLibrary();
  const filtered=state.libraryStatus==='favorites'
    ? list.filter(x=>x.favorite)
    : list.filter(x=>(x.status||'watching')===state.libraryStatus);
  $('#libraryGrid').innerHTML=filtered.map(x=>card(x)).join('');
  $('#libraryEmpty').hidden=filtered.length>0;
  bindCards($('#libraryGrid'));
}
function setLibraryStatus(status){
  state.libraryStatus=status;
  $$('#libraryFilters button').forEach(b=>b.classList.toggle('active',b.dataset.status===status));
  renderLibrary();
}

async function runSearch(){
  const q=$('#searchInput').value.trim();
  $('#clearSearch').hidden=!q;
  if(!q){
    $('#searchHistory').hidden=false;
    renderHistory();
    await renderBrowseLanding(state.browseFilter);
    return;
  }
  $('#searchHistory').hidden=true;
  $('#searchStatus').textContent='Searching…';
  try{
    const d=await anilist(`query($q:String){Page(page:1,perPage:40){media(type:ANIME,search:$q,sort:SEARCH_MATCH){${mediaFields}}}}`,{q});
    const items=d.Page.media.filter(mediaVisible);
    $('#searchGrid').innerHTML=items.map(x=>card(x)).join('');
    bindCards($('#searchGrid'));
    $('#searchStatus').textContent=`${items.length} results`;
    let h=JSON.parse(localStorage.getItem('anidash-searches')||'[]').filter(x=>x!==q);
    h.unshift(q);
    localStorage.setItem('anidash-searches',JSON.stringify(h.slice(0,8)));
  }catch(e){
    $('#searchGrid').innerHTML='';
    $('#searchStatus').textContent=e.message;
  }
}

function renderHistory(){
  const h=JSON.parse(localStorage.getItem('anidash-searches')||'[]');
  $('#searchHistory').innerHTML=h.length?`<div class="section-title"><h2>Recent searches</h2></div><div class="chips">${h.map(x=>`<button class="history">${esc(x)}</button>`).join('')}</div>`:'';
  $$('.history').forEach(b=>b.onclick=()=>{$('#searchInput').value=b.textContent;runSearch()});
}

async function renderBrowseLanding(filter='all'){
  state.browseFilter=filter;
  $('#searchStatus').textContent='Loading…';
  try{
    let items=[];
    if(filter==='all'&&state.homeData) items=state.homeData.trending.media;
    else if(filter==='popular'&&state.homeData) items=state.homeData.popular.media;
    else{
      const args=filter==='airing'?'status:RELEASING,sort:TRENDING_DESC':filter==='movie'?'format:MOVIE,sort:POPULARITY_DESC':'sort:TRENDING_DESC';
      const d=await anilist(`query{Page(page:1,perPage:36){media(type:ANIME,${args}){${mediaFields}}}}`);
      items=d.Page.media;
    }
    items=items.filter(mediaVisible);
    $('#searchGrid').innerHTML=items.map(x=>card(x)).join('');
    bindCards($('#searchGrid'));
    $('#searchStatus').textContent=filter==='all'?'Trending now':filter==='airing'?'Currently airing':filter==='movie'?'Popular movies':'Popular anime';
  }catch(e){$('#searchStatus').textContent=e.message}
}

function setBrowseFilter(filter){
  state.browseFilter=filter;
  $$('#browseFilters button').forEach(b=>b.classList.toggle('active',b.dataset.filter===filter));
  if(!$('#searchInput').value.trim()) renderBrowseLanding(filter);
}

async function loadManga(query=''){
  $('#clearManga').hidden=!query;
  $('#mangaStatus').textContent=query?'Searching…':'Loading manga…';
  try{
    const d=query
      ? await anilist(`query($q:String){Page(page:1,perPage:36){media(type:MANGA,search:$q,sort:SEARCH_MATCH){${mangaFields}}}}`,{q:query})
      : await anilist(`query{Page(page:1,perPage:36){media(type:MANGA,sort:TRENDING_DESC){${mangaFields}}}}`);
    const items=d.Page.media.filter(mediaVisible);
    $('#mangaGrid').innerHTML=items.map(x=>card(x,false,'manga')).join('');
    bindMangaCards($('#mangaGrid'));
    $('#mangaStatus').textContent=query?`${items.length} results`:'Trending manga';
  }catch(e){
    $('#mangaGrid').innerHTML='';
    $('#mangaStatus').textContent=e.message;
  }
}

const desktopShellQuery=window.matchMedia('(min-width:1100px)');
const isDesktopShell=()=>desktopShellQuery.matches;

const MAC_PAGE_META={
  homePage:['Home','i-home'],
  browsePage:['Browse','i-search'],
  mangaPage:['Manga','i-book'],
  watchlistPage:['Watchlist','i-bookmark'],
  historyPage:['Watch History','i-history'],
  aiPage:['AniAI Assistant','i-spark'],
  newsPage:['Anime News','i-news'],
  notificationsPage:['Notifications','i-bell'],
  extensionsPage:['Extensions','i-extension'],
  settingsPage:['Settings','i-settings']
};

function syncMacChrome(pageId,label,icon){
  const meta=MAC_PAGE_META[pageId]||['AniDash','i-home'];
  const title=label||meta[0];
  const iconId=icon||meta[1];
  const titleNode=$('#macPageTitle');
  const iconUse=$('#macPageIcon use');
  if(titleNode) titleNode.textContent=title;
  if(iconUse) iconUse.setAttribute('href','#'+iconId);
  $$('.mac-nav-item').forEach(button=>button.classList.remove('active'));
  $$('.mac-nav-item[data-page]').forEach(button=>{
    button.classList.toggle('active',button.dataset.page===pageId);
  });
}

function formatRelativeTime(timestamp){
  const diff=Math.max(0,Date.now()-Number(timestamp||0));
  const minutes=Math.floor(diff/60000);
  if(minutes<1) return 'Just now';
  if(minutes<60) return minutes+'m ago';
  const hours=Math.floor(minutes/60);
  if(hours<24) return hours+'h ago';
  const days=Math.floor(hours/24);
  if(days<30) return days+'d ago';
  return new Date(timestamp).toLocaleDateString();
}

function renderHistoryPage(){
  const grid=$('#historyGrid');
  const empty=$('#historyEmpty');
  if(!grid||!empty) return;
  let list=[];
  try{list=JSON.parse(localStorage.getItem('anidash-progress')||'[]')}catch(_){}
  const badge=$('#macHistoryBadge');
  if(badge) badge.textContent=list.length?(list.length>99?'99+':String(list.length)):'';

  grid.innerHTML=list.map(item=>`
    <button class="history-item" data-history-id="${esc(item.id)}">
      <img src="${esc(item.bannerImage||item.cover||'')}" loading="lazy" alt="">
      <span><b>${esc(item.title||'Anime')}</b><small>E${esc(item.episode||1)} · ${esc(item.episodeTitle||'Continue watching')}</small></span>
      <time>${esc(formatRelativeTime(item.time))}</time>
    </button>
  `).join('');
  empty.hidden=list.length>0;

  grid.querySelectorAll('.history-item').forEach(button=>{
    button.onclick=()=>{
      const item=list.find(entry=>String(entry.id)===button.dataset.historyId);
      if(item) openDetails({
        id:+item.id,
        title:item.title,
        cover:item.cover||item.bannerImage||''
      });
    };
  });
}

function buildAiContext(){
  let progress=[];
  let library=[];
  try{progress=JSON.parse(localStorage.getItem('anidash-progress')||'[]')}catch(_){}
  try{library=JSON.parse(localStorage.getItem('anidash-library')||'[]')}catch(_){}
  return {
    currentPage:$('.page.active')?.id||'homePage',
    librarySummary:{
      continueWatching:progress.slice(0,20),
      library:library.slice(0,50)
    },
    conversationHistory:state.aiConversation.slice(-12)
  };
}

function appendAiMessage(role,text){
  const box=$('#aiMessages');
  if(!box) return;
  const item=document.createElement('div');
  item.className='ai-message '+role;
  item.innerHTML=`
    <span class="ai-avatar"><svg class="icon"><use href="#${role==='user'?'i-user':'i-spark'}"/></svg></span>
    <div><b>${role==='user'?'You':'AniAI'}</b><p></p></div>
  `;
  item.querySelector('p').textContent=text;
  box.appendChild(item);
  box.scrollTop=box.scrollHeight;
}

async function sendAiMessage(message){
  const clean=String(message||'').trim();
  if(!clean) return;
  appendAiMessage('user',clean);
  state.aiConversation.push({role:'user',content:clean});
  const send=$('#aiSendButton');
  const input=$('#aiChatInput');
  if(send) send.disabled=true;
  if(input) input.disabled=true;

  const pending='Thinking…';
  appendAiMessage('assistant',pending);
  const pendingNode=$('#aiMessages .ai-message:last-child p');

  try{
    const response=await fetch('/api/ai',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        message:clean,
        assistantId:'coordinator',
        assistantDisplayName:'NEXUS',
        editAuthorized:false,
        context:buildAiContext(),
        instructions:{
          global:'Be concise, useful and focused on anime, manga and AniDash.',
          specialist:'Use the local AniDash watch/library context when it is relevant.'
        }
      })
    });
    const data=await response.json().catch(()=>({}));
    if(!response.ok) throw Error(data.error||'AniAI is temporarily unavailable');
    const answer=String(data.text||'').trim()||'I could not generate a response.';
    if(pendingNode) pendingNode.textContent=answer;
    state.aiConversation.push({role:'assistant',content:answer});
  }catch(error){
    if(pendingNode) pendingNode.textContent=error?.message||'AniAI is temporarily unavailable.';
  }finally{
    if(send) send.disabled=false;
    if(input){input.disabled=false;input.focus()}
  }
}

async function loadDesktopNews(force=false){
  if(state.newsLoaded&&!force) return;
  const status=$('#newsStatus');
  const grid=$('#newsGrid');
  if(!status||!grid) return;
  status.textContent='Loading latest anime news…';
  try{
    const response=await fetch('/api/news'+(force?'?refresh=1':''));
    const payload=await response.json().catch(()=>({}));
    if(!response.ok) throw Error(payload.error||'Could not load news');
    const items=Array.isArray(payload.items)?payload.items:[];
    grid.innerHTML=items.map(item=>`
      <a class="news-card" href="${esc(item.url)}" target="_blank" rel="noopener noreferrer">
        ${item.imageUrl?`<img src="${esc(item.imageUrl)}" loading="lazy" alt="">`:'<div class="news-card-placeholder"></div>'}
        <div><time>${esc(item.date?new Date(item.date).toLocaleDateString():'')}</time><b>${esc(item.title)}</b><p>${esc(item.excerpt||'')}</p></div>
      </a>
    `).join('');
    status.textContent=items.length?`${items.length} latest articles`:'No news is available right now.';
    state.newsLoaded=true;
  }catch(error){
    grid.innerHTML='';
    status.textContent=error?.message||'Anime news is temporarily unavailable.';
  }
}

function renderDesktopNotifications(){
  const card=$('#desktopNotificationCard');
  const button=$('#desktopNotificationPermission');
  if(!card||!button) return;
  const supported='Notification' in window;
  const permission=supported?Notification.permission:'unsupported';
  const installed=window.matchMedia('(display-mode: standalone)').matches||window.navigator.standalone===true;
  const label=permission==='granted'?'Allowed':permission==='denied'?'Blocked':permission==='default'?'Not requested':'Unsupported';
  card.innerHTML=`<h2>Notification Status</h2><p><b>${esc(label)}</b> · ${installed?'AniDash is running in standalone app mode.':'Install AniDash as a PWA for the most app-like notification experience.'}</p>`;
  button.hidden=!supported||permission==='granted';
  button.textContent=permission==='denied'?'Open Browser Settings':'Enable Notifications';
}

async function requestDesktopNotifications(){
  if(!('Notification' in window)) return;
  if(Notification.permission==='denied'){
    showUtility('Notifications','Notification permission is blocked for AniDash. Re-enable it from your browser or system site-notification settings, then reopen AniDash.');
    renderDesktopNotifications();
    return;
  }
  if(Notification.permission==='default'){
    try{await Notification.requestPermission()}catch(_){}
  }
  renderDesktopNotifications();
  updateNotificationPermissionStatus();
}

async function checkSourceHealth(){
  const badge=$('#sourceHealthBadge');
  if(!badge) return;
  badge.className='source-badge';
  badge.textContent='Checking…';
  try{
    await api({action:'search',query:'One Piece',page:'1'},{timeout:12000});
    badge.textContent='Online';
    badge.classList.add('ok');
  }catch(_){
    badge.textContent='Unavailable';
    badge.classList.add('bad');
  }
}

function renderHindiSearchResults(results){
  const grid=$('#hindiSearchGrid');
  if(!grid) return;
  if(!results.length){
    grid.innerHTML='';
    return;
  }
  grid.innerHTML=results.map(item=>`
    <button class="anime-card hindi-result" type="button" data-hindi-url="${encodeURIComponent(item.url)}" data-hindi-title="${encodeURIComponent(item.title)}" data-hindi-image="${encodeURIComponent(item.image||'')}">
      <div class="cover">${item.image?`<img src="${esc(item.image)}" loading="lazy" alt="">`:''}<span class="corner">HI</span></div>
      <strong>${esc(item.title)}</strong><small>Toonstream · Hindi</small>
    </button>`).join('');
  grid.querySelectorAll('.hindi-result').forEach(button=>{
    button.onclick=()=>loadHindiEpisodes({
      url:decodeURIComponent(button.dataset.hindiUrl),
      title:decodeURIComponent(button.dataset.hindiTitle),
      image:decodeURIComponent(button.dataset.hindiImage||'')
    });
  });
}
async function loadHindiSearch(query=''){
  const status=$('#hindiSearchStatus');
  if(!status) return;
  if($('#hindiEpisodesPanel')&&!$('#hindiEpisodesPanel').hidden) resetHindiEpisodes();
  $('#hindiSearchGrid').hidden=false;
  status.textContent=query?'Searching Hindi titles…':'Loading Hindi catalogue…';
  try{
    const payload=await hindiApi({action:'search',query,page:1});
    const results=payload.results||[];
    renderHindiSearchResults(results);
    status.textContent=results.length?`${results.length} Hindi titles found · Toonstream`:'No titles found. Try another search or open the source website.';
    state.hindiLoaded=true;
  }catch(error){
    status.textContent=error.message+' You can use the external source link below.';
  }
}
async function loadHindiEpisodes(item){
  state.hindiCurrent=item;
  state.current={id:item.url,title:item.title,cover:item.image||'',sourceProvider:'toonstream'};
  state.episodes=[];
  $('#hindiSearchGrid').hidden=true;
  $('#hindiEpisodesPanel').hidden=false;
  $('#hindiSelectedTitle').textContent=item.title;
  $('#hindiEpisodesStatus').textContent='Loading episodes…';
  $('#hindiEpisodeGrid').innerHTML='';
  try{
    const payload=await hindiApi({action:'episodes',url:item.url});
    state.episodes=(payload.episodes||[]).map((episode,index)=>({
      ...episode,
      number:Number(episode.number)||index+1,
      title:episode.title||'Episode '+(index+1),
      image:episode.image||item.image||''
    }));
    if(!state.episodes.length) throw Error('No episodes were returned by this source.');
    $('#hindiEpisodesStatus').textContent=state.episodes.length+' episodes available · Hindi source';
    $('#hindiEpisodeGrid').innerHTML=state.episodes.map((episode,index)=>`
      <button class="episode hindi-episode-button" type="button" data-hindi-episode="${index}">
        ${episode.image?`<img src="${esc(episode.image)}" loading="lazy" alt="">`:''}
        <span><strong>${esc(episode.season?episode.season+' · ':'')}${esc(episode.title)}</strong><small>Play Hindi source</small></span>
      </button>`).join('');
    $('#hindiEpisodeGrid').querySelectorAll('[data-hindi-episode]').forEach(button=>{
      button.onclick=()=>playEpisode(state.episodes[Number(button.dataset.hindiEpisode)]);
    });
  }catch(error){
    $('#hindiEpisodesStatus').textContent=error.message;
  }
}
function resetHindiEpisodes(){
  $('#hindiEpisodesPanel').hidden=true;
  $('#hindiSearchGrid').hidden=false;
  $('#hindiSearchStatus').textContent='Choose a Hindi title to view its episodes.';
  state.hindiCurrent=null;
  state.current=null;
  state.episodes=[];
}
function openSettingsFocus(query='',label='Settings',icon='i-settings'){
  openPage('settingsPage',{label,icon});
  const selected=$$('.mac-settings-link').find(button=>(button.dataset.settingsFocus||'')===query);
  if(selected) selected.classList.add('active');
  const input=$('#settingsSearchInput');
  const wrap=$('#settingsSearchWrap');
  if(input&&wrap){
    input.value=query;
    wrap.hidden=!query;
    input.dispatchEvent(new Event('input'));
  }
}

function cycleDesktopTheme(){
  if(webSettings.theme==='dark'&&!webSettings.amoled){
    webSettings.amoled=true;
  }else if(webSettings.amoled){
    webSettings.amoled=false;
    webSettings.theme='light';
  }else{
    webSettings.amoled=false;
    webSettings.theme='dark';
  }
  saveWebSettings();
}

async function toggleFullscreen(){
  try{
    if(document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  }catch(_){}
}

function desktopBack(){
  if(state.pageHistory.length){
    const previous=state.pageHistory.pop();
    openPage(previous,{fromBack:true});
  }else{
    openPage('homePage',{fromBack:true});
  }
}

function openPage(pageId,options={}){
  const current=$('.page.active')?.id;
  if(current&&current!==pageId&&!options.fromBack){
    state.pageHistory.push(current);
    if(state.pageHistory.length>30) state.pageHistory.shift();
  }
  if(pageId==='settingsPage'&&current&&current!=='settingsPage') state.lastMainPage=current;
  const isSubpage=pageId==='settingsPage';
  document.body.classList.toggle('subpage-open',isSubpage);
  $$('.page').forEach(p=>p.classList.toggle('active',p.id===pageId));
  $$('[data-page]').forEach(b=>b.classList.toggle('active',!isSubpage&&b.dataset.page===pageId));
  syncMacChrome(pageId,options.label,options.icon);

  if(pageId==='browsePage'){
    renderHistory();
    if(!$('#searchInput').value.trim()) renderBrowseLanding(state.browseFilter);
  }
  if(pageId==='mangaPage'&&!$('#mangaGrid').children.length) loadManga();
  if(pageId==='watchlistPage') renderLibrary();
  if(pageId==='historyPage') renderHistoryPage();
  if(pageId==='newsPage') loadDesktopNews();
  if(pageId==='notificationsPage') renderDesktopNotifications();
  if(pageId==='extensionsPage'){checkSourceHealth();if(!state.hindiLoaded)loadHindiSearch('');}
  if(pageId==='settingsPage') syncSettingsControls();
  window.scrollTo({top:0,behavior:'auto'});
}
function showUtility(title,body){
  $('#utilityTitle').textContent=title;
  $('#utilityBody').textContent=body;
  const dlg=$('#utilityDialog');
  if(!dlg.open) dlg.showModal();
}

$$('[data-page]').forEach(b=>b.onclick=()=>openPage(b.dataset.page));

function syncDesktopEdition(){
  const badge=$('#macEditionBadge');
  if(!badge) return;
  const ua=navigator.userAgent||'';
  badge.textContent=/Windows/i.test(ua)
    ? 'Windows Edition'
    : /(Macintosh|Mac OS X)/i.test(ua)
      ? 'macOS Edition'
      : 'Desktop Edition';
}

$('#macSidebarToggle').onclick=()=>{
  const collapsed=!document.body.classList.contains('mac-sidebar-collapsed');
  document.body.classList.toggle('mac-sidebar-collapsed',collapsed);
  localStorage.setItem('anidash-mac-sidebar-collapsed',collapsed?'1':'0');
  $('#macSidebarToggle').setAttribute('aria-label',collapsed?'Expand sidebar':'Collapse sidebar');
};
$('#macAiHero').onclick=()=>openPage('aiPage');
$('#macAiButton').onclick=()=>openPage('aiPage');
$('#macNotificationsButton').onclick=()=>openPage('notificationsPage');
$('#macThemeButton').onclick=cycleDesktopTheme;
$('#macFullscreenButton').onclick=toggleFullscreen;
$('#macBack').onclick=desktopBack;
$('#macProfileFooter').onclick=()=>$('#accountDialog').showModal();
$('#macAboutButton').onclick=()=>showUtility('About AniDash','AniDash PWA · Desktop Edition. The desktop shell mirrors the native macOS layout while keeping browser-safe playback, local library data, AniAI, news, notifications, settings, and PWA installation.');
$$('.mac-settings-link').forEach(button=>{
  button.onclick=()=>openSettingsFocus(
    button.dataset.settingsFocus||'',
    button.dataset.macLabel||'Settings',
    button.dataset.macIcon||'i-settings'
  );
});

$('#macSearchForm').onsubmit=event=>{
  event.preventDefault();
  const query=$('#macSearchInput').value.trim();
  if(!query) return;
  openPage('browsePage');
  $('#searchInput').value=query;
  runSearch();
};

$('#historyExplore').onclick=()=>openPage('browsePage');
$('#clearHistoryFromPage').onclick=()=>{
  if(confirm('Clear all AniDash watch history on this device?')){
    localStorage.removeItem('anidash-progress');
    renderHistoryPage();
    renderContinue();
  }
};

$('#aiChatForm').onsubmit=event=>{
  event.preventDefault();
  const input=$('#aiChatInput');
  const message=input.value.trim();
  if(!message) return;
  input.value='';
  sendAiMessage(message);
};
$('#aiChatInput').onkeydown=event=>{
  if(event.key==='Enter'&&!event.shiftKey){
    event.preventDefault();
    $('#aiChatForm').requestSubmit();
  }
};

$('#refreshNewsButton').onclick=()=>loadDesktopNews(true);
$('#desktopNotificationPermission').onclick=requestDesktopNotifications;
$('#checkSourceButton').onclick=checkSourceHealth;
$('#hindiQuickLink').onclick=()=>openPage('extensionsPage');
$('#hindiSearchForm').onsubmit=event=>{event.preventDefault();loadHindiSearch($('#hindiSearchInput').value.trim())};
$('#hindiEpisodesBack').onclick=resetHindiEpisodes;

document.addEventListener('keydown',event=>{
  const mod=event.metaKey||event.ctrlKey;
  if(event.key==='F11'){
    event.preventDefault();
    toggleFullscreen();
    return;
  }
  if(!mod||!isDesktopShell()) return;

  const key=event.key.toLowerCase();
  const digitPages={
    '1':'homePage','2':'browsePage','3':'mangaPage','5':'watchlistPage'
  };
  if(digitPages[key]){
    event.preventDefault();
    openPage(digitPages[key]);
    return;
  }
  if(key==='f'){
    event.preventDefault();
    $('#macSearchInput').focus();
    $('#macSearchInput').select();
  }else if(key==='k'){
    event.preventDefault();
    openPage('aiPage');
    setTimeout(()=>$('#aiChatInput')?.focus(),0);
  }else if(key==='n'){
    event.preventDefault();
    openPage('newsPage');
  }else if(key===','){
    event.preventDefault();
    openSettingsFocus('');
  }else if(key==='h'){
    event.preventDefault();
    openPage('historyPage');
  }else if(key==='e'){
    event.preventDefault();
    openPage('extensionsPage');
  }else if(key==='['){
    event.preventDefault();
    desktopBack();
  }
});

$('#searchInput').oninput=()=>{
  clearTimeout(state.searchTimer);
  state.searchTimer=setTimeout(runSearch,350);
};
$('#clearSearch').onclick=()=>{
  $('#searchInput').value='';
  runSearch();
};
$$('#browseFilters button').forEach(b=>b.onclick=()=>setBrowseFilter(b.dataset.filter));

$('#mangaSearch').oninput=()=>{
  clearTimeout(state.mangaTimer);
  const q=$('#mangaSearch').value.trim();
  $('#clearManga').hidden=!q;
  state.mangaTimer=setTimeout(()=>loadManga(q),420);
};
$('#clearManga').onclick=()=>{
  $('#mangaSearch').value='';
  loadManga();
};

$$('#libraryFilters button').forEach(b=>b.onclick=()=>setLibraryStatus(b.dataset.status));
$('#libraryExplore').onclick=()=>openPage('browsePage');

$('#profileButton').onclick=()=>$('#accountDialog').showModal();
$('.sheet-close').onclick=()=>$('#accountDialog').close();
$('.sheet-close-action').onclick=()=>$('#accountDialog').close();
$('#accountBrowse').onclick=()=>{$('#accountDialog').close();openPage('browsePage')};

$('#niaButton').onclick=()=>isDesktopShell()?openPage('aiPage'):showUtility('AniDash AI','AniAI is available in the desktop PWA workspace. The phone layout keeps the compact AniDash mobile experience.');
$('#newsButton').onclick=()=>isDesktopShell()?openPage('newsPage'):showUtility('AniDash News','Anime News is available in the desktop PWA workspace. The phone layout stays compact.');
$('#notificationButton').onclick=()=>isDesktopShell()?openPage('notificationsPage'):openPage('settingsPage');
$('#settingsButton').onclick=()=>openPage('settingsPage');
$('#libraryTune').onclick=()=>showUtility('Customize Library','Tracked titles are stored locally on this device and organized with the same AniDash status tabs.');
$('.utility-close').onclick=()=>$('#utilityDialog').close();
$('.utility-close-action').onclick=()=>$('#utilityDialog').close();

$('.details-back').onclick=()=>$('#detailsDialog').close();
$('.player-back').onclick=()=>closePlayer();
$('#audio').onchange=()=>{
  webSettings.preferredAudio=$('#audio').value;
  saveWebSettings();
  const number=player.episode?.number??state.playingEpisode?.number;
  const item=state.episodes.find(x=>String(x.number)===String(number));
  if(item) playEpisode(item);
};

$('#settingsBack').onclick=()=>isDesktopShell()?desktopBack():openPage(state.lastMainPage||'homePage');
$('#settingsSearchButton').onclick=()=>{
  const wrap=$('#settingsSearchWrap');
  wrap.hidden=!wrap.hidden;
  if(!wrap.hidden) $('#settingsSearchInput').focus();
};
$('#settingsSearchClear').onclick=()=>{
  $('#settingsSearchInput').value='';
  $('#settingsSearchInput').dispatchEvent(new Event('input'));
};
$('#settingsSearchInput').oninput=()=>{
  const q=$('#settingsSearchInput').value.trim().toLowerCase();
  let shown=0;
  $$('#settingsList .settings-section').forEach(section=>{
    const match=!q||section.textContent.toLowerCase().includes(q)||String(section.dataset.settingText||'').includes(q);
    section.hidden=!match;
    if(match) shown++;
  });
  $('#settingsNoResults').hidden=shown>0;
};

$('#webProfileSettings').onclick=()=>$('#accountDialog').showModal();
$('#installHelpButton').onclick=()=>showUtility('Install AniDash','On iPhone or iPad, open AniDash in Safari, tap Share, choose Add to Home Screen, then tap Add. Launch AniDash from the new Home Screen icon for the app-style experience.');

function bindToggle(id,onChange){
  const el=$('#'+id);
  if(el) el.onchange=()=>onChange(el.checked);
}
bindToggle('settingIncognito',v=>{webSettings.incognito=v;saveWebSettings()});
bindToggle('settingAdult',v=>{webSettings.showAdult=v;saveWebSettings();loadHome();if($('#searchInput').value.trim())runSearch();if($('#mangaGrid').children.length)loadManga($('#mangaSearch').value.trim())});
bindToggle('settingAmoled',v=>{webSettings.amoled=v;saveWebSettings()});
bindToggle('settingCompact',v=>{webSettings.compactCards=v;saveWebSettings()});
bindToggle('settingSpotlight',v=>{webSettings.spotlightAutoPlay=v;saveWebSettings();if(state.home.length)renderSpotlight(state.home)});
bindToggle('settingNavBrowse',v=>{webSettings.nav.browse=v;saveWebSettings()});
bindToggle('settingNavManga',v=>{webSettings.nav.manga=v;saveWebSettings()});
bindToggle('settingNavWatchlist',v=>{webSettings.nav.watchlist=v;saveWebSettings()});

$('#settingAudio').onchange=()=>{webSettings.preferredAudio=$('#settingAudio').value;saveWebSettings()};
$('#settingQuality').onchange=()=>{webSettings.preferredQuality=$('#settingQuality').value;saveWebSettings()};
$$('#themeSegments [data-theme-value]').forEach(button=>{
  button.onclick=()=>{
    webSettings.theme=button.dataset.themeValue;
    saveWebSettings();
  };
});

$('#notificationPermissionButton').onclick=async()=>{
  if(!('Notification' in window)){
    showUtility('Notifications','This browser does not expose web notification permission.');
    return;
  }
  if(Notification.permission==='default'){
    try{await Notification.requestPermission()}catch(_){}
  }
  updateNotificationPermissionStatus();
  if(Notification.permission==='granted'){
    try{
      const registration=await navigator.serviceWorker.ready;
      await registration.showNotification('AniDash',{body:'Notifications are allowed on this device.',icon:(window.__ANIDASH_BASE__||'')+'/assets/icon-192.png'});
    }catch(_){}
  }else if(Notification.permission==='denied'){
    showUtility('Notifications','Notification permission is blocked. Enable it from Safari or system website notification settings.');
  }
};

$('#clearProgressButton').onclick=()=>{
  if(confirm('Clear all Continue Watching progress on this device?')){
    localStorage.removeItem('anidash-progress');
    renderContinue();
  }
};
$('#clearLibraryButton').onclick=()=>{
  if(confirm('Clear the local AniDash library on this device?')){
    localStorage.removeItem('anidash-library');
    renderLibrary();
  }
};
$('#clearSearchesButton').onclick=()=>{
  localStorage.removeItem('anidash-searches');
  renderHistory();
};
$('#resetWebSettingsButton').onclick=()=>{
  if(confirm('Reset all AniDash web settings to defaults?')){
    webSettings=JSON.parse(JSON.stringify(DEFAULT_WEB_SETTINGS));
    localStorage.removeItem('anidash-web-settings');
    applyWebSettings();
    syncSettingsControls();
    loadHome();
  }
};

window.matchMedia?.('(prefers-color-scheme: dark)').addEventListener?.('change',()=>{
  if(webSettings.theme==='system') applyWebSettings();
});

const hour=new Date().getHours();
const greeting=hour<12?'Good morning':hour<17?'Good afternoon':'Good evening';
$('#greeting').textContent=greeting;

const standalone=window.matchMedia('(display-mode: standalone)').matches||window.navigator.standalone===true;
document.documentElement.classList.toggle('standalone',standalone);

const initialTab=new URLSearchParams(location.search).get('tab');
const initialPage={browse:'browsePage',manga:'mangaPage',watchlist:'watchlistPage'}[initialTab]||'homePage';

document.body.classList.toggle(
  'mac-sidebar-collapsed',
  localStorage.getItem('anidash-mac-sidebar-collapsed')==='1'
);
syncDesktopEdition();
applyWebSettings();
syncSettingsControls();
renderHistory();
renderHistoryPage();
renderLibrary();
loadHome();
if(initialPage!=='homePage') openPage(initialPage);
else syncMacChrome('homePage');

desktopShellQuery.addEventListener?.('change',event=>{
  const active=$('.page.active')?.id||'homePage';
  const desktopOnly=new Set(['historyPage','aiPage','newsPage','notificationsPage','extensionsPage']);
  if(!event.matches&&desktopOnly.has(active)){
    state.pageHistory=[];
    openPage('homePage',{fromBack:true});
    return;
  }
  syncMacChrome(active);
});

/* ============================== Player controls ============================== */

const playerVideo=$('#video')||document.createElement('video');
const playerDialog=$('#playerDialog')||{
  open:false,
  classList:{add(){},remove(){},contains(){return false}},
  addEventListener(){},
  close(){}
};
const playerProgress=$('#playerProgress')||document.createElement('div');

/** Bind a click handler only when the element exists (keeps the rest of the
 *  control bar alive if a single control is ever removed from the markup). */
const bindClick=(id,handler)=>{
  const element=$('#'+id);
  if(element) element.onclick=handler;
  return Boolean(element);
};

function formatTime(seconds){
  const value=Math.max(0,Math.floor(Number(seconds)||0));
  const hours=Math.floor(value/3600);
  const minutes=Math.floor((value%3600)/60);
  const secs=value%60;
  return hours
    ? `${hours}:${String(minutes).padStart(2,'0')}:${String(secs).padStart(2,'0')}`
    : `${minutes}:${String(secs).padStart(2,'0')}`;
}

function updatePlayerTitle(ep,series){
  const title=`E${ep.number} — ${ep.title||'Episode '+ep.number}`;
  $('#playerTitle').textContent=title;
  const name=series?.title?.english||series?.title?.romaji||series?.title?.native||'AniDash';
  $('#playerSeries').textContent=String(name);
  document.title=`${title} · ${name} — AniDash`;
}

function setPlayerStatus(text){
  const element=$('#playerStatus');
  if(element) element.textContent=text||'';
}

function hidePlaybackError(){
  const box=$('#playerError');
  if(box) box.hidden=true;
  player.fatal=false;
}

function showPlaybackError(message){
  player.fatal=true;
  const box=$('#playerError');
  if(!box) return;
  $('#playerErrorBody').textContent=message||'Playback failed.';
  box.hidden=false;
  $('#playerLoading').hidden=true;
  $('#playerBuffering').hidden=true;
  playerDialog.classList.remove('needs-tap');
  showControls(true);
  const tried=new Set((player.sources||[]).map(item=>item.serverId).filter(Boolean));
  const order=['megaplay','zokoanime','animegg','anineko'];
  const next=order.find(id=>!tried.has(id));
  const button=$('#playerNextServerBtn');
  button.hidden=!next&&Boolean(player.pendingServer);
  button.textContent=next?'Try another server':'Retry another source';
}

function hidePlayerChips(){
  const skip=$('#playerSkipIntro');
  const next=$('#playerNextEpisode');
  if(skip) skip.hidden=true;
  if(next) next.hidden=true;
}

function closePlayerMenus(){
  document.querySelectorAll('.player-menu').forEach(menu=>{menu.hidden=true});
  document.querySelectorAll('.player-anchor').forEach(button=>{
    button.classList.remove('is-open');
    button.setAttribute('aria-expanded','false');
  });
}

function anyMenuOpen(){
  return [...document.querySelectorAll('.player-menu')].some(menu=>!menu.hidden);
}

function toggleMenu(button,menu){
  if(!button||!menu) return;
  const willOpen=menu.hidden;
  closePlayerMenus();
  if(willOpen){
    menu.hidden=false;
    button.classList.add('is-open');
    button.setAttribute('aria-expanded','true');
    showControls(true);
  }
}

function currentEpisodeNumber(){
  return player.episode?.number??state.playingEpisode?.number;
}

function playAdjacent(direction){
  const episodes=state.episodes;
  if(!episodes.length) return;
  const index=episodes.findIndex(item=>String(item.number)===String(currentEpisodeNumber()));
  const next=episodes[index+direction];
  if(!next){
    setPlayerStatus(direction>0?'You have reached the last episode':'This is the first episode');
    showControls(true);
    return;
  }
  playEpisode(next);
}

function closePlayer(){
  const video=$('#video');
  if(state.playingEpisode&&state.current?.sourceProvider!=='toonstream') persistPlaybackProgress(state.playingEpisode,video,{force:true});
  const frame=$('#externalPlayerFrame');if(frame){frame.hidden=true;frame.src='about:blank'}
  $('#playerStage')?.classList.remove('external-embed-active');
  if(state.current?.sourceProvider==='toonstream') state.playingEpisode=null;
  if(playerDialog.open) playerDialog.close();
}

/* ---- menu construction ---- */

function menuItemMarkup(items,current){
  return items.map(item=>{
    const active=String(item.value)===String(current);
    return `<button type="button" class="player-menu-item${active?' is-active':''}" data-value="${esc(String(item.value))}" role="menuitemradio" aria-checked="${active}"><span>${esc(item.label)}</span>${item.hint?`<small>${esc(item.hint)}</small>`:''}</button>`;
  }).join('');
}

function bindMenuItems(menu,onPick){
  menu.querySelectorAll('.player-menu-item').forEach(item=>{
    item.onclick=event=>{
      event.stopPropagation();
      onPick(item.dataset.value);
      closePlayerMenus();
    };
  });
}

function currentQualityValue(){
  if(state.hls) return state.hls.autoLevelEnabled?'-1':String(state.hls.currentLevel);
  return String(player.levelIndex);
}

function renderQualityMenu(){
  const menu=$('#playerQualityMenu');
  const button=$('#playerQualityBtn');
  if(!menu||!button) return;

  const levels=player.levels.slice().sort((a,b)=>b.height-a.height||b.bitrate-a.bitrate);
  if(!levels.length){
    button.disabled=true;
    button.textContent='Auto';
    menu.innerHTML='<p class="player-menu-note">Quality adapts automatically for this stream.</p>';
    return;
  }

  button.disabled=false;
  menu.innerHTML=menuItemMarkup(
    [{value:'-1',label:'Auto',hint:'Recommended'}].concat(
      levels.map(level=>({
        value:String(level.index),
        label:level.label,
        hint:level.bitrate?`${Math.round(level.bitrate/1000)} kbps`:''
      }))
    ),
    currentQualityValue()
  );
  bindMenuItems(menu,value=>{
    const index=Number(value);
    player.levelIndex=index;
    if(state.hls){
      try{state.hls.currentLevel=index}catch(_){}
    }
    syncQualityMenuSelection();
  });
  syncQualityMenuSelection();
}

function syncQualityMenuSelection(){
  const menu=$('#playerQualityMenu');
  const button=$('#playerQualityBtn');
  if(!menu||!button) return;
  const current=currentQualityValue();
  let label='Auto';
  menu.querySelectorAll('.player-menu-item').forEach(item=>{
    const active=item.dataset.value===current;
    item.classList.toggle('is-active',active);
    item.setAttribute('aria-checked',String(active));
    if(active) label=item.querySelector('span')?.textContent||'Auto';
  });
  button.textContent=label;
  button.classList.toggle('is-menu-active',current!=='-1');
}

function renderSubtitleMenu(){
  const menu=$('#playerSubsMenu');
  const button=$('#playerSubsBtn');
  if(!menu||!button) return;

  if(!player.subtitles.length){
    menu.innerHTML='<p class="player-menu-note">No subtitles for this episode.</p>';
    syncSubtitleSelection();
    return;
  }

  menu.innerHTML=menuItemMarkup(
    [{value:'-1',label:'Off'}].concat(
      player.subtitles.map((track,index)=>({value:String(index),label:track.label}))
    ),
    String(player.subtitleIndex)
  );
  bindMenuItems(menu,value=>applySubtitle(Number(value)));
  syncSubtitleSelection();
}

function syncSubtitleSelection(){
  const menu=$('#playerSubsMenu');
  const button=$('#playerSubsBtn');
  if(!menu||!button) return;
  const current=String(player.subtitleIndex);
  let label='';
  menu.querySelectorAll('.player-menu-item').forEach(item=>{
    const active=item.dataset.value===current;
    item.classList.toggle('is-active',active);
    item.setAttribute('aria-checked',String(active));
    if(active&&item.dataset.value!=='-1') label=item.querySelector('span')?.textContent||'';
  });
  button.classList.toggle('is-menu-active',Boolean(label));
  button.setAttribute('aria-label',label?`Subtitles: ${label}`:'Subtitles');
}

function applySubtitle(index){
  const video=$('#video');
  if(!video) return;
  video.querySelectorAll('track[data-anidash]').forEach(node=>node.remove());
  player.subtitleIndex=index;
  const item=player.subtitles[index];

  if(!item){
    [...video.textTracks].forEach(track=>{track.mode='disabled'});
    renderSubtitleMenu();
    return;
  }

  if(item.url){
    const track=document.createElement('track');
    track.dataset.anidash='1';
    track.kind=item.kind||'subtitles';
    track.src=item.url;
    track.label=item.label;
    track.srclang=item.lang||'en';
    video.appendChild(track);
    [...video.textTracks].forEach((textTrack,position)=>{
      textTrack.mode=position===video.textTracks.length-1?'showing':'disabled';
    });
  }else if(item.hlsIndex!=null&&state.hls){
    try{
      state.hls.subtitleDisplayTrack=item.hlsIndex;
      state.hls.subtitleTrack=item.hlsIndex;
    }catch(_){}
  }
  renderSubtitleMenu();
  showControls();
}

function mergeHlsSubtitles(tracks){
  const known=new Set(player.subtitles.map(track=>track.label.toLowerCase()));
  (tracks||[]).forEach((track,index)=>{
    const label=String(track?.name||track?.lang||`Track ${index+1}`);
    if(known.has(label.toLowerCase())) return;
    known.add(label.toLowerCase());
    player.subtitles.push({label,lang:String(track?.lang||'und'),kind:'subtitles',hlsIndex:index});
  });
  renderSubtitleMenu();
}

function renderAudioMenu(){
  const menu=$('#playerAudioMenu');
  const button=$('#playerAudioBtn');
  if(!menu||!button) return;
  const tracks=[...(state.hls?.audioTracks||[])];
  if(tracks.length<2){
    button.disabled=true;
    menu.innerHTML='<p class="player-menu-note">This stream has a single audio track.</p>';
    return;
  }
  button.disabled=false;
  const current=state.hls&&state.hls.audioTrack>=0?String(state.hls.audioTrack):'0';
  menu.innerHTML=menuItemMarkup(
    tracks.map((track,index)=>({
      value:String(index),
      label:track.name||track.lang||`Track ${index+1}`
    })),
    current
  );
  bindMenuItems(menu,value=>{
    try{
      if(state.hls) state.hls.audioTrack=Number(value);
    }catch(_){}
    renderAudioMenu();
  });
}

const SPEEDS=[0.5,0.75,1,1.25,1.5,1.75,2];

function renderSpeedMenu(){
  const menu=$('#playerSpeedMenu');
  const button=$('#playerSpeedBtn');
  if(!menu||!button) return;
  const current=String(Number(webSettings.playbackSpeed)||1);
  menu.innerHTML=menuItemMarkup(
    SPEEDS.map(value=>({value:String(value),label:`${value}×`})),
    current
  );
  bindMenuItems(menu,value=>{
    const rate=Number(value)||1;
    webSettings.playbackSpeed=rate;
    saveWebSettings();
    try{playerVideo.playbackRate=rate}catch(_){}
    button.textContent=rate===1?'1×':`${rate}×`;
    button.classList.toggle('is-menu-active',rate!==1);
  });
}

let drawerRefreshTimer=null;

function renderEpisodeDrawer(ep){
  const box=$('#playerEpisodeList');
  if(!box) return;
  const count=$('#playerEpisodeCount');
  if(count) count.textContent=state.episodes.length?`${state.episodes.length} episodes`:'';
  if(!state.episodes.length){
    box.innerHTML='<p class="player-menu-note">Episode list unavailable.</p>';
    return;
  }
  renderEpisodeButtons(box,episodeLoader?'Loading more episodes…':'');
  clearTimeout(drawerRefreshTimer);
  if(episodeLoader&&$('#playerEpisodes')?.hidden===false&&playerDialog.open){
    drawerRefreshTimer=setTimeout(()=>renderEpisodeDrawer(ep),1500);
  }
}

function toggleEpisodeDrawer(){
  const drawer=$('#playerEpisodes');
  if(!drawer) return;
  const opening=drawer.hidden;
  if(opening){
    renderEpisodeDrawer(player.episode||state.playingEpisode);
    drawer.hidden=false;
    $('#playerEpisodesButton')?.setAttribute('aria-expanded','true');
    showControls(true);
  }else{
    drawer.hidden=true;
    $('#playerEpisodesButton')?.setAttribute('aria-expanded','false');
  }
}

/* ---- transport ---- */

function syncPlayButtons(){
  const video=$('#video');
  const paused=video.paused;
  const play=$('#playerPlay');
  const big=$('#playerBigPlay');
  if(play){
    play.dataset.state=paused?'play':'pause';
    play.setAttribute('aria-label',paused?'Play':'Pause');
  }
  if(big){
    big.dataset.state=paused?'play':'pause';
    big.setAttribute('aria-label',paused?'Play':'Pause');
  }
}

function togglePlay(){
  const video=$('#video');
  if(video.paused||video.ended){
    video.play().then(()=>{
      playerDialog.classList.remove('needs-tap');
      setPlayerStatus('');
      scheduleControlsHide();
    }).catch(()=>{
      playerDialog.classList.add('needs-tap');
      setPlayerStatus('Tap play to start');
      showControls(true);
    });
  }else{
    video.pause();
  }
}

function seekBy(delta){
  const video=$('#video');
  const duration=Number(video.duration);
  const target=Math.min(
    Math.max((Number(video.currentTime)||0)+delta,0),
    Number.isFinite(duration)&&duration>0?duration-0.25:Infinity
  );
  try{video.currentTime=target}catch(_){}
  renderProgress();
  showControls();
}

function setVolume(value){
  const video=$('#video');
  const clamped=Math.min(Math.max(Number(value)||0,0),1);
  video.muted=clamped===0;
  video.volume=clamped;
  if(clamped>0) player.lastVolume=clamped;
  webSettings.volume=clamped;
  webSettings.muted=video.muted;
  saveWebSettings();
  syncVolumeUI();
}

function toggleMute(){
  const video=$('#video');
  if(video.muted||video.volume===0){
    video.muted=false;
    video.volume=player.lastVolume>0?player.lastVolume:0.8;
  }else{
    video.muted=true;
  }
  webSettings.muted=video.muted;
  webSettings.volume=video.volume;
  saveWebSettings();
  syncVolumeUI();
}

function syncVolumeUI(){
  const video=$('#video');
  const value=video.muted?0:video.volume;
  const slider=$('#playerVolume');
  if(slider) slider.value=String(value);
  const button=$('#playerMute');
  if(button) button.dataset.muted=String(value===0);
  if(!video.muted&&video.volume>0) player.lastVolume=video.volume;
}

async function togglePictureInPicture(){
  const video=$('#video');
  try{
    if(document.pictureInPictureElement){
      await document.exitPictureInPicture();
    }else if(video.requestPictureInPicture){
      await video.requestPictureInPicture();
    }
  }catch(_){}
}

async function playerToggleFullscreen(){
  const stage=$('#playerStage')||playerDialog;
  try{
    if(document.fullscreenElement||document.webkitFullscreenElement){
      await (document.exitFullscreen?.()||document.webkitExitFullscreen?.());
      return;
    }
    if(stage.requestFullscreen) return await stage.requestFullscreen();
    if(stage.webkitRequestFullscreen) return stage.webkitRequestFullscreen();
    const video=$('#video');
    if(video.webkitEnterFullscreen) video.webkitEnterFullscreen();
  }catch(_){}
}

function syncFullscreenButton(){
  const button=$('#playerFull');
  if(!button) return;
  const active=Boolean(document.fullscreenElement||document.webkitFullscreenElement);
  button.dataset.active=String(active);
  button.setAttribute('aria-label',active?'Exit fullscreen':'Enter fullscreen');
}

function updateChapterChips(current,duration){
  const skip=$('#playerSkipIntro');
  const next=$('#playerNextEpisode');
  if(skip){
    const start=Number(player.intro?.start);
    const end=Number(player.intro?.end);
    const active=Number.isFinite(start)&&Number.isFinite(end)&&current>=start&&current<end-1;
    skip.hidden=!active;
  }
  if(next){
    const start=Number(player.outro?.start);
    const active=Number.isFinite(start)&&current>=start-1&&(!duration||current<duration-0.4);
    next.hidden=!active;
  }
}

function renderProgress(){
  const video=$('#video');
  const duration=Number(video.duration)||0;
  const current=Number(video.currentTime)||0;
  const ratio=duration>0?Math.min(1,current/duration):0;

  const played=$('#playerPlayed');
  const buffered=$('#playerBuffer');
  if(played) played.style.width=(ratio*100).toFixed(3)+'%';
  if(buffered&&duration>0&&video.buffered.length){
    let end=0;
    for(let index=0;index<video.buffered.length;index++){
      if(video.buffered.start(index)<=current+60){
        end=Math.max(end,video.buffered.end(index));
      }
    }
    buffered.style.width=Math.min(100,(end/duration)*100).toFixed(3)+'%';
  }

  const bar=$('#playerProgress');
  if(bar){
    bar.setAttribute('aria-valuenow',String(Math.round(ratio*100)));
    bar.setAttribute('aria-valuetext',`${formatTime(current)} of ${formatTime(duration)}`);
  }

  const currentLabel=$('#playerCurrent');
  const durationLabel=$('#playerDuration');
  if(currentLabel) currentLabel.textContent=formatTime(current);
  if(durationLabel) durationLabel.textContent=duration>0?formatTime(duration):'--:--';

  updateChapterChips(current,duration);
}

function updatePlayerChrome(){
  renderProgress();
  syncPlayButtons();
  syncVolumeUI();
  syncQualityMenuSelection();
  syncSubtitleSelection();
  syncFullscreenButton();

  const video=$('#video');
  const rate=Number(video.playbackRate)||1;
  const speedButton=$('#playerSpeedBtn');
  if(speedButton){
    speedButton.textContent=rate===1?'1×':`${rate}×`;
    speedButton.classList.toggle('is-menu-active',rate!==1);
  }

  const pipButton=$('#playerPiP');
  if(pipButton) pipButton.hidden=!(document.pictureInPictureEnabled&&video.requestPictureInPicture);

  const index=state.episodes.findIndex(item=>String(item.number)===String(currentEpisodeNumber()));
  const previous=$('#playerPrev');
  const next=$('#playerNext');
  if(previous) previous.disabled=index<=0;
  if(next) next.disabled=index<0||index>=state.episodes.length-1;
}

/* ---- controls visibility ---- */

function showControls(lock){
  playerDialog.classList.add('controls-visible');
  if(player.controlsTimer) clearTimeout(player.controlsTimer);
  player.controlsTimer=null;
  if(!lock) scheduleControlsHide();
}

function scheduleControlsHide(){
  if(player.controlsTimer) clearTimeout(player.controlsTimer);
  player.controlsTimer=setTimeout(()=>{
    const video=$('#video');
    const busy=
      !video.paused&&!video.ended&&!player.scrubbing&&!player.fatal&&!anyMenuOpen();
    if(busy) playerDialog.classList.remove('controls-visible');
  },3200);
}

/* ---- error recovery ---- */

function retryPlayback(){
  const episode=player.episode;
  if(!episode) return;
  const audio=webSettings.preferredAudio==='dub'?'dub':'sub';
  const server=player.pendingServer||'';
  try{
    sessionStorage.removeItem(sourceCacheKey(state.current.id,episode.number,audio,server));
  }catch(_){}
  hidePlaybackError();
  playEpisode(episode,{server});
}

function switchToNextServer(){
  const episode=player.episode;
  if(!episode) return;
  const tried=new Set((player.sources||[]).map(item=>item.serverId).filter(Boolean));
  const order=['megaplay','zokoanime','animegg','anineko'];
  const next=order.find(id=>!tried.has(id));
  hidePlaybackError();
  if(next){
    playEpisode(episode,{server:next});
    return;
  }
  retryPlayback();
}

/* ---- wiring ---- */

const progressRatio=event=>{
  const rect=playerProgress.getBoundingClientRect();
  const width=Math.max(rect.width,1);
  return Math.min(Math.max((event.clientX-rect.left)/width,0),1);
};

const seekToRatio=ratio=>{
  const video=$('#video');
  const duration=Number(video.duration)||0;
  if(!duration||!Number.isFinite(duration)) return;
  try{video.currentTime=Math.min(Math.max(duration*ratio,0),duration-0.25)}catch(_){}
  renderProgress();
};

playerProgress.addEventListener('pointerdown',event=>{
  event.preventDefault();
  try{playerProgress.setPointerCapture(event.pointerId)}catch(_){}
  player.scrubbing=true;
  playerDialog.classList.add('is-scrubbing');
  showControls(true);
  seekToRatio(progressRatio(event));
});

playerProgress.addEventListener('pointermove',event=>{
  const ratio=progressRatio(event);
  const tip=$('#playerTip');
  if(tip){
    tip.hidden=false;
    tip.style.left=(ratio*100).toFixed(2)+'%';
    const label=tip.querySelector('span');
    if(label) label.textContent=formatTime((Number($('#video').duration)||0)*ratio);
  }
  if(player.scrubbing) seekToRatio(ratio);
});

playerProgress.addEventListener('pointerleave',()=>{
  const tip=$('#playerTip');
  if(tip) tip.hidden=true;
});

const endScrub=event=>{
  if(!player.scrubbing) return;
  player.scrubbing=false;
  playerDialog.classList.remove('is-scrubbing');
  try{playerProgress.releasePointerCapture(event.pointerId)}catch(_){}
  const tip=$('#playerTip');
  if(tip) tip.hidden=true;
  scheduleControlsHide();
};
playerProgress.addEventListener('pointerup',endScrub);
playerProgress.addEventListener('pointercancel',endScrub);

playerProgress.addEventListener('keydown',event=>{
  if(event.key==='ArrowLeft'||event.key==='ArrowRight'){
    event.preventDefault();
    seekBy(event.key==='ArrowLeft'?-5:5);
  }
});

bindClick('playerPlay',togglePlay);
bindClick('playerBigPlay',togglePlay);
bindClick('playerBack10',()=>seekBy(-10));
bindClick('playerForward10',()=>seekBy(10));
bindClick('playerPrev',()=>playAdjacent(-1));
bindClick('playerNext',()=>playAdjacent(1));
bindClick('playerMute',toggleMute);
bindClick('playerFull',()=>playerToggleFullscreen());
bindClick('playerPiP',()=>togglePictureInPicture());
bindClick('playerEpisodesButton',()=>toggleEpisodeDrawer());
bindClick('playerEpisodesClose',()=>{
  const drawer=$('#playerEpisodes');
  if(drawer) drawer.hidden=true;
  const button=$('#playerEpisodesButton');
  if(button){
    button.setAttribute('aria-expanded','false');
    button.focus();
  }
});
bindClick('playerRetry',()=>retryPlayback());
bindClick('playerNextServerBtn',()=>switchToNextServer());
if($('#playerVolume')) $('#playerVolume').oninput=event=>setVolume(Number(event.target.value));

bindClick('playerSkipIntro',event=>{
  event.stopPropagation();
  const end=Number(player.intro?.end);
  if(Number.isFinite(end)){
    try{playerVideo.currentTime=end+0.5}catch(_){}
  }
  hidePlayerChips();
  showControls();
});

bindClick('playerNextEpisode',event=>{
  event.stopPropagation();
  playAdjacent(1);
});

[
  ['#playerQualityBtn','#playerQualityMenu'],
  ['#playerSubsBtn','#playerSubsMenu'],
  ['#playerAudioBtn','#playerAudioMenu'],
  ['#playerSpeedBtn','#playerSpeedMenu']
].forEach(([buttonId,menuId])=>{
  const button=$(buttonId);
  const menu=$(menuId);
  if(!button||!menu) return;
  button.onclick=event=>{
    event.stopPropagation();
    toggleMenu(button,menu);
  };
  menu.onclick=event=>event.stopPropagation();
});

document.addEventListener('click',event=>{
  if(event.target.closest?.('.player-popwrap')) return;
  closePlayerMenus();
});

/* ---- media events ---- */

playerVideo.addEventListener('loadedmetadata',()=>{
  renderProgress();
  const rate=Number(webSettings.playbackSpeed)||1;
  if(rate!==1){
    try{playerVideo.playbackRate=rate}catch(_){}
  }
  updatePlayerChrome();
});

playerVideo.addEventListener('durationchange',renderProgress);
playerVideo.addEventListener('progress',renderProgress);
playerVideo.addEventListener('seeked',renderProgress);

playerVideo.addEventListener('timeupdate',()=>{
  renderProgress();
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,playerVideo);
  if(!playerVideo.paused&&player.scrubbing===false&&!player.controlsTimer) scheduleControlsHide();
});

playerVideo.addEventListener('play',()=>{
  syncPlayButtons();
  playerDialog.classList.remove('needs-tap');
  showControls();
});

playerVideo.addEventListener('pause',()=>{
  syncPlayButtons();
  showControls(true);
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,playerVideo,{force:true});
});

playerVideo.addEventListener('ended',()=>{
  syncPlayButtons();
  showControls(true);
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,playerVideo,{force:true});
  const next=$('#playerNextEpisode');
  if(next&&player.episode) next.hidden=false;
});

playerVideo.addEventListener('waiting',()=>{
  const spinner=$('#playerBuffering');
  if(spinner&&!player.fatal) spinner.hidden=false;
});

const stopBuffering=()=>{
  const spinner=$('#playerBuffering');
  if(spinner) spinner.hidden=true;
};
playerVideo.addEventListener('playing',stopBuffering);
playerVideo.addEventListener('canplay',stopBuffering);
playerVideo.addEventListener('seeked',stopBuffering);

playerVideo.addEventListener('volumechange',syncVolumeUI);

playerVideo.addEventListener('error',()=>{
  if(player.fatal||!state.playingEpisode||!player.sources.length) return;
  showPlaybackError('The browser rejected this video stream. Try another server.');
});

document.addEventListener('fullscreenchange',syncFullscreenButton);
document.addEventListener('webkitfullscreenchange',syncFullscreenButton);

playerDialog.addEventListener('close',()=>{
  const video=$('#video');
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,video,{force:true});
  state.playingEpisode=null;
  player.token+=1;
  player.episode=null;
  resetVideoElement(video);
  playerDialog.classList.remove('needs-tap','controls-visible');
  hidePlaybackError();
  hidePlayerChips();
  closePlayerMenus();
  stopBuffering();
  setPlayerStatus('');
  document.title='AniDash — Discover & Watch Anime';
  const drawer=$('#playerEpisodes');
  if(drawer) drawer.hidden=true;
  clearTimeout(drawerRefreshTimer);
});

playerDialog.addEventListener('pointermove',()=>showControls());
playerDialog.addEventListener('pointerdown',()=>{
  if(playerDialog.classList.contains('controls-visible')) return;
  showControls();
});

/* ---- keyboard ---- */

document.addEventListener('keydown',event=>{
  if(!playerDialog.open) return;
  const target=event.target;
  const tag=String(target?.tagName||'').toLowerCase();
  if(tag==='input'||tag==='textarea'||tag==='select'||target?.isContentEditable) return;
  if(event.metaKey||event.ctrlKey||event.altKey) return;

  const video=$('#video');
  const key=event.key;

  if(key==='Escape'&&anyMenuOpen()){
    event.preventDefault();
    closePlayerMenus();
    return;
  }

  const handled=[' ','k','K','j','J','l','L','m','M','f','F','c','C','p','P','n','N','b','B','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'];
  if(!handled.includes(key)&&!/^[0-9]$/.test(key)) return;

  event.preventDefault();

  switch(key){
    case ' ':
    case 'k':
    case 'K':
      togglePlay();
      break;
    case 'j':
    case 'J':
      seekBy(-10);
      break;
    case 'l':
    case 'L':
      seekBy(10);
      break;
    case 'ArrowLeft':
      seekBy(event.shiftKey?-30:-10);
      break;
    case 'ArrowRight':
      seekBy(event.shiftKey?30:10);
      break;
    case 'ArrowUp':
      setVolume(Math.min((video.muted?0:video.volume)+0.05,1));
      break;
    case 'ArrowDown':
      setVolume(Math.max((video.muted?0:video.volume)-0.05,0));
      break;
    case 'm':
    case 'M':
      toggleMute();
      break;
    case 'f':
    case 'F':
      playerToggleFullscreen();
      break;
    case 'c':
    case 'C':{
      const options=player.subtitles.length;
      if(!options) break;
      const nextIndex=player.subtitleIndex>=options-1?-1:player.subtitleIndex+1;
      applySubtitle(nextIndex);
      break;
    }
    case 'p':
    case 'P':
      togglePictureInPicture();
      break;
    case 'n':
    case 'N':
      playAdjacent(1);
      break;
    case 'b':
    case 'B':
      playAdjacent(-1);
      break;
    default:
      if(/^[0-9]$/.test(key)) seekToRatio(Number(key)/10);
      break;
  }
  showControls();
});

/* ---- boot ---- */

if(typeof webSettings.volume==='number'&&webSettings.volume>=0&&webSettings.volume<=1){
  try{playerVideo.volume=webSettings.volume}catch(_){}
}
if(webSettings.muted) playerVideo.muted=true;
if(player.lastVolume===1&&playerVideo.volume>0) player.lastVolume=playerVideo.volume;
try{playerVideo.playbackRate=Number(webSettings.playbackSpeed)||1}catch(_){}

syncPlayButtons();
renderProgress();
updatePlayerChrome();
renderSpeedMenu();

window.addEventListener('pagehide',()=>{
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,playerVideo,{force:true});
});
window.addEventListener('beforeunload',()=>{
  if(state.playingEpisode) persistPlaybackProgress(state.playingEpisode,playerVideo,{force:true});
});

if('serviceWorker' in navigator){
  const nested=location.pathname==='/watch'||location.pathname.startsWith('/watch/');
  const swUrl=nested?'/watch/sw.js':'/sw.js';
  const swScope=nested?'/watch':'/';
  navigator.serviceWorker.register(swUrl,{scope:swScope}).catch(()=>{});
}
