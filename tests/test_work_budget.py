"""custom_bins/work-budget and claude/hooks/enforce_work_budget.py, against a temp state dir."""

import json
import os
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
CLI = REPO / "custom_bins" / "work-budget"
HOOK = REPO / "claude" / "hooks" / "enforce_work_budget.py"


@pytest.fixture
def env(tmp_path):
    return {**os.environ, "XDG_STATE_HOME": str(tmp_path / "state")}


def cli(env, *args):
    return subprocess.run(
        [str(CLI), *args], env=env, capture_output=True, text=True, check=False
    )


def hook(env, event):
    stdin = event if isinstance(event, str) else json.dumps(event)
    r = subprocess.run(
        ["python3", str(HOOK)],
        env=env,
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 0
    return json.loads(r.stdout) if r.stdout.strip() else None


def start(env, tmp_path, *args):
    r = cli(env, "start", *args)
    assert r.returncode == 0, r.stderr
    line = r.stdout.splitlines()[0]
    owner = tmp_path / "owner.jsonl"
    owner.write_text(json.dumps({"type": "tool_result", "content": r.stdout}) + "\n")
    return line.split()[0], owner


def budget(env, bid):
    return Path(env["XDG_STATE_HOME"]) / "work-budget" / f"{bid}.json"


def stop_event(transcript, **extra):
    return {
        "hook_event_name": "Stop",
        "transcript_path": str(transcript),
        "stop_hook_active": False,
        **extra,
    }


def test_owner_is_held_with_goal_and_count(env, tmp_path):
    bid, owner = start(env, tmp_path, "30m", "--goal", "beat the probe baseline")
    out = hook(env, stop_event(owner))
    assert out["decision"] == "block"
    assert bid in out["reason"] and "beat the probe baseline" in out["reason"]
    assert "refused 1 of 30" in out["reason"]
    assert json.loads(budget(env, bid).read_text())["blocks"] == 1


def test_other_session_is_never_held(env, tmp_path):
    bid, _ = start(env, tmp_path, "30m")
    other = tmp_path / "other.jsonl"
    other.write_text(json.dumps({"content": f"saw {bid} in a status listing"}) + "\n")
    assert hook(env, stop_event(other)) is None


def test_stop_expiry_cap_and_kill_release(env, tmp_path):
    bid, owner = start(env, tmp_path, "30m", "--max-blocks", "2")
    assert hook(env, stop_event(owner))
    assert hook(env, stop_event(owner))
    assert hook(env, stop_event(owner)) is None, "max_blocks spent"

    bid, owner = start(env, tmp_path, "30m")
    assert cli(env, "stop", bid, "goal met").returncode == 0
    assert hook(env, stop_event(owner)) is None, "stopped"

    bid, owner = start(env, tmp_path, "30m")
    rec = json.loads(budget(env, bid).read_text())
    rec["until"] = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    budget(env, bid).write_text(json.dumps(rec))
    assert hook(env, stop_event(owner)) is None, "expired"

    bid, owner = start(env, tmp_path, "30m")
    (Path(env["XDG_STATE_HOME"]) / "work-budget" / "KILL").touch()
    assert hook(env, stop_event(owner)) is None, "KILL file"


def test_waiting_on_background_work_is_not_held(env, tmp_path):
    _, owner = start(env, tmp_path, "30m")
    running = [{"id": "t1", "type": "shell", "status": "running"}]
    assert hook(env, stop_event(owner, background_tasks=running)) is None
    assert hook(env, stop_event(owner, session_crons=[{"id": "c1"}])) is None
    done = [{"id": "t1", "type": "shell", "status": "completed"}]
    assert hook(env, stop_event(owner, background_tasks=done))["decision"] == "block"


def test_subagent_is_judged_by_its_own_transcript(env, tmp_path):
    _, agent = start(env, tmp_path, "30m")
    parent = tmp_path / "parent.jsonl"
    parent.write_text("{}\n")
    ev = {
        "hook_event_name": "SubagentStop",
        "transcript_path": str(parent),
        "agent_transcript_path": str(agent),
    }
    assert hook(env, ev)["decision"] == "block"
    assert hook(env, stop_event(parent)) is None, "the parent did not start it"


def test_fails_open(env, tmp_path):
    start(env, tmp_path, "30m")
    assert hook(env, "not json") is None
    assert hook(env, stop_event(tmp_path / "missing.jsonl")) is None


@pytest.mark.parametrize("bad", ["0m", "25h", "soon", ""])
def test_rejects_bad_durations(env, bad):
    assert cli(env, "start", bad).returncode != 0


def test_stop_all_and_status(env, tmp_path):
    start(env, tmp_path, "30m", "--goal", "g1")
    start(env, tmp_path, "1h")
    assert "min left" in cli(env, "status").stdout
    assert cli(env, "stop", "--all", "wrapping up").returncode == 0
    assert cli(env, "status").stdout.count("stopped: wrapping up") == 2
