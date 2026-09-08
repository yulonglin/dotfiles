"""Backend outcomes of the custom PermissionRequest hook are recorded as metadata.

Why this file exists. The hook's two backends (API key, then the `claude`
subscription CLI) used to leave only human sentences in
`~/.cache/claude/approval-classifier.log`: "API BACKEND FAILED: …". Those
sentences cannot be counted per action, so nobody could say how often the
classifier failed, which failures the fallback recovered, or which category
they were.

Each backend outcome now writes ONE line whose payload is a versioned JSON
object, followed by the same human sentence the log always carried. The JSON
is metadata only — no command, no tool input, no prompt, no provider error
body — and carries an opaque per-action id so two backend failures for one
action are not read as two failed actions.

Scope: this covers the custom hook ONLY. Anthropic's built-in auto-mode
classifier is a different path and stays unobserved here.

No network, no `claude` CLI, no real log or health file.
"""

import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import urllib.error

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = pathlib.Path(
    os.environ.get("APPROVAL_CLASSIFIER_PATH")
    or ROOT / "claude" / "hooks" / "approval_classifier.py"
)
AUDIT = ROOT / "custom_bins" / "claude-usage-audit"

# Appears in the fixture tool input only. It must never reach the log.
SENTINEL = "SENTINEL-TOOL-INPUT-MUST-NOT-LEAK"
FIXTURE_COMMAND = f"frobnicate-{SENTINEL} --go"


