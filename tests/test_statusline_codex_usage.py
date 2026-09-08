"""Codex statusline contract tests, with a local stdio app-server double.

Run with `uv run --no-project python tests/test_statusline_codex_usage.py`.
The dispatcher is the default target; CLAUDE_TOOLS_TEST_BIN can target a build.
No real authentication, network, or model generation is used.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BINARY = Path(
    os.environ.get("CLAUDE_TOOLS_TEST_BIN", REPO / "custom_bins/claude-tools")
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Only the external process is doubled. It enforces the actual handshake, leaves
# stdin open, and deliberately sends notifications/unrelated responses first.
SERVER = r"""#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ["CODEX_HOME"])
with (root / "calls").open("a") as f:
    f.write(str(os.getpid()) + "\n")
mode = (root / "mode").read_text()
assert sys.argv[1:] == ["app-server"]
if mode == "exit":
    sys.exit(1)
if mode == "timeout":
    time.sleep(30)
if mode == "malformed":
    print("not json", flush=True)
    time.sleep(30)
init = json.loads(sys.stdin.readline())
assert init == {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "claude_statusline", "version": "1"}}}
print(json.dumps({"method": "notice", "params": {}}), flush=True)
print(json.dumps({"id": 99, "result": {}}), flush=True)
print(json.dumps({"id": 1, "result": {"userAgent": "fixture"}}), flush=True)
assert json.loads(sys.stdin.readline()) == {"method": "initialized"}
assert json.loads(sys.stdin.readline()) == {"id": 2, "method": "account/rateLimits/read"}
if mode == "response_timeout":
    time.sleep(30)
if mode == "partial":
    sys.stdout.write('{"id":2,')
    sys.stdout.flush()
    time.sleep(30)
if mode == "rpc_error":
    print(json.dumps({"id": 2, "error": {"code": -32603, "message": "fixture error not for display"}}), flush=True)
else:
    print(json.dumps({"method": "notice", "params": {}}), flush=True)
    if mode == "colliding_request":
        print(json.dumps({"id": 2, "method": "server/request", "params": {}}), flush=True)
    print(json.dumps({"id": 2, "result": json.loads((root / "response").read_text())}), flush=True)
