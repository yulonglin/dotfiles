"""Model-usage reporting from existing Claude Code records.

The audit must read persisted transcript and classifier usage, and may snapshot the
existing quota cache only when the command runs. Fixtures contain no real transcript
content, account identity, project path, or provider request.
"""

import argparse
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
    for line in path.read_bytes().decode("utf-8", "replace").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            records.append(record)
    return records


def run_cli(
    home: Path, tmpdir: Path, *args: str, tz: str | None = None
) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.update({"HOME": str(home), "TMPDIR": str(tmpdir)})
    if tz is not None:
        env["TZ"] = tz
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
    assert result["coverage"]["unusable_usage_rows"] == 1


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

    first = audit.quota_report(cache, history, now_epoch=now.timestamp())
    second = audit.quota_report(cache, history, now_epoch=now.timestamp())

    expected_buckets = [
        {"name": "five_hour", "utilization": 12.5, "resets_at": "2026-09-07T12:00:00Z"},
        {"name": "seven_day", "utilization": 44, "resets_at": None},
        {"name": "weekly_scoped:Fable", "utilization": 33, "resets_at": "2026-09-13T12:00:00Z"},
    ]
    assert first["current"] == {
        "available": True,
        "observed_at": "2026-09-07T10:00:00Z",
        "age_seconds": 120,
        "stale": False,
        "snapshot_added": True,
        "buckets": expected_buckets,
    }
    assert second["current"]["snapshot_added"] is False
    expected_row = {"observed_at": "2026-09-07T10:00:00Z", "buckets": expected_buckets}
    rows = read_jsonl(history)
    assert rows == [expected_row]
    # The just-appended observation must still reach the same run's history section.
    assert first["history"]["samples"] == [expected_row]
    assert first["history"]["coverage"]["samples_in_period"] == 1
    assert second["history"]["samples"] == [expected_row]
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

    report = audit.quota_report(
        cache,
        blocked_parent / "quota-history.jsonl",
        now_epoch=observed.timestamp(),
    )

    assert report["current"]["history_write"] == "failed"
    assert report["current"]["snapshot_added"] is False
    assert report["current"]["buckets"] == [
        {"name": "five_hour", "utilization": 50, "resets_at": None}
    ]
    assert report["history"]["samples"] == []
    assert report["history"]["coverage"]["available"] is False


