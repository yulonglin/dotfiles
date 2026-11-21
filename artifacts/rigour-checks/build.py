"""Inline checks.json into page.html, writing rigour-checks.html beside them,
then add the annotation layer (annotate-html, on PATH from custom_bins)."""

import json
import subprocess
from pathlib import Path

here = Path(__file__).parent
out = here / "rigour-checks.html"
checks = json.loads((here / "checks.json").read_text())
page = (here / "page.html").read_text()
data = json.dumps(checks, ensure_ascii=False).replace("</", "<\\/")
out.write_text(page.replace("/*__CHECKS__*/[]", data, 1))
subprocess.run(["annotate-html", "--key", "review-rigour-checks", str(out)], check=True)
