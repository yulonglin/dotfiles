"""Recovery decisions using isolated settings and mocked OS/network boundaries."""

import importlib.util
import http.client
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


MODULE = Path(__file__).resolve().parents[1] / "claude/hooks/ensure_model_router.py"


class RouterGuardTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), "router recovery hook is not implemented")
        spec = importlib.util.spec_from_file_location("router_guard", MODULE)
        self.guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.guard)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.token = "secret-ingress-token"
        self.base = "http://127.0.0.1:8787/t/" + self.token
        self.settings = self.home / ".claude/settings.json"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": self.base}}))
        state = self.home / ".local/state/model-router"
        (state / "launcher").mkdir(parents=True)
        (state / "ingress-token").write_text(self.token + "\n")
        self.launcher = state / "launcher/bootstrap.sh"
        self.launcher.write_text("#!/bin/bash\n")
        self.plist = self.home / "Library/LaunchAgents" / (self.guard.LABEL + ".plist")
        self.plist.parent.mkdir(parents=True)
        self.write_plist()
        self.calls = []
        self.state = "unloaded"
        self.loaded_launcher = self.launcher
        self.disabled = False
        self.bootstrap_code = 0
        self.now = 0.0
        self.addCleanup(patch.stopall)
        self.health = patch.object(self.guard, "healthy", return_value=False).start()
        patch.object(self.guard.subprocess, "run", side_effect=self.process).start()
        patch.object(self.guard.time, "monotonic", side_effect=lambda: self.now).start()
        patch.object(self.guard.time, "sleep", side_effect=self.sleep).start()

    def write_plist(self, **changes):
        config = {"Label": self.guard.LABEL,
                  "ProgramArguments": ["/bin/bash", str(self.launcher), "serve"]}
        config.update(changes)
        self.plist.write_bytes(plistlib.dumps(config))

    def sleep(self, seconds):
        self.now += seconds

    def process(self, args, **kwargs):
        self.calls.append(args)
        self.assertGreater(kwargs["timeout"], 0)
        self.assertLessEqual(kwargs["timeout"], 3)
        action = args[1]
        code, output = 0, ""
        if action == "print-disabled":
            output = 'disabled services = {\n "%s" => %s\n}' % (
                self.guard.LABEL, (str(self.disabled).lower() if isinstance(self.disabled, bool) else self.disabled))
        elif action == "print":
            code = 113 if self.state == "unloaded" else 0
            output = ("state = " + self.state + "\n\tpath = " + str(self.plist)
                      + "\n\tprogram = /bin/bash\n\targuments = {\n\t\t/bin/bash\n\t\t"
                      + str(self.loaded_launcher) + "\n\t\tserve\n\t}\n")
        elif action == "bootstrap":
            code = self.bootstrap_code
        return subprocess.CompletedProcess(args, code, output, "")

    def run_guard(self, event="UserPromptSubmit", **kwargs):
        return self.guard.ensure_router(event, home=self.home, env={}, system="Darwin", **kwargs)

    def actions(self):
        return [args[1] for args in self.calls]

    def test_missing_settings_and_explicit_off_skip(self):
        result = self.guard.ensure_router("SessionStart", home=self.home,
                                         env={"ANTHROPIC_BASE_URL": ""}, system="Darwin")
        self.assertIsNone(result)
        self.settings.unlink()
        self.assertIsNone(self.run_guard())
        self.health.assert_not_called()
        self.assertEqual(self.calls, [])

    def test_other_os_and_unowned_urls_skip(self):
        self.assertIsNone(self.guard.ensure_router("SessionStart", home=self.home, env={}, system="Linux"))
        for url in ["https://api.anthropic.com", "http://localhost:8787/t/" + self.token,
                    self.base + "/wrong", self.base + "?x=1", self.base.replace(self.token, "other")]:
            with self.subTest(url=url):
                self.assertIsNone(self.guard.ensure_router("SessionStart", home=self.home,
                                  env={"ANTHROPIC_BASE_URL": url}, system="Darwin"))
        self.health.assert_not_called()

    def test_healthy_is_silent_and_never_touches_launchctl(self):
        self.health.return_value = True
        self.assertIsNone(self.run_guard())
        self.assertEqual(self.calls, [])

    def test_unloaded_bootstraps_and_reports_recovery(self):
        self.health.side_effect = [False, True]
        result = self.run_guard()
        self.assertIn("recovered", result["systemMessage"].lower())
        self.assertEqual(self.actions(), ["print-disabled", "print", "bootstrap"])
        self.assertNotIn("decision", result)

    def test_loaded_stopped_kickstarts_without_killing(self):
        self.state = "waiting"
        self.health.side_effect = [False, True]
        self.assertIn("recovered", self.run_guard()["systemMessage"].lower())
        self.assertIn("kickstart", self.actions())
        self.assertFalse(any("-k" in args for args in self.calls))

    def test_loaded_stopped_foreign_definition_is_not_started(self):
        self.state = "waiting"
        self.loaded_launcher = Path("/tmp/unrelated-service.sh")
        result = self.run_guard()
        self.assertEqual(result["decision"], "block")
        self.assertNotIn("kickstart", self.actions())
        self.assertIn("loaded", result["reason"])

    def test_disabled_is_not_reenabled_and_blocks_prompt(self):
        self.disabled = True
        result = self.run_guard()
        self.assertEqual(result["decision"], "block")
        self.assertIn("disabled", result["reason"])
        self.assertEqual(self.actions(), ["print-disabled"])

    def test_launchctl_disabled_word_is_respected(self):
        self.disabled = "disabled"
        result = self.run_guard()
        self.assertEqual(result["decision"], "block")
        self.assertEqual(self.actions(), ["print-disabled"])

    def test_missing_token_and_nondefault_state_skip(self):
        self.assertIsNone(self.guard.ensure_router("SessionStart", home=self.home,
                          env={"XDG_STATE_HOME": "/tmp/unowned-state"}, system="Darwin"))
        (self.home / ".local/state/model-router/ingress-token").unlink()
        self.assertIsNone(self.run_guard())
        self.health.assert_not_called()

    def test_launchctl_timeout_is_bounded_and_redacted(self):
        self.guard.subprocess.run.side_effect = subprocess.TimeoutExpired(self.base, 3)
        result = self.run_guard()
        self.assertEqual(result["decision"], "block")
        self.assertIn("timed out", result["reason"])
        self.assertNotIn(self.token, json.dumps(result))

    def test_running_unhealthy_only_waits_then_blocks(self):
        self.state = "running"
        result = self.run_guard(budget=1)
        self.assertEqual(result["decision"], "block")
        self.assertIn("running", result["reason"])
        self.assertEqual(self.actions(), ["print-disabled", "print"])
        self.assertLessEqual(self.now, 1)

    def test_bootstrap_race_still_accepts_readiness(self):
        self.bootstrap_code = 5
        self.health.side_effect = [False, True]
        self.assertIn("recovered", self.run_guard()["systemMessage"].lower())

    def test_session_start_timeout_warns_without_block(self):
        result = self.run_guard("SessionStart", budget=1)
        self.assertIn("systemMessage", result)
        self.assertNotIn("decision", result)
        self.assertLessEqual(self.now, 1)

    def test_wrong_plist_never_loads_or_starts(self):
        for changes in [{"Label": "other"}, {"ProgramArguments": ["/bin/bash", "/tmp/other", "serve"]},
                        {"Program": "/tmp/unexpected"}]:
            with self.subTest(changes=changes):
                self.calls.clear()
                self.write_plist(**changes)
                self.assertEqual(self.run_guard()["decision"], "block")
                self.assertNotIn("bootstrap", self.actions())
                self.assertNotIn("kickstart", self.actions())

    def test_subprocess_error_redacts_secrets(self):
        self.guard.subprocess.run.side_effect = OSError(self.base)
        result = self.run_guard()
        self.assertEqual(result["decision"], "block")
        self.assertNotIn(self.token, json.dumps(result))
        self.assertNotIn(self.base, json.dumps(result))

    def test_malformed_settings_warns_without_secret_contents(self):
        self.settings.write_text(self.base)
        result = self.run_guard("SessionStart")
        self.assertIn("systemMessage", result)
        self.assertNotIn(self.token, json.dumps(result))


class HealthProbeTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("router_guard", MODULE)
        self.guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.guard)

    def test_probe_accepts_degraded_and_disables_proxy_and_redirect(self):
        response = MagicMock()
        response.status = 200
        response.read.return_value = b'{"status":"degraded","version":"1.0","cliproxy-upstream":"unavailable"}'
        response.__enter__.return_value = response
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(self.guard.urllib.request, "build_opener", return_value=opener) as build:
            self.assertTrue(self.guard.healthy("http://127.0.0.1:8787/t/synthetic", 0.7))
        handlers = build.call_args.args
        self.assertEqual(handlers[0].proxies, {})
        self.assertIsInstance(handlers[1], self.guard.NoRedirect)
        self.assertIsNone(handlers[1].redirect_request(None, None, 302, "", {}, "https://other"))
        opener.open.assert_called_once_with("http://127.0.0.1:8787/t/synthetic/__model-router/health", timeout=0.7)

    def test_unrelated_success_response_is_not_router_health(self):
        for data in [{"status": "ok"}, {"status": "ok", "version": "1.0"},
                     {"status": "ok", "version": "", "codex-upstream": "ready"}]:
            with self.subTest(data=data):
                response = MagicMock()
                response.status = 200
                response.read.return_value = json.dumps(data).encode()
                response.__enter__.return_value = response
                opener = MagicMock()
                opener.open.return_value = response
                with patch.object(self.guard.urllib.request, "build_opener", return_value=opener):
                    self.assertFalse(self.guard.healthy("http://127.0.0.1:8787/t/synthetic", 0.7))

    def test_truncated_http_response_is_unhealthy_not_a_crash(self):
        opener = MagicMock()
        opener.open.side_effect = http.client.IncompleteRead(b"partial")
        with patch.object(self.guard.urllib.request, "build_opener", return_value=opener):
            self.assertFalse(self.guard.healthy("http://127.0.0.1:8787/t/synthetic", 0.7))


if __name__ == "__main__":
    unittest.main()
