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
  libraryStatus:'watching',
  browseFilter:'all',
  lastMainPage:'homePage'
};

const DEFAULT_WEB_SETTINGS={
  theme:'system',
  amoled:false,
  compactCards:false,
  spotlightAutoPlay:true,
  showAdult:false,
  incognito:false,
  preferredAudio:'sub',
  preferredQuality:'Auto',
  nav:{browse:true,manga:true,downloads:true,watchlist:true}
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
    downloadsPage:webSettings.nav.downloads,
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
    settingNavDownloads:webSettings.nav.downloads,
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

const api=async params=>{
  const r=await fetch('/api/anidash?'+new URLSearchParams(params));
  const x=await r.json().catch(()=>({}));
  if(!r.ok) throw Error(x.error||'Could not load');
  return x;
};

const titleOf=x=>x?.title?.english||x?.title?.romaji||x?.title?.native||x?.name||x?.title||'Untitled';
const imageOf=x=>x?.coverImage?.extraLarge||x?.coverImage?.large||x?.cover||x?.poster||'';
const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const mediaFields=`id title{english romaji native} synonyms coverImage{extraLarge large} bannerImage seasonYear episodes format averageScore status description(asHtml:false) genres isAdult nextAiringEpisode{episode timeUntilAiring}`;
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

function card(x,wide=false,type='anime'){
  const title=titleOf(x);
  const baseImage=imageOf(x);
  const image=wide?(x.bannerImage||baseImage):baseImage;
  const meta=type==='manga'
    ? (x.chapters?`${x.chapters} CHAPTERS`:(x.format||'MANGA'))
    : (x.format==='MOVIE'?'MOVIE':(x.episodes?`${x.episodes} EPS`:(x.nextAiringEpisode?.episode>1?`${x.nextAiringEpisode.episode-1}+ EPS`:'? EPS')));
  const badge=type==='manga'?(x.format==='NOVEL'?'LN':'M'):seasonBadge(x);
  return `<button class="anime-card" data-id="${esc(x.id)}" data-title="${encodeURIComponent(title)}" data-image="${encodeURIComponent(baseImage)}" data-type="${type}">
    <div class="cover">
      <img src="${esc(image)}" loading="lazy" alt="">
      ${badge?`<span class="corner">${esc(badge)}</span>`:''}
      ${x.averageScore?`<span class="rating">★ ${(x.averageScore/10).toFixed(1)}</span>`:''}
      ${wide?'<span class="play-fab">▶</span><span class="progress"><i></i></span>':''}
    </div>
    <strong>${esc(title)}</strong>
    <small>${wide?`E${x.episode||1} · ${esc(x.episodeTitle||'Continue watching')}`:esc(meta)}</small>
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
  rail.innerHTML=heroes.map(hero=>`
    <button class="spotlight-slide" data-id="${hero.id}" data-title="${encodeURIComponent(titleOf(hero))}" data-image="${encodeURIComponent(imageOf(hero))}" style="background-image:url('${esc(hero.bannerImage||imageOf(hero))}')">
      <span class="score">★ ${hero.averageScore?(hero.averageScore/10).toFixed(1):'—'}</span>
      <div class="spotlight-content">
        <div class="spotlight-meta">
          <span class="badge">${esc(hero.status?.replaceAll('_',' ')||'ONGOING')}</span>
          <span class="badge">${esc(hero.format||'TV')}</span>
          <span class="badge">${hero.episodes||hero.nextAiringEpisode?.episode-1||'?'} EPISODES</span>
        </div>
        <h1>${esc(titleOf(hero))}</h1>
      </div>
    </button>
  `).join('');
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
  const saved=JSON.parse(localStorage.getItem('anidash-progress')||'[]').sort((a,b)=>b.time-a.time);
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

async function ensureEpisodes(){
  if(state.episodes.length) return;
  let page=1,x;
  do{
    x=await api({action:'episodes',id:state.current.id,page});
    state.episodes.push(...(x.episodes||[]));
    page++;
  }while(page<=(x.totalPages||1));
}

async function showEpisodes(){
  const box=$('#tabContent');
  box.innerHTML='<p>Fetching episodes…</p>';
  try{
    await ensureEpisodes();
    if(!state.episodes.length){box.innerHTML='<p>No episodes are available from this source.</p>';return}
    box.innerHTML=`<div class="episode-list">${state.episodes.map(ep=>`<button class="episode" data-episode="${esc(ep.number)}"><img src="${esc(ep.image||state.current.cover)}" loading="lazy" alt=""><span><strong>E${esc(ep.number)} — ${esc(ep.title||'Episode '+ep.number)}</strong><small>${ep.filler?'Filler episode':'Tap to watch'}</small></span></button>`).join('')}</div>`;
    box.querySelectorAll('.episode').forEach((b,i)=>b.onclick=()=>playEpisode(state.episodes[i]));
  }catch(e){box.innerHTML=`<p>${esc(e.message)}</p>`}
}

async function playEpisode(ep){
  const dlg=$('#playerDialog'),video=$('#video'),loading=$('#playerLoading');
  if(!dlg.open) dlg.showModal();
  $('#playerTitle').textContent=`E${ep.number} — ${ep.title||'Episode '+ep.number}`;
  $('#playerStatus').textContent='';
  loading.hidden=false;
  if(state.hls){state.hls.destroy();state.hls=null}
  video.pause();
  video.removeAttribute('src');
  video.load();
  try{
    const x=await api({action:'source',id:state.current.id,episode:ep.number,audio:$('#audio').value});
    const sources=x.sources||[];
    const preferred=String(webSettings.preferredQuality||'Auto').toLowerCase();
    const wanted=preferred==='auto'?null:preferred.replace('p','');
    const selected=wanted
      ? sources.find(source=>String(source.quality||'').toLowerCase().replace('p','').includes(wanted))
      : null;
    const src=(selected||sources[0])?.url;
    if(!src) throw Error($('#audio').value==='dub'?'English dub is not available. Try SUB.':'No playable source was found.');

    // Safari/iPhone/iPad have excellent native HLS support. Prefer it so an
    // installed Home Screen app uses the same native media pipeline as Safari.
    if(video.canPlayType('application/vnd.apple.mpegurl')){
      video.src=src;
      video.load();
      await video.play();
    }else if(globalThis.Hls&&Hls.isSupported()){
      state.hls=new Hls({
        maxBufferLength:100,
        maxMaxBufferLength:120,
        backBufferLength:30,
        enableWorker:true
      });
      await new Promise((ok,no)=>{
        let settled=false;
        state.hls.on(Hls.Events.MANIFEST_PARSED,()=>{if(!settled){settled=true;ok()}});
        state.hls.on(Hls.Events.ERROR,(_,d)=>{if(d.fatal&&!settled){settled=true;no(Error('Video stream could not be loaded'))}});
        state.hls.loadSource(src);
        state.hls.attachMedia(video);
      });
      await video.play();
    }else{
      throw Error('This browser cannot play this stream');
    }
    saveProgress(ep);
    loading.hidden=true;
  }catch(e){
    loading.hidden=true;
    $('#playerStatus').textContent=e.name==='NotAllowedError'?'Tap play to start':e.message;
  }
}

function saveProgress(ep){
  if(webSettings.incognito) return;
  let list=JSON.parse(localStorage.getItem('anidash-progress')||'[]').filter(x=>String(x.id)!==String(state.current.id));
  list.unshift({
    id:state.current.id,
    title:state.current.title||titleOf(state.current),
    cover:ep.image||state.current.bannerImage||state.current.cover||imageOf(state.current),
    bannerImage:ep.image||state.current.bannerImage,
    episode:+ep.number,
    episodeTitle:ep.title||`Episode ${ep.number}`,
    episodes:state.current.episodes,
    format:state.current.format,
    time:Date.now()
  });
  localStorage.setItem('anidash-progress',JSON.stringify(list.slice(0,30)));
  renderContinue();
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

function openPage(pageId){
  const current=$('.page.active')?.id;
  if(pageId==='settingsPage'&&current&&current!=='settingsPage') state.lastMainPage=current;
  const isSubpage=pageId==='settingsPage';
  document.body.classList.toggle('subpage-open',isSubpage);
  $$('.page').forEach(p=>p.classList.toggle('active',p.id===pageId));
  $$('[data-page]').forEach(b=>b.classList.toggle('active',!isSubpage&&b.dataset.page===pageId));
  if(pageId==='browsePage'){
    renderHistory();
    if(!$('#searchInput').value.trim()) renderBrowseLanding(state.browseFilter);
  }
  if(pageId==='mangaPage'&&!$('#mangaGrid').children.length) loadManga();
  if(pageId==='watchlistPage') renderLibrary();
  if(pageId==='settingsPage') syncSettingsControls();
  window.scrollTo({top:0,behavior:'auto'});
}

function showUtility(title,body){
  $('#utilityTitle').textContent=title;
  $('#utilityBody').textContent=body;
  const dlg=$('#utilityDialog');
  if(!dlg.open) dlg.showModal();
}

$('[data-page]').forEach(b=>b.onclick=()=>openPage(b.dataset.page));

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
$('#downloadsExplore').onclick=()=>openPage('browsePage');

$('#profileButton').onclick=()=>$('#accountDialog').showModal();
$('.sheet-close').onclick=()=>$('#accountDialog').close();
$('.sheet-close-action').onclick=()=>$('#accountDialog').close();
$('#accountBrowse').onclick=()=>{$('#accountDialog').close();openPage('browsePage')};

$('#niaButton').onclick=()=>showUtility('AniDash AI','The native AniDash AI service is not exposed to the public web client yet. Anime discovery and playback remain fully separate from this unavailable native service.');
$('#newsButton').onclick=()=>showUtility('AniDash News','News requires the native AniDash news service. This web build does not show a fake feed.');
$('#notificationButton').onclick=()=>openPage('settingsPage');
$('#settingsButton').onclick=()=>openPage('settingsPage');
$('#libraryTune').onclick=()=>showUtility('Customize Library','Tracked titles are stored locally on this device and organized with the same AniDash status tabs.');
$('.utility-close').onclick=()=>$('#utilityDialog').close();
$('.utility-close-action').onclick=()=>$('#utilityDialog').close();

$('.details-back').onclick=()=>$('#detailsDialog').close();
$('.player-back').onclick=()=>{
  const v=$('#video');
  v.pause();
  if(state.hls){state.hls.destroy();state.hls=null}
  v.removeAttribute('src');
  v.load();
  $('#playerDialog').close();
};
$('#audio').onchange=()=>{
  webSettings.preferredAudio=$('#audio').value;
  saveWebSettings();
  const ep=$('#playerTitle').textContent.match(/^E([\d.]+)/)?.[1];
  const item=state.episodes.find(x=>String(x.number)===ep);
  if(item) playEpisode(item);
};

$('#settingsBack').onclick=()=>openPage(state.lastMainPage||'homePage');
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
bindToggle('settingNavDownloads',v=>{webSettings.nav.downloads=v;saveWebSettings()});
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
      await registration.showNotification('AniDash',{body:'Notifications are allowed on this device.',icon:'https://anidashweb.vercel.app/assets/anidash_logo.png'});
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
const initialPage={browse:'browsePage',manga:'mangaPage',downloads:'downloadsPage',watchlist:'watchlistPage'}[initialTab]||'homePage';

applyWebSettings();
syncSettingsControls();
renderHistory();
renderLibrary();
loadHome();
if(initialPage!=='homePage') openPage(initialPage);

if('serviceWorker' in navigator){
  const nested=location.pathname==='/watch'||location.pathname.startsWith('/watch/');
  const swUrl=nested?'/watch/sw.js':'/sw.js';
  const swScope=nested?'/watch':'/';
  navigator.serviceWorker.register(swUrl,{scope:swScope}).catch(()=>{});
}
