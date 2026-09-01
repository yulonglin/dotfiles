#!/usr/bin/env python3
"""Regression tests: a rotated ANTHROPIC_API_KEY must heal on the 401, once.

Why this file exists. `.envrc` cannot watch a *remote* secret's value, so a
long-lived shell keeps exporting the pre-rotation key from its direnv snapshot,
and `with-anthropic-key.sh` deliberately defers to an already-set key. Every
hook in that session then inherits a dead key: the approval classifier fails
open on every tool call, and `anthropic_keycheck.py` prints the red "API key was
rejected" warning at every session start until the shell is replaced.

The fix is reactive recovery in `post_anthropic()`, shared by both callers. What
these tests pin is as much the CONSTRAINTS as the feature, because each one
would fail silently if broken:

  * Happy path  -- exactly ONE urlopen and ZERO subprocess calls. This hook runs
                   on the approval-classifier hot path for every tool call inside
                   a 30s budget, so an added validation ping or an unconditional
                   `dotfiles-secrets` call is a latency regression that no
                   functional test would notice.
  * One retry   -- exactly TWO urlopens on a double 401. A loop here multiplies
                   the hook's worst-case latency by however many times it loops.
  * 401 only    -- 403 and 429 must not re-resolve. `classify_api_problem` groups
                   401/403 for *messaging*; a different key value does not change
                   a permissions answer.
  * Fail open   -- every skip path (short budget, helper failure, helper exit 0
                   with no output, same key back) surfaces the ORIGINAL 401
                   rather than swallowing it.

No network and no real secret: urlopen and subprocess.run are both replaced with
capturing fakes, and SECRETS_HELPER points at a stub executable that is never
actually executed.
"""
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import time
import urllib.error
import urllib.request

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOKS = ROOT / "claude" / "hooks"
CLASSIFIER = pathlib.Path(
    os.environ.get("APPROVAL_CLASSIFIER_PATH") or HOOKS / "approval_classifier.py"
)
KEYCHECK = HOOKS / "anthropic_keycheck.py"

STALE_KEY = "sk-ant-stale-key-value-not-real"
FRESH_KEY = "sk-ant-fresh-key-value-not-real"


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def ac():
    # Function-scoped on purpose: post_anthropic mutates os.environ and the
    # module's budget clock starts at import, so a module shared across tests
    # would leak state between them.
    return load_module(CLASSIFIER, "approval_classifier")


def http_error(code, error_type="authentication_error", message="invalid x-api-key"):
    body = json.dumps({"error": {"type": error_type, "message": message}}).encode()
    return urllib.error.HTTPError(
        "https://api.anthropic.com/v1/messages", code, "err", {}, io.BytesIO(body)
    )