def test_quota_append_separates_a_truncated_tail_and_missing_cache_is_explicit(tmp_path):
    """A broken final row must stay broken rather than consume the next valid snapshot."""
    cache = tmp_path / "tmp" / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    history.write_text('{"observed_at":"truncated"')
    cache.parent.mkdir()
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))

    report = audit.quota_report(cache, history, now_epoch=observed.timestamp() + 300)

    assert report["current"]["stale"] is True
    assert len(read_jsonl(history)) == 1
    assert "\n{" in history.read_text()
    assert report["history"]["coverage"]["malformed_rows"] == 1
    missing = audit.quota_report(tmp_path / "absent.json", history, now_epoch=observed.timestamp())
    assert missing["current"] == {"available": False, "reason": "cache_missing"}
    # A missing cache must still not suppress the retained history.
    assert missing["history"]["coverage"]["samples_in_period"] == 1
    invalid = tmp_path / "invalid-cache.json"
    invalid.write_bytes(b"\xff")
    assert audit.quota_report(invalid, history)["current"] == {
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

    result = audit.quota_report(
        tmp_path / "absent-cache.json",
        history,
        cutoff_epoch=datetime(2026, 9, 5, tzinfo=timezone.utc).timestamp(),
    )["history"]

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
    assert model_report["coverage"]["native_auto_mode_classifier"] == (
        "persisted unavailability failures only; successful calls, retries, tokens and goal state unobserved"
    )
    assert model_report["coverage"]["approval_classifier"] == (
        "direct API USAGE log only; CLI subscription fallback is unobserved"
    )
    assert model_report["coverage"]["project_filter_scope"] == (
        "--project filters transcript usage and native failures only; approval and quota are host-wide"
    )
    assert model_report["coverage"]["quota_history"] == (
        "sampled only when --model-usage runs, without account attribution; "
        "samples may interleave accounts and no identity is recorded"
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
    assert "--project filters transcript usage and native failures only" in text_result.stdout

    assert legacy_result.returncode == 0, legacy_result.stderr
    legacy_report = json.loads(legacy_result.stdout)
    assert legacy_report["skills"] == {"fixture-skill": 1}
    assert "transcript_usage" not in legacy_report


@pytest.mark.parametrize(
    "value",
    [
        "2026-09-06T10:00:00",
        "2026-09-06T10:00:00.500000",
        "2026-09-06 10:00:00",
        "2026-09-06",
    ],
)
def test_parse_timestamp_rejects_a_timestamp_without_an_explicit_offset(value):
    """A naive stamp has no instant, so neither UTC nor local time may be assumed."""
    assert audit.parse_timestamp(value) is None
    assert audit.canonical_timestamp(value) is None


def test_parse_timestamp_keeps_offset_aware_stamps_and_canonicalizes_to_utc():
    assert audit.parse_timestamp("2026-09-06T10:00:00Z") == audit.parse_timestamp(
        "2026-09-06T05:00:00-05:00"
    )
    assert audit.canonical_timestamp("2026-09-06T05:00:00-05:00") == "2026-09-06T10:00:00Z"
    assert audit.canonical_timestamp("2026-09-06T12:00:00+02:00") == "2026-09-06T10:00:00Z"
    assert audit.canonical_timestamp("2026-09-06T10:00:00+00:00") == "2026-09-06T10:00:00Z"


def usage_row(uuid: str, message: dict) -> dict:
    return {
        "type": "assistant",
        "timestamp": "2026-09-06T10:00:00Z",
        "uuid": uuid,
        "message": dict(message),
    }


def test_a_present_but_unusable_usage_field_is_counted_and_an_absent_one_is_not(tmp_path):
    """Only a usage field that is there but unreadable makes the row corrupt."""
    projects = tmp_path / "projects"
    unusable_values = [None, "n/a", [], 5, True, {}, {"input_tokens": "x", "output_tokens": 1}]
    rows = [
        usage_row(f"unusable-{index}", {"model": "claude-test", "usage": value})
        for index, value in enumerate(unusable_values)
    ]
    rows.append(usage_row("no-usage-field", {"model": "claude-test"}))
    rows.append(assistant_row("2026-09-06T10:00:00Z", uuid="good", output_tokens=3))
    write_jsonl(projects / "one" / "session.jsonl", rows)

    result = audit.scan_transcript_model_usage(projects)

    assert result["requests"] == 1
    assert result["tokens"]["output_tokens"] == 3
    assert result["coverage"]["unusable_usage_rows"] == len(unusable_values)
    assert result["coverage"]["malformed_rows"] == 0
    assert result["coverage"]["invalid_timestamp_rows"] == 0
    assert result["coverage"]["unkeyed_rows"] == 0


def test_transcript_counts_a_naive_timestamp_as_invalid_and_keeps_the_offset_row(tmp_path):
    projects = tmp_path / "projects"
    write_jsonl(
        projects / "one" / "session.jsonl",
        [
            assistant_row("2026-09-06T10:00:00", uuid="naive", output_tokens=100),
            assistant_row("2026-09-06", uuid="date-only", output_tokens=200),
            assistant_row("2026-09-06T05:00:00-05:00", uuid="offset", output_tokens=7),
        ],
    )

    result = audit.scan_transcript_model_usage(projects)

    assert result["requests"] == 1
    assert result["tokens"]["output_tokens"] == 7
    assert result["coverage"]["invalid_timestamp_rows"] == 2
    assert result["coverage"]["earliest_in_period"] == "2026-09-06T10:00:00Z"


def test_the_other_parse_timestamp_callers_reject_naive_stamps_the_same_way(tmp_path):
    """Approval, quota history and reset times must not disagree about what parses."""
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        "2026-09-06T10:00:00 USAGE: model=claude-a input=1 output=1 cache_read=0 cache_create=0\n"
        "2026-09-06 USAGE: model=claude-a input=1 output=1 cache_read=0 cache_create=0\n"
        "2026-09-06T05:00:00-05:00 USAGE: model=claude-a input=2 output=3 cache_read=0 cache_create=0\n"
    )
    approval = audit.scan_approval_usage(log)
    assert approval["requests"] == 1
    assert approval["coverage"]["malformed_usage_lines"] == 2
    assert approval["coverage"]["earliest_retained_at"] == "2026-09-06T05:00:00-05:00"

    history = tmp_path / "quota-history.jsonl"
    bucket = [{"name": "five_hour", "utilization": 10, "resets_at": None}]
    write_jsonl(
        history,
        [
            {"observed_at": "2026-09-06T10:00:00", "buckets": bucket},
            {"observed_at": "2026-09-06", "buckets": bucket},
            {"observed_at": "2026-09-06T10:00:00Z", "buckets": bucket},
        ],
    )
    quota_history = audit.quota_report(tmp_path / "absent-cache.json", history)["history"]
    assert quota_history["coverage"]["malformed_rows"] == 2
    assert quota_history["coverage"]["earliest_retained_at"] == "2026-09-06T10:00:00Z"

    assert audit.quota_buckets({
        "five_hour": {"utilization": 10, "resets_at": "2026-09-07T12:00:00"},
        "seven_day": {"utilization": 20, "resets_at": "2026-09-07T07:00:00-05:00"},
    }) == [
        {"name": "five_hour", "utilization": 10, "resets_at": None},
        {"name": "seven_day", "utilization": 20, "resets_at": "2026-09-07T12:00:00Z"},
    ]


def test_model_usage_cli_output_does_not_depend_on_the_host_timezone(tmp_path):
    """Two hosts in different zones must report the same instants from the same records."""
    home = tmp_path / "home"
    tmpdir = tmp_path / "tmp"
    tmpdir.mkdir(parents=True)
    write_jsonl(
        home / ".claude" / "projects" / "fixture" / "session.jsonl",
        [
            assistant_row("2026-09-06T10:00:00Z", uuid="zulu", output_tokens=5),
            assistant_row("2026-09-06T05:00:00-05:00", uuid="offset", output_tokens=7),
            assistant_row("2026-09-06T10:00:00", uuid="naive", output_tokens=900),
            assistant_row("2026-09-06", uuid="date-only", output_tokens=900),
        ],
    )

    utc = run_cli(home, tmpdir, "--model-usage", "--json", tz="UTC0")
    est = run_cli(home, tmpdir, "--model-usage", "--json", tz="EST5EDT")

    assert utc.returncode == 0, utc.stderr
    assert est.returncode == 0, est.stderr
    assert utc.stdout == est.stdout
    transcript = json.loads(utc.stdout)["transcript_usage"]
    assert transcript["requests"] == 2
    assert transcript["tokens"]["output_tokens"] == 12
    assert transcript["coverage"]["invalid_timestamp_rows"] == 2
    assert transcript["coverage"]["earliest_in_period"] == "2026-09-06T10:00:00Z"
    assert transcript["coverage"]["latest_in_period"] == "2026-09-06T10:00:00Z"
    assert list(transcript["by_day"]) == ["2026-09-06"]


STAMP = "2026-09-06T10:00:00Z"


def test_streamed_rows_sharing_a_message_id_are_one_response(tmp_path):
    """Content blocks of one streamed response carry distinct row UUIDs and no requestId."""
    projects = tmp_path / "projects"
    write_jsonl(
        projects / "one" / "session.jsonl",
        [
            assistant_row(STAMP, message_id="m1", uuid="u1", output_tokens=1, input_tokens=999),
            assistant_row(STAMP, message_id="m1", uuid="u2", output_tokens=4, input_tokens=10),
            assistant_row(
                STAMP, message_id="m1", request_id="r1", uuid="u3", output_tokens=3, input_tokens=50
            ),
        ],
    )

    result = audit.scan_transcript_model_usage(projects)

    assert result["requests"] == 1
    # The whole highest-output snapshot wins; token fields are never maxed separately.
    assert result["tokens"]["output_tokens"] == 4
    assert result["tokens"]["input_tokens"] == 10


def test_request_id_keys_a_response_only_when_the_message_id_is_missing(tmp_path):
    projects = tmp_path / "projects"
    write_jsonl(
        projects / "one" / "session.jsonl",
        [
            assistant_row(STAMP, message_id="m1", request_id="shared", uuid="a", output_tokens=2),
            assistant_row(STAMP, message_id="m2", request_id="shared", uuid="b", output_tokens=3),
            assistant_row(STAMP, request_id="r9", uuid="c", output_tokens=5),
            assistant_row(STAMP, request_id="r9", uuid="d", output_tokens=7),
            assistant_row(STAMP, message_id="", request_id="r9", uuid="f", output_tokens=1),
            assistant_row(STAMP, uuid="e", output_tokens=11),
            assistant_row(STAMP, output_tokens=13),
        ],
    )

    result = audit.scan_transcript_model_usage(projects)

    assert result["requests"] == 4
    assert result["tokens"]["output_tokens"] == 23
    assert result["coverage"]["unkeyed_rows"] == 1


def test_model_usage_cli_survives_a_history_file_with_undecodable_bytes(tmp_path):
    """A damaged history must not abort the report, be rewritten, or be resampled."""
    home = tmp_path / "home"
    tmpdir = tmp_path / "tmp"
    cache = tmpdir / "claude-statusline-usage.json"
    cache.parent.mkdir(parents=True)
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    write_jsonl(
        home / ".claude" / "projects" / "fixture" / "session.jsonl",
        [assistant_row(STAMP, uuid="only", input_tokens=4, output_tokens=6)],
    )
    history = home / ".claude" / "usage-data" / "quota-history.jsonl"
    history.parent.mkdir(parents=True)
    seed = b"\xff\xfe{not json"
    history.write_bytes(seed)

    first = run_cli(home, tmpdir, "--model-usage", "--json")
    second = run_cli(home, tmpdir, "--model-usage", "--json")

    assert first.returncode == 0, first.stderr
    assert second.returncode == 0, second.stderr
    first_report = json.loads(first.stdout)
    second_report = json.loads(second.stdout)
    assert first_report["quota"]["current"]["snapshot_added"] is True
    assert second_report["quota"]["current"]["snapshot_added"] is False
    assert history.read_bytes().startswith(seed)
    assert len(read_jsonl(history)) == 1
    for report in (first_report, second_report):
        assert report["quota"]["history"]["coverage"]["malformed_rows"] == 1
        assert report["quota"]["history"]["coverage"]["samples_in_period"] == 1
        assert report["transcript_usage"]["requests"] == 1
        assert report["transcript_usage"]["tokens"]["total_tokens"] == 10


def test_quota_report_reads_the_history_once_per_run(tmp_path, monkeypatch):
    cache = tmp_path / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    opened = []
    real_open = Path.open

    def spy(self, *args, **kwargs):
        if self == history:
            opened.append(args[0] if args else kwargs.get("mode", "r"))
        return real_open(self, *args, **kwargs)

    monkeypatch.setattr(Path, "open", spy)

    report = audit.quota_report(cache, history, now_epoch=observed.timestamp())

    assert opened == ["a+b"]
    assert report["current"]["snapshot_added"] is True
    assert report["history"]["coverage"]["samples_in_period"] == 1
    assert report["history"]["samples"][0]["observed_at"] == report["current"]["observed_at"]


def test_a_damaged_row_does_not_suppress_the_sample_it_shares_a_timestamp_with(tmp_path):
    """Only a usable row proves an observation was already recorded."""
    cache = tmp_path / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    damaged = b'{"observed_at":"2026-09-07T10:00:00Z"}\n'
    history.write_bytes(damaged)

    first = audit.quota_report(cache, history, now_epoch=observed.timestamp())
    second = audit.quota_report(cache, history, now_epoch=observed.timestamp())

    assert first["current"]["snapshot_added"] is True
    assert second["current"]["snapshot_added"] is False
    assert history.read_bytes().startswith(damaged)
    assert len(read_jsonl(history)) == 2
    for report in (first, second):
        assert report["history"]["coverage"]["malformed_rows"] == 1
        assert report["history"]["coverage"]["samples_in_period"] == 1
        assert report["history"]["samples"][0]["buckets"] == [
            {"name": "five_hour", "utilization": 50, "resets_at": None}
        ]


def test_an_equivalent_offset_counts_as_the_same_recorded_observation(tmp_path):
    """Dedup is about instants, so a differently written same instant is not new."""
    cache = tmp_path / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    bucket = [{"name": "five_hour", "utilization": 50, "resets_at": None}]
    write_jsonl(
        history,
        [
            {"observed_at": "2026-09-07T10:00:00+00:00", "buckets": bucket},
            {"observed_at": "2026-09-07T05:00:00-05:00", "buckets": bucket},
        ],
    )
    seeded = history.read_bytes()

    first = audit.quota_report(cache, history, now_epoch=observed.timestamp())
    second = audit.quota_report(cache, history, now_epoch=observed.timestamp())

    assert first["current"]["observed_at"] == "2026-09-07T10:00:00Z"
    assert first["current"]["snapshot_added"] is False
    assert second["current"]["snapshot_added"] is False
    assert history.read_bytes() == seeded
    assert len(read_jsonl(history)) == 2
    assert first["history"]["coverage"]["samples_in_period"] == 2
    assert first["history"]["coverage"]["malformed_rows"] == 0


def test_history_samples_are_ordered_by_instant_not_by_timestamp_text(tmp_path):
    """Mixed precision and mixed offsets sort differently as text than as instants."""
    history = tmp_path / "quota-history.jsonl"
    absent_cache = tmp_path / "absent-cache.json"
    bucket = [{"name": "five_hour", "utilization": 10, "resets_at": None}]
    stamps = [
        "2026-09-06T10:00:00.500000Z",
        "2026-09-06T10:00:00Z",
        "2026-09-06T06:00:00-05:00",
        "2026-09-06T11:00:00+02:00",
    ]
    write_jsonl(history, [{"observed_at": stamp, "buckets": bucket} for stamp in stamps])

    result = audit.quota_report(absent_cache, history)["history"]

    assert [sample["observed_at"] for sample in result["samples"]] == [
        "2026-09-06T11:00:00+02:00",
        "2026-09-06T10:00:00Z",
        "2026-09-06T10:00:00.500000Z",
        "2026-09-06T06:00:00-05:00",
    ]
    assert result["coverage"]["earliest_retained_at"] == "2026-09-06T11:00:00+02:00"
    assert result["coverage"]["latest_retained_at"] == "2026-09-06T06:00:00-05:00"

    cutoff = datetime(2026, 9, 6, 10, 0, 0, 250000, tzinfo=timezone.utc)
    filtered = audit.quota_report(
        absent_cache, history, cutoff_epoch=cutoff.timestamp()
    )["history"]

    assert [sample["observed_at"] for sample in filtered["samples"]] == [
        "2026-09-06T10:00:00.500000Z",
        "2026-09-06T06:00:00-05:00",
    ]
    assert filtered["coverage"]["samples_in_period"] == 2
    # Period filtering must not shrink the retained boundary.
    assert filtered["coverage"]["earliest_retained_at"] == "2026-09-06T11:00:00+02:00"


def test_a_failed_append_still_reports_the_history_it_could_read(tmp_path, monkeypatch):
    """Losing the write must not also blank the retained history the reader can see."""
    cache = tmp_path / "claude-statusline-usage.json"
    history = tmp_path / "quota-history.jsonl"
    cache.write_text('{"five_hour":{"utilization":50,"resets_at":null}}')
    observed = datetime(2026, 9, 7, 10, tzinfo=timezone.utc)
    os.utime(cache, (observed.timestamp(), observed.timestamp()))
    bucket = [{"name": "five_hour", "utilization": 10, "resets_at": None}]
    write_jsonl(history, [{"observed_at": "2026-09-01T00:00:00Z", "buckets": bucket}])
    real_open = Path.open

    def refuse_append(self, *args, **kwargs):
        # Fail only the append handle, so the file stays genuinely readable.
        mode = args[0] if args else kwargs.get("mode", "r")
        if self == history and "a" in mode:
            raise PermissionError(13, "simulated append refusal")
        return real_open(self, *args, **kwargs)

    monkeypatch.setattr(Path, "open", refuse_append)

    report = audit.quota_report(cache, history, now_epoch=observed.timestamp())

    assert report["current"]["history_write"] == "failed"
    assert report["current"]["snapshot_added"] is False
    assert report["history"]["coverage"]["samples_in_period"] == 1
    assert report["history"]["coverage"]["earliest_retained_at"] == "2026-09-01T00:00:00Z"
    assert len(read_jsonl(history)) == 1


def test_project_filter_never_reads_an_excluded_project_directory(tmp_path, monkeypatch):
    """Excluding a project must skip its subtree, not read and then discard it."""
    projects = tmp_path / "projects"
    write_jsonl(projects / "keep-me" / "s.jsonl", [assistant_row(STAMP, uuid="k", output_tokens=5)])
    write_jsonl(
        projects / "skip-me" / "nested" / "s.jsonl",
        [assistant_row(STAMP, uuid="s", output_tokens=99)],
    )
    write_jsonl(projects / "root.jsonl", [assistant_row(STAMP, uuid="r", output_tokens=1)])
    excluded = str(projects / "skip-me")
    scanned = []
    real_scandir = os.scandir

    def spy(path=".", *args, **kwargs):
        scanned.append(os.path.normpath(os.fspath(path)))
        return real_scandir(path, *args, **kwargs)

    monkeypatch.setattr(os, "scandir", spy)

    filtered = audit.scan_transcript_model_usage(projects, project_filter="keep")

    assert filtered["requests"] == 1
    assert filtered["tokens"]["output_tokens"] == 5
    assert [path for path in scanned if path.startswith(excluded)] == []

    monkeypatch.undo()
    unfiltered = audit.scan_transcript_model_usage(projects)
    assert unfiltered["requests"] == 3
    assert unfiltered["tokens"]["output_tokens"] == 105


def test_a_project_filter_stays_fail_soft_on_an_unreadable_projects_root(tmp_path, monkeypatch):
    """Selecting projects must fail soft exactly as the unfiltered glob always did."""
    projects = tmp_path / "projects"
    write_jsonl(projects / "keep-me" / "s.jsonl", [assistant_row(STAMP, uuid="k", output_tokens=5)])
    root = os.path.normpath(str(projects))
    real_scandir = os.scandir

    def refuse_root(path=".", *args, **kwargs):
        if os.path.normpath(os.fspath(path)) == root:
            raise PermissionError(13, "simulated unreadable projects root")
        return real_scandir(path, *args, **kwargs)

    monkeypatch.setattr(os, "scandir", refuse_root)

    result = audit.scan_transcript_model_usage(projects, project_filter="keep")

    assert result["requests"] == 0
    assert result["coverage"]["earliest_in_period"] is None


def test_coverage_endpoints_do_not_depend_on_the_order_rows_are_read(tmp_path):
    """Only the extreme instants are reported, so aggregation needs no global sort."""
    projects = tmp_path / "projects"
    write_jsonl(
        projects / "one" / "session.jsonl",
        [
            assistant_row("2026-09-06T12:00:00Z", uuid="late", output_tokens=1),
            assistant_row("2026-09-06T08:00:00Z", uuid="early", output_tokens=1),
            assistant_row("2026-09-06T10:00:00Z", uuid="middle", output_tokens=1),
        ],
    )
    transcript = audit.scan_transcript_model_usage(projects)
    assert transcript["coverage"]["earliest_in_period"] == "2026-09-06T08:00:00Z"
    assert transcript["coverage"]["latest_in_period"] == "2026-09-06T12:00:00Z"

    log = tmp_path / "approval.log"
    log.write_text(
        "2026-09-06T12:00:00Z USAGE: model=a input=1 output=1 cache_read=0 cache_create=0\n"
        "2026-09-06T08:00:00Z USAGE: model=a input=1 output=1 cache_read=0 cache_create=0\n"
        "2026-09-06T10:00:00Z USAGE: model=a input=1 output=1 cache_read=0 cache_create=0\n"
    )
    approval = audit.scan_approval_usage(log)
    assert approval["coverage"]["earliest_retained_at"] == "2026-09-06T08:00:00Z"
    assert approval["coverage"]["latest_retained_at"] == "2026-09-06T12:00:00Z"

    history = tmp_path / "quota-history.jsonl"
    bucket = [{"name": "five_hour", "utilization": 10, "resets_at": None}]
    write_jsonl(
        history,
        [
            {"observed_at": "2026-09-06T12:00:00Z", "buckets": bucket},
            {"observed_at": "2026-09-06T08:00:00Z", "buckets": bucket},
            {"observed_at": "2026-09-06T10:00:00Z", "buckets": bucket},
        ],
    )
    quota = audit.quota_report(tmp_path / "absent-cache.json", history)["history"]
    assert quota["coverage"]["earliest_retained_at"] == "2026-09-06T08:00:00Z"
    assert quota["coverage"]["latest_retained_at"] == "2026-09-06T12:00:00Z"
    assert [sample["observed_at"] for sample in quota["samples"]] == [
        "2026-09-06T08:00:00Z",
        "2026-09-06T10:00:00Z",
        "2026-09-06T12:00:00Z",
    ]


def test_human_output_is_rendered_from_the_report_coverage_and_notes(tmp_path, capsys):
    """Editing an explanation in the report data must change the printed report too."""
    home = tmp_path / "home"
    tmpdir = tmp_path / "tmp"
    tmpdir.mkdir(parents=True)
    home.mkdir(parents=True)

    result = run_cli(home, tmpdir, "--model-usage", "--json")
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    sentinels = {key: f"sentinel-for-{key}" for key in data["coverage"]}
    assert set(sentinels) == {
        "native_auto_mode_classifier",
        "approval_classifier",
        "approval_classifier_failures",
        "project_filter_scope",
        "quota_history",
        "non_persisted_calls",
    }
    data["coverage"] = sentinels
    data["notes"] = ["sentinel-for-notes"]

    audit.print_model_usage_report(
        data, argparse.Namespace(json=False, days=0, project="fixture")
    )

    printed = capsys.readouterr().out
    for sentinel in sentinels.values():
        assert sentinel in printed
    assert "sentinel-for-notes" in printed


@pytest.mark.parametrize(
    "value,accepted",
    [
        (0, True),
        (5, True),
        (12.5, True),
        (-3, True),
        (True, False),
        (False, False),
        ("5", False),
        (None, False),
        (float("inf"), False),
        (float("nan"), False),
        ([], False),
        ({}, False),
    ],
)
def test_plain_and_scoped_buckets_accept_the_same_utilization_values(value, accepted):
    payload = {
        "five_hour": {"utilization": value, "resets_at": "2026-09-07T12:00:00Z"},
        "limits": [
            {
                "kind": "weekly_scoped",
                "percent": value,
                "resets_at": "2026-09-07T07:00:00-05:00",
                "scope": {"model": {"display_name": "Fable"}},
            }
        ],
    }

    buckets = audit.quota_buckets(payload)

    assert [bucket["name"] for bucket in buckets] == (
        ["five_hour", "weekly_scoped:Fable"] if accepted else []
    )
    for bucket in buckets:
        assert list(bucket) == ["name", "utilization", "resets_at"]
        assert bucket["resets_at"] == "2026-09-07T12:00:00Z"


def test_quota_bucket_builds_the_canonical_shape_or_rejects_the_value():
    assert audit.quota_bucket("five_hour", 12.5, "2026-09-07T07:00:00-05:00") == {
        "name": "five_hour",
        "utilization": 12.5,
        "resets_at": "2026-09-07T12:00:00Z",
    }
    assert audit.quota_bucket("five_hour", 0, "2026-09-07T12:00:00")["resets_at"] is None
    assert audit.quota_bucket("five_hour", True, None) is None
    assert audit.quota_bucket("five_hour", "50", None) is None
    assert audit.quota_bucket("five_hour", float("nan"), None) is None


# --- backend failure accounting for the custom PermissionRequest hook ---------
#
# Two log formats live in one rotating file, and they are mutually exclusive:
# a line written before this change starts with the human sentence, a line
# written after starts with BACKEND-EVENT and a versioned JSON payload. Old
# lines are counted but cannot be attributed to an action; new lines can.


def legacy_log() -> str:
    return (
        "2026-09-04T10:00:00Z API BACKEND FAILED: The approval classifier is rate limited. "
        "— HTTP 429: rate limit exceeded\n"
        "2026-09-04T10:00:01Z SUBSCRIPTION BACKEND: classified after the API backend failed\n"
        "2026-09-05T11:00:00Z API BACKEND FAILED: Anthropic API key appears to be out of credits. "
        "— HTTP 400: your credit balance is too low\n"
        "2026-09-05T11:00:01Z SUBSCRIPTION BACKEND SKIPPED: only 2.0s of budget left\n"
        "2026-09-05T12:00:00Z API BACKEND FAILED: The approval classifier could not reach the API. "
        "— timed out\n"
        "2026-09-05T12:00:30Z WARNING: The approval classifier could not reach the API. — timed out "
        "— subscription fallback also failed: The subscription classifier timed out after 18s.\n"
        "2026-09-05T13:00:00Z WARNING: The approval classifier's rules file could not be read. — /x/y\n"
        "2026-09-05T13:30:00Z ALLOW (fast-path): Bash — read-only lookup\n"
        "2026-09-05T14:00:00Z USAGE: model=claude-a input=1 output=1 cache_read=0 cache_create=0\n"
    )


def event_line(timestamp: str, payload: dict, human: str = "") -> str:
    tail = f" {human}" if human else ""
    return f"{timestamp} BACKEND-EVENT {json.dumps(payload)}{tail}\n"


def event(backend, outcome, *, action, category=None, **extra) -> dict:
    payload = {
        "v": 1,
        "backend": backend,
        "outcome": outcome,
        "failure_category": category,
        "action": action,
        "session": "0123456789abcdef",
        "tool": "Bash",
        "permission_mode": "default",
        "permission_mode_observed": True,
    }
    payload.update(extra)
    return payload


def test_legacy_failure_lines_are_counted_by_backend_and_category_but_unattributed(tmp_path):
    """Old human lines carry no action id, so they may be counted and never attributed."""
    log = tmp_path / "approval-classifier.log"
    log.write_text(legacy_log())

    result = audit.scan_approval_failures(log)

    legacy = result["legacy_unattributed"]
    assert legacy["backend_failures"]["total"] == 4
    assert legacy["backend_failures"]["by_backend"] == {"api": 3, "subscription": 1}
    assert legacy["backend_failures"]["by_category"] == {
        "credits": 1,
        "rate_limit": 1,
        "timeout": 2,
    }
    assert legacy["fallback"] == {"succeeded": 1, "failed": 1, "skipped_no_budget": 1}
    assert legacy["by_day"] == {"2026-09-04": 1, "2026-09-05": 3}
    # No per-action attribution is claimed for the legacy era.
    assert "actions" not in legacy
    assert result["structured"]["backend_failures"]["total"] == 0
    assert result["structured"]["actions"]["observed"] == 0
    # Four failures plus the fallback's success and its skip; the rules-file
    # warning, the fast-path allow and the USAGE row are not backend outcomes.
    assert result["coverage"]["legacy_records"] == 6
    assert result["coverage"]["structured_records"] == 0
    assert result["coverage"]["structured_first_at"] is None
    assert result["coverage"]["earliest_record_at"] == "2026-09-04T10:00:00Z"
    assert result["coverage"]["latest_record_at"] == "2026-09-05T12:00:30Z"


def test_cutoff_filters_failure_counts_but_keeps_the_retained_boundary(tmp_path):
    log = tmp_path / "approval-classifier.log"
    log.write_text(legacy_log())

    result = audit.scan_approval_failures(
        log, cutoff_epoch=datetime(2026, 9, 5, tzinfo=timezone.utc).timestamp()
    )

    assert result["legacy_unattributed"]["backend_failures"]["total"] == 3
    assert result["legacy_unattributed"]["fallback"] == {
        "succeeded": 0,
        "failed": 1,
        "skipped_no_budget": 1,
    }
    assert result["coverage"]["earliest_record_at"] == "2026-09-04T10:00:00Z"


def test_structured_events_attribute_actions_and_split_failures_from_failed_actions(tmp_path):
    """Two backend failures on one action are one failed action, not two."""
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        # Recovered action: API failed, fallback succeeded.
        event_line(
            "2026-09-06T10:00:00Z",
            event("api", "failure", action="a1", category="rate_limit"),
            "API BACKEND FAILED: The approval classifier is rate limited. — HTTP 429",
        )
        + event_line(
            "2026-09-06T10:00:05Z",
            event("subscription", "success", action="a1"),
            "SUBSCRIPTION BACKEND: classified after the API backend failed",
        )
        # Unresolved action: both backends failed.
        + event_line(
            "2026-09-06T11:00:00Z",
            event("api", "failure", action="a2", category="overloaded"),
        )
        + event_line(
            "2026-09-06T11:00:20Z",
            event("subscription", "failure", action="a2", category="timeout"),
        )
        # Unresolved action: no budget left for the fallback.
        + event_line(
            "2026-09-07T09:00:00Z",
            event("api", "failure", action="a3", category="auth"),
        )
        + event_line(
            "2026-09-07T09:00:01Z",
            event("subscription", "skipped", action="a3", reason="no_budget"),
        )
        # Truncated by rotation: the fallback outcome is gone.
        + event_line(
            "2026-09-07T10:00:00Z",
            event("api", "failure", action="a4", category="network"),
        )
    )

    result = audit.scan_approval_failures(log)

    structured = result["structured"]
    assert structured["backend_failures"]["total"] == 5
    assert structured["backend_failures"]["by_backend"] == {"api": 4, "subscription": 1}
    assert structured["backend_failures"]["by_category"] == {
        "auth": 1,
        "network": 1,
        "overloaded": 1,
        "rate_limit": 1,
        "timeout": 1,
    }
    assert structured["fallback"] == {"succeeded": 1, "failed": 1, "skipped_no_budget": 1}
    assert structured["actions"] == {
        "observed": 4,
        "recovered": 1,
        "unresolved": 2,
        "incomplete": 1,
    }
    assert structured["by_day"] == {"2026-09-06": 3, "2026-09-07": 2}
    # The human sentence trailing a structured payload is not a second record.
    assert result["legacy_unattributed"]["backend_failures"]["total"] == 0
    assert result["coverage"]["structured_first_at"] == "2026-09-06T10:00:00Z"
    assert result["coverage"]["structured_records"] == 7


