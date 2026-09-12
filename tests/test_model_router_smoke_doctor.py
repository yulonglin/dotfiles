"""Exercise the smoke script's actual doctor gate with synthetic CLI output."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DoctorGateTests(unittest.TestCase):
    def run_gate(self, data):
        script = (Path(__file__).parents[1] / "tests/test_model_router_gateway.sh").read_text()
        block = script.split("# doctor\n", 1)[1].split("# providers\n", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            bootstrap = Path(directory) / "bootstrap.sh"
            bootstrap.write_text('#!/bin/bash\nprintf "%s" "$DOCTOR_FIXTURE"\n')
            bootstrap.chmod(0o700)
            env = dict(os.environ, DOCTOR_FIXTURE=data, BOOTSTRAP_FIXTURE=str(bootstrap))
            preamble = 'bootstrap="$BOOTSTRAP_FIXTURE"; ok() { printf "PASS\\n"; }; fail() { printf "FAIL\\n"; };\n'
            result = subprocess.run(["/bin/bash", "-c", preamble + block], capture_output=True, text=True, env=env)
            return result.stdout.strip()

    def test_valid_complete_result_passes(self):
        self.assertEqual(self.run_gate(json.dumps({"checks": [{"name": "router", "ok": True}]})), "PASS")

    def test_malformed_or_empty_checks_never_pass(self):
        for data in ["not json", "{}", "[]", '{"checks": []}',
                     '{"checks":[{"name":"router","ok":"true"}]}',
                     '{"checks":[{"name":"config","ok":true}]}']:
            with self.subTest(data=data):
                self.assertEqual(self.run_gate(data), "FAIL")

    def test_failed_check_fails(self):
        self.assertEqual(self.run_gate(json.dumps({"checks": [{"name": "router", "ok": False}]})), "FAIL")


if __name__ == "__main__":
    unittest.main()
