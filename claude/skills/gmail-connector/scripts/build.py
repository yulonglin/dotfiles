#!/usr/bin/env python3
"""Build a Gmail-print-style HTML page per thread from claude.ai Gmail connector captures.

Inputs, any mix:
  - a get_thread result saved as JSON ({"id": <threadId>, "messages": [{sender, toRecipients,
    ccRecipients, date, subject, htmlBody | plaintextBody, attachments}, ...]}), fetched with
    messageFormat FULL_CONTENT so htmlBody is present; output name is the file stem
  - a delimited threads.txt: blocks start "=== THREAD <threadId> | <basename> ===", each message
    starts "--- MESSAGE ---", then From/To/Cc/Date/Subject/Attachments header lines, then a line
    "--- HTML ---" or "--- TEXT ---" and the body up to the next marker; dates are UTC "Z"

Writes <out>/<basename>.html (headers, message count, each message boxed, tracking pixels and
tokenised links stripped) and prints one line per thread. Feed the result to render.py.
Exit 1 if any input fails to parse.
"""
import argparse
import html
import json
import re
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

TRACKING_HOSTS = ("unsubscribe", "track", "click", "pixel", "beacon", "open.")
TOKEN_PARAM = re.compile(r"[?&][^=&]*=([A-Za-z0-9_\-%.,]{20,})")