class Resp:
    def __init__(self, payload):
        self._payload = payload

    def read(self):
        return json.dumps(self._payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


VERDICT = {"content": [{"type": "text", "text": '{"decision":"allow","reason":"t"}'}]}


@pytest.fixture
def rig(ac, monkeypatch, tmp_path):
    """Wire up fake urlopen / fake helper and record every call."""
    calls = {"urlopen": [], "run": [], "log": []}

    # A real executable file so os.access(X_OK) passes; never actually run,
    # because subprocess.run is faked below.
    stub = tmp_path / "dotfiles-secrets"
    stub.write_text("#!/bin/sh\nexit 1\n")
    stub.chmod(0o755)
    monkeypatch.setattr(ac, "SECRETS_HELPER", str(stub))

    monkeypatch.setattr(ac, "log", lambda msg: calls["log"].append(msg))
    # Pinned rather than measured: the real budget counts down from module import,
    # so a slow suite would otherwise start skipping the retry non-deterministically.
    # post_anthropic now takes the budget as an argument, so tests hand it
    # rig.remaining; the module global stays pinned too because classify() is the
    # caller that supplies it.
    budget = {"seconds": 20.0}
    monkeypatch.setattr(ac, "remaining_budget", lambda: budget["seconds"])
    monkeypatch.setenv("ANTHROPIC_API_KEY", STALE_KEY)

    def set_responses(*responses):
        queue = list(responses)

        def fake_urlopen(req, timeout=None):
            calls["urlopen"].append({
                "key": req.get_header("X-api-key"),
                "timeout": timeout,
                "body": json.loads(req.data),
            })
            item = queue.pop(0)
            if isinstance(item, Exception):
                raise item
            return Resp(item)

        monkeypatch.setattr(ac.urllib.request, "urlopen", fake_urlopen)

    def set_helper(returncode=0, stdout=FRESH_KEY + "\n", exc=None):
        def fake_run(cmd, **kwargs):
            calls["run"].append({"cmd": cmd, "kwargs": kwargs})
            if exc is not None:
                raise exc
            return subprocess.CompletedProcess(cmd, returncode, stdout=stdout, stderr=None)

        monkeypatch.setattr(ac.subprocess, "run", fake_run)

    rig = type("Rig", (), {})()
    rig.calls = calls
    rig.set_responses = set_responses
    rig.set_helper = set_helper
    rig.set_budget = lambda seconds: budget.__setitem__("seconds", seconds)
    rig.remaining = lambda: budget["seconds"]
    rig.helper_path = str(stub)
    return rig


# --- the happy path must stay free ------------------------------------------

def test_happy_path_makes_one_call_and_never_shells_out(ac, rig):
    rig.set_responses(VERDICT)
    rig.set_helper()

    ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert len(rig.calls["urlopen"]) == 1
    assert rig.calls["run"] == [], (
        "A 200 must not touch dotfiles-secrets. This hook runs for every tool "
        "call inside a 30s budget; a BWS call here is a per-tool-call latency tax."
    )
    assert rig.calls["urlopen"][0]["key"] == STALE_KEY


# --- 401: re-resolve and retry exactly once ---------------------------------

def test_401_reresolves_the_key_and_retries_once(ac, rig):
    rig.set_responses(http_error(401), VERDICT)
    rig.set_helper()

    ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert len(rig.calls["urlopen"]) == 2
    # The SECOND request must carry the fresh key. Reusing the first Request
    # object would resend the stale header and silently retry nothing.
    assert rig.calls["urlopen"][0]["key"] == STALE_KEY
    assert rig.calls["urlopen"][1]["key"] == FRESH_KEY
    # The rest of the process must see the working key too.
    assert os.environ["ANTHROPIC_API_KEY"] == FRESH_KEY
    assert rig.calls["run"][0]["cmd"] == [
        rig.helper_path, "get-value", "ANTHROPIC_API_KEY",
    ]


def test_helper_stdout_is_captured_and_stderr_is_inherited(ac, rig):
    rig.set_responses(http_error(401), VERDICT)
    rig.set_helper()

    ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    kwargs = rig.calls["run"][0]["kwargs"]
    assert kwargs["stdout"] is subprocess.PIPE, "the key must never reach a log or the terminal"
    assert kwargs["stderr"] is None, (
        "the helper's diagnostics (ambiguous env name, missing BWS token) are "
        "the only signal that resolution failed — never silence them"
    )
    assert kwargs["timeout"] is not None, "an unbounded helper call can outlive the hook deadline"


def test_no_part_of_either_key_is_ever_logged(ac, rig):
    rig.set_responses(http_error(401), VERDICT)
    rig.set_helper()

    ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    joined = " ".join(rig.calls["log"])
    for key in (STALE_KEY, FRESH_KEY):
        for width in (8, 12, len(key)):
            assert key[:width] not in joined
    assert "KEY REFRESH" in joined, "a silent self-heal is unauditable"


def test_second_401_surfaces_the_error_and_does_not_loop(ac, rig):
    rig.set_responses(http_error(401), http_error(401))
    rig.set_helper()

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert excinfo.value.code == 401
    assert len(rig.calls["urlopen"]) == 2, "at most one retry — never a loop"
    assert len(rig.calls["run"]) == 1


# --- what must NOT trigger a re-resolve -------------------------------------

@pytest.mark.parametrize("code", [403, 429, 500, 529])
def test_non_401_statuses_never_reresolve(ac, rig, code):
    rig.set_responses(http_error(code, "permission_error", "not allowed"))
    rig.set_helper()

    with pytest.raises(urllib.error.HTTPError):
        ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert len(rig.calls["urlopen"]) == 1
    assert rig.calls["run"] == [], (
        f"HTTP {code} is not an authentication rejection; a different key value "
        "cannot change the answer, so re-resolving only burns budget."
    )


def test_identical_key_from_the_helper_is_not_retried(ac, rig):
    rig.set_responses(http_error(401))
    rig.set_helper(stdout=STALE_KEY + "\n")

    with pytest.raises(urllib.error.HTTPError):
        ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert len(rig.calls["urlopen"]) == 1, "the same key would just be rejected again"


@pytest.mark.parametrize("helper", [
    {"returncode": 1},
    {"returncode": 0, "stdout": ""},          # exit 0 is not success on its own
    {"returncode": 0, "stdout": "   \n"},
    {"exc": subprocess.TimeoutExpired("dotfiles-secrets", 6)},
    {"exc": OSError("no such file")},
])
def test_helper_failures_surface_the_original_401(ac, rig, helper):
    rig.set_responses(http_error(401))
    rig.set_helper(**helper)

    with pytest.raises(urllib.error.HTTPError) as excinfo:
        ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert excinfo.value.code == 401
    assert len(rig.calls["urlopen"]) == 1


def test_retry_is_skipped_when_the_hook_budget_is_nearly_gone(ac, rig):
    rig.set_budget(1.0)
    rig.set_responses(http_error(401))
    rig.set_helper()

    with pytest.raises(urllib.error.HTTPError):
        ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert rig.calls["run"] == [], (
        "being killed mid-retry writes no health file and emits no warning — "
        "the silent stale-health case the budget exists to prevent"
    )


def test_retry_timeout_is_clamped_to_the_remaining_budget(ac, rig):
    rig.set_budget(5.0)
    rig.set_responses(http_error(401), VERDICT)
    rig.set_helper()

    ac.post_anthropic(b'{"x":1}', timeout=8, remaining=rig.remaining)

    assert rig.calls["urlopen"][1]["timeout"] <= 5.0


# --- both callers actually route through it ---------------------------------

def test_classify_recovers_from_a_rotated_key(ac, rig):
    rig.set_responses(http_error(401), VERDICT)
    rig.set_helper()

    result = ac.classify("Bash", {"command": "ls"}, "/tmp", "RULES")

    assert result == {"decision": "allow", "reason": "t"}
    assert len(rig.calls["urlopen"]) == 2
    # The recovered request must still be a well-formed classifier call.
    assert rig.calls["urlopen"][1]["body"]["thinking"] == {"type": "disabled"}


def test_keycheck_recovers_instead_of_warning(ac, rig, monkeypatch, tmp_path, capsys):
    """The end-to-end path: SessionStart ping 401s, then reports healthy."""
    kc = load_module(KEYCHECK, "anthropic_keycheck")
    cache = tmp_path / "keycheck-ok"
    monkeypatch.setattr(kc, "CACHE_FILE", str(cache))
    # keycheck imports its own copy of approval_classifier, but urlopen and
    # subprocess.run are patched on the shared stdlib modules, so both see the fakes.
    rig.set_responses(http_error(401), {"content": [{"type": "text", "text": "ok"}]})
    rig.set_helper()

    kc.main()

    out = capsys.readouterr()
    assert out.out == "", f"expected silence on recovery, got: {out.out!r}"
    assert "rejected" not in out.out and "rejected" not in out.err
    assert cache.exists(), "a healthy key marks the cache; a warned-about one does not"


def test_keycheck_still_warns_when_both_attempts_are_rejected(ac, rig, monkeypatch, tmp_path, capsys):
    kc = load_module(KEYCHECK, "anthropic_keycheck")
    monkeypatch.setattr(kc, "CACHE_FILE", str(tmp_path / "keycheck-ok"))
    rig.set_responses(http_error(401), http_error(401))
    rig.set_helper()

    kc.main()

    payload = json.loads(capsys.readouterr().out)
    assert "rejected" in payload["systemMessage"]
    assert not (tmp_path / "keycheck-ok").exists()


# --- the two things every test above was blind to -----------------------------
# Both of these passed for months against a feature that could not fire in
# production: SECRETS_HELPER was monkeypatched to a stub in every retry test, and
# the budget was pinned to 20.0, so neither the symlinked install path nor
# keycheck's much shorter hook deadline was ever exercised.

def test_helper_path_survives_a_symlinked_hooks_directory(tmp_path):
    """`~/.claude` is a SYMLINK to <dotfiles>/claude, and settings.json invokes
    the hook through it. With os.path.abspath the "../.." traversal stayed on the
    link's side and resolved to ~/custom_bins/dotfiles-secrets — a path that does
    not exist, so every production 401 logged "no executable helper" and gave up.
    """
    claude_dir = CLASSIFIER.resolve().parent.parent          # <dotfiles>/claude
    link = tmp_path / ".claude"
    link.symlink_to(claude_dir)

    mod = load_module(link / "hooks" / CLASSIFIER.name, "approval_classifier_symlinked")

    helper = pathlib.Path(mod.SECRETS_HELPER)
    assert helper == claude_dir.parent / "custom_bins" / "dotfiles-secrets", (
        f"the helper must resolve into the real dotfiles tree, got {helper}"
    )
    assert os.access(helper, os.X_OK), (
        "an unexecutable path here means the retry logs 'no executable helper' "
        "and re-raises the 401 — the feature is dead in every real session"
    )
    assert str(tmp_path) not in str(helper), "the symlink must be resolved, not carried through"


def test_keycheck_hook_timeout_matches_settings_json():
    """The budget is only honest while it tracks the timeout Claude enforces."""
    kc = load_module(KEYCHECK, "anthropic_keycheck_timeout")
    settings = json.loads((ROOT / "claude" / "settings.json").read_text())
    timeouts = [
        h["timeout"]
        for matcher in settings["hooks"]["SessionStart"]
        for h in matcher["hooks"]
        if "anthropic_keycheck.py" in h.get("command", "")
    ]
    assert timeouts, "no SessionStart entry runs anthropic_keycheck.py"
    assert timeouts == [kc.HOOK_TIMEOUT_SECONDS] * len(timeouts), (
        f"settings.json gives keycheck {timeouts}s but it budgets for "
        f"{kc.HOOK_TIMEOUT_SECONDS}s"
    )
    assert kc.TOTAL_BUDGET_SECONDS < kc.HOOK_TIMEOUT_SECONDS, "the epilogue needs room"


@pytest.mark.parametrize("first_call_seconds,expect_retry", [
    (0.4, True),    # a fast rejection leaves room to recover
    (8.0, False),   # a slow one does not — surface the 401 rather than be killed
])
def test_keycheck_never_plans_past_its_own_10s_deadline(
    monkeypatch, tmp_path, capsys, first_call_seconds, expect_retry
):
    """Worst case, measured on a virtual clock every stage advances by its own
    timeout. Borrowing the classifier's 26s budget put this at 0.4 + 6 + 8 =
    14.4s inside a 10s hook: Claude kills it, no health file is written and no
    warning is printed — the silent session-start stall the budget prevents.
    """
    kc = load_module(KEYCHECK, "anthropic_keycheck_clock")
    cache = tmp_path / "keycheck-ok"
    monkeypatch.setattr(kc, "CACHE_FILE", str(cache))
    monkeypatch.setenv("ANTHROPIC_API_KEY", STALE_KEY)
    monkeypatch.delenv("APPROVAL_CLASSIFIER_HOOK_START", raising=False)

    clock = {"t": 0.0}
    monkeypatch.setattr(time, "monotonic", lambda: clock["t"])

    urlopens = []

    def fake_urlopen(req, timeout=None):
        urlopens.append(timeout)
        if len(urlopens) == 1:
            clock["t"] += first_call_seconds
            raise http_error(401)
        clock["t"] += timeout          # worst case: the retry uses all of it
        return Resp({"content": [{"type": "text", "text": "ok"}]})

    def fake_run(cmd, **kwargs):
        clock["t"] += kwargs["timeout"]  # worst case: BWS is as slow as allowed
        return subprocess.CompletedProcess(cmd, 0, stdout=FRESH_KEY + "\n", stderr=None)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setattr(subprocess, "run", fake_run)

    kc.main()

    out = capsys.readouterr()
    assert clock["t"] <= kc.HOOK_TIMEOUT_SECONDS - 1.0, (
        f"worst case spent {clock['t']:.1f}s of a {kc.HOOK_TIMEOUT_SECONDS}s hook"
    )
    if expect_retry:
        assert len(urlopens) == 2
        assert out.out == "", f"a recovered key reports nothing, got: {out.out!r}"
        assert cache.exists()
    else:
        assert len(urlopens) == 1, "no room to retry — the 401 must surface instead"
        assert "rejected" in json.loads(out.out)["systemMessage"]
        assert not cache.exists()
