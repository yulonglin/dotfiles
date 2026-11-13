"""Argument validation for custom_bins/xpost; no network calls required."""

import subprocess
import sys
import unittest
from pathlib import Path

XPOST = Path(__file__).resolve().parents[1] / "custom_bins" / "xpost"


class ArgumentTests(unittest.TestCase):
    def test_negative_parent_count_is_a_usage_error(self):
        for target in ("2083215259876417834", "@karpathy"):
            with self.subTest(target=target):
                result = subprocess.run(
                    [sys.executable, str(XPOST), "--parents", "-1", target],
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=5,
                )
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("--parents must be non-negative", result.stderr)


if __name__ == "__main__":
    unittest.main()
