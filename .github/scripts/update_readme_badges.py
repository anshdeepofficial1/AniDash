#!/usr/bin/env python3
"""Refresh AniDash README SVG badges using real GitHub and public stats."""
import html
import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO = os.environ.get("GITHUB_REPOSITORY", "anshdeepofficial1/AniDash")
API = f"https://api.github.com/repos/{REPO}"
TOKEN = os.environ.get("GITHUB_TOKEN", "")
OUT = Path("assets/badges")
OUT.mkdir(parents=True, exist_ok=True)

def fetch(url, github=True, timeout=25, retries=3):
    headers = {"User-Agent": "AniDash-README-badges", "Accept": "application/vnd.github+json" if github else "application/json"}
    if github and TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    for attempt in range(1, retries + 1):
        try:
            with urlopen(Request(url, headers=headers), timeout=timeout) as resp:
                return json.load(resp)
        except Exception as exc:
            if attempt >= retries:
                raise
            print(f"Warning: fetch attempt {attempt} failed for {url} ({exc}), retrying...")
            time.sleep(2 * attempt)

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

def text_width(s):
    w = 0.0
    for c in str(s):
        if c in "MW@#%":
            w += 8.8
        elif c in "m":
            w += 8.2
        elif c in "w":
            w += 7.5
        elif c in "fjlrtI1":
            w += 3.8
        elif c in "i":
            w += 3.2
        elif c in ".,:;!'|-+ ":
            w += 3.8
        elif c.isupper() or c.isdigit():
            w += 6.8
        elif c.islower():
            w += 6.0
        else:
            w += 6.5
    return w

def measure(text, min_pad=22):
    return max(40, int(round(text_width(text) + min_pad)))

def badge(label, value, color):
    label, value = str(label), str(value)
    left, right = measure(label), measure(value)
    width = left + right
    esc_label = html.escape(label, quote=True)
    esc_value = html.escape(value, quote=True)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="26" viewBox="0 0 {width} 26" role="img" aria-label="{esc_label}: {esc_value}">\n'
        f'  <title>{esc_label}: {esc_value}</title>\n'
        f'  <defs>\n'
        f'    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">\n'
        f'      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.12"/>\n'
        f'      <stop offset="100%" stop-color="#000000" stop-opacity="0.16"/>\n'
        f'    </linearGradient>\n'
        f'    <clipPath id="c">\n'
        f'      <rect width="{width}" height="26" rx="5"/>\n'
        f'    </clipPath>\n'
        f'  </defs>\n'
        f'  <g clip-path="url(#c)">\n'
        f'    <rect width="{left}" height="26" fill="#1e293b"/>\n'
        f'    <rect x="{left}" width="{right}" height="26" fill="#{color}"/>\n'
        f'    <rect width="{width}" height="26" fill="url(#g)"/>\n'
        f'    <rect width="{width}" height="26" rx="5" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n'
        f'  </g>\n'
        f'  <g font-family="-apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, \'Helvetica Neue\', Arial, sans-serif" font-size="11" font-weight="600" text-anchor="middle" dominant-baseline="central">\n'
        f'    <text x="{left/2:.1f}" y="14" fill="#000000" opacity="0.3">{esc_label}</text>\n'
        f'    <text x="{left/2:.1f}" y="13" fill="#ffffff">{esc_label}</text>\n'
        f'    <text x="{left + right/2:.1f}" y="14" fill="#000000" opacity="0.3">{esc_value}</text>\n'
        f'    <text x="{left + right/2:.1f}" y="13" fill="#ffffff">{esc_value}</text>\n'
        f'  </g>\n'
        f'</svg>\n'
    )

def save(name, label, value, color):
    path = OUT / f"{name}.svg"
    data = badge(label, value, color)
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
    active_users = "200+"
    active_path = OUT / "active-users.svg"
    if active_path.exists():
        import re
        m = re.search(r'aria-label="Active Users:\s*([^"]+)"', active_path.read_text(encoding="utf-8"))
        if m:
            active_users = m.group(1).strip()
    try:
        stats = fetch("https://anidashweb.vercel.app/api/public-stats", github=False, timeout=6)
        message = str(stats.get("message", "")).strip() if isinstance(stats, dict) else ""
        if message and len(message) <= 26 and message.lower() not in {"error", "unknown", "undefined", "nan"}:
            active_users = message
    except Exception as exc:
        print(f"Live active-user endpoint unavailable; using preserved '{active_users}': {exc}")
    save("active-users", "Active Users", active_users, "10B981")
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
