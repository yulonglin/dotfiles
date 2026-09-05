#!/usr/bin/env python3
"""Render HTML files (from build.py, or any saved receipt page) to PDF with headless Chrome.

Writes <out>/<stem>.pdf for each input and prints "<stem>\tstatus\tbytes\tpages" per file.
Chrome 152 headless never exits after --print-to-pdf, so each run is polled until the PDF size
stops changing, then the process is killed. Run with the sandbox off: Chrome cannot start its
helpers inside it. A PDF under --min-bytes is reported as failed (blank page). Exit 1 if any
file failed. Then `cp` (never `mv`) the PDFs into the pack.
"""
import argparse
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def page_count(pdf: Path) -> int:
    return len(re.findall(rb"/Type\s*/Page[^s]", pdf.read_bytes()))


def render(src: Path, out_dir: Path, chrome: str, profile: Path, timeout: int, min_bytes: int) -> tuple[str, int, int]:
    pdf = out_dir / f"{src.stem}.pdf"
    clean = profile / f"{src.stem}.clean.html"  # the page's own window.print() would block the export
    clean.write_text(re.sub(r"window\.print\(\)", "", src.read_text(errors="replace")))
    pdf.unlink(missing_ok=True)
    proc = subprocess.Popen(
        [chrome, "--headless=new", "--disable-gpu", "--disable-crash-reporter",
         f"--user-data-dir={profile}", "--no-pdf-header-footer",
         f"--print-to-pdf={pdf}", f"file://{clean.resolve()}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + timeout
    last, stable = -1, 0
    while time.time() < deadline:
        time.sleep(1)
        if proc.poll() is not None:
            break
        size = pdf.stat().st_size if pdf.exists() else -1
        stable = stable + 1 if size > 0 and size == last else 0
        if stable >= 2:
            break
        last = size
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
    if not pdf.exists():
        return ("render failed (no pdf)", 0, 0)
    size = pdf.stat().st_size
    if size < min_bytes:
        return (f"pdf too small ({size} B)", size, page_count(pdf))
    return ("ok", size, page_count(pdf))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("html", nargs="+", type=Path, help="HTML files to print")
    ap.add_argument("--out", type=Path, required=True, help="directory for the PDFs")
    ap.add_argument("--chrome", default=CHROME, help=f"Chrome binary (default: {CHROME})")
    ap.add_argument("--timeout", type=int, default=90, help="seconds to wait per file (default 90)")
    ap.add_argument("--min-bytes", type=int, default=10_000, help="smaller PDFs count as failed (default 10000)")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    failed = 0
    with tempfile.TemporaryDirectory(prefix="chrome-headless-") as tmp:
        for src in a.html:
            if not src.exists():
                status, size, pages = "missing html", 0, 0
            else:
                status, size, pages = render(src, a.out, a.chrome, Path(tmp), a.timeout, a.min_bytes)
            failed += status != "ok"
            print(f"{src.stem}\t{status}\t{size}\t{pages}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
