"""Regression tests for custom_bins/figcheck-pdf.

The suite exists for one defect: the clipping gate reported clean on the worst
case. MuPDF's default structured text drops whatever falls outside the page box,
so a label that ran far enough off the page was absent from the extraction, and
absent text cannot fail a bounds check. A label poking 5 pt over the edge failed;
the same label 30 pt over passed. The direction tests below therefore matter more
than their line count suggests — the bug was position-dependent, so one fixture
proves nothing about its neighbour.

Every fixture is generated, so nothing binary is committed. Fixtures come from
the tool's own `minimal_pdf`, which is also what its startup probe measures; a
writer that emitted no text would fail the on-page control, not pass it.

Run: python3 -m unittest tests.test_figcheck_pdf   (or pytest tests/test_figcheck_pdf.py)
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "custom_bins" / "figcheck-pdf"

_spec = importlib.util.spec_from_loader(
    "figcheck_pdf", importlib.machinery.SourceFileLoader("figcheck_pdf", str(SCRIPT))
)
figcheck_pdf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(figcheck_pdf)


# Skipped test by test rather than raised at import, because tests/run-all.sh counts a
# Python suite as SKIP only when every test in it skipped, and reads a module-level
# SkipTest as a collection failure.
@unittest.skipIf(shutil.which("mutool") is None, "mutool (mupdf-tools) is not installed")
class FigcheckPdfTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)

    def pdf(self, name: str, text: str = "Hello world", x: float = 20, y: float = 100, **kwargs) -> Path:
        path = self.tmp / name
        path.write_bytes(figcheck_pdf.minimal_pdf([(text, x, y)], **kwargs))
        return path

    def merge(self, name: str, *pages: Path) -> Path:
        path = self.tmp / name
        subprocess.run(["mutool", "merge", "-o", str(path), *(str(p) for p in pages)],
                       capture_output=True, check=True)
        return path

    def check(self, pdf: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(SCRIPT), str(pdf), *args],
                              capture_output=True, text=True, check=False)

    def assertClipped(self, pdf: Path, *args: str) -> None:
        result = self.check(pdf, *args)
        self.assertEqual(result.returncode, 1, f"expected a reported problem\n{result.stdout}{result.stderr}")
        self.assertIn("CLIPPED", result.stdout)

    def assertClean(self, pdf: Path, *args: str) -> None:
        result = self.check(pdf, *args)
        self.assertEqual(result.returncode, 0, f"expected no problem\n{result.stdout}{result.stderr}")
        self.assertIn("0 problems", result.stdout)

    # ── the clipping gate ────────────────────────────────────────────────────

    def test_text_just_over_the_edge_is_reported(self):
        """The one clipping case that always worked: the tail pokes past the page box."""
        self.assertClipped(self.pdf("edge.pdf", x=190))

    def test_text_mostly_over_the_edge_is_reported(self):
        """Only 'He' survived the default extraction, ending at 200.3 on a 200 pt page."""
        self.assertClipped(self.pdf("mostly.pdf", x=185))

    def test_text_wholly_off_the_page_is_reported(self):
        """Nothing survived the default extraction, so the page read as empty and clean."""
        self.assertClipped(self.pdf("gone.pdf", x=220))

    def test_off_the_page_in_every_direction_is_reported(self):
        for direction, placement in [("left", {"x": -60}), ("right", {"x": 220}),
                                     ("above", {"y": 260}), ("below", {"y": -40})]:
            with self.subTest(direction=direction):
                self.assertClipped(self.pdf(f"{direction}.pdf", **placement))

    def test_off_the_page_is_reported_when_the_page_box_has_a_non_zero_origin(self):
        """A cropped paper page: the box starts at (100, 100), and the label sits left of it."""
        self.assertClipped(self.pdf("origin.pdf", x=50, y=150, box=(100, 100, 300, 300)))

    def test_text_cropped_off_the_visible_page_is_reported(self):
        """The page box is the CropBox: a label inside the MediaBox but outside the crop is gone."""
        wide = figcheck_pdf.minimal_pdf([("Outside the crop", 320, 200)], box=(0, 0, 400, 400))
        raw = self.tmp / "crop-raw.pdf"
        raw.write_bytes(wide.replace(b"/MediaBox [0 0 400 400]",
                                     b"/MediaBox [0 0 400 400] /CropBox [100 100 300 300]"))
        cropped = self.tmp / "crop.pdf"
        subprocess.run(["mutool", "clean", str(raw), str(cropped)], capture_output=True, check=True)
        self.assertClipped(cropped)

    def test_warn_reports_the_clipped_label_and_still_exits_zero(self):
        result = self.check(self.pdf("gone.pdf", x=220), "--warn")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CLIPPED", result.stdout)

    # ── what must not regress ────────────────────────────────────────────────

    def test_text_inside_the_page_is_clean(self):
        self.assertClean(self.pdf("clean.pdf"))

    def test_overlapping_lines_are_reported(self):
        path = self.tmp / "overlap.pdf"
        path.write_bytes(figcheck_pdf.minimal_pdf([("Alpha beta", 20, 100), ("Gamma delta", 30, 103)]))
        result = self.check(path)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("OVERLAP", result.stdout)

    def test_separated_lines_are_clean(self):
        path = self.tmp / "separated.pdf"
        path.write_bytes(figcheck_pdf.minimal_pdf([("Alpha beta", 20, 40), ("Gamma delta", 20, 100)]))
        self.assertClean(path)

    # ── which page was actually checked ──────────────────────────────────────

    def three_pages(self) -> Path:
        """Clean, clipped, clean — so a page number that slips reports the wrong verdict."""
        return self.merge("three.pdf",
                          self.pdf("one.pdf", "page one"),
                          self.pdf("two.pdf", "page two", x=220),
                          self.pdf("three.pdf", "page three"))

    def test_a_named_page_is_the_page_checked(self):
        document = self.three_pages()
        self.assertClipped(document, "--page", "2")
        self.assertClean(document, "--page", "3")

    def test_all_reaches_every_page(self):
        result = self.check(self.three_pages(), "--all")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for page in ("p1:", "p2:", "p3:"):
            self.assertIn(page, result.stdout)

    def test_a_page_past_the_end_is_a_usage_error(self):
        result = self.check(self.three_pages(), "--page", "99")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("out of range", result.stderr)
        self.assertNotIn("problems", result.stdout)

    def test_page_zero_is_a_usage_error(self):
        result = self.check(self.three_pages(), "--page", "0")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertNotIn("problems", result.stdout)

    def test_page_and_all_together_are_a_usage_error(self):
        result = self.check(self.three_pages(), "--all", "--page", "2")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertNotIn("problems", result.stdout)

    # ── the gate refuses rather than certifies what it cannot check ──────────

    def test_an_extraction_that_drops_off_page_text_refuses_to_report(self):
        """mutool ignores an unknown -O option silently, which would restore the defect."""
        source = SCRIPT.read_text()
        self.assertEqual(source.count('"mediabox-clip=no"'), 1)
        crippled = self.tmp / "figcheck-pdf-crippled"
        crippled.write_text(source.replace('"mediabox-clip=no"', '"bogus-option=yes"'))
        result = subprocess.run([sys.executable, str(crippled), str(self.pdf("clean.pdf")), "--warn"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("outside the page box", result.stderr)
        self.assertNotIn("problems", result.stdout)


if __name__ == "__main__":
    unittest.main()
