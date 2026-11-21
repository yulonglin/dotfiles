"""custom_bins/work-budget and claude/hooks/enforce_work_budget.py, against a temp state dir."""

import importlib.util
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


_calls = iter(range(1, 10**6))


def bash_event(kind, who, command, call, stdout=""):
    ev = {
        "hook_event_name": kind,
        "tool_name": "Bash",
        "tool_input": {"command": command},
        "tool_use_id": call,
        **who,
    }
    if kind == "PostToolUse":
        ev["tool_response"] = {"stdout": stdout, "stderr": "", "interrupted": False}
    return ev


def run_bash(env, who, command, run):
    """Fire PreToolUse, run `run()` for stdout, fire PostToolUse, as Claude Code does."""
    call = f"toolu_{next(_calls)}"
    hook(env, bash_event("PreToolUse", who, command, call))
    stdout = run()
    hook(env, bash_event("PostToolUse", who, command, call, stdout))
    return stdout


def start(env, who, *args):
    """Run `work-budget start` as `who` through the Bash hooks; return (id, stdout)."""

    def run():
        r = cli(env, "start", *args)
        assert r.returncode == 0, r.stderr
        return r.stdout

    stdout = (
        run()
        if who is None
        else run_bash(env, who, "work-budget start " + " ".join(args), run)
    )
    return stdout.split()[0], stdout


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
    # Another session pastes the whole start output, or re-prints it.
    run_bash(env, OTHER, "cat run.log", lambda: stdout)
    run_bash(env, OTHER, "work-budget start 1h", lambda: stdout)
    assert hook(env, stop(OTHER)) is None
    assert hook(env, stop(MAIN))["decision"] == "block", "the owner is unchanged"


def test_inspecting_an_unclaimed_budget_does_not_claim_it(env):
    bid, stdout = start(env, None, "30m")  # started outside Claude Code
    run_bash(env, OTHER, 'rg -C2 "work-budget start" run.log', lambda: stdout)
    run_bash(env, OTHER, "work-budget start 1h --goal x | tee log", lambda: stdout)
    run_bash(env, OTHER, "echo log; work-budget start 1h", lambda: stdout)
    assert "owner" not in json.loads(budget(env, bid).read_text())
    assert hook(env, stop(OTHER)) is None


def test_a_real_start_claims_only_what_it_created(env):
    old, old_out = start(env, None, "30m")
    rec = json.loads(budget(env, old).read_text())
    rec["created"] = (datetime.now(timezone.utc) - timedelta(seconds=5)).isoformat()
    budget(env, old).write_text(json.dumps(rec))

    def run():
        r = cli(env, "start", "1h")
        return old_out + r.stdout  # the old start line is in this call's output too

    new = run_bash(env, MAIN, "work-budget start 1h", run).splitlines()[-2].split()[0]
    assert "owner" not in json.loads(budget(env, old).read_text())
    assert json.loads(budget(env, new).read_text())["owner"]["session_id"] == "s-main"


def test_parent_and_child_are_different_owners(env):
    start(env, CHILD, "30m")
    assert hook(env, stop(CHILD))["decision"] == "block"
    assert hook(env, stop(MAIN)) is None, "the parent did not start it"


def test_unclaimed_budget_holds_nobody(env):
    start(env, None, "30m")
    assert hook(env, stop(MAIN)) is None


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("work-budget start 2h --goal 'a; b | c'", True),
        ("FOO=1 work-budget start 1h", True),
        ("/Users/x/code/dotfiles/custom_bins/work-budget start 45m", True),
        ("work-budget status", False),
        ('rg "work-budget start" log', False),
        ("work-budget start 1h | tee log", False),
        ("cat log; work-budget start 1h", False),
        ("work-budget start 1h > out", False),
        ("echo $(work-budget start 1h)", False),
        ("work-budget start 'unterminated", False),
    ],
)
def test_only_a_plain_start_command_counts(command, expected):
    spec = importlib.util.spec_from_file_location("ewb", HOOK)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.is_start_call(command) is expected


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