def fmt_date(z: str) -> str:
    dt = datetime.strptime(z, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return dt.strftime("%a, %d %b %Y %H:%M UTC")


def clean_href(href: str) -> str:
    """Unwrap linkprotect wrappers and drop query strings carrying opaque tokens."""
    raw = html.unescape(href)
    p = urllib.parse.urlsplit(raw)
    if p.netloc.endswith("linkprotect.cudasvc.com"):
        target = urllib.parse.parse_qs(p.query).get("a", [""])[0]
        if target:
            return html.escape(target, quote=True)
    if p.query and TOKEN_PARAM.search("?" + p.query):
        return html.escape(urllib.parse.urlunsplit((p.scheme, p.netloc, p.path, "", "")), quote=True)
    return href


def strip_img(m: re.Match) -> str:
    tag = m.group(0)
    if re.search(r'width=["\']?1["\']?', tag) and re.search(r'height=["\']?1["\']?', tag):
        return ""
    src = re.search(r'src=["\']([^"\']+)', tag)
    if src and src.group(1).startswith("http"):
        host = urllib.parse.urlsplit(src.group(1)).netloc.lower()
        if any(k in host for k in TRACKING_HOSTS):
            return ""
    return tag


def clean_html_body(body: str) -> str:
    body = re.sub(r"<!DOCTYPE[^>]*>", "", body, flags=re.I)
    body = re.sub(r"<head\b.*?</head>", "", body, flags=re.I | re.S)
    body = re.sub(r"</?html\b[^>]*>", "", body, flags=re.I)
    body = re.sub(r"</?body\b[^>]*>", "", body, flags=re.I)
    body = re.sub(r"<img\b[^>]*>", strip_img, body, flags=re.I)
    body = re.sub(r'href="([^"]+)"', lambda m: f'href="{clean_href(m.group(1))}"', body)
    return body.strip()


def parse_threads_txt(path: Path) -> dict[str, dict]:
    text = path.read_text(errors="replace")
    threads = {}
    blocks = re.split(r"^=== THREAD (\S+) \| (\S+) ===\n", text, flags=re.M)
    for i in range(1, len(blocks), 3):
        tid, base, body = blocks[i], blocks[i + 1], blocks[i + 2]
        msgs = []
        for chunk in re.split(r"^--- MESSAGE ---\n", body, flags=re.M)[1:]:
            m = re.match(r"(.*?)\n--- (HTML|TEXT) ---\n(.*)\Z", chunk, re.S)
            if not m:
                raise ValueError(f"{path}: malformed message in thread {tid}")
            hdr, kind, content = m.group(1), m.group(2), m.group(3)
            h = {}
            for line in hdr.split("\n"):
                k, _, v = line.partition(": ")
                h[k] = v
            msgs.append({
                "from": h["From"], "to": h.get("To", ""), "cc": h.get("Cc", ""),
                "date": h["Date"], "subject": h["Subject"],
                "attachments": h.get("Attachments", ""),
                "kind": kind, "body": content.rstrip("\n"),
            })
        threads[base] = {"id": tid, "messages": msgs}
    return threads


def parse_thread_json(path: Path) -> dict:
    d = json.loads(path.read_text())
    msgs = []
    for m in d["messages"]:
        att = m.get("attachments") or []
        names = ", ".join(a.get("filename", a.get("name", "")) for a in att) if isinstance(att, list) else ""
        if m.get("htmlBody"):
            kind, body = "HTML", m["htmlBody"]
        else:
            kind, body = "TEXT", m.get("plaintextBody", "")
        msgs.append({
            "from": m["sender"], "to": ", ".join(m.get("toRecipients") or []),
            "cc": ", ".join(m.get("ccRecipients") or []), "date": m["date"],
            "subject": m["subject"], "attachments": names, "kind": kind, "body": body,
        })
    return {"id": d["id"], "messages": msgs}


def build(base: str, thread: dict, out_dir: Path, account: str, footer: str) -> Path:
    msgs = thread["messages"]
    subject = msgs[0]["subject"]
    n = len(msgs)
    parts = [f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{html.escape(subject)}</title>
<style>
body {{ font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #000; margin: 24px; }}
.hdr {{ display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1px solid #ccc; padding-bottom: 6px; }}
.hdr .wordmark {{ font-size: 22px; font-weight: bold; color: #444; }}
h2 {{ font-size: 18px; margin: 14px 0 4px; }}
.count {{ color: #555; margin-bottom: 14px; }}
.msg {{ border: 1px solid #ccc; padding: 10px 12px; margin-bottom: 14px; page-break-inside: avoid; }}
.msg .sender {{ font-weight: bold; }}
.msg .meta {{ color: #666; }}
.msg hr {{ border: 0; border-top: 1px solid #ddd; margin: 8px 0; }}
.msg pre {{ white-space: pre-wrap; font-family: Arial, Helvetica, sans-serif; font-size: 13px; margin: 0; }}
.body img {{ max-width: 100%; }}
.footer {{ color: #666; font-size: 11px; border-top: 1px solid #ccc; padding-top: 6px; margin-top: 20px; }}
</style></head><body>
<div class="hdr"><span>{html.escape(account)}</span><span class="wordmark">Gmail</span></div>
<h2>{html.escape(subject)}</h2>
<div class="count">{n} message{"s" if n != 1 else ""}</div>
"""]
    for m in msgs:
        meta = [f"To: {html.escape(m['to'])}"]
        if m["cc"]:
            meta.append(f"Cc: {html.escape(m['cc'])}")
        if m["attachments"]:
            meta.append(f"Attachments: {html.escape(m['attachments'])}")
        if m["kind"] == "HTML":
            body = clean_html_body(m["body"])
        else:
            body = f"<pre>{html.escape(m['body'])}</pre>"
        parts.append(f"""<div class="msg">
<div class="sender">{html.escape(m['from'])} &nbsp; {fmt_date(m['date'])}</div>
<div class="meta">{"<br>".join(meta)}</div>
<hr>
<div class="body">{body}</div>
</div>
""")
    parts.append(f"""<div class="footer">{html.escape(footer)}; thread id {thread['id']}</div>
</body></html>
""")
    out = out_dir / f"{base}.html"
    out.write_text("".join(parts))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", type=Path, help="threads.txt files and/or get_thread JSON files")
    ap.add_argument("--out", type=Path, required=True, help="directory for the .html files")
    ap.add_argument("--account", required=True, help="mailbox address shown in the page header")
    ap.add_argument("--footer", default=None,
                    help='footer text; default "Printed from Gmail via the Gmail API on <today> (UTC)"')
    a = ap.parse_args()
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    footer = a.footer or f"Printed from Gmail via the Gmail API on {today} (UTC)"
    a.out.mkdir(parents=True, exist_ok=True)

    threads: dict[str, dict] = {}
    failed = 0
    for p in a.inputs:
        try:  # spilled tool results are .txt whatever they hold, so sniff the content
            if p.read_text(errors="replace").lstrip().startswith("{"):
                threads[p.stem] = parse_thread_json(p)
            else:
                threads.update(parse_threads_txt(p))
        except (ValueError, KeyError, OSError) as e:
            print(f"{p}\tFAILED\t{e}", file=sys.stderr)
            failed += 1
    for base, t in threads.items():
        out = build(base, t, a.out, a.account, footer)
        print(f"{base}\t{t['id']}\t{len(t['messages'])} msgs\t{out.stat().st_size} B")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
