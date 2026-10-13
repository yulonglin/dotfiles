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
MAIN = {"session_id": "s-main"}
CHILD = {"session_id": "s-main", "agent_id": "a-child"}
OTHER = {"session_id": "s-other"}


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


def bash_event(who, command, stdout):
    return {
        "hook_event_name": "PostToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command},
        "tool_response": {"stdout": stdout, "stderr": "", "interrupted": False},
        **who,
    }


def start(env, who, *args):
    """Run `work-budget start` as `who` and fire the PostToolUse claim; return (id, stdout)."""
    r = cli(env, "start", *args)
    assert r.returncode == 0, r.stderr
    if who is not None:
        hook(env, bash_event(who, "work-budget start " + " ".join(args), r.stdout))
    return r.stdout.split()[0], r.stdout


def budget(env, bid):
    return Path(env["XDG_STATE_HOME"]) / "work-budget" / f"{bid}.json"


def stop(who, **extra):
    kind = "SubagentStop" if who.get("agent_id") else "Stop"
    return {"hook_event_name": kind, "stop_hook_active": False, **who, **extra}


def test_owner_is_held_with_goal_and_count(env):
    bid, _ = start(env, MAIN, "30m", "--goal", "beat the probe baseline")
    assert json.loads(budget(env, bid).read_text())["owner"] == {
        "session_id": "s-main",
        "agent_id": None,
    }
    out = hook(env, stop(MAIN))
    assert out["decision"] == "block"
    assert bid in out["reason"] and "beat the probe baseline" in out["reason"]
    assert "refused 1 of 30" in out["reason"]
    assert json.loads(budget(env, bid).read_text())["blocks"] == 1


def test_seeing_the_start_line_is_not_ownership(env):
    _, stdout = start(env, MAIN, "30m")
    # Another session pastes the whole start output, or runs a command that prints it.
    hook(env, bash_event(OTHER, "cat run.log", stdout))
    hook(env, bash_event(OTHER, "work-budget start 1h # copy of their log", stdout))
    assert hook(env, stop(OTHER)) is None
    assert hook(env, stop(MAIN))["decision"] == "block", "the owner is unchanged"


def test_parent_and_child_are_different_owners(env):
    start(env, CHILD, "30m")
    assert hook(env, stop(CHILD))["decision"] == "block"
    assert hook(env, stop(MAIN)) is None, "the parent did not start it"


def test_unclaimed_or_late_claimed_budget_holds_nobody(env):
    bid, stdout = start(env, None, "30m")
    assert hook(env, stop(MAIN)) is None, "no PostToolUse claim, no owner"
    rec = json.loads(budget(env, bid).read_text())
    rec["start"] = (datetime.now(timezone.utc) - timedelta(minutes=11)).isoformat()
    budget(env, bid).write_text(json.dumps(rec))
    hook(env, bash_event(MAIN, "work-budget start 30m", stdout))
    assert "owner" not in json.loads(budget(env, bid).read_text()), (
        "claim window passed"
    )


def test_stop_expiry_cap_and_kill_release(env):
    bid, _ = start(env, MAIN, "30m", "--max-blocks", "2")
    assert hook(env, stop(MAIN))
    assert hook(env, stop(MAIN))
    assert hook(env, stop(MAIN)) is None, "max_blocks spent"

    bid, _ = start(env, MAIN, "30m")
    assert cli(env, "stop", bid, "goal met").returncode == 0
    assert hook(env, stop(MAIN)) is None, "stopped"

    bid, _ = start(env, MAIN, "30m")
    rec = json.loads(budget(env, bid).read_text())
    rec["until"] = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    budget(env, bid).write_text(json.dumps(rec))
    assert hook(env, stop(MAIN)) is None, "expired"

    start(env, MAIN, "30m")
    (Path(env["XDG_STATE_HOME"]) / "work-budget" / "KILL").touch()
    assert hook(env, stop(MAIN)) is None, "KILL file"


def test_waiting_on_background_work_is_not_held(env):
    start(env, MAIN, "30m")
    running = [{"id": "t1", "type": "shell", "status": "running"}]
    assert hook(env, stop(MAIN, background_tasks=running)) is None
    assert hook(env, stop(MAIN, session_crons=[{"id": "c1"}])) is None
    done = [{"id": "t1", "type": "shell", "status": "completed"}]
    assert hook(env, stop(MAIN, background_tasks=done))["decision"] == "block"


def test_fails_open(env):
    start(env, MAIN, "30m")
    assert hook(env, "not json") is None
    assert hook(env, {"hook_event_name": "Stop"}) is None, "no session_id"


@pytest.mark.parametrize("bad", ["0m", "25h", "soon", ""])
def test_rejects_bad_durations(env, bad):
    assert cli(env, "start", bad).returncode != 0


def test_stop_all_and_status(env):
    start(env, MAIN, "30m", "--goal", "g1")
    start(env, MAIN, "1h")
    assert "min left" in cli(env, "status").stdout
    assert cli(env, "stop", "--all", "wrapping up").returncode == 0
    assert cli(env, "status").stdout.count("stopped: wrapping up") == 2
