"""Model-usage reporting from existing Claude Code records.

The audit must read persisted transcript and classifier usage, and may snapshot the
existing quota cache only when the command runs. Fixtures contain no real transcript
content, account identity, project path, or provider request.
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

AUDIT = Path(__file__).resolve().parent.parent / "custom_bins" / "claude-usage-audit"
_loader = importlib.machinery.SourceFileLoader("claude_usage_audit", str(AUDIT))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
audit = importlib.util.module_from_spec(_spec)
_loader.exec_module(audit)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def assistant_row(
    timestamp: str,
    *,
    message_id: str | None = None,
    request_id: str | None = None,
    uuid: str | None = None,
    model: str = "claude-test",
    input_tokens: int = 0,
    output_tokens: int = 0,
    cache_read: int = 0,
    cache_create: int = 0,
) -> dict:
    row = {
        "type": "assistant",
        "timestamp": timestamp,
        "message": {
            "model": model,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "cache_read_input_tokens": cache_read,
                "cache_creation_input_tokens": cache_create,
            },
            "content": [{"type": "text", "text": "fixture text must never enter output"}],
        },
    }
    if message_id is not None:
        row["message"]["id"] = message_id
    if request_id is not None:
        row["requestId"] = request_id
    if uuid is not None:
        row["uuid"] = uuid
    return row


def write_jsonl(path: Path, rows: list[object], malformed: str | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as fh:
        for row in rows:
            fh.write(json.dumps(row) + "\n")
        if malformed is not None:
            fh.write(malformed)


def read_jsonl(path: Path) -> list[dict]:
    records = []
    for line in path.read_text().splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            records.append(record)
    return records


def run_cli(home: Path, tmpdir: Path, *args: str) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update({"HOME": str(home), "TMPDIR": str(tmpdir)})
    return subprocess.run(
        [sys.executable, str(AUDIT), *args],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )


def test_transcript_usage_deduplicates_whole_snapshots_globally(tmp_path):
    """A retry snapshot must replace a response whole, not max each token field."""
    projects = tmp_path / "projects"
    day = datetime(2026, 9, 6, 10, tzinfo=timezone.utc)
    write_jsonl(
        projects / "one" / "a.jsonl",
        [
            assistant_row(iso(day), message_id="m1", request_id="r1", input_tokens=999, output_tokens=9),
            assistant_row(iso(day + timedelta(minutes=1)), message_id="m1", request_id="r1", input_tokens=5, output_tokens=10),
            assistant_row(iso(day + timedelta(minutes=2)), uuid="u2", input_tokens=10, output_tokens=3, cache_read=90),
        ],
    )
    write_jsonl(
        projects / "two" / "b.jsonl",
        [
            assistant_row(iso(day + timedelta(minutes=3)), message_id="m1", request_id="r1", input_tokens=4, output_tokens=10),
            assistant_row(iso(day + timedelta(minutes=4)), uuid="u2", input_tokens=20, output_tokens=3, cache_read=90),
            {"type": "assistant", "timestamp": iso(day), "message": {"usage": "not-an-object"}},
        ],
        malformed='{"type":"assistant"',
    )

    result = audit.scan_transcript_model_usage(projects, cutoff_epoch=0)

    assert result["requests"] == 2
    assert result["tokens"] == {
        "input_tokens": 25,
        "output_tokens": 13,
        "cache_read_input_tokens": 90,
        "cache_creation_input_tokens": 0,
        "total_tokens": 128,
    }
    assert result["cache_read_fraction"] == pytest.approx(90 / 115)
    assert result["by_model"]["claude-test"]["requests"] == 2
    assert result["by_day"]["2026-09-06"]["tokens"]["input_tokens"] == 25
    assert result["coverage"]["malformed_rows"] == 1


def test_transcript_usage_tolerates_bad_utf8(tmp_path):
    projects = tmp_path / "projects"
    path = projects / "one" / "session.jsonl"
    path.parent.mkdir(parents=True)
    valid = assistant_row("2026-09-06T00:00:00Z", uuid="valid", output_tokens=2)
    unusable = assistant_row("2026-09-06T00:01:00Z", uuid="bad", output_tokens=2)
    unusable["message"]["usage"]["input_tokens"] = -1
    path.write_bytes(
        json.dumps(valid).encode()
        + b"\n"
        + json.dumps(unusable).encode()
        + b"\n\xff\n"
    )

    result = audit.scan_transcript_model_usage(projects)

    assert result["requests"] == 1
    assert result["coverage"]["malformed_rows"] == 1
    assert result["coverage"]["unusable_usage_rows"] == 1


def test_transcript_equal_rank_dedup_is_path_deterministic(tmp_path):
    projects = tmp_path / "projects"
    timestamp = "2026-09-06T00:00:00Z"
    write_jsonl(
        projects / "z-created-first" / "session.jsonl",
        [assistant_row(timestamp, message_id="m", request_id="r", model="z-model", output_tokens=2)],
    )
    write_jsonl(
        projects / "a-created-second" / "session.jsonl",
        [assistant_row(timestamp, message_id="m", request_id="r", model="a-model", output_tokens=2)],
    )

    result = audit.scan_transcript_model_usage(projects)

    assert list(result["by_model"]) == ["a-model"]


@pytest.mark.parametrize("value", [-1, 1.5, float("inf"), float("nan")])
def test_numeric_tokens_rejects_invalid_counts(value):
    usage = {"input_tokens": value, "output_tokens": 1}

    assert audit.numeric_tokens(usage) is None


def test_transcript_usage_filters_each_top_level_timestamp_and_uses_uuid_fallback(tmp_path):
    """A recent file must not pull an old response through a file-mtime shortcut."""
    projects = tmp_path / "projects"
    cutoff = datetime(2026, 9, 5, tzinfo=timezone.utc)
    write_jsonl(
        projects / "one" / "session.jsonl",
        [
            assistant_row("2026-09-04T23:59:59Z", uuid="old", output_tokens=100),
            assistant_row("2026-09-05T00:00:01Z", uuid="new", output_tokens=7),
            assistant_row("not-a-date", uuid="bad-date", output_tokens=50),
            assistant_row("2026-09-06T00:00:00Z", output_tokens=60),
            ["arbitrary", "json"],
        ],
    )

    result = audit.scan_transcript_model_usage(projects, cutoff_epoch=cutoff.timestamp())

    assert result["requests"] == 1
    assert result["tokens"]["output_tokens"] == 7
    assert result["coverage"]["invalid_timestamp_rows"] == 1
    assert result["coverage"]["unkeyed_rows"] == 1


def test_approval_usage_is_separate_and_reports_retained_coverage(tmp_path):
    """The rotating approval log must expose its retained boundary, not claim all time."""
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        "2026-09-04T10:00:00Z USAGE: model=claude-a input=10 output=2 cache_read=90 cache_create=0\n"
        "2026-09-05T10:00:00Z unrelated diagnostic text\n"
        "2026-09-06T10:00:00Z USAGE: model=claude-a input=20 output=3 cache_read=80 cache_create=5\n"
        "2026-09-06T11:00:00Z USAGE: model=claude-b input=x output=3 cache_read=0 cache_create=0\n"
    )

    result = audit.scan_approval_usage(
        log,
        cutoff_epoch=datetime(2026, 9, 5, tzinfo=timezone.utc).timestamp(),
    )

    assert result["requests"] == 1
    assert result["tokens"]["total_tokens"] == 108
    assert result["by_model"]["claude-a"]["tokens"]["cache_creation_input_tokens"] == 5
    assert result["coverage"] == {
        "available": True,
        "earliest_retained_at": "2026-09-04T10:00:00Z",
        "latest_retained_at": "2026-09-06T10:00:00Z",
        "malformed_usage_lines": 1,
        "retention": "rotating_1mb_log",
    }


def test_quota_snapshot_uses_cache_mtime_allowlist_and_deduplicates(tmp_path):
    """A command rerun must not duplicate one cache observation or leak cache metadata."""
    cache = tmp_path / "tmp" / "claude-statusline-usage.json"
    history = tmp_path / "home" / ".claude" / "usage-data" / "quota-history.jsonl"
    cache.parent.mkdir()
    cache.write_text(json.dumps({
        "five_hour": {"utilization": 12.5, "resets_at": "2026-09-07T12:00:00+00:00", "secret": "drop-me"},
        "seven_day": {"utilization": 44, "resets_at": "private reset text"},
        "limits": [
            {"kind": "weekly_scoped", "percent": 33, "resets_at": "2026-09-13T12:00:00Z", "scope": {"model": {"display_name": "Fable"}}},
            {"kind": "unknown", "percent": 99, "scope": {"email": "private@example.test"}},
        ],
        "email": "private@example.test",
        "token": "not-a-real-token",
    }))
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    now = observed + timedelta(seconds=120)

    first = audit.snapshot_quota_cache(cache, history, now_epoch=now.timestamp())
    second = audit.snapshot_quota_cache(cache, history, now_epoch=now.timestamp())

    expected_buckets = [
        {"name": "five_hour", "utilization": 12.5, "resets_at": "2026-09-07T12:00:00Z"},
        {"name": "seven_day", "utilization": 44, "resets_at": None},
        {"name": "weekly_scoped:Fable", "utilization": 33, "resets_at": "2026-09-13T12:00:00Z"},
    ]
    assert first == {
        "available": True,
        "observed_at": "2026-09-07T10:00:00Z",
        "age_seconds": 120,
        "stale": False,
        "snapshot_added": True,
        "buckets": expected_buckets,
    }
    assert second["snapshot_added"] is False
    rows = read_jsonl(history)
    assert rows == [{
        "observed_at": "2026-09-07T10:00:00Z",
        "buckets": expected_buckets,
    }]
    stored = history.read_text()
    assert "private@example.test" not in stored
    assert "not-a-real-token" not in stored
    assert "drop-me" not in stored
    assert "private reset text" not in stored
    assert str(cache) not in stored


def test_quota_snapshot_keeps_current_buckets_when_history_write_fails(tmp_path):
    cache = tmp_path / "claude-statusline-usage.json"
    blocked_parent = tmp_path / "not-a-directory"
    blocked_parent.write_text("block history directory creation")
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))

    status = audit.snapshot_quota_cache(
        cache,
        blocked_parent / "quota-history.jsonl",
        now_epoch=observed.timestamp(),
    )

    assert status["history_write"] == "failed"
    assert status["buckets"] == [
        {"name": "five_hour", "utilization": 50, "resets_at": None}
    ]


def test_quota_append_separates_a_truncated_tail_and_missing_cache_is_explicit(tmp_path):
    """A broken final row must stay broken rather than consume the next valid snapshot."""
    cache = tmp_path / "tmp" / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    history.write_text('{"observed_at":"truncated"')
    cache.parent.mkdir()
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))

    status = audit.snapshot_quota_cache(cache, history, now_epoch=observed.timestamp() + 300)

    assert status["stale"] is True
    assert len(read_jsonl(history)) == 1
    assert "\n{" in history.read_text()
    missing = audit.snapshot_quota_cache(tmp_path / "absent.json", history, now_epoch=observed.timestamp())
    assert missing == {"available": False, "reason": "cache_missing"}
    invalid = tmp_path / "invalid-cache.json"
    invalid.write_bytes(b"\xff")
    assert audit.snapshot_quota_cache(invalid, history) == {
        "available": False,
        "reason": "cache_invalid",
    }


def test_quota_history_days_filter_keeps_all_time_coverage(tmp_path):
    """Period filtering must not erase the history's actual retained boundary."""
    history = tmp_path / "quota-history.jsonl"
    rows = [
        {"observed_at": "2026-09-01T00:00:00Z", "buckets": [{"name": "five_hour", "utilization": 10, "resets_at": None}]},
        {"observed_at": "2026-09-06T00:00:00Z", "buckets": [{"name": "five_hour", "utilization": 20, "resets_at": None}]},
    ]
    write_jsonl(history, rows, malformed="not-json")

    result = audit.read_quota_history(
        history,
        cutoff_epoch=datetime(2026, 9, 5, tzinfo=timezone.utc).timestamp(),
    )

    assert result["samples"] == [rows[1]]
    assert result["coverage"] == {
        "available": True,
        "earliest_retained_at": "2026-09-01T00:00:00Z",
        "latest_retained_at": "2026-09-06T00:00:00Z",
        "samples_in_period": 1,
        "malformed_rows": 1,
    }


