#!/usr/bin/env python3
"""Pins the advisor gate: claude/hooks/nudge_advisor_skipped.py + advisor_seen.py.

Run: python3 tests/test_advisor_skipped.py   (or via pytest / tests/run-all.sh)

The load-bearing assertions are the SILENT ones. A gate that fires on a trivial
turn gets switched off, so the tests below spend most of their length proving
that a small session, a session where the advisor was already called, and a
session where the tool was never offered all pass through with no output. The
one-shot property is tested by calling the hook twice with the same session id.
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
SEEN = REPO / "claude" / "hooks" / "advisor_seen.py"


def tool_use(name: str, **inputs) -> dict:
    return {
        "type": "assistant",
        "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": "t", "name": name, "input": inputs},
        ]},
    }


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

    # --- it fires -----------------------------------------------------------
    def test_blocks_a_substantive_session_with_no_advisor_call(self) -> None:
        out = self.stop(self.substantive_rows())
        payload = json.loads(out)
        self.assertEqual(payload["decision"], "block")
        self.assertIn("advisor()", payload["reason"])
        # The reason must tell a model that DID call advisor how to get out,
        # because the marker channel can fail.
        self.assertIn("one-shot", payload["reason"])

    def test_bash_heredoc_edits_count_as_substantive(self) -> None:
        """Auto mode edits through Bash, so Edit/Write counts alone undercount."""
        rows = [
            advisor_offered(),
            tool_use("Bash", command="cat > /tmp/one.py <<'PY'\nx=1\nPY"),
            tool_use("Bash", command="sed -i '' s/a/b/ /tmp/two.py"),
            tool_use("Bash", command="tee /tmp/three.txt <<'EOF'\nx\nEOF"),
        ]
        self.assertTrue(self.stop(rows), "three Bash edits should trip the gate")

    def test_plain_output_redirects_do_not_count_as_edits(self) -> None:
        """Deliberately conservative: a scratch file is not a change to the repo."""
        rows = [advisor_offered()] + [
            tool_use("Bash", command="python3 scan.py > out-%d.txt" % i)
            for i in range(5)
        ]
        self.assertEqual(self.stop(rows), "")

    # --- it stays silent ----------------------------------------------------
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
        self.assertTrue(self.stop(rows, session="one-shot"))
        self.assertEqual(self.stop(rows, session="one-shot"), "",
                         "the gate must never fire twice in one session")

    # --- the marker channel -------------------------------------------------
    def test_marker_from_the_posttooluse_hook_suppresses_the_gate(self) -> None:
        self.run_hook(SEEN, {"tool_name": "advisor", "session_id": "marked",
                             "tool_input": {}, "tool_response": {}})
        self.assertTrue((self.state / "seen-marked").exists())
        self.assertEqual(self.stop(self.substantive_rows(), session="marked"), "")

    def test_marker_hook_ignores_other_tools(self) -> None:
        self.run_hook(SEEN, {"tool_name": "Bash", "session_id": "other"})
        self.assertFalse((self.state / "seen-other").exists())

    def test_marker_hook_survives_garbage(self) -> None:
        proc = subprocess.run([sys.executable, str(SEEN)], input="{",
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
