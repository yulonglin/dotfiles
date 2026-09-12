"""Update validation uses disposable homes and smoke scripts, never real upgrades."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "claude/hooks/check_model_router_update.py"


class UpdateCheckTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.exists(), "version-change checker is missing")
        spec = importlib.util.spec_from_file_location("router_update", SOURCE)
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo"
        self.state = self.home / ".local/state/model-router"
        self.state.mkdir(parents=True)
        (self.state / "ingress-token").write_text("private-ingress")
        self.settings = self.home / ".claude/settings.json"
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:8787/t/private-ingress"}}))
        self.binary = self.home / ".local/bin/claude"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("#!/bin/sh\nexit 0\n")
        self.binary.chmod(0o755)
        self.smoke = self.repo / "tests/test_model_router_gateway.sh"
        self.smoke.parent.mkdir(parents=True)
        self.counter = self.home / "runs"
        self.set_smoke("echo '[ok] doctor'\n")

    def set_smoke(self, body):
        self.smoke.write_text('test "$1" = --skip-probes || exit 7\n'
                              'test "$CLAUDE_BIN" = "$HOME/.local/bin/claude" || exit 8\n'
                              'echo run >> "$HOME/runs"\n' + body)

    def check(self, **kwargs):
        env = {"HOME": str(self.home), "PATH": os.environ["PATH"]}
        env.update(kwargs.pop("env", {}))
        return self.mod.check_update(home=self.home, repo=self.repo, env=env, **kwargs)

    def runs(self):
        return len(self.counter.read_text().splitlines()) if self.counter.exists() else 0

    def test_the_managed_drop_in_supplies_the_url_once_the_user_file_is_stripped(self):
        # `update-ai-tools` runs this checker from a plain shell, where nothing
        # exports ANTHROPIC_BASE_URL, and after the drop-in migration the user
        # settings file no longer carries it either. Without the drop-in in the
        # fallback chain the post-update validation silently skips.
        self.settings.write_text(json.dumps({"env": {"TMPDIR": "/tmp/claude"}}))
        self.assertEqual(self.check(), (0, None))
        self.assertEqual(self.runs(), 0)
        managed = self.home / "managed-settings.d/50-model-router.json"
        managed.parent.mkdir(parents=True)
        managed.write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:8787/t/private-ingress"}}))
        self.assertEqual(self.check(env={"MODEL_ROUTER_MANAGED": str(managed)})[0], 0)
        self.assertEqual(self.runs(), 1)

    def test_an_empty_base_url_in_the_environment_stays_an_explicit_off(self):
        managed = self.home / "managed-settings.d/50-model-router.json"
        managed.parent.mkdir(parents=True)
        managed.write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:8787/t/private-ingress"}}))
        self.assertEqual(self.check(env={"ANTHROPIC_BASE_URL": "", "MODEL_ROUTER_MANAGED": str(managed)}), (0, None))
        self.assertEqual(self.runs(), 0)

    def test_changed_then_unchanged_and_native_update(self):
        self.assertEqual(self.check()[0], 0)
        self.assertEqual(self.runs(), 1)
        self.assertEqual(self.check(), (0, None))
        self.assertEqual(self.runs(), 1)
        self.binary.write_text("#!/bin/sh\n# upgraded native version\nexit 0\n")
        self.assertEqual(self.check()[0], 0)
        self.assertEqual(self.runs(), 2)

    def test_router_launcher_and_plugin_changes(self):
        self.check()
        launcher = self.state / "launcher/binary-version"
        launcher.parent.mkdir()
        launcher.write_text("0.2.0")
        self.check()
        plugin = self.home / ".claude/plugins/cache/alignment-hive/model-router/0.2/.claude-plugin/plugin.json"
        plugin.parent.mkdir(parents=True)
        plugin.write_text('{"version":"0.2"}')
        registry = self.home / ".claude/plugins/installed_plugins.json"
        registry.write_text(json.dumps({"plugins": {"model-router@alignment-hive": [{"installPath": str(plugin.parents[1]), "version": "0.2"}]}}))
        with patch.object(self.mod, "versions_ready", return_value=True):
            self.check()
        self.assertEqual(self.runs(), 3)

    def test_failure_cooldown_and_force_retry(self):
        self.set_smoke("echo '[FAIL] providers unavailable'\nexit 1\n")
        self.assertNotEqual(self.check(now=1000)[0], 0)
        code, msg = self.check(now=1001)
        self.assertNotEqual(code, 0)
        self.assertIn("previous", msg)
        self.assertEqual(self.runs(), 1)
        self.assertNotEqual(self.check(force=True, now=1002)[0], 0)
        self.assertEqual(self.runs(), 2)
        self.assertNotEqual(self.check(now=1400)[0], 0)
        self.assertEqual(self.runs(), 3)
        saved = json.loads((self.state / "update-check/state.json").read_text())
        self.assertFalse(saved.get("success"))

    def test_failure_redacts_tokens_and_report_is_private_bounded(self):
        self.set_smoke("echo 'http://127.0.0.1:8787/t/private-ingress x-api-key: secret-credential Authorization: Bearer auth-secret'\n"
                       "echo 'OPENAI_API_KEY=sk-super-private'\n"
                       "printf '%02000d' 0\nexit 1\n")
        with patch.object(self.mod, "MAX_REPORT", 1024):
            code, msg = self.check()
        self.assertEqual(code, 1)
        report = self.state / "update-check/report.txt"
        text = report.read_text()
        for secret in ("private-ingress", "secret-credential", "auth-secret", "sk-super-private"):
            self.assertNotIn(secret, text + msg)
        self.assertLessEqual(report.stat().st_size, 32768)
        self.assertEqual(report.stat().st_mode & 0o777, 0o600)
        self.assertEqual(report.parent.stat().st_mode & 0o777, 0o700)

    def test_truncated_output_cannot_leak_partial_secret(self):
        self.set_smoke("echo http://" + "x" * 100 + "\nprintf '%0396d' 0\nprintf 'private-ingress-overflow\\n'\nexit 1\n")
        with patch.object(self.mod, "MAX_REPORT", 512):
            self.check()
        report = (self.state / "update-check/report.txt").read_text()
        self.assertNotIn("private-", report)

    def test_timeout_terminates_smoke_and_redacts_output(self):
        self.set_smoke("echo private-ingress\nsleep 5\n")
        code, msg = self.check(timeout=0.1)
        self.assertEqual(code, 1)
        self.assertIn("timed out", msg)
        self.assertNotIn("private-ingress", (self.state / "update-check/report.txt").read_text())

    def test_update_during_smoke_is_not_cached(self):
        self.set_smoke('echo "# update" >> "$HOME/.local/bin/claude"\n')
        code, msg = self.check()
        self.assertEqual(code, 1)
        self.assertIn("changed", msg)
        self.check()
        self.assertEqual(self.runs(), 2)

    def test_cached_success_does_not_hide_running_version_drift(self):
        self.check()
        with patch.object(self.mod, "versions_ready", return_value=False):
            code, msg = self.check()
        self.assertEqual(code, 1)
        self.assertIn("changed", msg)
        self.assertEqual(self.runs(), 2)

    def test_active_plugin_pin_matches_stable_and_running_version(self):
        root = self.home / ".claude/plugins/cache/alignment-hive/model-router/0.2"
        root.mkdir(parents=True)
        (root / "binary-version").write_text("0.2")
        (root.parents[3] / "installed_plugins.json").write_text(json.dumps({"plugins": {"model-router@alignment-hive": [{"installPath": str(root), "version": "0.2"}]}}))
        stable = self.state / "launcher/binary-version"
        stable.parent.mkdir()
        stable.write_text("0.1")
        self.assertFalse(self.mod.versions_ready(self.home, "http://127.0.0.1"))
        stable.write_text("0.2")
        from unittest.mock import MagicMock
        opener = MagicMock()
        opener.open.return_value.__enter__.return_value.read.return_value = b'{"version":"0.2"}'
        with patch.object(self.mod.urllib.request, "build_opener", return_value=opener):
            self.assertTrue(self.mod.versions_ready(self.home, "http://127.0.0.1"))
            opener.open.return_value.__enter__.return_value.read.return_value = b'{"version":"0.1"}'
            self.assertFalse(self.mod.versions_ready(self.home, "http://127.0.0.1"))
            opener.open.side_effect = self.mod.http.client.BadStatusLine("private-ingress")
            self.assertFalse(self.mod.versions_ready(self.home, "http://127.0.0.1"))

    def test_atomic_lock_prevents_duplicate_smoke(self):
        directory = self.state / "update-check"
        directory.mkdir()
        with (directory / "lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.check(), (0, None))
            self.assertNotEqual(self.check(force=True)[0], 0)
        self.assertEqual(self.runs(), 0)

    def test_unconfigured_disabled_or_unowned_is_noop(self):
        for url in ("", "https://api.anthropic.com", "http://127.0.0.1:8787/t/someone-else"):
            self.assertEqual(self.check(env={"ANTHROPIC_BASE_URL": url}), (0, None))
        self.settings.unlink()
        self.assertEqual(self.check(), (0, None))
        self.assertEqual(self.runs(), 0)


if __name__ == "__main__":
    unittest.main()
