"""Tests for custom_bins/cloud-spend-check.

The fixture is a real capture: `modal billing report -r d --json` for workspace
elj-c8-wen over 2026-07-16..2026-09-15, 126 rows across 87 object IDs, taken on
2026-09-16. Costs, descriptions and object IDs are untouched. It contains both
things the rule has to tell apart -- the idle H100 that billed ~$96/day flat
for 30 days, and the bursty eval work either side of it.

The false-positive test is the one that matters. A magnitude threshold on this
same series fires on six days of legitimate work; the whole reason the rule
keys on flatness is to score zero there, so a change that makes detection more
eager has to keep that test green to be worth anything.

Four of these tests exist because a review found the corresponding defect:
keying on description rather than object ID (8 of 12 names in the fixture map
to several objects, one to 36), inherited MODAL_TOKEN_* silently redirecting
every profile to one workspace, one bad profile discarding every other
profile's findings, and a stopped resource being re-reported daily until it
aged out of the lookback window.
"""

from __future__ import annotations

import collections
import importlib.machinery
import importlib.util
import json
from datetime import date
from pathlib import Path

import pytest

CHECK = Path(__file__).resolve().parent.parent / "custom_bins" / "cloud-spend-check"
FIXTURE = (
    Path(__file__).resolve().parent
    / "fixtures"
    / "modal-billing-2026-07-16_2026-09-15.json"
)

_loader = importlib.machinery.SourceFileLoader("cloud_spend_check", str(CHECK))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
csc = importlib.util.module_from_spec(_spec)
_loader.exec_module(csc)

IDLE_APP = "impossiblebench-qwen36-vllm"


def series_upto(last_day: str) -> dict:
    """Real billing rows as the tool would have seen them on `last_day`."""
    rows = json.loads(FIXTURE.read_text())
    out: dict = collections.defaultdict(dict)
    for row in rows:
        day = row["Interval Start"][:10]
        if day <= last_day:
            key = ("modal", "elj-c8-wen", row["Object ID"], row["Description"])
            out[key][day] = float(row["Cost"])
    return dict(out)


def day_after(iso: str) -> date:
    return date.fromisoformat(iso) + (date(2000, 1, 2) - date(2000, 1, 1))


# ── the incident ────────────────────────────────────────────────────────────


def test_fires_on_the_real_idle_run() -> None:
    findings = csc.analyse(series_upto("2026-09-13"), today=day_after("2026-09-13"))
    assert [f["resource"] for f in findings] == [IDLE_APP]
    only = findings[0]
    assert only["flat_days"] >= 20, "the run was flat for about four weeks"
    assert 95 <= only["mean_daily_usd"] <= 98
    assert only["projected_30d_usd"] > 2800
    assert only["resource_id"].startswith("ap-")


def test_would_have_fired_two_days_after_the_watchdog_started() -> None:
    """2026-08-17 is the first day the rule could see three flat days."""
    assert csc.analyse(series_upto("2026-08-16"), today=day_after("2026-08-16")) == []
    findings = csc.analyse(series_upto("2026-08-17"), today=day_after("2026-08-17"))
    assert [f["resource"] for f in findings] == [IDLE_APP]
    assert findings[0]["flat_days"] == 3


def test_no_false_positive_on_real_eval_work() -> None:
    """The July/early-August work is bursty, so nothing should fire."""
    findings = csc.analyse(series_upto("2026-08-14"), today=day_after("2026-08-14"))
    assert findings == [], f"fired on legitimate work: {findings}"


def test_partial_final_day_breaks_the_run() -> None:
    """2026-09-14 billed $45 against $96 the day before: the run has ended."""
    assert csc.analyse(series_upto("2026-09-14"), today=day_after("2026-09-14")) == []


# ── keyed on object ID, not description ─────────────────────────────────────


def test_fixture_really_does_reuse_descriptions() -> None:
    """Guards the premise of the next test against a fixture regeneration."""
    rows = json.loads(FIXTURE.read_text())
    ids_per_name: dict[str, set[str]] = collections.defaultdict(set)
    for row in rows:
        ids_per_name[row["Description"]].add(row["Object ID"])
    reused = {n: len(i) for n, i in ids_per_name.items() if len(i) > 1}
    assert len(reused) >= 8, reused
    assert max(reused.values()) >= 30, reused


