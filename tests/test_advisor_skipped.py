#!/usr/bin/env python3
"""Pins the advisor reminder: claude/hooks/nudge_advisor_skipped.py.

Run: python3 tests/test_advisor_skipped.py   (or via pytest / tests/run-all.sh)

The load-bearing assertions are the SILENT ones. A gate that fires on a trivial
turn gets switched off, so the tests below spend most of their length proving
that a small session, a session where the advisor was already called, and a
session where the tool was never offered all pass through with no output. The
one-shot property is tested by calling the hook twice with the same session id.
Every firing case also asserts the output carries no `decision` key: the hook is
a user-facing reminder and must never block a stop.

Advisor calls are synthesised the way Claude Code 2.1.296 records them: an
assistant `server_tool_use` block named `advisor`, then an `advisor_tool_result`.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GATE = REPO / "claude" / "hooks" / "nudge_advisor_skipped.py"


def tool_use(name: str, **inputs) -> dict:
    return {
        "type": "assistant",
        "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": "t", "name": name, "input": inputs},
        ]},
    }


def advisor_call(sidechain: bool = False) -> list[dict]:
    rows = [
        {"type": "assistant", "isSidechain": sidechain, "message": {
            "role": "assistant", "content": [
                {"type": "server_tool_use", "id": "srvtoolu_x", "name": "advisor",
                 "input": {}}]}},
        {"type": "assistant", "isSidechain": sidechain, "message": {
            "role": "assistant", "content": [
                {"type": "advisor_tool_result", "tool_use_id": "srvtoolu_x",
                 "content": {"type": "advisor_redacted_result",
                             "encrypted_content": "x"}}]}},
    ]
    return rows


def advisor_offered(available: bool = True, change: str = "add") -> dict:
    return {"attachment": {"type": "advisor_tool", "available": available,
                           "model": "claude-fable-5-1", "toolChange": change}}


class AdvisorGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.state = self.tmp / "state"
        self.addCleanup(self._tmp.cleanup)

    # --- helpers ------------------------------------------------------------
    def transcript(self, rows: list[dict], name: str = "t.jsonl") -> Path:
        path = self.tmp / name
        path.write_text("".join(json.dumps(r) + "\n" for r in rows))
        return path

    def run_hook(self, script: Path, payload: dict) -> str:
        proc = subprocess.run(
            [sys.executable, str(script)],
            input=json.dumps(payload), capture_output=True, text=True,
            env={"PATH": "/usr/bin:/bin", "HOME": str(self.tmp),
                 "CLAUDE_ADVISOR_STATE_DIR": str(self.state)},
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.strip()

    def stop(self, rows: list[dict], session: str = "s1", active: bool = False) -> str:
        return self.run_hook(GATE, {
            "session_id": session,
            "transcript_path": str(self.transcript(rows, name=session + ".jsonl")),
            "stop_hook_active": active,
        })

    @staticmethod
    def substantive_rows() -> list[dict]:
        return [
            advisor_offered(),
            tool_use("Read", file_path="/a"),
            tool_use("Edit", file_path="/a"),
            tool_use("Write", file_path="/b"),
            tool_use("Edit", file_path="/c"),
            tool_use("Bash", command="git commit -m done"),
        ]

    def assert_reminder(self, out: str) -> None:
        payload = json.loads(out)
        self.assertNotIn("decision", payload, "the reminder must never block a stop")
        self.assertNotIn("hookSpecificOutput", payload,
                         "additionalContext would continue the turn; not yet")
        self.assertIn("advisor()", payload["systemMessage"])

    # --- it fires -----------------------------------------------------------
    def test_warns_on_a_substantive_session_with_no_advisor_call(self) -> None:
        self.assert_reminder(self.stop(self.substantive_rows()))

    def test_a_subagent_advisor_call_does_not_count(self) -> None:
        """Only the main agent's own consultation satisfies its own contract."""
        rows = self.substantive_rows() + advisor_call(sidechain=True)
        self.assert_reminder(self.stop(rows))

    def test_bash_heredoc_edits_count_as_substantive(self) -> None:
        """Auto mode edits through Bash, so Edit/Write counts alone undercount."""
        rows = [
            advisor_offered(),
            tool_use("Bash", command="cat > /tmp/one.py <<'PY'\nx=1\nPY"),
            tool_use("Bash", command="sed -i '' s/a/b/ /tmp/two.py"),
            tool_use("Bash", command="tee /tmp/three.txt <<'EOF'\nx\nEOF"),
        ]
        self.assert_reminder(self.stop(rows))

    def test_plain_output_redirects_do_not_count_as_edits(self) -> None:
        """Deliberately conservative: a scratch file is not a change to the repo."""
        rows = [advisor_offered()] + [
            tool_use("Bash", command="python3 scan.py > out-%d.txt" % i)
            for i in range(5)
        ]
        self.assertEqual(self.stop(rows), "")

    # --- it stays silent ----------------------------------------------------
    def test_silent_when_the_transcript_shows_an_advisor_call(self) -> None:
        rows = self.substantive_rows()
        self.assertEqual(self.stop(rows[:2] + advisor_call() + rows[2:]), "")

    def test_silent_when_the_advisor_was_called_at_the_end(self) -> None:
        self.assertEqual(self.stop(self.substantive_rows() + advisor_call()), "")

    def test_another_server_tool_is_not_an_advisor_call(self) -> None:
        rows = self.substantive_rows() + [{"type": "assistant", "message": {
            "content": [{"type": "server_tool_use", "name": "web_search",
                         "id": "srvtoolu_y", "input": {}}]}}]
        self.assert_reminder(self.stop(rows))

    def test_silent_on_a_small_session(self) -> None:
        rows = [advisor_offered(), tool_use("Read", file_path="/a"),
                tool_use("Edit", file_path="/a"),
                tool_use("Bash", command="ls -la")]
        self.assertEqual(self.stop(rows), "")

    def test_silent_on_one_edit_and_its_commit(self) -> None:
        rows = [advisor_offered(), tool_use("Edit", file_path="/a"),
                tool_use("Bash", command="git commit -m typo")]
        self.assertEqual(self.stop(rows), "")

    def test_silent_when_read_only(self) -> None:
        rows = [advisor_offered()] + [tool_use("Read", file_path="/a")] * 20
        self.assertEqual(self.stop(rows), "")

    def test_silent_when_the_advisor_tool_was_never_offered(self) -> None:
        rows = [r for r in self.substantive_rows() if "attachment" not in r]
        self.assertEqual(self.stop(rows), "")

    def test_silent_when_the_advisor_tool_was_withdrawn(self) -> None:
        rows = self.substantive_rows() + [advisor_offered(False, "remove")]
        self.assertEqual(self.stop(rows), "")

    def test_silent_inside_a_stop_hook_continuation(self) -> None:
        self.assertEqual(self.stop(self.substantive_rows(), active=True), "")

    def test_silent_on_a_missing_transcript(self) -> None:
        out = self.run_hook(GATE, {"session_id": "s", "transcript_path": "/nope.jsonl"})
        self.assertEqual(out, "")

    def test_silent_on_garbage_input(self) -> None:
        proc = subprocess.run([sys.executable, str(GATE)], input="not json",
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "")

    # --- one-shot -----------------------------------------------------------
    def test_second_stop_passes(self) -> None:
        rows = self.substantive_rows()
        self.assert_reminder(self.stop(rows, session="one-shot"))
        self.assertEqual(self.stop(rows, session="one-shot"), "",
                         "the gate must never fire twice in one session")


if __name__ == "__main__":
    unittest.main(verbosity=2)