@pytest.mark.parametrize(
    "overrides",
    [
        {"action": None},
        {"action": ""},
        {"v": True},
        {"v": 1.0},
        {"backend": "api", "outcome": "success"},
        {"backend": "subscription", "outcome": "skipped"},
        {"backend": "subscription", "outcome": "skipped", "reason": "other"},
    ],
)
def test_invalid_event_identity_or_skip_reason_is_not_counted(tmp_path, overrides):
    payload = event("api", "failure", action="attempt", category="rate_limit")
    payload.update(overrides)
    log = tmp_path / "approval-classifier.log"
    log.write_text(event_line("2026-09-06T10:00:00Z", payload))

    result = audit.scan_approval_failures(log)

    assert result["coverage"]["malformed_events"] == 1
    assert result["coverage"]["structured_records"] == 0
    assert result["structured"]["backend_failures"]["total"] == 0
    assert result["structured"]["fallback"]["skipped_no_budget"] == 0
    assert result["structured"]["actions"]["observed"] == 0


def test_damaged_rotated_and_unsupported_event_lines_never_abort_the_scan(tmp_path):
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        'T10:00:00Z BACKEND-EVENT {"v": 1, "backend": "api"}\n'
        "2026-09-06T10:00:00 BACKEND-EVENT "
        + json.dumps(event("api", "failure", action="naive", category="auth"))
        + "\n"
        '2026-09-06T10:01:00Z BACKEND-EVENT {"v": 1, "backend": "api", "outcome"\n'
        "2026-09-06T10:02:00Z BACKEND-EVENT not-json-at-all\n"
        '2026-09-06T10:03:00Z BACKEND-EVENT ["not", "an", "object"]\n'
        "2026-09-06T10:04:00Z BACKEND-EVENT "
        + json.dumps(event("api", "failure", action="future", category="auth", v=3))
        + "\n"
        "2026-09-06T10:05:00Z BACKEND-EVENT "
        + json.dumps(event("api", "failure", action="ok", category="rate_limit"))
        + "\n"
        "2026-09-06T10:06:00Z BACKEND-EVENT "
        + json.dumps(event("api", "failure", action="oddcat", category="not-a-category"))
        + "\n"
    )

    result = audit.scan_approval_failures(log)

    assert result["structured"]["backend_failures"]["total"] == 2
    assert result["structured"]["backend_failures"]["by_category"] == {
        "other": 1,
        "rate_limit": 1,
    }
    assert result["coverage"]["malformed_events"] == 5
    assert result["coverage"]["unsupported_event_versions"] == 1


