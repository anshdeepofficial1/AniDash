const pages = [
  ["Home", "/"],
  ["Watch", "/watch"],
  ["Features", "/features"],
  ["Screens", "/screens"],
  ["Downloads", "/downloads"],
  ["Platforms", "/platforms"],
  ["FAQ", "/faq"],
  ["Changelogs", "/changelogs"],
  ["Legal", "/legal"],
  ["About", "/about"]
];

const path = location.pathname.replace(/\.html$/, "").replace(/\/$/, "") || "/";
const header = document.getElementById("site-header");

if (header) {
  header.innerHTML =
    '<div class="navshell"><div class="wrap"><nav>' +
    '<a class="brand" href="/"><img src="/assets/anidash_logo.png" alt="AniDash"><span>AniDash</span></a>' +
    '<div class="navlinks">' +
    pages.map(([n, u]) => '<a class="' + (path === u ? "active" : "") + '" href="' + u + '">' + n + '</a>').join("") +
    '<a class="btn primary" href="/downloads">Get AniDash ⚡</a></div>' +
    '<a class="btn primary mobile" href="/downloads">Get App</a>' +
    '</nav></div></div>';
}

const footer = document.getElementById("site-footer");
if (footer) {
  footer.innerHTML =
    '<footer><div class="wrap"><div class="foot">' +
    '<div class="brand"><img src="/assets/anidash_logo.png" alt=""><span>AniDash</span></div>' +
    '<div>Android · Windows · macOS · Open Source · Apache 2.0 · Designed with ❤️ by Anshdeep Singh</div>' +
    '</div></div></footer>';
}

const RELEASES_API = "https://api.github.com/repos/anshdeepofficial1/AniDash/releases?per_page=20";
const RELEASES_PAGE = "https://github.com/anshdeepofficial1/AniDash/releases";

function findAsset(releases, predicate) {
  for (const release of releases) {
    for (const asset of (release.assets || [])) {
      if (predicate(asset.name || "")) return { asset, release };
    }
  }
  return null;
}

function setHref(selector, item) {
  document.querySelectorAll(selector).forEach(el => {
    el.href = item?.asset?.browser_download_url || RELEASES_PAGE;
  });
}

function setText(selector, value) {
  if (!value) return;
  document.querySelectorAll(selector).forEach(el => el.textContent = value);
}

function formatSize(bytes) {
  if (!bytes) return "";
  return (bytes / 1048576).toFixed(1) + " MB";
}

function buildInfo(item, label) {
  if (!item) return label || "Open GitHub releases";
  const size = formatSize(item.asset.size);
  return `${item.release.tag_name || "Latest"} · ${size}`;
}

async function fetchLatestReleases() {
  try {
    const response = await fetch(RELEASES_API, {
      headers: { Accept: "application/vnd.github+json" }
    });
    if (!response.ok) throw new Error("GitHub release request failed");
    const raw = await response.json();
    const releases = (raw || []).filter(r => !r.draft && !r.prerelease);
    if (!releases.length) return;

    const newest = releases[0];
    const latestTag = newest.tag_name || "v3.2.6";
    setText("[data-version]", latestTag);
    setText("[data-latest-tag]", latestTag);

    // Specific architecture APKs
    const arm64 = findAsset(releases, name => name.toLowerCase().includes("arm64-v8a") && name.endsWith(".apk"));
    const arm32 = findAsset(releases, name => name.toLowerCase().includes("armeabi-v7a") && name.endsWith(".apk"));
    const x86 = findAsset(releases, name => name.toLowerCase().includes("x86_64") && name.endsWith(".apk"));
    const universal = findAsset(releases, name => 
      (name.toLowerCase().includes("universal") || name.toLowerCase() === "app-release.apk") && name.endsWith(".apk")
    ) || findAsset(releases, name => name.endsWith(".apk"));

    // Desktop builds
    const macos = findAsset(releases, name => {
      const n = name.toLowerCase();
      return n.endsWith(".dmg") || (n.includes("macos") && n.endsWith(".zip")) || (n.includes("darwin") && n.endsWith(".zip"));
    });

    const windows = findAsset(releases, name => {
      const n = name.toLowerCase();
      return n.endsWith(".exe") && (n.includes("setup") || n.includes("installer") || n.includes("windows"));
    }) || findAsset(releases, name => name.toLowerCase().endsWith(".exe"));

    const windowsPortable = findAsset(releases, name => {
      const n = name.toLowerCase();
      return n.endsWith(".zip") && (n.includes("windows") || n.includes("win")) && (n.includes("portable") || n.includes("bundle"));
    });

    // Wire up links
    setHref("[data-apk]", arm64 || universal);
    setHref("[data-apk-universal]", universal);
    setHref("[data-apk-arm64]", arm64 || universal);
    setHref("[data-apk-arm32]", arm32 || universal);
    setHref("[data-apk-x86]", x86 || universal);
    setHref("[data-macos]", macos);
    setHref("[data-windows]", windows);
    setHref("[data-windows-portable]", windowsPortable || windows);

    // Text & Version labels
    setText("[data-android-version]", latestTag);
    setText("[data-macos-version]", macos?.release?.tag_name || latestTag);
    setText("[data-windows-version]", windows?.release?.tag_name || windowsPortable?.release?.tag_name || latestTag);

    setText("[data-android-info]", buildInfo(arm64 || universal, "Universal APK"));
    setText("[data-apk-universal-size]", universal ? formatSize(universal.asset.size) : "~78 MB");
    setText("[data-apk-arm64-size]", arm64 ? formatSize(arm64.asset.size) : "~34 MB");
    setText("[data-apk-arm32-size]", arm32 ? formatSize(arm32.asset.size) : "~34 MB");
    setText("[data-apk-x86-size]", x86 ? formatSize(x86.asset.size) : "~35 MB");

    setText("[data-macos-info]", buildInfo(macos, "macOS DMG"));
    setText("[data-windows-info]", buildInfo(windows, "Windows Setup"));
    setText("[data-windows-portable-info]", buildInfo(windowsPortable, "Portable ZIP"));

    document.querySelectorAll("[data-download-status]").forEach(el => {
      if (el.textContent.includes("Checking")) el.textContent = latestTag;
    });
  } catch (err) {
    document.querySelectorAll("[data-download-status]").forEach(el => el.textContent = "GitHub Releases");
  }
}

fetchLatestReleases();
