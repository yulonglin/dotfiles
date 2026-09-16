"""Tests for custom_bins/cloud-spend-check.

The fixture is a real capture: `modal billing report -r d --json` for workspace
elj-c8-wen over 2026-07-16..2026-09-15, 126 rows, taken on 2026-09-16. Object
IDs were dropped; app descriptions and costs are untouched. It contains both
things the rule has to tell apart -- the idle H100 that billed ~$96/day flat
for 30 days, and the bursty eval work either side of it.

The false-positive test is the one that matters. A magnitude threshold on this
same series fires on six days of legitimate work; the whole reason the rule
keys on flatness is to score zero there, so a change that makes detection more
eager has to keep that test green to be worth anything.
"""

from __future__ import annotations

import collections
import importlib.machinery
import importlib.util
import json
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

# The incident: the watchdog started 2026-08-15, the endpoint died 2026-09-14.
IDLE_APP = "impossiblebench-qwen36-vllm"


def series_upto(last_day: str) -> dict[tuple[str, str, str], dict[str, float]]:
    """Real billing rows as the tool would have seen them on `last_day`."""
    rows = json.loads(FIXTURE.read_text())
    out: dict[tuple[str, str, str], dict[str, float]] = collections.defaultdict(dict)
    for row in rows:
        day = row["Interval Start"][:10]
        if day <= last_day:
            out[("modal", "elj-c8-wen", row["Description"])][day] = float(row["Cost"])
    return dict(out)


def test_fires_on_the_real_idle_run() -> None:
    findings = csc.analyse(series_upto("2026-09-13"))
    assert [f["resource"] for f in findings] == [IDLE_APP]
    only = findings[0]
    assert only["flat_days"] >= 20, "the run was flat for about four weeks"
    assert 95 <= only["mean_daily_usd"] <= 98
    assert only["projected_30d_usd"] > 2800


def test_would_have_fired_two_days_after_the_watchdog_started() -> None:
    """2026-08-17 is the first day the rule could see three flat days."""
    assert csc.analyse(series_upto("2026-08-16")) == []
    findings = csc.analyse(series_upto("2026-08-17"))
    assert [f["resource"] for f in findings] == [IDLE_APP]
    assert findings[0]["flat_days"] == 3


def test_no_false_positive_on_real_eval_work() -> None:
    """The July/early-August work is bursty, so nothing should fire."""
    findings = csc.analyse(series_upto("2026-08-14"))
    assert findings == [], f"fired on legitimate work: {findings}"


def test_partial_final_day_breaks_the_run() -> None:
    """2026-09-14 billed $45 against $96 the day before: the run has ended."""
    assert csc.analyse(series_upto("2026-09-14")) == []


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


def test_exit_code_3_when_nothing_could_be_checked() -> None:
    """An all-clear with no provider queried must not look like success."""
    report = csc.build_report(days=7, wanted={"vastai"})
    assert report["checked"] == []
    assert not report["findings"]
