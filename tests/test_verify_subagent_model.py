#!/usr/bin/env python3
"""Pins claude/hooks/verify_subagent_model.py: which model answered a subagent.

Run: python3 tests/test_verify_subagent_model.py   (or via pytest / tests/run-all.sh)

Fixtures in tests/fixtures/verify_subagent_model/ are real subagent transcripts
from 2026-11-20 to 11-24, trimmed to the model-bearing fields (message.id renumbered,
all content, paths and session ids removed):

  agent-gemini-audit             gemini agent; replies google/gemini-4-neon, but
                                 requestedModel, api-request and the model
                                 attachment all say "gemini" (the decoys)
  agent-gemini-comments          gemini agent, longer run
  agent-general-purpose-advisor  Opus 5.5 agent with the advisor (Fable 5.2) on
                                 offer; Fable appears only in advisorModel, the
                                 advisor_tool attachment and the tool shape
  agent-astra                    codex route: "astra" answered as gpt-6.2-astra
  agent-gemini-silent-fallback   SYNTHETIC: gemini requested, Opus answered, plus
                                 an API-error and a <synthetic> record to skip

The router table is pinned (ROUTER_TOML below) so a roster edit in
config/model-router.toml cannot break these tests; one test checks that the
real file still parses the same way with and without tomllib.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HOOK = REPO / "claude" / "hooks" / "verify_subagent_model.py"
FIX = REPO / "tests" / "fixtures" / "verify_subagent_model"

ROUTER_TOML = """
[[models]]
id = "claude-opus-5-5"
provider = "anthropic"

[[models]]
id = "gpt-6.2-astra"
aliases = ["astra"]
provider = "codex"