TOTAL_FAILURE_WARNING = (
    "WARNING: Anthropic API key was rejected. — HTTP 401 "
    "— subscription fallback also failed: The subscription classifier timed out after 18s.\n"
)


def test_a_genuine_legacy_total_failure_warning_counts_whenever_it_was_written(tmp_path):
    """Old and new writers can interleave; a legacy record is read on its own terms.

    The current hook does not log this warning at all — its structured events
    carry both headlines — so a line of this shape was written by an older hook,
    whatever else is in the file. Nothing about it depends on when structured
    events start.
    """
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        "2026-09-01T09:00:00Z " + TOTAL_FAILURE_WARNING
        + event_line(
            "2026-09-06T10:00:00Z", event("api", "failure", action="a1", category="auth")
        )
        # An older hook still running after the new one first wrote an event.
        + "2026-09-06T11:00:00Z " + TOTAL_FAILURE_WARNING
    )

    result = audit.scan_approval_failures(log)

    assert result["legacy_unattributed"]["backend_failures"] == {
        "total": 2,
        "by_backend": {"api": 0, "subscription": 2},
        "by_category": {"timeout": 2},
    }
    assert result["legacy_unattributed"]["fallback"]["failed"] == 2
    assert result["structured"]["backend_failures"]["total"] == 1
    assert result["coverage"]["earliest_record_at"] == "2026-09-01T09:00:00Z"
    assert result["coverage"]["latest_record_at"] == "2026-09-06T11:00:00Z"


