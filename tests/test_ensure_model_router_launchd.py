"""Opt-in real launchd recovery test; uses a disposable service and HTTP fixture.

Run outside the sandbox on macOS:
  MODEL_ROUTER_LAUNCHD_TEST=1 python3 -m unittest discover -s tests -p '*router_launchd.py'
"""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch


@unittest.skipUnless(sys.platform == "darwin" and os.environ.get("MODEL_ROUTER_LAUNCHD_TEST") == "1",
                     "opt-in real macOS launchd integration")
class LaunchdRecoveryTest(unittest.TestCase):
    def test_unloaded_service_recovers_and_healthy_check_is_silent(self):
        spec = importlib.util.spec_from_file_location(
            "ensure_model_router", Path(__file__).parents[1] / "claude/hooks/ensure_model_router.py")
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)
        label = "com.alignment-hive.model-router.test." + str(os.getpid())
        target = "gui/{}/{}".format(os.getuid(), label)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with tempfile.TemporaryDirectory(prefix="router-launchd-") as temp:
            root = Path(temp)
            state = root / ".local/state/model-router"
            launcher = state / "launcher/bootstrap.sh"
            launcher.parent.mkdir(parents=True)
            (state / "ingress-token").write_text("synthetic-test-token")
            server = root / "server.py"
            server.write_text(textwrap.dedent("""
                import json, sys
                from http.server import HTTPServer, BaseHTTPRequestHandler
                class Handler(BaseHTTPRequestHandler):
                    def do_GET(self):
                        if self.path != '/t/synthetic-test-token/__model-router/health':
                            self.send_error(404)
                            return
                        body = json.dumps({'status': 'ok', 'version': 'test',
                                           'cliproxy-upstream': 'ready'}).encode()
                        self.send_response(200)
                        self.send_header('Content-Type', 'application/json')
                        self.send_header('Content-Length', str(len(body)))
                        self.end_headers()
                        self.wfile.write(body)
                    def log_message(self, *args):
                        pass
                HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
            """))
            launcher.write_text('#!/bin/bash\nexec /usr/bin/python3 "{}" {}\n'.format(server, port))
            launcher.chmod(0o700)
            plist = root / "Library/LaunchAgents" / (label + ".plist")
            plist.parent.mkdir(parents=True)
            plist.write_bytes(plistlib.dumps({
                "Label": label, "ProgramArguments": ["/bin/bash", str(launcher), "serve"],
                "RunAtLoad": True, "KeepAlive": False,
                "StandardOutPath": str(root / "stdout.log"),
                "StandardErrorPath": str(root / "stderr.log"),
            }))
            env = {"ANTHROPIC_BASE_URL": "http://127.0.0.1:{}/t/synthetic-test-token".format(port)}
            try:
                with patch.object(guard, "LABEL", label), patch.object(guard, "PORT", port):
                    recovered = guard.ensure_router("UserPromptSubmit", home=root, env=env, system="Darwin")
                    self.assertIsNotNone(recovered)
                    self.assertNotEqual(recovered.get("decision"), "block", recovered)
                    state_check = subprocess.run(["launchctl", "print", target], capture_output=True, text=True)
                    self.assertEqual(state_check.returncode, 0, state_check.stderr)
                    self.assertIn("state = running", state_check.stdout)
                    self.assertIsNone(guard.ensure_router("UserPromptSubmit", home=root, env=env, system="Darwin"))
            finally:
                subprocess.run(["launchctl", "bootout", target], capture_output=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
