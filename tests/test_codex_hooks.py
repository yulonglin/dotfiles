#!/usr/bin/env python3
"""Exercise hook processes with real JSON payloads; command strings never execute."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HOOKS = Path(__file__).resolve().parents[1] / "codex" / "hooks"


class CodexHooksTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop("VIRTUAL_ENV", None)
        self.env.pop("CLAUDE_TOOL_INPUT", None)

    def run_hook(self, script, command="", mode=None, cwd=None, payload=None):
        executable = "bash" if script.endswith(".sh") else sys.executable
        arguments = [executable, str(HOOKS / script)]
        if mode:
            arguments.append(mode)
        if payload is None:
            payload = {"tool_name": "Bash", "tool_input": {"command": command},
                       "cwd": str(cwd or self.home)}
        return subprocess.run(arguments, input=json.dumps(payload), capture_output=True,
                              text=True, env=self.env, cwd=str(self.home), timeout=5)

    def context(self, result, event="PreToolUse"):
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(set(output), {"hookSpecificOutput"})
        specific = output["hookSpecificOutput"]
        self.assertEqual(specific["hookEventName"], event)
        self.assertEqual(set(specific), {"hookEventName", "additionalContext"})
        self.assertTrue(specific["additionalContext"])
        return specific["additionalContext"]

    def test_file_reads_are_silent_and_allowed(self):
        for command in ["cat README.md", "head -20 README.md", "tail -5 README.md",
                        "sed -n '1,20p' README.md", "bat --paging=never README.md"]:
            with self.subTest(command=command):
                result = self.run_hook("nudge_modern_tools.sh", command)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_modern_tool_advice_is_context_not_denial(self):
        for command, advice in [("grep needle README.md", "rg"),
                                ("find . -name '*.py'", "rg --files"),
                                ("sed -i 's/old/new/' file", "apply_patch")]:
            with self.subTest(command=command):
                message = self.context(self.run_hook("nudge_modern_tools.sh", command))
                self.assertIn(advice, message)
                for unavailable in ["Read tool", "Grep tool", "Edit tool", "Monitor", "bypass"]:
                    self.assertNotIn(unavailable, message)

    def test_dependency_context_and_non_install(self):
        for command in ["npm install example", "uv pip install example",
                        "python3 -m pip install example", "uv sync"]:
            with self.subTest(command=command):
                self.assertIn("dependencies", self.context(self.run_hook(
                    "context.py", command, mode="dependency-install")))
        result = self.run_hook("context.py", "python3 script.py", mode="dependency-install")
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_loop_denies_stdin_payload_including_multiline(self):
        for command in ["for x in 1; do sudo true; done",
                        "while true; do rm -rf sample; done",
                        "for x in 1\ndo\n  git reset --hard\ndone",
                        "for x in 1; do sudo true; for y in 2; do echo ok; done; done"]:
            with self.subTest(command=command):
                result = self.run_hook("check_loop_bypass.sh", command)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("BLOCKED", result.stderr)

    def test_benign_loops_and_non_loop_commands_are_allowed(self):
        for command in ["for x in 1; do echo ok; done", "while false\ndo\n echo ok\ndone",
                        "cat README.md", "git reset --hard"]:
            with self.subTest(command=command):
                result = self.run_hook("check_loop_bypass.sh", command)
                self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_loop_retains_literal_policy_for_quoted_patterns(self):
        result = self.run_hook("check_loop_bypass.sh", "for x in 1; do printf '%s' 'sudo true'; done")
        self.assertEqual(result.returncode, 2)

    def test_loop_ignores_legacy_input_environment(self):
        self.env["CLAUDE_TOOL_INPUT"] = json.dumps({"command": "for x in 1; do sudo true; done"})
        result = self.run_hook("check_loop_bypass.sh", "for x in 1; do echo ok; done")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_session_uses_payload_cwd_for_git_root(self):
        repo = self.home / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True, capture_output=True)
        child = repo / "nested"
        child.mkdir()
        self.env["PWD"] = "/stale/inherited/path"
        message = self.context(self.run_hook("context.py", mode="session-start", cwd=child), "SessionStart")
        self.assertIn(str(repo.resolve()), message)
        self.assertIn(str(child.resolve()), message)
        self.assertNotIn("/stale/inherited/path", message)
        result = self.run_hook("context.py", mode="session-start", cwd=repo)
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_session_detects_stale_environment_at_payload_cwd(self):
        project = self.home / "project"
        environment = project / ".venv"
        (environment / "bin").mkdir(parents=True)
        (environment / "bin" / "activate").write_text('VIRTUAL_ENV="/old/project/.venv"\n')
        self.env["VIRTUAL_ENV"] = "/another/.venv"
        message = self.context(self.run_hook("context.py", mode="session-start", cwd=project), "SessionStart")
        self.assertIn(str(environment.resolve()), message)
        self.assertIn("/another/.venv", message)
        self.assertIn("stale path /old/project/.venv", message)
        self.assertFalse((self.home / ".claude").exists())

    def test_session_does_not_fall_back_to_process_cwd(self):
        result = self.run_hook("context.py", mode="session-start", payload={})
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_session_notes_are_bounded_data_not_python_source(self):
        notes = self.home / "NOTES.md"
        # The prior shell hook interpolated this content into Python source.
        injected = "'" * 3 + "; open('executed', 'w').write('bad'); #"
        notes.write_text("OLD_PREFIX" + "x" * 20_000 + "\n" + injected)
        message = self.context(self.run_hook("context.py", mode="session-start"), "SessionStart")
        self.assertIn(injected, message)
        self.assertNotIn("OLD_PREFIX", message)
        self.assertLess(len(message.encode()), 16_600)
        self.assertFalse((self.home / "executed").exists())
        notes.write_text("\n".join("line-" + str(i) for i in range(130)))
        message = self.context(self.run_hook("context.py", mode="session-start"), "SessionStart")
        self.assertNotIn("\nline-9\n", message)
        self.assertIn("\nline-10\n", message)
        self.assertIn("\nline-129\n", message)

    def test_network_noop_and_isolated_json_log(self):
        result = self.run_hook("network_audit.py", "bat README.md")
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        log = self.home / ".cache" / "codex" / "network-audit.jsonl"
        self.assertFalse(log.exists())
        result = self.run_hook("network_audit.py", "curl https://example.com/status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("example.com", json.loads(result.stdout)["systemMessage"])
        entry = json.loads(log.read_text())
        self.assertEqual(entry["domains"], ["example.com"])
        self.assertEqual(entry["purpose"], "curl HTTP request")
        self.assertFalse((self.home / ".cache" / "claude").exists())

    def test_malformed_context_payload_is_silent(self):
        for payload in [None, [], {"tool_input": None}, {"tool_input": {"command": []}}]:
            if payload is None:
                payload = {"tool_input": None}
            result = self.run_hook("context.py", mode="modern-tools", payload=payload)
            self.assertEqual((result.returncode, result.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