def test_same_description_different_objects_stay_separate() -> None:
    """Two objects sharing a name must not overwrite each other's days.

    Keyed on description, the cheap object below would clobber the expensive
    one on every shared day and the flat run would vanish.
    """
    expensive = ("modal", "p", "ap-expensive", "same-name")
    cheap = ("modal", "p", "ap-cheap", "same-name")
    series = {
        expensive: {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-03": 100.0},
        cheap: {"2026-09-01": 0.5, "2026-09-02": 0.5, "2026-09-03": 0.5},
    }
    findings = csc.analyse(series, today=day_after("2026-09-03"))
    assert [f["resource_id"] for f in findings] == ["ap-expensive"]
    assert findings[0]["mean_daily_usd"] == 100.0


# ── a stopped resource stops being reported ─────────────────────────────────


def test_resource_that_stopped_is_not_reported_once_billing_moves_on() -> None:
    stopped = ("modal", "p", "ap-stopped", "stopped")
    running = ("modal", "p", "ap-running", "running")
    series = {
        stopped: {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-03": 100.0},
        running: {
            "2026-09-05": 90.0,
            "2026-09-06": 90.0,
            "2026-09-07": 90.0,
        },
    }
    findings = csc.analyse(series, today=day_after("2026-09-07"))
    assert [f["resource_id"] for f in findings] == ["ap-running"]


def test_wholly_stale_series_reports_nothing() -> None:
    """Everything stopped a week ago: history, not a live bill."""
    series = {
        ("modal", "p", "ap-old", "old"): {
            "2026-09-01": 100.0,
            "2026-09-02": 100.0,
            "2026-09-03": 100.0,
        }
    }
    assert csc.analyse(series, today=date(2026, 9, 20)) == []


# ── the flatness rule itself ────────────────────────────────────────────────


def test_calendar_gap_ends_a_run() -> None:
    flat = {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-03": 100.0}
    assert csc.flat_run(flat) == (3, 100.0)
    gapped = {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-04": 100.0}
    assert csc.flat_run(gapped) is None


def test_floor_suppresses_cheap_flat_runs() -> None:
    cheap = {"2026-09-01": 1.0, "2026-09-02": 1.0, "2026-09-03": 1.0}
    assert csc.flat_run(cheap) is None


def test_variance_above_tolerance_is_not_flat() -> None:
    varied = {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-03": 80.0}
    assert csc.flat_run(varied) is None


def test_flat_run_requires_the_cutoff_day() -> None:
    flat = {"2026-09-01": 100.0, "2026-09-02": 100.0, "2026-09-03": 100.0}
    assert csc.flat_run(flat, cutoff="2026-09-03") == (3, 100.0)
    assert csc.flat_run(flat, cutoff="2026-09-04") is None


# ── credentials and profile isolation ───────────────────────────────────────


def test_inherited_modal_tokens_are_dropped_from_the_child(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """MODAL_TOKEN_* outrank .modal.toml, so they must not reach the child.

    Left in place, every per-profile query hits whichever workspace the tokens
    belong to while being labelled with a different profile name each time.
    """
    monkeypatch.setenv("MODAL_TOKEN_ID", "ak-leaked")
    monkeypatch.setenv("MODAL_TOKEN_SECRET", "as-leaked")
    probe = [
        "python3",
        "-c",
        "import os;print(os.environ.get('MODAL_TOKEN_ID','ABSENT'),"
        "os.environ.get('MODAL_PROFILE','ABSENT'))",
    ]
    out = csc.run_cmd(
        probe, env={"MODAL_PROFILE": "other"}, drop=csc.MODAL_CREDENTIAL_OVERRIDES
    )
    assert out.split() == ["ABSENT", "other"]


def test_tokens_survive_when_not_dropped(monkeypatch: pytest.MonkeyPatch) -> None:
    """The drop is doing the work, not some other part of the environment."""
    monkeypatch.setenv("MODAL_TOKEN_ID", "ak-leaked")
    probe = ["python3", "-c", "import os;print(os.environ.get('MODAL_TOKEN_ID','ABSENT'))"]
    assert csc.run_cmd(probe).strip() == "ak-leaked"


def test_one_bad_profile_does_not_discard_the_others(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(csc, "modal_profiles", lambda config=None: ["bad", "good"])

    def fake_run(cmd, env=None, drop=(), timeout=180):
        if env and env.get("MODAL_PROFILE") == "bad":
            raise csc.ProviderError("modal exited 1: token expired")
        return json.dumps(
            [
                {
                    "Object ID": "ap-1",
                    "Description": "gpu",
                    "Interval Start": f"2026-09-0{d}T00:00:00",
                    "Cost": "90.0",
                }
                for d in (1, 2, 3)
            ]
        )

    monkeypatch.setattr(csc, "run_cmd", fake_run)
    series, errors, checked = csc.collect_modal(days=7)
    assert checked == ["modal/good"], checked
    assert any("bad" in e for e in errors), errors
    assert series, "the healthy profile's rows were discarded"
    findings = csc.analyse(series, today=day_after("2026-09-03"))
    assert [f["profile"] for f in findings] == ["good"]


# ── reporting contract ──────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw",
    [
        '\x1b[1m[\x1b[0m{"Description": "x", "Interval Start": "2026-09-01T00:00:00", '
        '"Cost": "1.0"}\x1b[1m]\x1b[0m',
        '[{"Description": "x", "Interval Start": "2026-09-01T00:00:00", "Cost": "1.0"}]',
    ],
)
def test_ansi_is_stripped_before_parsing(raw: str) -> None:
    """modal keeps bold SGR codes in --json even under NO_COLOR=1 and TERM=dumb."""
    assert json.loads(csc.ANSI.sub("", raw))[0]["Description"] == "x"


def test_modal_profiles_reads_every_section(tmp_path: Path) -> None:
    cfg = tmp_path / "modal.toml"
    cfg.write_text(
        "[phuong-c8-yulong]\ntoken_id = 'a'\n"
        "[yulonglin]\ntoken_id = 'b'\n"
        "[elj-c8-wen]\ntoken_id = 'c'\nactive = true\n"
    )
    assert csc.modal_profiles(cfg) == ["phuong-c8-yulong", "yulonglin", "elj-c8-wen"]


def test_missing_modal_config_yields_no_profiles(tmp_path: Path) -> None:
    assert csc.modal_profiles(tmp_path / "absent.toml") == []


def test_planned_providers_are_reported_not_silently_skipped() -> None:
    report = csc.build_report(days=7, wanted={"runpod"})
    assert report["checked"] == []
    assert any("runpod" in s for s in report["skipped"])


def test_empty_series_is_not_a_crash() -> None:
    assert csc.analyse({}) == []
