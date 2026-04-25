#!/usr/bin/env python3
"""
Обогащает docs/specs/podcasts-feeds.json и LiboLibo/Resources/podcasts.json
двумя полями для каждого подкаста:
  - description: канальное описание из RSS (первые html-теги выкинуты)
  - lastEpisodeDate: ISO-дата самого свежего выпуска

Результат используется приложением, чтобы сегментировать подкасты
на «выходят сейчас / недавно выходили / давно не выходят» без сетевых
запросов на каждом запуске. Перезапускать раз в сутки/неделю.
"""

import json
import re
import ssl
import sys
import urllib.request
import xml.etree.ElementTree as ET

# macOS Python часто не находит system CA bundle.
# Подкаст-RSS фиды публичные, не критично для proof-of-concept.
SSL_CONTEXT = ssl.create_default_context()
SSL_CONTEXT.check_hostname = False
SSL_CONTEXT.verify_mode = ssl.CERT_NONE
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/specs/podcasts-feeds.json"
BUNDLE_COPY = ROOT / "LiboLibo/Resources/podcasts.json"

ITUNES_NS = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"

HTML_TAG = re.compile(r"<[^>]+>")
HTML_ENTITIES = {
    "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'",
    "&#39;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
    "&hellip;": "…", "&laquo;": "«", "&raquo;": "»",
}

def strip_html(s: str) -> str:
    if not s:
        return ""
    s = HTML_TAG.sub("", s)
    for k, v in HTML_ENTITIES.items():
        s = s.replace(k, v)
    s = re.sub(r"\s{2,}", " ", s)
    return s.strip()


def fetch_feed(p: dict) -> dict:
    url = p["feedUrl"]
    req = urllib.request.Request(url, headers={"User-Agent": "libolibo/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20, context=SSL_CONTEXT) as resp:
            data = resp.read()
    except Exception as e:
        return {"id": p["id"], "error": f"fetch failed: {e}"}

    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        return {"id": p["id"], "error": f"parse failed: {e}"}

    chan = root.find("channel")
    if chan is None:
        return {"id": p["id"], "error": "no channel element"}

    desc = chan.findtext("description") or chan.findtext(f"{ITUNES_NS}summary") or ""
    desc = strip_html(desc)

    latest = None
    for it in chan.findall("item"):
        pd_text = it.findtext("pubDate")
        if not pd_text:
            continue
        try:
            dt = parsedate_to_datetime(pd_text.strip())
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if latest is None or dt > latest:
                latest = dt
        except Exception:
            continue

    return {
        "id": p["id"],
        "description": desc,
        "lastEpisodeDate": latest.isoformat() if latest else None,
    }


def main():
    payload = json.loads(SOURCE.read_text(encoding="utf-8"))
    podcasts = payload["podcasts"]

    print(f"Refreshing {len(podcasts)} feeds…")
    enriched: dict[int, dict] = {}
    with ThreadPoolExecutor(max_workers=12) as pool:
        futures = {pool.submit(fetch_feed, p): p for p in podcasts}
        for f in as_completed(futures):
            res = f.result()
            enriched[res["id"]] = res

    failures = []
    for p in podcasts:
        meta = enriched.get(p["id"], {})
        if "error" in meta:
            failures.append((p["name"], meta["error"]))
            continue
        if "description" in meta:
            p["description"] = meta["description"]
        if "lastEpisodeDate" in meta and meta["lastEpisodeDate"]:
            p["lastEpisodeDate"] = meta["lastEpisodeDate"]

    payload["fetchedAt"] = datetime.now(timezone.utc).isoformat()
    SOURCE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    BUNDLE_COPY.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Done. Wrote {SOURCE} and {BUNDLE_COPY}.")
    if failures:
        print(f"\n{len(failures)} failures:")
        for name, err in failures:
            print(f"  {name}: {err}")


if __name__ == "__main__":
    main()