def test_model_usage_cli_is_metadata_only_and_legacy_json_mode_survives(tmp_path):
    """The new mode must be explicit; the old component report stays the default."""
    home = tmp_path / "home"
    tmpdir = tmp_path / "tmp"
    now = datetime.now(timezone.utc).replace(microsecond=0)
    quota_cache = tmpdir / "claude-statusline-usage.json"
    quota_cache.parent.mkdir(parents=True)
    quota_cache.write_text(json.dumps({
        "five_hour": {
            "utilization": 25,
            "resets_at": iso(now + timedelta(hours=2)),
        }
    }))
    os.utime(quota_cache, (now.timestamp(), now.timestamp()))
    transcript = home / ".claude" / "projects" / "fixture" / "session.jsonl"
    write_jsonl(transcript, [
        assistant_row(iso(now), message_id="m", request_id="r", input_tokens=4, output_tokens=2),
        {
            "type": "assistant",
            "timestamp": iso(now),
            "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": "fixture-skill"}}]},
        },
    ])
    approval = home / ".cache" / "claude" / "approval-classifier.log"
    approval.parent.mkdir(parents=True)
    approval.write_text(f"{iso(now)} USAGE: model=claude-approval input=1 output=1 cache_read=0 cache_create=0\n")

    model_result = run_cli(home, tmpdir, "--model-usage", "--days", "1", "--json")
    text_result = run_cli(
        home,
        tmpdir,
        "--model-usage",
        "--days",
        "1",
        "--project",
        "fixture",
    )
    legacy_result = run_cli(home, tmpdir, "--json")

    assert model_result.returncode == 0, model_result.stderr
    model_report = json.loads(model_result.stdout)
    assert model_report["transcript_usage"]["requests"] == 1
    assert model_report["approval_classifier_usage"]["requests"] == 1
    assert model_report["quota"]["current"]["buckets"] == [
        {
            "name": "five_hour",
            "utilization": 25,
            "resets_at": iso(now + timedelta(hours=2)),
        }
    ]
    assert model_report["coverage"]["native_auto_mode_classifier"] == "successful calls unobserved"
    assert model_report["coverage"]["approval_classifier"] == (
        "direct API USAGE log only; CLI subscription fallback unobserved"
    )
    assert model_report["coverage"]["project_filter_scope"] == (
        "transcript only; approval and quota host-wide"
    )
    assert model_report["coverage"]["quota_history"] == (
        "unattributed; samples may interleave accounts; no identity recorded"
    )
    assert model_report["coverage"]["non_persisted_calls"] == "absent"
    assert "tokens are not subscription quota" in model_report["notes"]
    serialized = json.dumps(model_report)
    assert "fixture text" not in serialized
    assert str(home) not in serialized
    assert "session.jsonl" not in serialized

    assert text_result.returncode == 0, text_result.stderr
    assert now.date().isoformat() in text_result.stdout
    assert "Transcript by day" in text_result.stdout
    assert "Approval classifier by day" in text_result.stdout
    assert "persisted responses" in text_result.stdout
    assert " requests" not in text_result.stdout
    assert f"Approval log retained since {iso(now)}" in text_result.stdout
    assert "rotating 1 MB log" in text_result.stdout
    assert "direct API USAGE log only" in text_result.stdout
    assert "CLI subscription fallback is unobserved" in text_result.stdout
    assert "five_hour: 25% utilized" in text_result.stdout
    assert f"resets {iso(now + timedelta(hours=2))}" in text_result.stdout
    assert "sampled only when --model-usage runs" in text_result.stdout
    assert "without account attribution" in text_result.stdout
    assert "may interleave accounts" in text_result.stdout
    assert "no identity is recorded" in text_result.stdout
    assert "--project filters transcript usage only" in text_result.stdout

    assert legacy_result.returncode == 0, legacy_result.stderr
    legacy_report = json.loads(legacy_result.stdout)
    assert legacy_report["skills"] == {"fixture-skill": 1}
    assert "transcript_usage" not in legacy_report
