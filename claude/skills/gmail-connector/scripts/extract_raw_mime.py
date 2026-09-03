#!/usr/bin/env python3
"""Extract attachments and a plain-text body from a Gmail message fetched via the claude.ai Gmail
connector with messageFormat=RAW.

Input is either the connector's JSON result ({"id": ..., "raw": <base64url MIME>}) or a bare .eml
file. Writes <out>/<message-id>/{<attachment files>, _body.txt, _meta.json} and prints one summary
line per message. PDFs are checked for the %PDF- magic so a truncated payload is caught.
"""
import argparse, base64, email, html, json, pathlib, re, sys
from email import policy
from email.utils import parsedate_to_datetime


def load(path: pathlib.Path):
    data = path.read_bytes()
    try:
        d = json.loads(data)
        raw = d["raw"]
        return d.get("id", path.stem), base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
    except (ValueError, KeyError, TypeError):
        return path.stem, data  # bare .eml


def html_to_text(s: str) -> str:
    s = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", s, flags=re.S | re.I)
    s = re.sub(r"<br\s*/?>|</(p|div|tr|td|li|h\d)>", "\n", s, flags=re.I)
    s = html.unescape(re.sub(r"<[^>]+>", " ", s))
    s = re.sub(r"[ \t‌͏\xa0]+", " ", s)
    return re.sub(r"\n\s*\n+", "\n", s).strip()


def extract(src: pathlib.Path, out: pathlib.Path) -> int:
    mid, rb = load(src)
    msg = email.message_from_bytes(rb, policy=policy.default)
    od = out / mid
    od.mkdir(parents=True, exist_ok=True)
    atts, bad = [], []
    for part in msg.walk():
        fn = part.get_filename()
        if not fn:
            continue
        payload = part.get_payload(decode=True) or b""
        (od / fn).write_bytes(payload)
        atts.append(f"{fn} ({len(payload)} B)")
        if fn.lower().endswith(".pdf") and not payload.startswith(b"%PDF-"):
            bad.append(fn)
    body = msg.get_body(preferencelist=("plain", "html"))
    txt = ""
    if body is not None:
        txt = body.get_content()
        if body.get_content_type() == "text/html":
            txt = html_to_text(txt)
    (od / "_body.txt").write_text(txt)
    try:
        date = parsedate_to_datetime(msg["date"]).strftime("%Y-%m-%d")
    except Exception:
        date = "?"
    meta = {"id": mid, "date": date, "from": str(msg["from"]), "to": str(msg["to"]),
            "subject": str(msg["subject"]), "attachments": atts, "bad_pdf": bad}
    (od / "_meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    flag = "  !! NOT A PDF: " + ", ".join(bad) if bad else ""
    print(f"{date} {mid} | {str(msg['from'])[:40]} | {str(msg['subject'])[:60]} | {atts}{flag}")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", type=pathlib.Path, help="connector JSON result(s) or .eml file(s)")
    ap.add_argument("--out", type=pathlib.Path, required=True, help="output directory (one subdir per message id)")
    a = ap.parse_args()
    rc = 0
    for p in a.inputs:
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr); rc = 2; continue
        rc = max(rc, extract(p, a.out))
    return rc


if __name__ == "__main__":
    sys.exit(main())
