"""Recovery decisions using isolated settings and mocked OS/network boundaries."""

import importlib.util
import http.client
import json
import plistlib
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
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
            output = ("\tstate = " + self.state + "\n\tpath = " + str(self.plist)
                      + "\n\tprogram = /bin/bash\n\targuments = {\n\t\t/bin/bash\n\t\t"
                      + str(self.loaded_launcher) + "\n\t\tserve\n\t}\n")
        elif action == "bootstrap":
            code = self.bootstrap_code
        return subprocess.CompletedProcess(args, code, output, "")

    def run_guard(self, event="UserPromptSubmit", **kwargs):
        return self.guard.ensure_router(event, home=self.home, env={}, system="Darwin", **kwargs)

    def actions(self):
        return [args[1] for args in self.calls]

    def incidents(self):
        return sorted((self.home / ".local/state/model-router/diagnostics").glob("incident-*.json"))

    def test_incident_written_before_mutation_and_completed_after(self):
        original = self.process
        def inspect(args, **kwargs):
            if args[1] == "bootstrap":
                paths = self.incidents()
                self.assertEqual(len(paths), 1)
                evidence = json.loads(paths[0].read_text())
                self.assertEqual(evidence["outcome"], "pending")
                self.assertEqual(evidence["action"], "bootstrap")
                self.assertEqual(evidence["launchctl"]["print"]["returncode"], 113)
            return original(args, **kwargs)
        self.guard.subprocess.run.side_effect = inspect
        self.health.side_effect = [False, True]
        result = self.run_guard()
        evidence = json.loads(self.incidents()[0].read_text())
        self.assertEqual(evidence["outcome"], "recovered")
        self.assertEqual(evidence["event"], "UserPromptSubmit")
        self.assertIn(str(self.incidents()[0]), result["systemMessage"])

    def test_incident_failure_preserved_with_no_secret_log_content(self):
        state = self.home / ".local/state/model-router"
        (state / "logs").mkdir()
        (state / "logs/router.log").write_text("ERROR token=" + self.token + " sk-sensitive-key\nStarted server\n")
        (state / "launcher/binary-version").write_text("0.8.1\n")
        self.state = "running"
        original = self.process
        def inspect(args, **kwargs):
            result = original(args, **kwargs)
            if args[1] == "print":
                result.stdout += "\tpid = 42\n\truns = 3\n\tlast exit code = 9\n\tlast terminating signal = Terminated: 15\n\tenvironment = {\n\t\tSECRET = " + self.token + "\n\t}\n"
            return result
        self.guard.subprocess.run.side_effect = inspect
        result = self.run_guard(budget=1)
        path = self.incidents()[0]
        text = path.read_text()
        evidence = json.loads(text)
        self.assertEqual(evidence["outcome"], "failed")
        self.assertEqual(evidence["launchctl"]["print"]["pid"], 42)
        self.assertEqual(evidence["launchctl"]["print"]["last_exit_signal"], 15)
        self.assertEqual(evidence["launchctl"]["print"]["last_exit_code"], 9)
        self.assertEqual(evidence["launchctl"]["print"]["runs"], 3)
        self.assertEqual(evidence["versions"]["stable"], "0.8.1")
        self.assertEqual(evidence["log"]["markers"]["error"], 1)
        self.assertNotIn(self.token, text)
        self.assertNotIn("sk-sensitive-key", text)
        self.assertNotIn("SECRET", text)
        self.assertIn(str(path), result["reason"])
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)

    def test_healthy_router_does_not_write_diagnostics(self):
        self.health.return_value = True
        self.assertIsNone(self.run_guard())
        self.assertFalse((self.home / ".local/state/model-router/diagnostics").exists())

    def test_incident_storage_failure_does_not_break_recovery(self):
        path = self.home / ".local/state/model-router/diagnostics"
        path.write_text("not a directory")
        self.health.side_effect = [False, True]
        result = self.run_guard()
        self.assertIn("recovered", result["systemMessage"].lower())
        self.assertIn("diagnostic capture failed", result["systemMessage"].lower())
        self.assertNotIn("decision", result)

    def test_log_tail_capture_is_bounded_and_version_text_is_allowlisted(self):
        state = self.home / ".local/state/model-router"
        (state / "logs").mkdir()
        (state / "logs/router.log").write_text("ERROR old\n" + "x" * 20000 + "\nStarted server\n")
        (state / "launcher/binary-version").write_text("0.8.1 sk-do-not-save")
        installed = self.home / ".claude/plugins/cache/alignment-hive/model-router/1.0"
        installed.mkdir(parents=True)
        (installed / "binary-version").write_text("0.8.2\n")
        self.health.side_effect = [False, True]
        self.run_guard()
        evidence = json.loads(self.incidents()[0].read_text())
        self.assertEqual(evidence["log"]["tail_bytes"], 16384)
        self.assertEqual(evidence["log"]["markers"]["error"], 0)
        self.assertEqual(evidence["versions"], {"stable": None, "cached_pins": ["0.8.2"]})
        self.assertNotIn("sk-do-not-save", self.incidents()[0].read_text())

    def test_private_incident_retention_and_concurrent_unique_paths(self):
        self.assertTrue(hasattr(self.guard, "Incident"), "incident capture is missing")
        def capture(_):
            incident = self.guard.Incident(self.home, "SessionStart")
            incident.update(outcome="failed")
            return incident.path
        with ThreadPoolExecutor(max_workers=4) as pool:
            paths = list(pool.map(capture, range(24)))
        self.assertEqual(len(set(paths)), 24)
        self.assertEqual(len(self.incidents()), 10)
        for path in self.incidents():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            json.loads(path.read_text())

    def test_missing_settings_and_explicit_off_skip(self):
        result = self.guard.ensure_router("SessionStart", home=self.home,
                                         env={"ANTHROPIC_BASE_URL": ""}, system="Darwin")
        self.assertIsNone(result)
        self.settings.unlink()
        self.assertIsNone(self.run_guard())
        self.health.assert_not_called()
        self.assertEqual(self.calls, [])

    def test_the_managed_drop_in_supplies_the_url_once_the_user_file_is_stripped(self):
        # The migrated user settings file carries no gateway key, so recovery
        # has to read the root-owned drop-in or it silently stops running.
        self.settings.write_text(json.dumps({"env": {"TMPDIR": "/tmp/claude"}}))
        self.assertIsNone(self.guard.ensure_router("SessionStart", home=self.home, env={}, system="Darwin"))
        self.health.assert_not_called()
        managed = self.home / "managed-settings.d/50-model-router.json"
        managed.parent.mkdir(parents=True)
        managed.write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": self.base}}))
        self.guard.ensure_router("SessionStart", home=self.home,
                                 env={"MODEL_ROUTER_MANAGED": str(managed)}, system="Darwin")
        self.health.assert_called()

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

    def test_loaded_stopped_accepts_canonical_path_to_same_plist(self):
        alias = self.home / "launchagents-alias"
        alias.symlink_to(self.plist.parent, target_is_directory=True)
        output = ("\tpath = " + str(self.plist)
                  + "\n\tprogram = /bin/bash\n\targuments = {\n\t\t/bin/bash\n\t\t"
                  + str(self.launcher) + "\n\t\tserve\n\t}\n")
        expected = ["/bin/bash", str(self.launcher), "serve"]
        self.assertTrue(self.guard.loaded_definition_matches(output, alias / self.plist.name, expected))
        self.assertFalse(self.guard.loaded_definition_matches(output, self.home / "missing.plist", expected))

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

    def test_mutation_timeout_still_polls_without_repeating_action(self):
        for action, healthy_after in [("bootstrap", True), ("kickstart", True),
                                      ("bootstrap", False), ("kickstart", False)]:
            with self.subTest(action=action, healthy_after=healthy_after):
                self.calls.clear()
                self.now = 0.0
                self.state = "unloaded" if action == "bootstrap" else "waiting"
                original = self.process
                def inspect(args, **kwargs):
                    result = original(args, **kwargs)
                    if args[1] == action:
                        self.now += 3
                        raise subprocess.TimeoutExpired(self.base, 3)
                    return result
                self.guard.subprocess.run.side_effect = inspect
                self.health.side_effect = [False, True] if healthy_after else None
                self.health.return_value = False
                result = self.run_guard(budget=4)
                if healthy_after:
                    self.assertIn("recovered", result["systemMessage"].lower())
                    self.assertNotIn("decision", result)
                else:
                    self.assertEqual(result["decision"], "block")
                    self.assertEqual(self.now, 4)
                self.assertEqual(self.actions().count(action), 1)
                evidence = json.loads(self.incidents()[-1].read_text())
                self.assertTrue(evidence["launchctl"][action]["timed_out"])
                self.assertNotIn(self.token, json.dumps(evidence))

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