def test_a_damaged_or_future_event_never_suppresses_a_genuine_legacy_warning(tmp_path):
    """A record the scan cannot read must not silence records it can."""
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        "2026-09-06T09:00:00Z BACKEND-EVENT not-json-at-all\n"
        + event_line(
            "2026-09-06T09:30:00Z", event("api", "failure", action="future", v=3, category="auth")
        )
        + "2026-09-06T10:00:00Z " + TOTAL_FAILURE_WARNING
    )

    result = audit.scan_approval_failures(log)

    assert result["legacy_unattributed"]["fallback"]["failed"] == 1
    assert result["legacy_unattributed"]["backend_failures"]["total"] == 1
    assert result["coverage"]["malformed_events"] == 1
    assert result["coverage"]["unsupported_event_versions"] == 1


def test_a_missing_log_reports_unavailable_rather_than_zero_failures(tmp_path):
    result = audit.scan_approval_failures(tmp_path / "absent.log")

    assert result["coverage"]["available"] is False
    assert result["structured"]["actions"]["observed"] == 0
    assert result["legacy_unattributed"]["backend_failures"]["total"] == 0


def test_model_usage_report_states_the_failure_counts_and_what_stays_unobserved(tmp_path):
    home = tmp_path / "home"
    tmpdir = tmp_path / "tmp"
    tmpdir.mkdir(parents=True)
    log = home / ".cache" / "claude" / "approval-classifier.log"
    log.parent.mkdir(parents=True)
    log.write_text(
        legacy_log()
        + event_line(
            "2026-09-06T10:00:00Z",
            event("api", "failure", action="a1", category="rate_limit"),
        )
        + event_line("2026-09-06T10:00:05Z", event("subscription", "success", action="a1"))
    )

    report = run_cli(home, tmpdir, "--model-usage", "--json")
    text = run_cli(home, tmpdir, "--model-usage")

    assert report.returncode == 0, report.stderr
    data = json.loads(report.stdout)
    failures = data["approval_classifier_failures"]
    assert failures["structured"]["actions"] == {
        "observed": 1,
        "recovered": 1,
        "unresolved": 0,
        "incomplete": 0,
    }
    assert failures["legacy_unattributed"]["backend_failures"]["total"] == 4
    assert data["coverage"]["approval_classifier_failures"] == (
        "custom PermissionRequest hook only; legacy log lines are unattributed to an action"
    )
    assert data["coverage"]["native_auto_mode_classifier"] == (
        "persisted unavailability failures only; successful calls, retries, tokens and goal state unobserved"
    )

    assert text.returncode == 0, text.stderr
    assert "Approval backend failures (structured): 1" in text.stdout
    assert "Approval backend failures (legacy, unattributed): 4" in text.stdout
    assert "1 recovered by fallback" in text.stdout
    assert "custom PermissionRequest hook only" in text.stdout
    assert "successful calls, retries, tokens and goal state unobserved" in text.stdout


# Native fixtures are synthetic; unfamiliar reasons test compatibility, not prevalence.
NATIVE_PREFIX = (
    "claude-fable-5 is temporarily unavailable (rate-limited), "
    "so auto mode cannot determine the safety of FixtureTool right now."
)


def native_row(timestamp=STAMP, tool_use_id="native-attempt", content=NATIVE_PREFIX):
    return {
        "type": "user",
        "timestamp": timestamp,
        "sessionId": "private-session-sentinel",
        "uuid": "private-row-sentinel",
        "message": {
            "role": "user",
            "content": [{
                "type": "tool_result",
                "tool_use_id": tool_use_id,
                "is_error": True,
                "content": content,
            }],
        },
    }


def test_native_typed_failures_are_separate_from_conversation_usage(tmp_path):
    projects = tmp_path / "projects"
    write_jsonl(projects / "one" / "session.jsonl", [
        assistant_row(STAMP, message_id="response", model="conversation-model", output_tokens=9),
        native_row(content=NATIVE_PREFIX + "\nprivate-command-sentinel"),
        native_row(tool_use_id="another", content=NATIVE_PREFIX.replace("rate-limited", "synthetic-reason")),
    ])

    usage, native = audit.scan_transcripts(projects)

    assert usage == audit.scan_transcript_model_usage(projects)
    assert usage["requests"] == 1
    assert usage["tokens"]["total_tokens"] == 9
    assert list(usage["by_model"]) == ["conversation-model"]
    assert native["total"] == 2
    assert native["by_category"] == {"rate_limit": 1, "other": 1}
    assert native["by_model"] == {"claude-fable-5": 2}
    assert native["by_day"] == {"2026-09-06": 2}
    assert native["by_hour"] == {"2026-09-06T10:00:00Z": 2}
    assert set(native) == {
        "total", "sessions", "records", "exposure", "coverage",
        *(f"by_{name}" for name in audit.NATIVE_SLICES),
    }
    assert native["coverage"]["raw_matching_observations"] == 2
    # Attribution is exported in the clear (2026-09-09 boundary): the failing
    # call's id, tool, reason and session, and the conversation model that
    # preceded it in the same file.
    assert native["by_session_id"] == {"private-session-sentinel": 2}
    assert native["by_session_model"] == {"conversation-model": 2}
    assert native["by_tool"] == {"FixtureTool": 2}
    assert native["by_reason"] == {"rate-limited": 1, "synthetic-reason": 1}
    assert [r["tool_use_id"] for r in native["records"]] == ["another", "native-attempt"]
    # What stays out: the text after the recognised sentence, row UUIDs, file paths.
    for sentinel in ("private-command-sentinel", "private-row-sentinel", str(projects)):
        assert sentinel not in json.dumps(native)