def load_module(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def ac():
    return load_module(HOOK, "approval_classifier")


@pytest.fixture(scope="module")
def audit():
    return load_module(AUDIT, "claude_usage_audit")


def http_error(status, error_type, message):
    body = json.dumps({"type": "error", "error": {"type": error_type, "message": message}})
    return urllib.error.HTTPError(
        "https://api.anthropic.test/v1/messages",
        status,
        error_type,
        {},
        io.BytesIO(body.encode()),
    )


def run_hook(ac, monkeypatch, tmp_path, hook_input, *, api_raises, sub_run):
    """Drive main() with both backends stubbed and every real path redirected."""
    log_path = tmp_path / "approval-classifier.log"
    monkeypatch.setattr(ac, "LOG_PATH", str(log_path))
    monkeypatch.setattr(ac, "HEALTH_PATH", str(tmp_path / "health.json"))
    monkeypatch.setattr(
        ac,
        "detect_repo_trust",
        lambda cwd: {"remote_url": "", "owner": "", "trusted": False, "personal": False},
    )
    monkeypatch.setattr(ac, "repo_local_executables", lambda *a, **k: [])
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-not-a-real-key")
    monkeypatch.delenv(ac.NESTED_ENV, raising=False)

    def fake_urlopen(req, timeout=None):
        raise api_raises

    monkeypatch.setattr(ac.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(ac.subprocess, "run", sub_run)
    monkeypatch.setattr(ac.sys, "stdin", io.StringIO(json.dumps(hook_input)))

    ac.main()
    return log_path


def read_events(log_path):
    events = []
    decoder = json.JSONDecoder()
    for line in pathlib.Path(log_path).read_text().splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[1] == "BACKEND-EVENT":
            payload, _ = decoder.raw_decode(parts[2])
            events.append(payload)
    return events


def sub_ok(cmd, **kwargs):
    return subprocess.CompletedProcess(
        cmd,
        0,
        stdout=json.dumps({"is_error": False, "result": '{"decision":"allow","reason":"t"}'}),
        stderr="",
    )


def hook_input(**extra):
    payload = {
        "tool_name": "Bash",
        "tool_input": {"command": FIXTURE_COMMAND},
        "cwd": "/nonexistent-fixture-cwd",
        "transcript_path": "",
    }
    payload.update(extra)
    return payload


def test_api_failure_then_fallback_success_shares_one_action_id(ac, monkeypatch, tmp_path):
    """Two backend outcomes for one action must be one action, not two failures."""
    log_path = run_hook(
        ac,
        monkeypatch,
        tmp_path,
        hook_input(permission_mode="acceptEdits", session_id="session-uuid-fixture"),
        api_raises=http_error(429, "rate_limit_error", "rate limit exceeded"),
        sub_run=sub_ok,
    )

    events = read_events(log_path)
    assert [(e["backend"], e["outcome"]) for e in events] == [
        ("api", "failure"),
        ("subscription", "success"),
    ]
    assert {e["v"] for e in events} == {ac.BACKEND_EVENT_VERSION}
    assert events[0]["failure_category"] == "rate_limit"
    assert events[1]["failure_category"] is None
    assert events[0]["action"] == events[1]["action"]
    assert len(events[0]["action"]) >= 8
    assert all(e["tool"] == "Bash" for e in events)
    assert all(e["permission_mode"] == "acceptEdits" for e in events)
    assert all(e["permission_mode_observed"] is True for e in events)
    # Session is fingerprinted, never carried through in the clear.
    assert events[0]["session"] and events[0]["session"] != "session-uuid-fixture"
    assert events[0]["session"] == events[1]["session"]

    text = log_path.read_text()
    assert SENTINEL not in text
    # The human sentence the log always carried is still on the same line.
    assert "API BACKEND FAILED:" in text


def test_skipped_fallback_records_a_skip_and_an_absent_permission_mode(ac, monkeypatch, tmp_path):
    """No budget for the fallback is a distinct outcome, not a second failure."""
    monkeypatch.setattr(ac, "remaining_budget", lambda: 1.0)

    def sub_must_not_run(cmd, **kwargs):  # pragma: no cover - guard
        raise AssertionError("the fallback must not run when the budget is gone")

    log_path = run_hook(
        ac,
        monkeypatch,
        tmp_path,
        hook_input(),
        api_raises=http_error(500, "api_error", "internal server error"),
        sub_run=sub_must_not_run,
    )

    events = read_events(log_path)
    assert [(e["backend"], e["outcome"]) for e in events] == [
        ("api", "failure"),
        ("subscription", "skipped"),
    ]
    assert events[0]["failure_category"] == "other"
    assert events[1]["reason"] == "no_budget"
    # Absent is distinguishable from observed.
    assert events[0]["permission_mode"] == "unknown"
    assert events[0]["permission_mode_observed"] is False
    assert events[0]["session"] is None


def test_both_backends_failing_records_two_categorized_failures(
    ac, monkeypatch, tmp_path, capsys
):
    """A single action can carry two backend failures; both must be recorded."""

    def sub_times_out(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd, 18)

    log_path = run_hook(
        ac,
        monkeypatch,
        tmp_path,
        hook_input(permission_mode="default"),
        api_raises=http_error(529, "overloaded_error", "Overloaded"),
        sub_run=sub_times_out,
    )

    events = read_events(log_path)
    assert [(e["backend"], e["outcome"], e["failure_category"]) for e in events] == [
        ("api", "failure", "overloaded"),
        ("subscription", "failure", "timeout"),
    ]
    assert events[0]["action"] == events[1]["action"]
    # The user still sees the combined warning, but it is not a third log record:
    # both headlines are already on the two structured lines.
    assert "WARNING:" not in log_path.read_text()
    assert "subscription fallback also failed" in capsys.readouterr().err


def test_two_invocations_never_share_an_action_id(ac, monkeypatch, tmp_path):
    """An action is one classification attempt — a retry is a separate attempt."""
    first = run_hook(
        ac, monkeypatch, tmp_path / "a", hook_input(),
        api_raises=http_error(429, "rate_limit_error", "slow down"), sub_run=sub_ok,
    )
    second = run_hook(
        ac, monkeypatch, tmp_path / "b", hook_input(),
        api_raises=http_error(429, "rate_limit_error", "slow down"), sub_run=sub_ok,
    )
    assert read_events(first)[0]["action"] != read_events(second)[0]["action"]


@pytest.mark.parametrize(
    "scenario,expected_failures,expected_actions",
    [
        ("recovered", 1, {"observed": 1, "recovered": 1, "unresolved": 0, "incomplete": 0}),
        ("both_failed", 2, {"observed": 1, "recovered": 0, "unresolved": 1, "incomplete": 0}),
        ("skipped", 1, {"observed": 1, "recovered": 0, "unresolved": 1, "incomplete": 0}),
    ],
)
def test_what_the_hook_writes_is_what_the_audit_counts(
    ac, audit, monkeypatch, tmp_path, scenario, expected_failures, expected_actions
):
    """Round trip: the audit must read a real hook log, not a hand-written one.

    The loud warning the user sees on a total failure is still a plain WARNING
    line, and it restates the fallback's headline. It must not be counted a
    second time as a legacy record.
    """
    if scenario == "skipped":
        monkeypatch.setattr(ac, "remaining_budget", lambda: 1.0)

    def sub_times_out(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd, 18)

    log_path = run_hook(
        ac,
        monkeypatch,
        tmp_path,
        hook_input(),
        api_raises=http_error(429, "rate_limit_error", "rate limit exceeded"),
        sub_run=sub_ok if scenario == "recovered" else sub_times_out,
    )

    result = audit.scan_approval_failures(log_path)

    assert result["structured"]["backend_failures"]["total"] == expected_failures
    assert result["structured"]["actions"] == expected_actions
    assert result["legacy_unattributed"]["backend_failures"]["total"] == 0
    assert result["legacy_unattributed"]["fallback"] == {
        "succeeded": 0,
        "failed": 0,
        "skipped_no_budget": 0,
    }
    assert result["coverage"]["legacy_records"] == 0


CATEGORY_CASES = [
    # (status, error_type, message, expected category)
    (429, "rate_limit_error", "rate limit exceeded", "rate_limit"),
    (401, "authentication_error", "invalid x-api-key", "auth"),
    (403, "permission_error", "forbidden", "auth"),
    (400, "invalid_request_error", "your credit balance is too low", "credits"),
    (400, "invalid_request_error", "workspace api spend limit reached", "usage_limit"),
    (529, "overloaded_error", "Overloaded", "overloaded"),
    (500, "api_error", "internal server error", "other"),
]


def test_hook_and_audit_agree_on_every_shipped_failure_category(ac, audit):
    """The audit's fossil classifier for old log lines must match what the hook writes."""
    warnings = [
        (ac.classify_api_problem(status, etype, msg), expected)
        for status, etype, msg, expected in CATEGORY_CASES
    ]
    warnings += [
        (
            ac.ApprovalClassifierWarning(
                "The approval classifier could not reach the API.", "timed out", ""
            ),
            "timeout",
        ),
        (
            ac.ApprovalClassifierWarning(
                "The approval classifier could not reach the API.",
                "[Errno -2] Name or service not known",
                "",
            ),
            "network",
        ),
        (
            ac.ApprovalClassifierWarning(
                "ANTHROPIC_API_KEY is not set for the approval classifier hook.", "", ""
            ),
            "auth",
        ),
        (
            ac.ApprovalClassifierWarning(
                "The subscription classifier timed out after 18s.",
                "The API-key backend had already failed.",
                "",
            ),
            "timeout",
        ),
        (
            ac.ApprovalClassifierWarning(
                "Both classifier backends failed — API key AND subscription.",
                "Not logged in",
                "",
            ),
            "auth",
        ),
        (
            ac.ApprovalClassifierWarning(
                "The subscription classifier returned unreadable output.", "", ""
            ),
            "other",
        ),
    ]

    for warning, expected in warnings:
        assert ac.failure_category(warning.headline, warning.details) == expected, warning.headline
        assert (
            audit.legacy_failure_category(warning.headline, warning.details) == expected
        ), warning.headline
