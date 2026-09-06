"""claude-jobs-reap: the unpin pass and its interaction with reaping.

Pins live in <jobs>/pins.json (a JSON array of job ids) and the agents view
merges them into rows on read, so this is the file the unpin pass edits. The
CLI guards it with a proper-lockfile directory `pins.json.lock` (stale after
5 s); the reaper must honour a live lock and break a stale one.
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

REAPER = Path(__file__).resolve().parent.parent / "custom_bins" / "claude-jobs-reap"

# No .py suffix, so spec_from_file_location would return None; name the loader explicitly.
_loader = importlib.machinery.SourceFileLoader("claude_jobs_reap", str(REAPER))
spec = importlib.util.spec_from_loader(_loader.name, _loader)
reap = importlib.util.module_from_spec(spec)
_loader.exec_module(reap)

DAY = 86400.0


def make_job(jobs: Path, name: str, age_days: float, state: str = "done", order: bool = False) -> Path:
    job = jobs / name
    job.mkdir()
    updated = datetime.now(timezone.utc) - timedelta(days=age_days)
    (job / "state.json").write_text(json.dumps({"state": state, "updatedAt": updated.isoformat().replace("+00:00", "Z")}))
    if order:
        (job / "order").write_text("1788248652217")
    stamp = updated.timestamp()
    os.utime(job / "state.json", (stamp, stamp))
    os.utime(job, (stamp, stamp))
    return job


def write_pins(jobs: Path, pins: list[str]) -> Path:
    pins_file = jobs / "pins.json"
    pins_file.write_text(json.dumps(pins, indent=2))
    return pins_file


def run(jobs: Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    full_env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_JOB")}
    full_env.update(env or {})
    return subprocess.run(
        [sys.executable, str(REAPER), "--jobs-dir", str(jobs), *args],
        capture_output=True,
        text=True,
        env=full_env,
    )


def test_idle_pin_is_dropped_and_its_order_sidecar_removed(tmp_path):
    make_job(tmp_path, "idle0001", age_days=4, order=True)
    make_job(tmp_path, "fresh001", age_days=1, order=True)
    write_pins(tmp_path, ["idle0001", "fresh001"])

    result = run(tmp_path, "--days", "30")

    assert result.returncode == 0, result.stderr
    assert json.loads((tmp_path / "pins.json").read_text()) == ["fresh001"]
    assert not (tmp_path / "idle0001" / "order").exists()
    assert (tmp_path / "fresh001" / "order").exists(), "the CLI only deletes the sidecar of the job it unpins"
    assert "unpinned 1" in result.stdout


def test_order_sidecar_of_unpinned_job_is_left_alone(tmp_path):
    # `order` also exists on jobs that were never pinned; the pass must not touch those.
    make_job(tmp_path, "idle0001", age_days=4)
    make_job(tmp_path, "other001", age_days=4, order=True)
    write_pins(tmp_path, ["idle0001"])

    run(tmp_path, "--days", "30")

    assert (tmp_path / "other001" / "order").exists()


def test_dangling_pin_is_dropped(tmp_path):
    make_job(tmp_path, "fresh001", age_days=0.5)
    write_pins(tmp_path, ["gone0001", "fresh001"])

    result = run(tmp_path, "-v")

    assert result.returncode == 0, result.stderr
    assert json.loads((tmp_path / "pins.json").read_text()) == ["fresh001"]
    assert "unpin gone0001: job dir gone" in result.stdout


def test_active_state_does_not_shield_a_pin(tmp_path):
    # The 30-day active grace exists because deletion is irreversible; unpinning is not.
    make_job(tmp_path, "runn0001", age_days=4, state="running")
    write_pins(tmp_path, ["runn0001"])

    run(tmp_path)

    assert json.loads((tmp_path / "pins.json").read_text()) == []
    assert (tmp_path / "runn0001").is_dir(), "still inside the active grace, so not reaped"


def test_pin_order_is_preserved(tmp_path):
    for name in ("aaaa0001", "bbbb0001", "cccc0001"):
        make_job(tmp_path, name, age_days=1)
    make_job(tmp_path, "idle0001", age_days=9)
    write_pins(tmp_path, ["cccc0001", "idle0001", "aaaa0001", "bbbb0001"])

    run(tmp_path)

    assert json.loads((tmp_path / "pins.json").read_text()) == ["cccc0001", "aaaa0001", "bbbb0001"]


def test_dry_run_leaves_pins_byte_identical(tmp_path):
    make_job(tmp_path, "idle0001", age_days=4, order=True)
    pins_file = write_pins(tmp_path, ["idle0001", "gone0001"])
    before = pins_file.read_bytes()

    result = run(tmp_path, "--dry-run")

    assert result.returncode == 0, result.stderr
    assert pins_file.read_bytes() == before
    assert (tmp_path / "idle0001" / "order").exists()
    assert "would unpin idle0001" in result.stdout
    assert "would unpin gone0001" in result.stdout
    assert "would unpin 2; would reap 0 job(s)" in result.stdout


def test_live_lock_skips_the_pass_without_writing(tmp_path):
    make_job(tmp_path, "idle0001", age_days=4)
    pins_file = write_pins(tmp_path, ["idle0001"])
    (tmp_path / "pins.json.lock").mkdir()  # fresh mtime: a live Claude Code process holds it

    result = run(tmp_path)

    assert result.returncode == 0, result.stderr
    assert json.loads(pins_file.read_text()) == ["idle0001"]
    assert (tmp_path / "pins.json.lock").is_dir(), "never break a live lock"
    assert "skipping unpin" in result.stderr
    assert "unpin skipped (locked)" in result.stdout


def test_stale_lock_is_broken_and_released(tmp_path):
    make_job(tmp_path, "idle0001", age_days=4)
    pins_file = write_pins(tmp_path, ["idle0001"])
    lock = tmp_path / "pins.json.lock"
    lock.mkdir()
    old = time.time() - reap.PIN_LOCK_STALE_SECONDS - 60
    os.utime(lock, (old, old))

    result = run(tmp_path)

    assert result.returncode == 0, result.stderr
    assert json.loads(pins_file.read_text()) == []
    assert not lock.exists(), "our own lock is released after the write"


def test_lock_dir_is_not_mistaken_for_a_job(tmp_path):
    make_job(tmp_path, "fresh001", age_days=1)
    write_pins(tmp_path, ["fresh001"])
    lock = tmp_path / "pins.json.lock"
    lock.mkdir()
    old = time.time() - 40 * DAY
    os.utime(lock, (old, old))

    result = run(tmp_path, "-v")

    assert "pins.json.lock" not in result.stdout


def test_pinned_job_is_exempt_from_reaping(tmp_path):
    # Only reachable when --unpin-days exceeds --days: a pin means keep.
    make_job(tmp_path, "pinn0001", age_days=10)
    make_job(tmp_path, "loose001", age_days=10)
    write_pins(tmp_path, ["pinn0001"])

    result = run(tmp_path, "--days", "7", "--unpin-days", "30")

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "pinn0001").is_dir()
    assert not (tmp_path / "loose001").exists()
    assert "kept 0 recent, 0 active, 1 pinned" in result.stdout


def test_keep_pins_flag_skips_unpin_but_still_shields(tmp_path):
    make_job(tmp_path, "pinn0001", age_days=10)
    write_pins(tmp_path, ["pinn0001"])

    result = run(tmp_path, "--keep-pins")

    assert json.loads((tmp_path / "pins.json").read_text()) == ["pinn0001"]
    assert (tmp_path / "pinn0001").is_dir()
    assert "unpinned 0" in result.stdout


def test_current_session_is_never_unpinned(tmp_path):
    job = make_job(tmp_path, "self0001", age_days=10)
    write_pins(tmp_path, ["self0001"])

    result = run(tmp_path, env={"CLAUDE_JOB_DIR": str(job)})

    assert result.returncode == 0, result.stderr
    assert json.loads((tmp_path / "pins.json").read_text()) == ["self0001"]
    assert job.is_dir()


def test_env_vars_set_the_defaults(tmp_path):
    make_job(tmp_path, "idle0001", age_days=2)
    make_job(tmp_path, "olde0001", age_days=5)
    write_pins(tmp_path, ["idle0001"])

    result = run(tmp_path, env={"CLAUDE_JOBS_REAP_UNPIN_DAYS": "1", "CLAUDE_JOBS_REAP_DAYS": "4"})

    assert result.returncode == 0, result.stderr
    assert json.loads((tmp_path / "pins.json").read_text()) == []
    assert not (tmp_path / "olde0001").exists()
    assert (tmp_path / "idle0001").is_dir()


def test_flags_override_env(tmp_path):
    make_job(tmp_path, "idle0001", age_days=2)
    write_pins(tmp_path, ["idle0001"])

    run(tmp_path, "--unpin-days", "5", env={"CLAUDE_JOBS_REAP_UNPIN_DAYS": "1"})

    assert json.loads((tmp_path / "pins.json").read_text()) == ["idle0001"]


def test_bad_env_value_falls_back_to_default(tmp_path):
    make_job(tmp_path, "idle0001", age_days=2)
    write_pins(tmp_path, ["idle0001"])

    result = run(tmp_path, env={"CLAUDE_JOBS_REAP_UNPIN_DAYS": "soon"})

    assert result.returncode == 0
    assert "ignoring CLAUDE_JOBS_REAP_UNPIN_DAYS" in result.stderr
    assert json.loads((tmp_path / "pins.json").read_text()) == ["idle0001"], "2d < default 3d"


@pytest.mark.parametrize("flag", ["--days", "--unpin-days"])
def test_negative_threshold_is_rejected(tmp_path, flag):
    result = run(tmp_path, flag, "-1")
    assert result.returncode == 2
    assert "non-negative" in result.stderr


def test_no_pins_file_is_fine(tmp_path):
    make_job(tmp_path, "olde0001", age_days=10)

    result = run(tmp_path)

    assert result.returncode == 0, result.stderr
    assert not (tmp_path / "pins.json").exists()
    assert not (tmp_path / "olde0001").exists()