@pytest.mark.parametrize("change", [
    "assistant_type", "human_type", "missing_role", "assistant_role", "missing_message",
    "message_list", "content_string", "content_dict", "text_block", "tool_use", "missing_error",
    "false_error", "integer_error", "string_error", "nested_content", "null_content", "input",
    "quoted", "embedded", "indented", "newline", "generic_error", "safety_denial", "truncated",
    "spaced_model", "oversized_model", "model_path", "missing_tool", "empty_reason",
])
def test_native_ignores_unsupported_shapes_and_non_native_errors(tmp_path, change):
    row = native_row()
    message = row["message"]
    block = message["content"][0]
    if change == "assistant_type":
        row["type"] = "assistant"
    elif change == "human_type":
        row["type"] = "human"
    elif change == "missing_role":
        message.pop("role")
    elif change == "assistant_role":
        message["role"] = "assistant"
    elif change == "missing_message":
        row.pop("message")
    elif change == "message_list":
        row["message"] = [message]
    elif change == "content_string":
        message["content"] = NATIVE_PREFIX
    elif change == "content_dict":
        message["content"] = block
    elif change == "text_block":
        block.update(type="text", text=NATIVE_PREFIX)
    elif change == "tool_use":
        block["type"] = "tool_use"
    elif change == "missing_error":
        block.pop("is_error")
    elif change in ("false_error", "integer_error", "string_error"):
        block["is_error"] = {"false_error": False, "integer_error": 1, "string_error": "true"}[change]
    elif change == "nested_content":
        block["content"] = [{"type": "text", "text": NATIVE_PREFIX}]
    elif change == "null_content":
        block["content"] = None
    elif change == "input":
        block.update(content="ordinary tool failure", input={"command": NATIVE_PREFIX})
    else:
        block["content"] = {
            "quoted": f'"{NATIVE_PREFIX}"',
            "embedded": f"Reported error: {NATIVE_PREFIX}",
            "indented": f" {NATIVE_PREFIX}",
            "newline": f"\n{NATIVE_PREFIX}",
            "generic_error": "HTTP 429 rate limit exceeded",
            "safety_denial": "Auto mode denied this tool because it is not safe.",
            "truncated": NATIVE_PREFIX.removesuffix(" right now."),
            "spaced_model": NATIVE_PREFIX.replace("claude-fable-5", "the classifier"),
            "oversized_model": NATIVE_PREFIX.replace("claude-fable-5", "claude-" + "x" * 200),
            "model_path": NATIVE_PREFIX.replace("claude-fable-5", "claude-/private/model"),
            "missing_tool": NATIVE_PREFIX.replace("FixtureTool", ""),
            "empty_reason": NATIVE_PREFIX.replace("rate-limited", ""),
        }[change]
    projects = tmp_path / "projects"
    write_jsonl(projects / "one" / "s.jsonl", [row, None, [], 4])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 0
    assert native["coverage"]["raw_matching_observations"] == 0


@pytest.mark.parametrize("reverse", [False, True])
def test_native_dedup_is_global_earliest_before_cutoff_and_order_independent(tmp_path, monkeypatch, reverse):
    projects = tmp_path / "projects"
    first = projects / "one" / "a.jsonl"
    second = projects / "two" / "b.jsonl"
    rows = [
        native_row("2026-09-05T23:59:59Z", "mirrored"),
        native_row("2026-09-06T08:00:00Z", "same-instant", NATIVE_PREFIX),
        native_row("2026-09-06T08:00:00Z", "tie-category", NATIVE_PREFIX),
    ]
    mirrors = [
        native_row("2026-09-07T12:00:00Z", "mirrored"),
        native_row("2026-09-06T10:00:00+02:00", "same-instant", NATIVE_PREFIX.replace("fable", "opus")),
        native_row("2026-09-06T08:00:00Z", "tie-category", NATIVE_PREFIX.replace("rate-limited", "synthetic")),
        native_row("2026-09-06T09:45:00Z", "distinct"),
        native_row("2026-09-06T09:46:00Z", "distinct"),
    ]
    for row in mirrors:
        row["sessionId"] = "another-private-session"
    write_jsonl(first, rows[::-1] if reverse else rows)
    write_jsonl(second, mirrors[::-1] if reverse else mirrors)
    monkeypatch.setattr(audit, "transcript_paths", lambda *_: [second, first] if reverse else [first, second])

    _, native = audit.scan_transcripts(projects, audit.parse_timestamp("2026-09-06T00:00:00Z"))

    assert native["total"] == 3
    assert native["by_category"] == {"other": 1, "rate_limit": 2}
    assert native["by_model"] == {"claude-fable-5": 3}
    assert native["by_day"] == {"2026-09-06": 3}
    assert native["by_hour"] == {"2026-09-06T08:00:00Z": 2, "2026-09-06T09:00:00Z": 1}
    assert native["coverage"]["raw_matching_observations"] == 8
    assert native["coverage"]["duplicate_observations"] == 4
    assert native["coverage"]["earliest_in_period"] == "2026-09-06T08:00:00Z"
    assert native["coverage"]["latest_in_period"] == "2026-09-06T09:45:00Z"


@pytest.mark.parametrize("bad_id", [None, "", 3, False, [], {}])
def test_native_missing_identity_is_coverage_only_never_uuid_fallback(tmp_path, bad_id):
    projects = tmp_path / "projects"
    row = native_row(tool_use_id=bad_id)
    write_jsonl(projects / "one" / "s.jsonl", [row, row])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 0
    assert native["coverage"]["raw_matching_observations"] == 2
    assert native["coverage"]["missing_id_observations"] == 2
    assert native["coverage"]["duplicate_observations"] == 0


def test_native_invalid_timestamps_do_not_poison_identity_and_coverage_is_unfiltered(tmp_path):
    projects = tmp_path / "projects"
    rows = [native_row(stamp) for stamp in (None, 42, "not-a-date", "2026-09-06", "2026-09-06T10:00:00")]
    rows += [native_row(STAMP), native_row("2026-09-01T00:00:00Z", None)]
    rows += [native_row(None, None)]
    write_jsonl(projects / "one" / "s.jsonl", rows, malformed="broken-json\n")

    _, native = audit.scan_transcripts(projects, audit.parse_timestamp("2026-09-06T10:00:00Z"))

    assert native["total"] == 1
    assert native["coverage"]["raw_matching_observations"] == 8
    assert native["coverage"]["invalid_timestamp_observations"] == 6
    assert native["coverage"]["missing_id_observations"] == 2
    assert native["coverage"]["duplicate_observations"] == 5
    assert native["coverage"]["malformed_rows"] == 1


@pytest.mark.parametrize("reverse", [False, True])
def test_native_duplicate_coverage_includes_invalid_timestamp_mirrors(tmp_path, reverse):
    projects = tmp_path / "projects"
    rows = [native_row(None), native_row("bad"), native_row(STAMP)]
    write_jsonl(projects / "one" / "s.jsonl", rows[::-1] if reverse else rows)

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 1
    assert native["coverage"]["duplicate_observations"] == 2
    assert native["coverage"]["invalid_timestamp_observations"] == 2
    assert native["coverage"]["earliest_in_period"] == STAMP


