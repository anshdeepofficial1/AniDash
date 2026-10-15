#!/usr/bin/env python3
"""Refresh AniDash README SVG badges using real GitHub and public stats."""
import html
import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO = os.environ.get("GITHUB_REPOSITORY", "anshdeepofficial1/AniDash")
API = f"https://api.github.com/repos/{REPO}"
TOKEN = os.environ.get("GITHUB_TOKEN", "")
OUT = Path("assets/badges")
OUT.mkdir(parents=True, exist_ok=True)

def fetch(url, github=True):
    headers = {"User-Agent": "AniDash-README-badges", "Accept": "application/vnd.github+json" if github else "application/json"}
    if github and TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    with urlopen(Request(url, headers=headers), timeout=25) as resp:
        return json.load(resp)

def releases():
    result = []
    for page in range(1, 31):
        batch = fetch(f"{API}/releases?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("Unexpected releases response")
        result.extend(batch)
        if len(batch) < 100:
            return result
    raise ValueError("Too many releases; extend pagination")

def measure(text):
    return max(44, int(sum(7.7 if c in "MW@%#0123456789" else 7.0 if c.isupper() else 6.5 if c.islower() else 5.0 for c in str(text)) + 26))

def badge(label, value, color):
    label, value = str(label), str(value)
    left, right = measure(label), measure(value)
    width = left + right
    label, value = html.escape(label, quote=True), html.escape(value, quote=True)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="28" viewBox="0 0 {width} 28" role="img" aria-label="{label}: {value}">\n'
        f'  <title>{label}: {value}</title>\n'
        f'  <defs><clipPath id="badge"><rect width="{width}" height="28" rx="6"/></clipPath></defs>\n'
        f'  <g clip-path="url(#badge)">\n'
        f'    <rect width="{left}" height="28" fill="#202830"/>\n'
        f'    <rect x="{left}" width="{right}" height="28" fill="#{color}"/>\n'
        f'  </g>\n'
        f'  <g font-family="DejaVu Sans,Verdana,Arial,sans-serif" font-size="12" font-weight="600" fill="#ffffff" text-anchor="middle" dominant-baseline="central">\n'
        f'    <text x="{left/2:.1f}" y="14" textLength="{left-18}" lengthAdjust="spacingAndGlyphs">{label}</text>\n'
        f'    <text x="{left+right/2:.1f}" y="14" textLength="{right-18}" lengthAdjust="spacingAndGlyphs">{value}</text>\n'
        f'  </g>\n'
        f'</svg>\n'
    )

def save(name, label, value, color):
    path = OUT / f"{name}.svg"
    data = badge(label, value, color)
    if not path.exists() or path.read_text(encoding="utf-8") != data:
        path.write_text(data, encoding="utf-8")
        print(f"Updated {path}")

def main():
    all_versions = releases()
    if not all_versions:
        raise ValueError("No releases returned; refusing to erase counters")
    assets = [asset for release in all_versions for asset in release.get("assets", [])]
    total = sum(int(a.get("download_count") or 0) for a in assets)
    apk = sum(int(a.get("download_count") or 0) for a in assets if str(a.get("name","")).lower().endswith(".apk"))
    info = fetch(API)
    latest = fetch(f"{API}/releases/latest")
    issues = fetch(f"https://api.github.com/search/issues?q=repo%3A{REPO}+is%3Aissue+is%3Aopen")
    save("latest-release", "Latest", latest["tag_name"], "0EA5E9")
    save("total-downloads", "Total Downloads", f"{total:,}", "16A34A")
    save("android-downloads", "Android APKs", f"{apk:,}", "22C55E")
    save("stars", "Stars", f"{int(info['stargazers_count']):,}", "8B5CF6")
    save("forks", "Forks", f"{int(info['forks_count']):,}", "06B6D4")
    save("open-issues", "Open Issues", f"{int(issues['total_count']):,}", "F59E0B")
    save("license", "License", (info.get("license") or {}).get("spdx_id") or "Apache-2.0", "3B82F6")
    try:
        stats = fetch("https://anidashweb.vercel.app/api/public-stats", github=False)
        message = str(stats.get("message", "")).strip() if isinstance(stats, dict) else ""
        if message and len(message) <= 26 and message.lower() not in {"error", "unknown", "undefined", "nan"}:
            save("active-users", "Active Users", message, "10B981")
        else:
            print("No verified active-user count; preserving existing badge")
    except (HTTPError, URLError, ValueError, TimeoutError) as exc:
        print(f"Live active-user endpoint unavailable; preserving existing badge: {exc}")
    for name, label, value, color in [
        ("android","Android","6.0+","3DDC84"), ("ios","iOS","Test Build","475569"),
        ("windows","Windows","Supported","0078D4"), ("linux","Linux","Supported","A16207"),
        ("flutter","Flutter","3.35.7","02569B"), ("dart","Dart","3.7+","0175C2"),
        ("download-apk","Download","Latest APK","16A34A"), ("obtainium","Add to","Obtainium","7C3AED"),
        ("orion-store","Get it on","Orion Store","0EA5E9")
    ]:
        save(name, label, value, color)
    print(f"Refreshed: {len(all_versions)} releases; {total:,} all downloads; {apk:,} APK downloads")

if __name__ == "__main__":
    main()
