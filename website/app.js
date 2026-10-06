const pages=[
  ["Home","/"],
  ["Features","/features"],
  ["Screens","/screens"],
  ["Downloads","/downloads"],
  ["Platforms","/platforms"],
  ["FAQ","/faq"],
  ["Changelogs","/changelogs"],
  ["Legal","/legal"],
  ["About","/about"]
];

const path=location.pathname.replace(/\.html$/,"").replace(/\/$/,"")||"/";
const header=document.getElementById("site-header");

if(header){
  header.innerHTML=
    '<div class="navshell"><div class="wrap"><nav>'+
    '<a class="brand" href="/"><img src="/assets/anidash_logo.png" alt="AniDash"><span>AniDash</span></a>'+
    '<div class="navlinks">'+
    pages.map(([n,u])=>'<a class="'+(path===u?"active":"")+'" href="'+u+'">'+n+'</a>').join("")+
    '<a class="btn primary" href="/downloads">Get AniDash</a></div>'+
    '<a class="btn primary mobile" href="/downloads">Get app</a>'+
    '</nav></div></div>';
}

const footer=document.getElementById("site-footer");
if(footer){
  footer.innerHTML=
    '<footer><div class="wrap"><div class="foot">'+
    '<div class="brand"><img src="/assets/anidash_logo.png" alt=""><span>AniDash</span></div>'+
    '<div>Android · Windows · macOS · Open source · Apache 2.0 · Made by Anshdeep Singh</div>'+
    '</div></div></footer>';
}

const RELEASES_API="https://api.github.com/repos/anshdeepofficial1/AniDash/releases?per_page=20";
const RELEASES_PAGE="https://github.com/anshdeepofficial1/AniDash/releases";

function firstAsset(releases,predicate){
  for(const release of releases){
    for(const asset of (release.assets||[])){
      if(predicate(asset.name||"")) return {asset,release};
    }
  }
  return null;
}

function setHref(selector,item){
  document.querySelectorAll(selector).forEach(el=>{
    el.href=item?.asset?.browser_download_url||RELEASES_PAGE;
  });
}

function setText(selector,value){
  if(!value) return;
  document.querySelectorAll(selector).forEach(el=>el.textContent=value);
}

function buildInfo(item){
  if(!item) return "Open GitHub releases";
  const size=(item.asset.size/1048576).toFixed(1);
  return `${item.release.tag_name||"Latest"} · ${size} MB`;
}

async function latest(){
  try{
    const response=await fetch(RELEASES_API,{headers:{Accept:"application/vnd.github+json"}});
    if(!response.ok) throw new Error("GitHub release request failed");
    const raw=await response.json();
    const releases=(raw||[]).filter(r=>!r.draft&&!r.prerelease);
    if(!releases.length) return;

    const newest=releases[0];
    setText("[data-version]",newest.tag_name||"Latest release");

    const android=firstAsset(releases,name=>name.toLowerCase().endsWith(".apk"));
    const macos=firstAsset(releases,name=>{
      const n=name.toLowerCase();
      return n.endsWith(".dmg")||n.includes("macos")&&n.endsWith(".zip")||n.includes("darwin")&&n.endsWith(".zip");
    });
    const windows=firstAsset(releases,name=>{
      const n=name.toLowerCase();
      return n.endsWith(".exe")&&(n.includes("setup")||n.includes("installer")||n.includes("windows"));
    })||firstAsset(releases,name=>name.toLowerCase().endsWith(".exe"));
    const windowsPortable=firstAsset(releases,name=>{
      const n=name.toLowerCase();
      return n.endsWith(".zip")&&(n.includes("windows")||n.includes("win"))&&(n.includes("portable")||n.includes("bundle"));
    });

    setHref("[data-apk]",android);
    setHref("[data-macos]",macos);
    setHref("[data-windows]",windows);
    setHref("[data-windows-portable]",windowsPortable||windows);

    setText("[data-android-version]",android?.release?.tag_name||"Latest available");
    setText("[data-macos-version]",macos?.release?.tag_name||"Latest available");
    setText("[data-windows-version]",windows?.release?.tag_name||windowsPortable?.release?.tag_name||"Latest available");

    setText("[data-android-info]",buildInfo(android));
    setText("[data-macos-info]",buildInfo(macos));
    setText("[data-windows-info]",buildInfo(windows));
    setText("[data-windows-portable-info]",buildInfo(windowsPortable));
  }catch{
    document.querySelectorAll("[data-download-status]").forEach(el=>el.textContent="Open GitHub releases");
  }
}

latest();
