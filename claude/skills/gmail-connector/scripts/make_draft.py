#!/usr/bin/env python3
"""Create or replace a Gmail draft through `gws`, with an HTML part so Gmail never hard-wraps it.

A draft whose only body part is text/plain opens in Gmail's plain-text compose mode, and
Gmail hard-wraps plain-text mode at about 70 characters when it sends. The recipient then
gets a newline in the middle of every sentence (observed 13 Nov 2026 on a J-1 support-letter
request that the recipient had to copy onto letterhead). This script always writes a
multipart/alternative body: the plain text as written plus an HTML rendering of it.

Body format: paragraphs separated by a blank line; a single newline inside a paragraph is a
line break (for address blocks, lists, signatures). Write each paragraph on one line.

Examples:
  make_draft.py --to a@x.org --cc b@x.org --subject "Hello" --body-file body.txt \
      --attach form.pdf --attach-name "Lin_form.pdf"
  make_draft.py ... --reply-to <message-id> --thread-id <thread-id>     # threaded reply
  make_draft.py ... --update <draft-id>                                 # replace a draft in place
  make_draft.py ... --out draft.eml                                     # build only, no upload
"""

import argparse
import html
import json
import mimetypes
import subprocess
import sys
import tempfile
from email.message import EmailMessage
from pathlib import Path


def to_html(text: str) -> str:
    paras = [p for p in text.strip().split("\n\n") if p.strip()]
    body = "".join("<p>" + html.escape(p.strip("\n")).replace("\n", "<br>") + "</p>" for p in paras)
    return f'<div dir="ltr">{body}</div>'


def build(args: argparse.Namespace) -> bytes:
    text = Path(args.body_file).read_text()
    msg = EmailMessage()
    msg["To"] = ", ".join(args.to)
    if args.cc:
        msg["Cc"] = ", ".join(args.cc)
    msg["Subject"] = args.subject
    if args.reply_to:
        mid = args.reply_to if args.reply_to.startswith("<") else f"<{args.reply_to}>"
        msg["In-Reply-To"] = mid
        msg["References"] = mid
    msg.set_content(text.strip() + "\n")
    msg.add_alternative(to_html(text), subtype="html")
    names = args.attach_name or []
    for i, path in enumerate(args.attach or []):
        p = Path(path)
        ctype = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
        maintype, subtype = ctype.split("/", 1)
        name = names[i] if i < len(names) else p.name
        msg.add_attachment(p.read_bytes(), maintype=maintype, subtype=subtype, filename=name)
    return bytes(msg)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--to", action="append", required=True)
    ap.add_argument("--cc", action="append")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--body-file", required=True, help="plain text; blank line between paragraphs")
    ap.add_argument("--attach", action="append", help="file to attach (repeatable)")
    ap.add_argument("--attach-name", action="append", help="filename shown to the recipient, in --attach order")
    ap.add_argument("--reply-to", help="Message-ID header of the message being answered")
    ap.add_argument("--thread-id", help="Gmail thread id, so the draft lands in that thread")
    ap.add_argument("--update", metavar="DRAFT_ID", help="replace this draft instead of creating one")
    ap.add_argument("--out", help="write the .eml here and stop (no upload)")
    args = ap.parse_args()

    raw = build(args)
    if args.out:
        Path(args.out).write_bytes(raw)
        print(f"wrote {args.out} ({len(raw)} bytes)")
        return 0

    with tempfile.NamedTemporaryFile(suffix=".eml", delete=False) as f:
        f.write(raw)
        eml = f.name
    meta: dict = {"message": {}}
    if args.thread_id:
        meta["message"]["threadId"] = args.thread_id
    if args.update:
        meta["id"] = args.update
        cmd = ["gws", "gmail", "users", "drafts", "update",
               "--params", json.dumps({"userId": "me", "id": args.update})]
    else:
        cmd = ["gws", "gmail", "users", "drafts", "create", "--params", json.dumps({"userId": "me"})]
    cmd += ["--json", json.dumps(meta), "--upload", eml, "--upload-content-type", "message/rfc822"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout[res.stdout.find("{"):] if "{" in res.stdout else res.stdout
    if res.returncode != 0 or '"error"' in out:
        sys.stderr.write(res.stderr + out)
        return 1
    d = json.loads(out)
    thread = d["message"]["threadId"]
    print(json.dumps({
        "draft_id": d["id"],
        "thread_id": thread,
        "url": f"https://mail.google.com/mail/u/0/#all?compose=thread-f:{int(thread, 16)}%2Bmsg-a:{d['id']}",
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