def test_native_mid_read_failure_keeps_prefix_and_continues_other_files(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    damaged = projects / "one" / "a.jsonl"
    good = projects / "two" / "b.jsonl"
    write_jsonl(damaged, [native_row(), assistant_row(STAMP, uuid="prefix-usage", output_tokens=3)])
    write_jsonl(good, [native_row(tool_use_id="after-error")])
    real_open = Path.open

    class InterruptedFile:
        def __init__(self, lines):
            self.lines = lines
            self.reads = 0

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            self.lines.close()

        def __iter__(self):
            return self

        def __next__(self):
            if self.reads == 2:
                raise OSError("synthetic read failure after a valid prefix")
            self.reads += 1
            return next(self.lines)

    def interrupted_open(self, *args, **kwargs):
        lines = real_open(self, *args, **kwargs)
        return InterruptedFile(lines) if self == damaged else lines

    monkeypatch.setattr(Path, "open", interrupted_open)
    usage, native = audit.scan_transcripts(projects)

    assert usage["tokens"]["total_tokens"] == 3
    assert native["total"] == 2
    assert native["coverage"]["scanned_files"] == 2
    assert native["coverage"]["unreadable_files"] == 1
    assert native["coverage"]["raw_matching_observations"] == 2
    assert "read failures" in native["coverage"]["limits"]


def test_native_scan_counts_unreadable_files_and_never_reads_snapshot_text(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    readable = projects / "one" / "good.jsonl"
    blocked = projects / "one" / "blocked.jsonl"
    write_jsonl(readable, [native_row()], malformed="broken-json\n")
    write_jsonl(blocked, [native_row(tool_use_id="blocked")])
    (projects / "one" / "snapshot.txt").write_text(json.dumps(native_row(tool_use_id="snapshot")))
    real_open = Path.open

    def refuse(self, *args, **kwargs):
        if self == blocked:
            raise PermissionError("synthetic unreadable file")
        assert self.suffix != ".txt"
        return real_open(self, *args, **kwargs)

    monkeypatch.setattr(Path, "open", refuse)
    usage, native = audit.scan_transcripts(projects)

    assert native["total"] == 1
    assert native["coverage"]["scanned_files"] == 1
    assert native["coverage"]["unreadable_files"] == 1
    assert native["coverage"]["malformed_rows"] == usage["coverage"]["malformed_rows"] == 1
    assert "limits" in native["coverage"]
    assert "successful calls" in native["coverage"]["limits"]


def test_native_cli_uses_utc_project_date_scope_and_exports_aggregates_only(tmp_path):
    home, tmpdir = tmp_path / "home", tmp_path / "tmp"
    tmpdir.mkdir()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    projects = home / ".claude" / "projects"
    write_jsonl(projects / "KEEP-fixture" / "s.jsonl", [
        native_row(iso(now), "private-attempt-sentinel", NATIVE_PREFIX + "\nprivate-suffix-sentinel"),
        native_row(iso(now - timedelta(days=5)), "old"),
    ])
    write_jsonl(projects / "excluded" / "s.jsonl", [native_row(iso(now), "excluded")])
    log = home / ".cache" / "claude" / "approval-classifier.log"
    log.parent.mkdir(parents=True)
    log.write_text(f"{iso(now)} USAGE: model=hook-model input=1 output=1 cache_read=0 cache_create=0\n")
    (tmpdir / "claude-statusline-usage.json").write_text('{"five_hour":{"utilization":5}}')
    args = ("--model-usage", "--project", "keep", "--days", "1")
    utc = run_cli(home, tmpdir, *args, "--json", tz="UTC0")
    other_zone = run_cli(home, tmpdir, *args, "--json", tz="EST5EDT")
    text = run_cli(home, tmpdir, *args)
    assert utc.returncode == other_zone.returncode == text.returncode == 0
    data = json.loads(utc.stdout)
    native = data["native_auto_mode_classifier_failures"]
    assert native == json.loads(other_zone.stdout)["native_auto_mode_classifier_failures"]
    assert native["total"] == 1
    assert native["coverage"]["scanned_files"] == 1
    assert native["coverage"]["raw_matching_observations"] == 2
    assert native["by_hour"] == {iso(now.replace(minute=0, second=0)): 1}
    assert data["approval_classifier_usage"]["requests"] == 1
    assert data["quota"]["current"]["available"] is True
    for value in ("private-suffix-sentinel", "private-row-sentinel", str(projects), "s.jsonl"):
        assert value not in utc.stdout + text.stdout
    assert native["records"][0]["tool_use_id"] == "private-attempt-sentinel"
    assert native["records"][0]["session_id"] == "private-session-sentinel"
    assert "Native auto-mode failures: 1 across 1 sessions" in text.stdout
    assert "FixtureTool: 1" in text.stdout
    assert "rate_limit 1" in text.stdout
    assert "claude-fable-5: 1" in text.stdout
    assert f"{now.date().isoformat()}: 1" in text.stdout
    assert f"Peak UTC hour: {iso(now.replace(minute=0, second=0))} (1)" in text.stdout
    assert "Native coverage: 1 scanned files, 0 unreadable" in text.stdout
    assert "calls, failures, retries and goal state unobserved" not in utc.stdout + text.stdout


def test_model_usage_report_scans_each_transcript_once(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    transcript = projects / "one" / "s.jsonl"
    write_jsonl(transcript, [native_row(), assistant_row(STAMP, uuid="response", output_tokens=3)])
    monkeypatch.setattr(audit, "PROJECTS_DIR", projects)
    monkeypatch.setattr(audit, "APPROVAL_LOG", tmp_path / "absent.log")
    monkeypatch.setattr(audit, "QUOTA_HISTORY", tmp_path / "absent-history.jsonl")
    monkeypatch.setenv("TMPDIR", str(tmp_path))
    real_open = Path.open
    reads = []

    def spy(self, *args, **kwargs):
        if self == transcript:
            reads.append(self)
        return real_open(self, *args, **kwargs)

    monkeypatch.setattr(Path, "open", spy)
    result = audit.model_usage_report(argparse.Namespace(days=0, project=""))

    assert reads == [transcript]
    assert result["native_auto_mode_classifier_failures"]["total"] == 1
    assert result["transcript_usage"]["tokens"]["total_tokens"] == 3


# `astra` was observed (2026-09-08) on a session routed to a foreign model, beside
# `claude-opus-5[1m]` on Claude-model sessions: the token names whatever served the
# classifier call, so it is not always an Anthropic catalogue ID.
@pytest.mark.parametrize("model", [
    "claude-fable-5", "claude-opus-4-8", "claude-sonnet-4-5-20250929", "claude-fable-5.1",
    "astra", "gpt-6-astra",
])
def test_native_accepts_bounded_model_tokens_and_multiple_result_blocks(tmp_path, model):
    projects = tmp_path / "projects"
    row = native_row("1969-12-31T23:59:59Z", content=NATIVE_PREFIX.replace("claude-fable-5", model))
    row["message"]["content"].extend([None, "ignored", native_row(tool_use_id="second")["message"]["content"][0]])
    write_jsonl(projects / "one" / "s.jsonl", [row])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 2
    assert native["by_model"][model] == (2 if model == "claude-fable-5" else 1)
    assert native["by_hour"] == {"1969-12-31T23:00:00Z": 2}


@pytest.mark.parametrize("reason,tool", [
    ("synthetic-compatibility-" * 20, "FixtureTool"),
    ("synthetic-reason", "private-tool-sentinel " * 20),
    ("synthetic-reason", "Fixture tool (compatibility)"),
])
def test_native_reason_and_tool_compatibility_has_no_arbitrary_length_cap(tmp_path, reason, tool):
    projects = tmp_path / "projects"
    content = NATIVE_PREFIX.replace("rate-limited", reason).replace("FixtureTool", tool)
    write_jsonl(projects / "one" / "s.jsonl", [native_row(content=content)])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 1
    assert native["by_category"] == {"other": 1}
    # Retained in the clear, but bounded: the template's free text is capped.
    assert native["by_reason"] == {reason[:audit.NATIVE_TEXT_CAP]: 1}
    assert native["by_tool"] == {tool.strip()[:audit.NATIVE_TEXT_CAP]: 1}


@pytest.mark.parametrize("reason,category", [
    ("rate-limited", "rate_limit"), ("overloaded", "overloaded"),
    ("server-error", "server_error"), ("synthetic", "other"),
])
def test_native_documented_reasons_get_their_own_category(tmp_path, reason, category):
    projects = tmp_path / "projects"
    write_jsonl(projects / "one" / "s.jsonl", [
        native_row(content=NATIVE_PREFIX.replace("rate-limited", reason)),
    ])

    _, native = audit.scan_transcripts(projects)

    assert native["by_category"] == {category: 1}
    assert native["by_reason"] == {reason: 1}


def test_native_records_carry_the_row_attributes_and_the_preceding_session_model(tmp_path):
    """Every transcript row is stamped with cwd, version, gitBranch and sessionId;
    the conversation model is on the assistant rows before the failure."""
    projects = tmp_path / "projects"
    stamped = native_row("2026-09-06T10:05:00Z", "stamped")
    stamped.update(cwd="/fixture/repo", version="2.1.263", gitBranch="fixture-branch")
    later = native_row("2026-09-06T10:06:00Z", "later")
    later.update(cwd="/fixture/repo", version="2.1.264", gitBranch="fixture-branch")
    write_jsonl(projects / "one" / "s.jsonl", [
        native_row("2026-09-06T10:00:00Z", "before-any-assistant"),
        assistant_row("2026-09-06T10:01:00Z", uuid="a1", model="first-model"),
        assistant_row("2026-09-06T10:02:00Z", uuid="a2", model="second-model"),
        stamped,
        later,
    ])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == 3
    assert native["sessions"] == 1
    assert native["by_session_model"] == {"None": 1, "second-model": 2}
    assert native["by_cli_version"] == {"2.1.263": 1, "2.1.264": 1, "None": 1}
    assert native["by_cwd"] == {"/fixture/repo": 2, "None": 1}
    assert native["by_branch"] == {"fixture-branch": 2, "None": 1}
    record = native["records"][1]
    assert record == {
        "timestamp": "2026-09-06T10:05:00Z",
        "tool_use_id": "stamped",
        "model": "claude-fable-5",
        "category": "rate_limit",
        "reason": "rate-limited",
        "tool": "FixtureTool",
        "cwd": "/fixture/repo",
        "cli_version": "2.1.263",
        "branch": "fixture-branch",
        "session_id": "private-session-sentinel",
        "session_model": "second-model",
    }
    assert native["records"][0]["session_model"] is None


def tool_use_row(timestamp, calls, version=None):
    row = {
        "type": "assistant",
        "timestamp": timestamp,
        "message": {
            "model": "claude-test",
            "content": [
                {"type": "tool_use", "id": call_id, "name": name, "input": {}}
                for call_id, name in calls
            ],
        },
    }
    if version is not None:
        row["version"] = version
    return row


def test_native_exposure_counts_classifier_bound_calls_once_per_id_by_day(tmp_path):
    projects = tmp_path / "projects"
    rows = [
        tool_use_row("2026-09-05T23:00:00Z", [("c1", "Bash"), ("c2", "Read"), ("c3", "Agent")], "2.1.262"),
        tool_use_row("2026-09-06T09:00:00Z", [("c4", "Bash"), ("c5", "Monitor"), ("c6", "Edit")], "2.1.263"),
        native_row("2026-09-06T09:30:00Z", "f1", NATIVE_PREFIX.replace("FixtureTool", "Bash")),
        native_row("2026-09-06T09:31:00Z", "f2", NATIVE_PREFIX.replace("FixtureTool", "SendMessage")),
        # A tool the denominator does not count: real, but no call count to divide by.
        native_row("2026-09-06T09:32:00Z", "f3"),
        tool_use_row("2026-09-06T10:00:00Z", [("c4", "Bash"), ("c7", "Task")], "2.1.263"),
        {"type": "assistant", "timestamp": "bad", "message": {"content": [{"type": "tool_use", "id": "c8", "name": "Bash"}]}},
    ]
    write_jsonl(projects / "one" / "a.jsonl", rows)
    # A mirrored copy of the same session must not double the exposure.
    write_jsonl(projects / "two" / "b.jsonl", rows[:2])

    _, native = audit.scan_transcripts(projects)
    exposure = native["exposure"]

    assert exposure["classifier_bound_calls_by_day"] == {
        "2026-09-05": {"Agent": 1, "Bash": 1},
        "2026-09-06": {"Bash": 1, "Monitor": 1, "Task": 1},
    }
    assert exposure["cli_versions_by_day"] == {
        "2026-09-05": {"2.1.262": 2},
        "2026-09-06": {"2.1.263": 3},
    }
    # Three failures, but only the two on tools the denominator counts may be divided
    # by it: 2 of 3 bound calls on 09-06.
    assert native["total"] == 3
    assert exposure["failures_in_denominator"] == 2
    assert exposure["failures_outside_denominator"] == {
        "total": 1,
        "by_tool": {"FixtureTool": 1},
        "note": (
            "counted in total and every by_* slice, excluded from every rate: "
            "the denominator counts only CLASSIFIER_BOUND_TOOLS"
        ),
    }
    assert exposure["failures_per_100_bound_calls_by_day"] == {"2026-09-06": pytest.approx(66.67)}
    # The printed numerator must be the one the rate divides, or the line
    # contradicts itself: 2 of 3 bound calls is 66.67, and the third failure sits
    # outside the denominator rather than being added to that numerator.
    assert exposure["failures_in_denominator_by_day"] == {"2026-09-06": 2}
    assert native["by_day"] == {"2026-09-06": 3}
    # The failures' session model is the newest assistant model before the row in the
    # same file (claude-test here); a day's bound calls are split by the same field.
    assert exposure["by_day_and_session_model"] == {
        "2026-09-05": {"claude-test": {"bound_calls": 2, "failures": 0, "per_100_bound_calls": 0.0}},
        "2026-09-06": {"claude-test": {"bound_calls": 3, "failures": 2, "per_100_bound_calls": pytest.approx(66.67)}},
    }
    assert "upper bound on classifier calls" in native["coverage"]["limits"]
    assert "failures_outside_denominator" in native["coverage"]["limits"]
    # The bias is not constant across days, so the day series is not a trend.
    assert "must not be read as a trend" in native["coverage"]["limits"]


def test_a_rate_never_divides_a_failure_the_denominator_does_not_count(tmp_path):
    """Numerator and denominator must span the same tool set.

    Found by the 2026-09-10 council review: 107 real failures on SendMessage, Edit
    and an MCP tool were being divided by a denominator built only from Bash,
    PowerShell, Monitor, Agent and Task.
    """
    projects = tmp_path / "projects"
    write_jsonl(projects / "one" / "s.jsonl", [
        tool_use_row("2026-09-06T09:00:00Z", [("c1", "Bash")], "2.1.263"),
        native_row("2026-09-06T09:30:00Z", "edit", NATIVE_PREFIX.replace("FixtureTool", "Edit")),
        native_row("2026-09-06T09:31:00Z", "mcp", NATIVE_PREFIX.replace("FixtureTool", "mcp__x__y")),
    ])

    _, native = audit.scan_transcripts(projects)
    exposure = native["exposure"]

    assert native["total"] == 2
    assert native["by_day"] == {"2026-09-06": 2}
    # Both failures are real and counted, and neither inflates a rate.
    assert exposure["failures_in_denominator"] == 0
    assert exposure["failures_outside_denominator"]["by_tool"] == {"Edit": 1, "mcp__x__y": 1}
    assert exposure["failures_per_100_bound_calls_by_day"] == {}
    assert exposure["by_day_and_session_model"]["2026-09-06"]["claude-test"]["failures"] == 0

    _, in_period = audit.scan_transcripts(projects, audit.parse_timestamp("2026-09-06T00:00:00Z"))
    assert list(in_period["exposure"]["classifier_bound_calls_by_day"]) == ["2026-09-06"]


def v2_event(backend, outcome, *, action, category=None, **extra):
    payload = event(backend, outcome, action=action, category=category, v=2)
    payload.pop("session")
    payload.update({
        "session_id": "session-in-the-clear",
        "model": "claude-sonnet-5" if backend == "api" else "sonnet",
        "host": "fixture-host",
        "cwd": "/fixture/repo/sub",
        "repo": "repo",
        "remote": "git@github.test:owner/repo.git",
        "commit": "abc123def456",
        "branch": "fixture-branch",
        "cli_version": "2.1.263",
        "session_model": "claude-fable-5-1",
        "account": "person@example.test",
    })
    payload.update(extra)
    return payload


def test_v2_events_are_counted_like_v1_and_sliced_by_where_they_happened(tmp_path):
    log = tmp_path / "approval-classifier.log"
    log.write_text(
        event_line("2026-09-06T10:00:00Z", v2_event("api", "failure", action="a1", category="rate_limit"))
        + event_line("2026-09-06T10:00:05Z", v2_event("subscription", "success", action="a1"))
        + event_line("2026-09-06T11:00:00Z", v2_event("api", "failure", action="a2", category="auth", cli_version="2.1.264"))
        + event_line("2026-09-06T12:00:00Z", event("api", "failure", action="a3", category="auth"))
    )

    result = audit.scan_approval_failures(log)
    structured = result["structured"]

    assert result["coverage"]["unsupported_event_versions"] == 0
    assert structured["backend_failures"]["total"] == 3
    assert structured["actions"] == {"observed": 3, "recovered": 1, "unresolved": 0, "incomplete": 2}
    assert structured["by_model"] == {"claude-sonnet-5": 2, "unknown": 1}
    assert structured["by_cli_version"] == {"2.1.263": 1, "2.1.264": 1, "unknown": 1}
    assert structured["by_repo"] == {"repo": 2, "unknown": 1}
    assert structured["by_account"] == {"person@example.test": 2, "unknown": 1}
    assert structured["by_commit"] == {"abc123def456": 2, "unknown": 1}
    assert [r["action"] for r in structured["records"]] == ["a1", "a2", "a3"]
    assert structured["records"][0]["timestamp"] == "2026-09-06T10:00:00Z"
    assert structured["records"][0]["session_id"] == "session-in-the-clear"


@pytest.mark.parametrize("suffix,accepted", [("[1m]", True), ("[2m]", False), ("[1m][1m]", False), ("[private]", False)])
def test_native_context_suffix_retains_verified_classifier_identity(tmp_path, suffix, accepted):
    projects = tmp_path / "projects"
    model = "claude-opus-5" + suffix
    write_jsonl(projects / "one" / "s.jsonl", [
        native_row(content=NATIVE_PREFIX.replace("claude-fable-5", model)),
    ])

    _, native = audit.scan_transcripts(projects)

    assert native["total"] == int(accepted)
    assert native["by_model"] == ({model: 1} if accepted else {})


def test_native_limits_do_not_claim_attempt_rates_or_complete_history(tmp_path):
    _, native = audit.scan_transcripts(tmp_path / "missing")

    for limit in (
        "upper bound on classifier calls", "hidden HTTP attempts", "complete historical coverage",
        "CLI wording changes", "not proof", "identical-command", "missing evidence",
    ):
        assert limit in native["coverage"]["limits"]


def test_native_empty_root_is_an_explicit_empty_summary(tmp_path):
    usage, native = audit.scan_transcripts(tmp_path / "missing")
    assert usage["requests"] == native["total"] == 0
    assert native["by_hour"] == {}
    assert native["coverage"]["scanned_files"] == 0
    assert native["coverage"]["earliest_in_period"] is None
    assert native["coverage"]["latest_in_period"] is None