[[models]]
id = "gemini-4-neon"
aliases = ["gemini"]
provider = "openrouter"
slug = "google/gemini-4-neon"
"""


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        (self.tmp / "router.toml").write_text(ROUTER_TOML)
        self.env = {
            **os.environ,
            "XDG_STATE_HOME": str(self.tmp / "state"),
            "MODEL_ROUTER_SOURCE": str(self.tmp / "router.toml"),
        }

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, str(HOOK), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def hook(self, payload):
        raw = payload if isinstance(payload, str) else json.dumps(payload)
        p = subprocess.run(
            [sys.executable, str(HOOK)],
            input=raw,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout) if p.stdout.strip() else None

    def stop_payload(self, name, session="sess-1", agent_id="a1"):
        return {
            "hook_event_name": "SubagentStop",
            "session_id": session,
            "agent_id": agent_id,
            "agent_type": "gemini",
            "agent_transcript_path": str(FIX / f"{name}.jsonl"),
            "transcript_path": str(self.tmp / "parent.jsonl"),
            "stop_hook_active": False,
        }

    def log_lines(self):
        path = self.tmp / "state" / "model-router" / "agent-model-checks.jsonl"
        return (
            [json.loads(x) for x in path.read_text().splitlines()]
            if path.exists()
            else []
        )


class RealTranscripts(Base):
    def check(self, name):
        p = self.cli("--transcript", str(FIX / f"{name}.jsonl"), "--json")
        return p.returncode, json.loads(p.stdout)

    def test_gemini_audit_answered_by_neon_not_the_alias(self):
        code, r = self.check("agent-gemini-audit")
        self.assertEqual(code, 0)
        self.assertEqual(r["verdict"], "match")
        self.assertEqual(
            r["actual"], {"google/gemini-4-neon": 12}
        )  # 40 records, 12 replies
        self.assertEqual(r["requested"], "gemini")
        self.assertEqual(r["expected_source"], "meta.json")

    def test_gemini_comments(self):
        code, r = self.check("agent-gemini-comments")
        self.assertEqual((code, r["actual"]), (0, {"google/gemini-4-neon": 44}))

    def test_advisor_model_is_not_counted_as_an_answer(self):
        code, r = self.check("agent-general-purpose-advisor")
        self.assertEqual(code, 0)
        self.assertEqual(r["actual"], {"claude-opus-5-5": 10})
        self.assertNotIn("claude-fable-5-2", json.dumps(r["actual"]))

    def test_codex_alias_resolves_through_router_table(self):
        code, r = self.check("agent-astra")
        self.assertEqual((code, r["actual"]), (0, {"gpt-6.2-astra": 12}))

    def test_requested_model_fallback_without_meta(self):
        shutil.copy(FIX / "agent-gemini-audit.jsonl", self.tmp / "agent-x.jsonl")
        p = self.cli("--transcript", str(self.tmp / "agent-x.jsonl"), "--json")
        r = json.loads(p.stdout)
        self.assertEqual((p.returncode, r["expected_source"]), (0, "requestedModel"))


class Mismatch(Base):
    def test_cli_reports_silent_fallback(self):
        p = self.cli("--transcript", str(FIX / "agent-gemini-silent-fallback.jsonl"))
        self.assertEqual(p.returncode, 1)
        self.assertIn(
            "agent 'gemini' answered from claude-opus-5-5 in 5/5 replies", p.stdout
        )
        self.assertIn("expected gemini-4-neon or google/gemini-4-neon", p.stdout)
        self.assertIn("this is the silent Claude fallback", p.stdout)

    def test_unlisted_route_counts_only_a_claude_answer(self):
        neon = self.cli(
            "--transcript",
            str(FIX / "agent-gemini-audit.jsonl"),
            "--expect",
            "zz-unlisted",
        )
        self.assertEqual(
            neon.returncode, 3
        )  # a different non-Claude name proves nothing
        opus = self.cli(
            "--transcript",
            str(FIX / "agent-gemini-silent-fallback.jsonl"),
            "--expect",
            "zz-unlisted",
        )
        self.assertEqual(opus.returncode, 1)
        self.assertIn("silent Claude fallback", opus.stdout)

    def test_inherit_is_logged_not_judged(self):
        p = self.cli(
            "--transcript",
            str(FIX / "agent-general-purpose-advisor.jsonl"),
            "--expect",
            "inherit",
        )
        self.assertEqual(p.returncode, 3)
        self.assertIn("inherits the parent's model", p.stdout)

    def test_expect_override(self):
        p = self.cli(
            "--transcript", str(FIX / "agent-gemini-audit.jsonl"), "--expect", "opus"
        )
        self.assertEqual(p.returncode, 1)
        self.assertIn("expected claude-opus-*", p.stdout)

    def test_mixed_transcript_counts_only_wrong_replies(self):
        rows = [
            {
                "type": "assistant",
                "requestedModel": "gemini",
                "message": {"id": f"m{i}", "model": m},
            }
            for i, m in enumerate(["google/gemini-4-neon"] * 3 + ["claude-opus-5-5"])
        ]
        t = self.tmp / "agent-mixed.jsonl"
        t.write_text("".join(json.dumps(r) + "\n" for r in rows))
        p = self.cli("--transcript", str(t))
        self.assertEqual(p.returncode, 1)
        self.assertIn("answered from claude-opus-5-5 in 1/4 replies", p.stdout)


class Resolution(Base):
    def load(self):
        spec = importlib.util.spec_from_file_location("vsm", HOOK)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_aliases(self):
        os.environ["MODEL_ROUTER_SOURCE"] = str(self.tmp / "router.toml")
        self.addCleanup(os.environ.pop, "MODEL_ROUTER_SOURCE", None)
        m = self.load()
        self.assertTrue(m.matches("claude-sonnet-5", m.accepted_names("sonnet")[0]))
        self.assertFalse(m.matches("claude-opus-5-5", m.accepted_names("sonnet")[0]))
        self.assertTrue(
            m.matches(
                "claude-opus-5-5-20261001", m.accepted_names("claude-opus-5-5[1m]")[0]
            )
        )
        self.assertTrue(
            m.matches("google/gemini-4-neon", m.accepted_names("gemini")[0])
        )
        self.assertTrue(m.matches("gemini-4-neon", m.accepted_names("gemini")[0]))
        self.assertFalse(m.matches("claude-opus-5-5", m.accepted_names("gemini")[0]))
        self.assertFalse(
            m.matches("claude-opus-5-5", m.accepted_names("kimi")[0])
        )  # unlisted name

    def test_fallback_parser_agrees_with_tomllib_on_real_router_file(self):
        if importlib.util.find_spec("tomllib") is None:
            self.skipTest("tomllib needs Python 3.11+")
        m = self.load()
        m.ROUTER_TOML = REPO / "config" / "model-router.toml"
        full = [
            (e.get("id"), e.get("slug"), tuple(e.get("aliases") or ()))
            for e in m.router_models()
        ]
        saved = sys.modules.pop("tomllib")
        sys.modules["tomllib"] = None  # force the ImportError path
        try:
            lite = [
                (e.get("id"), e.get("slug"), tuple(e.get("aliases") or ()))
                for e in m.router_models()
            ]
        finally:
            sys.modules["tomllib"] = saved
        self.assertEqual(full, lite)
        self.assertTrue(any(i == "gemini-4-neon" for i, _, _ in full))


class HookMode(Base):
    def test_mismatch_warns_user_and_never_steers_the_subagent(self):
        out = self.hook(self.stop_payload("agent-gemini-silent-fallback"))
        self.assertIn("claude-opus-5-5 in 5/5 replies", out["systemMessage"])
        self.assertNotIn("decision", out)  # would keep the subagent running
        self.assertNotIn(
            "hookSpecificOutput", out
        )  # additionalContext goes to the subagent
        [line] = self.log_lines()
        self.assertEqual(
            (line["verdict"], line["agent_id"], line["session_id"]),
            ("mismatch", "a1", "sess-1"),
        )

    def test_pending_note_reaches_main_model_once(self):
        self.hook(self.stop_payload("agent-gemini-silent-fallback"))
        # a tool call inside a subagent must not consume it
        self.assertIsNone(
            self.hook(
                {
                    "hook_event_name": "PostToolUse",
                    "session_id": "sess-1",
                    "agent_id": "other",
                    "tool_name": "Bash",
                }
            )
        )
        # another session does not see it
        self.assertIsNone(
            self.hook(
                {
                    "hook_event_name": "PostToolUse",
                    "session_id": "sess-2",
                    "tool_name": "Bash",
                }
            )
        )
        out = self.hook(
            {
                "hook_event_name": "PostToolUse",
                "session_id": "sess-1",
                "tool_name": "Bash",
            }
        )
        hso = out["hookSpecificOutput"]
        self.assertEqual(hso["hookEventName"], "PostToolUse")
        self.assertIn(
            "MISMATCH: agent 'gemini' answered from claude-opus-5-5",
            hso["additionalContext"],
        )
        self.assertIsNone(
            self.hook({"hook_event_name": "Stop", "session_id": "sess-1"})
        )
        self.assertFalse(
            (
                self.tmp / "state" / "model-router" / "agent-model-pending" / "sess-1"
            ).exists()
        )

    def test_stop_drains_mismatch(self):
        self.hook(self.stop_payload("agent-gemini-silent-fallback"))
        out = self.hook(
            {
                "hook_event_name": "Stop",
                "session_id": "sess-1",
                "stop_hook_active": False,
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "Stop")
        self.assertNotIn("decision", out)

    def test_foreign_match_confirms_at_next_tool_call(self):
        out = self.hook(self.stop_payload("agent-gemini-audit"))
        self.assertIn(
            "verified: answered from google/gemini-4-neon in 12/12",
            out["systemMessage"],
        )
        out = self.hook(
            {
                "hook_event_name": "PostToolUse",
                "session_id": "sess-1",
                "tool_name": "Read",
            }
        )
        self.assertIn("verified", out["hookSpecificOutput"]["additionalContext"])

    def test_stop_drops_match_notes_without_extending_the_turn(self):
        self.hook(self.stop_payload("agent-gemini-audit"))
        self.assertIsNone(
            self.hook({"hook_event_name": "Stop", "session_id": "sess-1"})
        )
        pending = self.tmp / "state" / "model-router" / "agent-model-pending"
        self.assertEqual(list(pending.iterdir()), [])  # shell gate closes again
        self.assertIsNone(
            self.hook(
                {
                    "hook_event_name": "PostToolUse",
                    "session_id": "sess-1",
                    "tool_name": "Read",
                }
            )
        )

    def test_claude_match_is_logged_only(self):
        payload = {
            **self.stop_payload("agent-general-purpose-advisor"),
            "agent_type": "general-purpose",
        }
        self.assertIsNone(self.hook(payload))
        self.assertEqual(self.log_lines()[0]["verdict"], "match")
        self.assertFalse(
            (self.tmp / "state" / "model-router" / "agent-model-pending").exists()
        )

    def test_fail_open(self):
        for payload in [
            "",
            "not json",
            "[1]",
            {
                "hook_event_name": "SubagentStop",
                "agent_transcript_path": "/nonexistent.jsonl",
            },
            {"hook_event_name": "SubagentStop"},
        ]:
            self.assertIsNone(self.hook(payload))
        # an unwritable state dir loses the log, never the warning
        (self.tmp / "state").write_text("a file, not a directory")
        out = self.hook(self.stop_payload("agent-gemini-silent-fallback"))
        self.assertIn("claude-opus-5-5 in 5/5", out["systemMessage"])
        self.assertIsNone(
            self.hook({"hook_event_name": "PostToolUse", "session_id": "sess-1"})
        )


class Cli(Base):
    def test_help_and_usage_errors(self):
        self.assertEqual(self.cli("--help").returncode, 0)
        self.assertEqual(
            self.cli("--transcript", str(self.tmp / "missing.jsonl")).returncode, 2
        )
        self.assertEqual(self.cli("--bogus").returncode, 2)

    def test_no_replies_is_indeterminate(self):
        t = self.tmp / "agent-empty.jsonl"
        t.write_text(
            json.dumps({"type": "api-request", "params": {"model": "gemini"}}) + "\n"
        )
        self.assertEqual(
            self.cli("--transcript", str(t), "--expect", "gemini").returncode, 3
        )


if __name__ == "__main__":
    unittest.main()