# A client using output()/wait_with_output() deadlocks here. The caller must
# consume the matching response while stdin is still open, then kill and reap.
assert sys.stdin.readline() == ""
time.sleep(30)
"""


def window(pct: int, minutes: int | None, reset: int | None = None) -> dict:
    return {"usedPercent": pct, "windowDurationMins": minutes, "resetsAt": reset}


def bucket(
    primary: dict | None,
    secondary: dict | None = None,
    name: str | None = None,
    limit_id: str | None = "codex",
) -> dict:
    return {
        "limitId": limit_id,
        "limitName": name,
        "primary": primary,
        "secondary": secondary,
        "credits": None,
        "planType": "pro",
        "individualLimit": None,
        "rateLimitReachedType": None,
        "spendControlReached": None,
    }


def response(aggregate: dict | None, extras: dict | None = None) -> dict:
    limits = {"codex": aggregate} if aggregate is not None else {}
    limits.update(extras or {})
    return {"rateLimits": aggregate or bucket(None), "rateLimitsByLimitId": limits}


class CodexUsageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(
            prefix="codex-statusline-", dir=os.environ.get("TMPDIR")
        )
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.codex = self.home / ".codex"
        self.bin = self.root / "bin"
        self.cache = self.root / "cache"
        self.tmp = self.root / "tmp"
        for path in (self.codex, self.bin, self.cache, self.tmp):
            path.mkdir(parents=True)
        executable = self.bin / "codex"
        executable.write_text(SERVER)
        executable.chmod(0o755)
        # Neutralize unrelated statusline helpers and date: Codex epochs must
        # never need an external date parser.
        for name in ("machine-name", "security", "date"):
            helper = self.bin / name
            helper.write_text("#!/bin/sh\nexit 1\n")
            helper.chmod(0o755)
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            CODEX_HOME=str(self.codex),
            XDG_CACHE_HOME=str(self.cache),
            TMPDIR=str(self.tmp),
            PATH=f"{self.bin}:{os.environ['PATH']}",
            CLAUDE_CODE_OAUTH_TOKEN="",
        )
        (self.codex / "auth.json").write_text("{}")  # metadata only; not a token
        (self.codex / "mode").write_text("success")
        self.set_response(response(bucket(window(64, 10080))))
        (self.tmp / "claude-statusline-usage.json").write_text(
            json.dumps(
                {"five_hour": {"utilization": 25}, "seven_day": {"utilization": 50}}
            )
        )

    def tearDown(self) -> None:
        # Failure must not leave a fake server behind, even during RED.
        for calls in self.home.rglob("calls"):
            for pid in calls.read_text().splitlines():
                try:
                    os.kill(int(pid), 9)
                except ProcessLookupError:
                    pass
        self.temp.cleanup()

    def set_response(self, value: dict) -> None:
        (self.codex / "response").write_text(json.dumps(value))

    def render(self) -> tuple[str, str]:
        process = subprocess.run(
            [str(BINARY), "statusline"],
            env=self.env,
            input=json.dumps(
                {
                    "workspace": {"current_dir": str(self.root)},
                    "model": {"display_name": "Opus"},
                }
            ),
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        self.assertEqual(process.stderr, "")
        output = ANSI.sub("", process.stdout)
        self.assertEqual(output.splitlines()[2], "5h ◔ 25% · 7d ◑ 50%")
        codex = "\n".join(
            line for line in output.splitlines() if line.startswith("Codex")
        )
        return codex, output

    def count_calls(self) -> int:
        calls = self.codex / "calls"
        return len(calls.read_text().splitlines()) if calls.exists() else 0

    def expire_cache(self) -> None:
        files = list(self.cache.rglob("codex-usage-*.json"))
        self.assertEqual(len(files), 1, "expected separate persistent Codex cache")
        value = json.loads(files[0].read_text())
        value["fetched_at"] = int(time.time()) - 600
        value["attempted_at"] = int(time.time()) - 600
        files[0].write_text(json.dumps(value))

    def assert_reaped(self) -> None:
        self.assertGreater(self.count_calls(), 0)
        for pid in (self.codex / "calls").read_text().splitlines():
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pid), 0)

    def test_primary_weekly_is_not_five_hour(self) -> None:
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")
        self.assert_reaped()

    def test_server_request_with_matching_id_is_not_a_response(self) -> None:
        (self.codex / "mode").write_text("colliding_request")
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")
        self.assert_reaped()

    def test_two_windows_use_durations_not_positions(self) -> None:
        self.set_response(response(bucket(window(80, 10080), window(25, 300))))
        self.assertEqual(self.render()[0], "Codex 7d ◕ 80% · 5h ◔ 25%")

    def test_named_model_quotas_are_hidden(self) -> None:
        # Spark is a separate per-model allowance; only the aggregate is shown.
        self.set_response(
            response(
                bucket(window(64, 10080)),
                {
                    "codex_bengalfox": bucket(
                        window(0, 300), window(0, 10080), "Spark", "codex_bengalfox"
                    )
                },
            )
        )
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")

    def test_model_only_map_is_not_aggregate(self) -> None:
        spark = bucket(window(30, 300), name="Spark", limit_id="codex_bengalfox")
        self.set_response(
            {"rateLimits": spark, "rateLimitsByLimitId": {"codex_bengalfox": spark}}
        )
        self.assertEqual(self.render()[0], "Codex usage unavailable")

    def test_legacy_aggregate_fallback(self) -> None:
        self.set_response(
            {"rateLimits": bucket(window(40, 300)), "rateLimitsByLimitId": None}
        )
        self.assertEqual(self.render()[0], "Codex 5h ◑ 40%")

    def test_legacy_model_fallback_is_not_aggregate(self) -> None:
        self.set_response(
            {
                "rateLimits": bucket(
                    window(40, 300), name="Spark", limit_id="codex_bengalfox"
                )
            }
        )
        self.assertEqual(self.render()[0], "Codex usage unavailable")

    def test_legacy_fallback_without_limit_id_is_aggregate(self) -> None:
        self.set_response({"rateLimits": bucket(window(40, 300), limit_id=None)})
        self.assertEqual(self.render()[0], "Codex 5h ◑ 40%")

    def test_unknown_duration_not_invented(self) -> None:
        self.set_response(response(bucket(window(20, None), window(45, 90))))
        self.assertEqual(self.render()[0], "Codex window? ◔ 20% · 90m ◑ 45%")

    def test_percentage_clamping(self) -> None:
        self.set_response(response(bucket(window(-2, 300), window(150, 10080))))
        self.assertEqual(self.render()[0], "Codex 5h ○ 0% · 7d ● 100%")

    def test_null_windows_are_not_zero_percent(self) -> None:
        self.set_response(response(bucket(None)))
        self.assertEqual(self.render()[0], "Codex usage unavailable")

    def test_invalid_window_is_not_zero_percent(self) -> None:
        self.set_response(
            response(bucket({"usedPercent": None, "windowDurationMins": 300}))
        )
        self.assertEqual(self.render()[0], "Codex usage unavailable")

    def test_pace_uses_epoch_without_date_process(self) -> None:
        self.set_response(response(bucket(window(25, 300, int(time.time()) + 9000))))
        self.assertIn("Codex 5h ◔ 25% -25% ⟳ 2h30m", self.render()[0])

    def test_past_reset_is_expired_not_current_usage(self) -> None:
        self.set_response(response(bucket(window(80, 300, int(time.time()) - 5))))
        self.assertEqual(self.render()[0], "Codex 5h ◕ 80% (expired)")

    def test_cache_hit_skips_process(self) -> None:
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")
        (self.codex / "mode").write_text("exit")
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")
        self.assertEqual(self.count_calls(), 1)

    def test_stale_refresh_failure_is_labelled_and_backed_off(self) -> None:
        self.render()
        self.expire_cache()
        (self.codex / "mode").write_text("rpc_error")
        self.assertIn("Codex 7d ◕ 64%", self.render()[0])
        self.assertIn("stale", self.render()[0])
        self.assertEqual(self.count_calls(), 2)

    def test_expired_cache_refreshes_successfully(self) -> None:
        self.render()
        self.expire_cache()
        self.set_response(response(bucket(window(12, 300))))
        self.assertEqual(self.render()[0], "Codex 5h ○ 12%")
        self.assertEqual(self.count_calls(), 2)

    def test_account_metadata_change_discards_old_usage(self) -> None:
        self.render()
        (self.codex / "auth.json").write_text('{"changed":true}')
        (self.codex / "mode").write_text("rpc_error")
        self.assertEqual(self.render()[0], "Codex usage unavailable")
        self.assertEqual(self.count_calls(), 2)

    def test_different_codex_home_has_separate_cache(self) -> None:
        self.render()
        self.codex = self.home / "other-codex"
        self.codex.mkdir()
        for name, text in (("auth.json", "{}"), ("mode", "success")):
            (self.codex / name).write_text(text)
        self.env["CODEX_HOME"] = str(self.codex)
        self.set_response(response(bucket(window(9, 300))))
        self.assertEqual(self.render()[0], "Codex 5h ○ 9%")
        self.assertEqual(len(list(self.cache.rglob("codex-usage-*.json"))), 2)

    def test_default_home_is_honored(self) -> None:
        self.env.pop("CODEX_HOME")
        self.assertEqual(self.render()[0], "Codex 7d ◕ 64%")

    def test_no_auth_omits_line_without_process(self) -> None:
        (self.codex / "auth.json").unlink()
        self.assertEqual(self.render()[0], "")
        self.assertEqual(self.count_calls(), 0)

    def test_logout_does_not_show_cached_usage(self) -> None:
        self.render()
        (self.codex / "auth.json").unlink()
        self.assertEqual(self.render()[0], "")
        self.assertEqual(self.count_calls(), 1)

    def test_missing_executable_omits_line(self) -> None:
        (self.bin / "codex").unlink()
        for name in ("bash", "uname", "dirname"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env["PATH"] = str(self.bin)  # no real Codex fallback
        self.assertEqual(self.render()[0], "")

    def test_display_names_never_reach_the_terminal(self) -> None:
        # Neither a named scope nor the aggregate's own name is rendered, so a
        # server-supplied name cannot inject control sequences or line breaks.
        hostile = "Bad\x1b[31m\nName"
        self.set_response(
            response(
                bucket(window(5, 300), name=hostile),
                {"custom": bucket(window(9, 300), name=hostile, limit_id="custom")},
            )
        )
        line, raw = self.render()
        self.assertEqual(line, "Codex 5h ○ 5%")
        self.assertEqual(len(raw.splitlines()), 4)

    def test_process_errors_are_bounded_and_reaped(self) -> None:
        # Each mode is isolated; failure backoff must not hide the next case.
        for mode in (
            "exit",
            "malformed",
            "timeout",
            "response_timeout",
            "partial",
            "rpc_error",
        ):
            with self.subTest(mode=mode):
                (self.codex / "auth.json").write_text(json.dumps({"case": mode}))
                (self.codex / "mode").write_text(mode)
                started = time.monotonic()
                self.assertEqual(self.render()[0], "Codex usage unavailable")
                self.assertLess(time.monotonic() - started, 3.5)
                self.assert_reaped()

    def test_failed_first_fetch_backoff(self) -> None:
        (self.codex / "mode").write_text("rpc_error")
        self.assertEqual(self.render()[0], "Codex usage unavailable")
        self.assertEqual(self.render()[0], "Codex usage unavailable")
        self.assertEqual(self.count_calls(), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
