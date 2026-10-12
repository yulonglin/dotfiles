"""Tests for custom_bins/runrec, run end to end on free commands.

Each refusal in the spec (artifacts/research-run-records/spec.md, R2 and R3)
must exit 2 and leave no run behind; each stop must end in its own status with
the command's whole process group gone. Two tests exist because the
cross-family spec review found the defect they pin: runrec's own heartbeat
writes resetting the idle clock, and a resumed --run-dir crediting old lines
as new progress.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

RUNREC = Path(__file__).resolve().parent.parent / "custom_bins" / "runrec"
FAST = {
    "RUNREC_TICK": "0.1",
    "RUNREC_HEARTBEAT": "0.3",
    "RUNREC_SCAN": "0.2",
    "RUNREC_GRACE_INT": "1",
    "RUNREC_GRACE_TERM": "1",
    "RUNREC_BOARD_INTERVAL": "0.5",
    "RUNREC_API_POLL": "1000",
}

_loader = importlib.machinery.SourceFileLoader("runrec", str(RUNREC))
_spec = importlib.util.spec_from_loader("runrec", _loader)
runrec = importlib.util.module_from_spec(_spec)
_loader.exec_module(runrec)


def launch(
    out: Path, *args: str, env: dict | None = None, timeout: float = 30
) -> subprocess.CompletedProcess:
    e = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("RUNREC_", "OPENROUTER"))
    }
    e.update(FAST, **(env or {}))
    return subprocess.run(
        [sys.executable, str(RUNREC), "launch", "--out-root", str(out), *args],
        capture_output=True,
        text=True,
        env=e,
        timeout=timeout,
        check=False,
        cwd=out.parent,
    )


def events(out: Path) -> list[dict]:
    p = out / "runs.jsonl"
    return (
        [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
    )


def only_run_dir(out: Path) -> Path:
    dirs = [d for d in out.iterdir() if d.is_dir()]
    assert len(dirs) == 1, dirs
    return dirs[0]


@pytest.fixture
def out(tmp_path: Path) -> Path:
    return tmp_path / "out"


# --- refusals -------------------------------------------------------------------


@pytest.mark.parametrize(
    "args, needle",
    [
        (
            ["--slug", "a", "--backend", "modal", "--api-cap", "0", "--", "sleep", "1"],
            "--cost-cap, --rate, --max-idle",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "runpod",
                "--cost-cap",
                "1",
                "--rate",
                "1",
                "--api-cap",
                "0",
                "--",
                "true",
            ],
            "--max-idle",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "local",
                "--api-cap",
                "0",
                "--",
                "modal",
                "run",
                "x.py",
            ],
            "declare the real backend",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "local",
                "--api-cap",
                "0",
                "--",
                "bash",
                "-c",
                "runpodctl create pod",
            ],
            "declare the real backend",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "modal",
                "--cost-cap",
                "1",
                "--rate",
                "1",
                "--max-idle",
                "5m",
                "--api-cap",
                "0",
                "--",
                "modal",
                "deploy",
                "x.py",
            ],
            "modal deploy",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "modal",
                "--cost-cap",
                "1",
                "--rate",
                "1",
                "--max-idle",
                "5m",
                "--api-cap",
                "0",
                "--",
                "modal",
                "run",
                "-d",
                "x.py",
            ],
            "--detach",
        ),
        (
            [
                "--slug",
                "a",
                "--backend",
                "local",
                "--cost-cap",
                "1",
                "--api-cap",
                "0",
                "--",
                "true",
            ],
            "--cost-cap needs --rate",
        ),
        (
            [
                "--slug",
                "Bad Slug",
                "--backend",
                "local",
                "--api-cap",
                "0",
                "--",
                "true",
            ],
            "slug",
        ),
        (
            ["--slug", "a", "--backend", "local", "--api-cap", "2", "--", "true"],
            "OpenRouter balance",
        ),
    ],
)
def test_refusals_exit_2_and_leave_nothing(
    out: Path, args: list[str], needle: str
) -> None:
    r = launch(out, *args)
    assert r.returncode == 2, r.stderr
    assert needle in r.stderr
    assert not out.exists() or not any(out.iterdir())


def test_api_cap_is_required(out: Path) -> None:
    r = launch(out, "--slug", "a", "--backend", "local", "--", "true")
    assert r.returncode == 2 and "--api-cap" in r.stderr


def test_modal_scaledown_longer_than_max_idle_is_refused(
    out: Path, tmp_path: Path
) -> None:
    app = tmp_path / "app.py"
    app.write_text(
        "@app.function(gpu='H100', timeout=600, scaledown_window=20 * 60)\ndef f(): ...\n"
    )
    base = [
        "--slug",
        "a",
        "--backend",
        "modal",
        "--cost-cap",
        "1",
        "--rate",
        "1",
        "--api-cap",
        "0",
    ]
    r = launch(out, *base, "--max-idle", "5m", "--", "modal", "run", str(app))
    assert (
        r.returncode == 2
        and "scaledown_window=1200s exceeds --max-idle 300s" in r.stderr
    )


def test_modal_function_without_timeout_warns(tmp_path: Path) -> None:
    app = tmp_path / "app.py"
    app.write_text("@app.function(gpu='H100', scaledown_window=60)\ndef f(): ...\n")
    refusals, warnings = runrec.scan_modal_files(["modal", "run", f"{app}::f"], 300)
    assert refusals == [] and any("no timeout" in w for w in warnings)


# --- record ---------------------------------------------------------------------


def test_success_writes_index_manifest_and_log(out: Path, tmp_path: Path) -> None:
    cfg = tmp_path / "exp.yaml"
    cfg.write_text("n: 2\n")
    r = launch(
        out,
        "--slug",
        "ok",
        "--backend",
        "local",
        "--api-cap",
        "0",
        "--config",
        str(cfg),
        "--",
        "sh",
        "-c",
        'echo hello; echo "$RUN_ID" > "$RUN_DIR/id"',
    )
    assert r.returncode == 0, r.stderr
    run_dir = only_run_dir(out)
    assert run_dir.name.endswith("_ok")
    ev = events(out)
    assert [e["event"] for e in ev] == ["launch", "finish"]
    assert ev[1]["status"] == "succeeded" and ev[1]["exit_code"] == 0
    launch_rec = json.loads((run_dir / "manifest.json").read_text())["launch"]
    assert launch_rec["schema"] == "run-launch/1"
    assert (run_dir / "id").read_text().strip() == launch_rec["run_id"]
    assert (
        launch_rec["config"][0]["sha256"] and (run_dir / "config" / "exp.yaml").exists()
    )
    assert "hello" in (run_dir / "launch.log").read_text()


def test_failure_exit_code_propagates(out: Path) -> None:
    r = launch(
        out,
        "--slug",
        "bad",
        "--backend",
        "local",
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        "exit 3",
    )
    assert r.returncode == 3
    assert events(out)[-1]["status"] == "failed"


def test_existing_run_dir_is_refused(out: Path) -> None:
    assert (
        launch(
            out, "--slug", "dup", "--backend", "local", "--api-cap", "0", "--", "true"
        ).returncode
        == 0
    )
    r = launch(
        out, "--slug", "dup", "--backend", "local", "--api-cap", "0", "--", "true"
    )
    assert r.returncode == 2 and "already exists" in r.stderr


def test_script_that_clobbers_manifest_keeps_its_keys_and_gains_launch(
    out: Path,
) -> None:
    script = 'printf \'{"schema_version":"run-manifest/1","stages":{"judge":1}}\' > "$RUN_DIR/manifest.json"; sleep 1'
    r = launch(
        out,
        "--slug",
        "clob",
        "--backend",
        "local",
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        script,
    )
    assert r.returncode == 0, r.stderr
    m = json.loads((only_run_dir(out) / "manifest.json").read_text())
    assert m["stages"] == {"judge": 1} and m["schema_version"] == "run-manifest/1"
    assert m["launch"]["status"] == "succeeded"


def test_four_concurrent_launches_write_eight_clean_lines(out: Path) -> None:
    with ThreadPoolExecutor(4) as pool:
        results = list(
            pool.map(
                lambda i: launch(
                    out,
                    "--slug",
                    f"c{i}",
                    "--backend",
                    "local",
                    "--api-cap",
                    "0",
                    "--",
                    "sleep",
                    "0.5",
                ),
                range(4),
            )
        )
    assert all(r.returncode == 0 for r in results), [r.stderr for r in results]
    ev = events(out)
    assert len(ev) == 8 and len({e["run_id"] for e in ev}) == 4


# --- stops ----------------------------------------------------------------------


def _assert_group_gone(pidfile: Path) -> None:
    pid = int(pidfile.read_text())
    time.sleep(0.2)
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


def test_cost_cap_stops_the_whole_group(out: Path, tmp_path: Path) -> None:
    pidfile = tmp_path / "pid"
    # A background grandchild that would outlive a plain kill of the direct child.
    script = f"sleep 60 & echo $! > {pidfile}; wait"
    r = launch(
        out,
        "--slug",
        "cost",
        "--backend",
        "runpod",
        "--cost-cap",
        "1",
        "--rate",
        "3600",
        "--max-idle",
        "1h",
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        script,
    )
    assert r.returncode == 124, r.stderr
    assert events(out)[-1]["status"] == "stopped:cost"
    _assert_group_gone(pidfile)


def test_timeout_stop(out: Path) -> None:
    r = launch(
        out,
        "--slug",
        "to",
        "--backend",
        "local",
        "--timeout",
        "1s",
        "--api-cap",
        "0",
        "--",
        "sleep",
        "30",
    )
    assert r.returncode == 124
    assert events(out)[-1]["status"] == "stopped:timeout"


def test_idle_stop_is_not_reset_by_runrec_heartbeats(out: Path) -> None:
    # Heartbeats rewrite launch.json every 0.3 s; a silent command must still go idle.
    t0 = time.time()
    r = launch(
        out,
        "--slug",
        "idle",
        "--backend",
        "local",
        "--max-idle",
        "2s",
        "--api-cap",
        "0",
        "--",
        "sleep",
        "30",
    )
    assert r.returncode == 124
    assert events(out)[-1]["status"] == "stopped:idle"
    assert time.time() - t0 < 10


def test_log_chatter_without_progress_is_idle(out: Path, tmp_path: Path) -> None:
    prog = tmp_path / "results.jsonl"
    prog.touch()
    script = "while true; do echo retrying; sleep 0.2; done"
    r = launch(
        out,
        "--slug",
        "chatty",
        "--backend",
        "local",
        "--max-idle",
        "2s",
        "--progress-path",
        str(prog),
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        script,
    )
    assert r.returncode == 124
    assert events(out)[-1]["status"] == "stopped:idle"


def test_steady_progress_is_not_idle(out: Path, tmp_path: Path) -> None:
    prog = tmp_path / "results.jsonl"
    script = f"for i in 1 2 3 4 5 6; do echo '{{}}' >> {prog}; sleep 0.5; done"
    r = launch(
        out,
        "--slug",
        "steady",
        "--backend",
        "local",
        "--max-idle",
        "2s",
        "--progress-path",
        str(prog),
        "--expect-n",
        "6",
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        script,
    )
    assert r.returncode == 0, r.stderr
    assert events(out)[-1]["status"] == "succeeded"
    m = json.loads((only_run_dir(out) / "manifest.json").read_text())["launch"]
    assert m["progress"]["done"] == 6


def test_resumed_run_dir_counts_only_new_progress(out: Path, tmp_path: Path) -> None:
    run_dir = tmp_path / "resume"
    run_dir.mkdir()
    prog = run_dir / "results.jsonl"
    prog.write_text("{}\n" * 5)
    r = launch(
        out,
        "--slug",
        "resume",
        "--backend",
        "local",
        "--run-dir",
        str(run_dir),
        "--progress-path",
        str(prog),
        "--api-cap",
        "0",
        "--",
        "sh",
        "-c",
        f"echo '{{}}' >> {prog}",
    )
    assert r.returncode == 0, r.stderr
    m = json.loads((run_dir / "manifest.json").read_text())["launch"]
    assert m["progress"] == {
        "done": 1,
        "expected": None,
        "path": str(prog),
        "baseline": 5,
    }


def test_sigterm_to_wrapper_is_interrupted(out: Path) -> None:
    e = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("RUNREC_", "OPENROUTER"))
    }
    e.update(FAST)
    p = subprocess.Popen(
        [
            sys.executable,
            str(RUNREC),
            "launch",
            "--out-root",
            str(out),
            "--slug",
            "int",
            "--backend",
            "local",
            "--api-cap",
            "0",
            "--",
            "sleep",
            "30",
        ],
        env=e,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(1)
    p.send_signal(signal.SIGTERM)
    assert p.wait(timeout=15) == 124
    assert events(out)[-1]["status"] == "interrupted"


@pytest.mark.skipif(
    not sys.platform.startswith("linux"), reason="PR_SET_PDEATHSIG is Linux-only"
)
def test_sigkilled_wrapper_takes_the_command_with_it_and_shows_lost(
    out: Path, tmp_path: Path
) -> None:
    pidfile = tmp_path / "pid"
    e = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("RUNREC_", "OPENROUTER"))
    }
    e.update(FAST)
    p = subprocess.Popen(
        [
            sys.executable,
            str(RUNREC),
            "launch",
            "--out-root",
            str(out),
            "--slug",
            "orphan",
            "--backend",
            "local",
            "--api-cap",
            "0",
            "--",
            "sh",
            "-c",
            f"echo $$ > {pidfile}; exec sleep 60",
        ],
        env=e,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.5)
    p.kill()
    p.wait()
    _assert_group_gone(pidfile)
    time.sleep(1.2)  # three 0.3 s heartbeats
    board = runrec.render_board(out, {})
    assert "`orphan`" in board.split("## Lost")[1]


# --- API preflight ----------------------------------------------------------------


def test_account_empty_refuses_even_with_key_headroom(monkeypatch) -> None:
    replies = {
        "/key": {"limit_remaining": 50.0, "usage": 10.0},
        "/credits": {"total_credits": 20.0, "total_usage": 19.5},
    }
    monkeypatch.setattr(runrec, "openrouter_get", lambda path, key: replies[path])
    assert runrec.openrouter_state("k") == (0.5, 10.0)


def test_unlimited_key_without_management_key_is_unknown(monkeypatch) -> None:
    replies = {"/key": {"limit_remaining": None, "usage": 3.0}, "/credits": None}
    monkeypatch.setattr(runrec, "openrouter_get", lambda path, key: replies[path])
    assert runrec.openrouter_state("k") == (None, 3.0)


# --- board ----------------------------------------------------------------------


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def test_board_marks_lost_and_computes_eta(out: Path, tmp_path: Path) -> None:
    out.mkdir()
    t = datetime.now(timezone.utc)
    base = {
        "backend": "modal",
        "host": "hn",
        "caps": {"api_cap_usd": 0, "cost_cap_usd": 10, "timeout_s": 3600},
        "spend": {"gpu_est_usd": 1.0, "api_usd_upper": None},
        "heartbeat_s": 60,
    }
    for slug, hb, prog in (
        ("dead", t - timedelta(minutes=10), {"done": None, "expected": None}),
        ("alive", t, {"done": 25, "expected": 100}),
    ):
        d = tmp_path / slug
        d.mkdir()
        rec = {
            **base,
            "run_id": slug,
            "slug": slug,
            "run_dir": str(d),
            "status": "running",
            "started_at": _iso(t - timedelta(minutes=20)),
            "heartbeat_at": _iso(hb),
            "progress": prog,
        }
        (d / "launch.json").write_text(json.dumps(rec))
        runrec.append_event(out, {"event": "launch", **rec})
    board = runrec.render_board(out, {"project": "demo"})
    assert "# Run board: demo" in board
    lost = board.split("## Lost")[1].split("## Recent")[0]
    running = board.split("## Running")[1].split("## Lost")[0]
    assert "`dead`" in lost and "`dead`" not in running
    assert (
        "`alive`" in running and "| 60m |" in running
    )  # 25 of 100 in 20 min leaves 60 min
    assert "$1.00 est / $10.00" in running


def test_board_says_no_eta_without_denominator(out: Path) -> None:
    r = launch(out, "--slug", "x", "--backend", "local", "--api-cap", "0", "--", "true")
    assert r.returncode == 0
    run = runrec.read_runs(out)[0]
    run.update(
        status="running", heartbeat_at=_iso(datetime.now(timezone.utc)), ended_at=None
    )
    view = runrec.run_view(run, datetime.now(timezone.utc))
    assert runrec.cell_eta(view) == "no ETA"


def test_board_file_is_written_from_runrec_json(out: Path, tmp_path: Path) -> None:
    out.mkdir()
    board = tmp_path / "vault" / "run-board.md"
    (out / "runrec.json").write_text(
        json.dumps({"project": "demo", "board": str(board)})
    )
    assert (
        launch(
            out, "--slug", "b", "--backend", "local", "--api-cap", "0", "--", "true"
        ).returncode
        == 0
    )
    text = board.read_text()
    assert "`b` | succeeded" in text
