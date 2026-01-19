#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html as htmllib
import re
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import Optional, Sequence


class ArticleTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self._in_script = False
        self._in_style = False
        self._in_article = False
        self._article_depth = 0
        self._parts: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag in ("script", "noscript"):
            self._in_script = True
            return
        if tag == "style":
            self._in_style = True
            return

        if tag == "article":
            self._in_article = True
            self._article_depth = 1
        elif self._in_article:
            self._article_depth += 1

        if self._in_article and tag in ("p", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre"):
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "noscript"):
            self._in_script = False
            return
        if tag == "style":
            self._in_style = False
            return

        if self._in_article:
            self._article_depth -= 1
            if tag == "article" or self._article_depth <= 0:
                self._in_article = False
                self._article_depth = 0

        if self._in_article and tag in ("p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre"):
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._in_script or self._in_style or not self._in_article:
            return
        txt = data.strip()
        if not txt:
            return
        self._parts.append(txt + " ")

    def handle_entityref(self, name: str) -> None:
        if self._in_script or self._in_style or not self._in_article:
            return
        self._parts.append(htmllib.unescape(f"&{name};"))

    def handle_charref(self, name: str) -> None:
        if self._in_script or self._in_style or not self._in_article:
            return
        self._parts.append(htmllib.unescape(f"&#{name};"))

    def text(self) -> str:
        s = "".join(self._parts)
        s = re.sub(r"[ \t\r\f\v]+", " ", s)
        s = re.sub(r"\n\s*\n+", "\n\n", s)
        return s.strip()


def strip_html_best_effort(html: str) -> str:
    s = re.sub(r"(?is)<(script|style|noscript).*?>.*?</\1>", "", html)
    s = re.sub(r"(?s)<[^>]+>", " ", s)
    s = htmllib.unescape(s)
    s = re.sub(r"[ \t\r\f\v]+", " ", s)
    s = re.sub(r"\n\s*\n+", "\n\n", s)
    return s.strip()


def fetch_url(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "codex-summarize-pipeline/1.0 (+https://openai.com/)",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
        content_type = resp.headers.get("Content-Type", "")
        m = re.search(r"charset=([a-zA-Z0-9._-]+)", content_type)
        encoding = m.group(1) if m else "utf-8"
        try:
            return raw.decode(encoding, errors="replace")
        except LookupError:
            return raw.decode("utf-8", errors="replace")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Fetch a URL or HTML file and extract article-ish plain text.")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--url", help="URL to fetch.")
    g.add_argument("--input-html", help="Path to an HTML file.")
    p.add_argument("--output", required=True, help="Output .txt file path.")
    return p.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    out = Path(args.output).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    html: Optional[str]
    if args.url:
        html = fetch_url(args.url)
    else:
        html = Path(args.input_html).read_text("utf-8", errors="replace")

    parser = ArticleTextExtractor()
    parser.feed(html)
    text = parser.text()
    if len(text) < 500:
        text = strip_html_best_effort(html)

    out.write_text(text + "\n", "utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)

