#!/usr/bin/env python3
"""Regression tests: BOTH classifier backends must suppress adaptive thinking.

Why this file exists. Sonnet 5 thinks by default when nothing says otherwise,
whereas the Haiku/Sonnet-4.6 generation did not. That difference broke this hook
in two distinct ways, and each backend needed a different remedy:

  * API backend      -- `max_tokens` caps thinking AND response text together, so
                        an adaptive reply spends the budget reasoning and gets
                        truncated before it emits the JSON verdict. Remedy:
                        `thinking: {"type": "disabled"}` in the request body.
  * Subscription CLI -- no max_tokens exists here, so nothing truncates; instead
                        the child thinks while the hook's deadline runs out.
                        Claude Code 2.1.223 has no `--thinking` flag, so the
                        mitigation is `--effort low`. Note the asymmetry: this
                        is a behavioural signal, not a token budget, so it
                        reduces thinking without forbidding it. The two
                        backends are NOT equivalent, and the timeout clamp --
                        not the effort flag -- is what actually bounds this
                        path.

Both failures are silent: the hook fails open to a manual permission prompt, so
a regression looks like "the classifier just stopped helping" rather than an
error. Hence pinning the wire format and the argv rather than trusting comments.

No network and no subprocess: urlopen and subprocess.run are both replaced with
capturing fakes, so this is safe to run anywhere.
"""
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Overridable so the suite can be pointed at a deliberately-broken copy to prove
# these tests can actually fail -- a green assertion nobody has seen go red is
# not evidence of anything. See tmp/mutation_check.sh.
HOOK = pathlib.Path(
    os.environ.get("APPROVAL_CLASSIFIER_PATH")
    or ROOT / "claude" / "hooks" / "approval_classifier.py"
)


def load_module():
    spec = importlib.util.spec_from_file_location("approval_classifier", HOOK)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def ac():
    return load_module()


# --- constants -------------------------------------------------------------

def test_api_model_is_sonnet_5(ac):
    assert ac.MODEL == "claude-sonnet-5"


def test_subscription_model_is_sonnet(ac):
    assert ac.SUBSCRIPTION_MODEL == "sonnet"


def test_thinking_is_disabled_not_merely_absent(ac):
    """Absence is the bug, so an omitted/None THINKING must fail this test."""
    assert ac.THINKING == {"type": "disabled"}


def test_subscription_effort_is_pinned_to_low(ac):
    # Pinned to the LITERAL value, not to membership in the CLI's accepted set
    # (`claude --help` 2.1.223: low, medium, high, xhigh, max). Membership was
    # the original assertion and it was close to a tautology: `max` is a legal
    # value that would restore the very latency this setting exists to remove,
    # and it left this entire suite green. The earlier mutation check missed it
    # because the mutation chosen ("minimal") was invalid rather than
    # valid-but-wrong.
    #
    # Note on what this does NOT claim: `--effort low` is a behavioural signal,
    # not a token budget, so the child may still think on a hard enough prompt.
    # It is best-effort latency reduction -- not the equivalent of the API
    # path's `thinking: {"type": "disabled"}`, which the CLI cannot express.
    assert ac.SUBSCRIPTION_EFFORT == "low"


# --- API backend: the request body actually sent ---------------------------

def test_api_request_body_disables_thinking(ac, monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout=None):
        captured["body"] = json.loads(req.data)
        payload = {
            "content": [{"type": "text",
                         "text": '{"decision":"allow","reason":"test"}'}],
            "stop_reason": "end_turn",
        }

        class Resp:
            def read(self):
                return json.dumps(payload).encode()

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        return Resp()

    monkeypatch.setattr(ac.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-not-a-real-key")

    ac.classify("Bash", {"command": "curl https://example.com"}, "/tmp", "RULES")

    body = captured["body"]
    assert body["thinking"] == {"type": "disabled"}, (
        "Sonnet 5 thinks adaptively when `thinking` is omitted; max_tokens then "
        "covers thinking + text and the JSON verdict gets truncated away."
    )
    assert body["model"] == "claude-sonnet-5"
    # Guard the interaction, not just the field: disabled thinking is rejected
    # at effort xhigh/max, so a future edit adding a high effort would 400.
    assert "effort" not in body or body["effort"] in {"low", "medium", "high"}


# --- Subscription backend: the argv actually spawned ------------------------

def test_subscription_argv_passes_effort(ac, monkeypatch):
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(
            cmd, 0,
            stdout=json.dumps({
                "is_error": False,
                "result": '{"decision":"allow","reason":"test"}',
            }),
            stderr="",
        )

    monkeypatch.setattr(ac.subprocess, "run", fake_run)

    ac.classify_via_subscription(
        "Bash", {"command": "curl https://example.com"}, "/tmp", "RULES",
    )

    cmd = captured["cmd"]
    assert "--effort" in cmd, (
        "Without --effort the CLI child runs Sonnet 5's adaptive thinking and "
        "can outlive the hook's remaining budget."
    )
    # Literal, NOT `== ac.SUBSCRIPTION_EFFORT`: comparing the argv against the
    # same constant that produced it only proves the constant reached the argv,
    # which stays true for any value the constant is changed to.
    assert cmd[cmd.index("--effort") + 1] == "low"
    assert cmd[cmd.index("--model") + 1] == "sonnet"
    # --bare must never appear: its help states OAuth and keychain are never
    # read, so it is the one mode that cannot reach the subscription at all.
    assert "--bare" not in cmd


def test_subscription_argv_keeps_its_hardening_flags(ac, monkeypatch):
    """The effort flag must not have displaced any sandboxing flag."""
    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(
            cmd, 0,
            stdout=json.dumps({
                "is_error": False,
                "result": '{"decision":"allow","reason":"test"}',
            }),
            stderr="",
        )

    monkeypatch.setattr(ac.subprocess, "run", fake_run)
    ac.classify_via_subscription("Bash", {"command": "ls"}, "/tmp", "RULES")

    cmd = captured["cmd"]
    for flag in ("--safe-mode", "--disable-slash-commands",
                 "--strict-mcp-config", "--tools"):
        assert flag in cmd, f"{flag} was dropped from the child argv"

    # The OPERAND is the whole point, and asserting only that `--tools` appears
    # does not check it. `claude --help` (2.1.223): "" disables all tools,
    # "default" uses all tools. So `"--tools", ""` -> `"--tools", "default"`
    # passed the presence-only version of this test while handing the child
    # Bash, Read and Edit -- a child that receives attacker-influenced tool
    # input, runs in the user's home directory, and whose hook backstop
    # --safe-mode has already switched off.
    assert cmd[cmd.index("--tools") + 1] == "", (
        "--tools must be given the empty operand; 'default' would ENABLE every "
        "built-in tool in the classifier child"
    )


def test_subscription_timeout_fails_open_rather_than_crashing(ac, monkeypatch):
    """A killed child must surface as the warning that drives the manual prompt.

    This is the path the SUBSCRIPTION_MIN_SECONDS floor is reasoned about: the
    floor is defensible only because timing out and skipping converge on the
    same outcome. If a timeout escaped as a raw TimeoutExpired it would crash
    the hook instead, and that argument would no longer hold.
    """
    def fake_run(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd, kwargs.get("timeout") or 1)

    monkeypatch.setattr(ac.subprocess, "run", fake_run)

    with pytest.raises(ac.ApprovalClassifierWarning):
        ac.classify_via_subscription(
            "Bash", {"command": "curl https://example.com"}, "/tmp", "RULES",
        )


def test_rendered_user_message_is_reused_across_backends(ac, monkeypatch):
    """Push context can require several Git probes. The fallback must reuse the
    first rendering instead of rerunning those probes after its timeout budget
    was computed (Codex P2 r8)."""
    rendered = "Tool: Bash\nInput: cached once\nGit context: cached once"
    captured = {}

    def must_not_rebuild(*args, **kwargs):
        raise AssertionError("build_classify_user_msg reran instead of using cached text")

    def fake_urlopen(req, timeout):
        captured["api_body"] = json.loads(req.data)
        payload = {
            "content": [{"type": "text", "text": '{"decision":"allow","reason":"test"}'}],
            "stop_reason": "end_turn",
        }

        class Resp:
            def read(self):
                return json.dumps(payload).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        return Resp()

    def fake_run(cmd, **kwargs):
        captured["subscription_input"] = kwargs["input"]
        return subprocess.CompletedProcess(
            cmd, 0,
            stdout=json.dumps({
                "is_error": False,
                "result": '{"decision":"allow","reason":"test"}',
            }),
            stderr="",
        )

    monkeypatch.setattr(ac, "build_classify_user_msg", must_not_rebuild)
    monkeypatch.setattr(ac.urllib.request, "urlopen", fake_urlopen)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-not-a-real-key")
    ac.classify("Bash", {"command": "git push"}, "/tmp", "RULES",
                rendered_user_msg=rendered)
    assert captured["api_body"]["messages"][0]["content"] == rendered

    monkeypatch.setattr(ac.subprocess, "run", fake_run)
    ac.classify_via_subscription(
        "Bash", {"command": "git push"}, "/tmp", "RULES",
        rendered_user_msg=rendered,
    )
    assert captured["subscription_input"] == rendered


def test_main_renders_once_for_api_to_subscription_fallback(ac, monkeypatch, tmp_path):
    """Exercise the actual orchestration: an API failure must hand the exact
    pre-rendered prompt to the subscription fallback without probing Git twice."""
    rules_path = tmp_path / "rules.md"
    rules_path.write_text("RULES")
    rendered = "Tool: Bash\nInput: rendered once\nGit context: rendered once"
    calls = {"build": 0}

    def fake_build(*args, **kwargs):
        calls["build"] += 1
        return rendered

    def fake_api(*args, **kwargs):
        assert kwargs["rendered_user_msg"] == rendered
        raise ac.ApprovalClassifierWarning("api failed", "test", "fix api")

    def fake_subscription(*args, **kwargs):
        assert kwargs["rendered_user_msg"] == rendered
        return {"decision": "allow", "reason": "fallback test"}

    hook_input = {
        "tool_name": "Bash",
        "tool_input": {"command": "git push"},
        "cwd": str(tmp_path),
        "transcript_path": "",
    }
    monkeypatch.setattr(ac, "RULES_PATH", str(rules_path))
    monkeypatch.setattr(ac, "build_classify_user_msg", fake_build)
    monkeypatch.setattr(ac, "classify", fake_api)
    monkeypatch.setattr(ac, "classify_via_subscription", fake_subscription)
    monkeypatch.setattr(ac, "remaining_budget", lambda: 20.0)
    monkeypatch.setattr(ac, "detect_repo_trust", lambda cwd: {
        "remote_url": "", "owner": "", "trusted": False, "personal": False,
    })
    monkeypatch.setattr(ac, "fast_classify_bash", lambda command: None)
    monkeypatch.setattr(ac, "write_health", lambda *args, **kwargs: None)
    monkeypatch.setattr(ac, "log", lambda *args, **kwargs: None)
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(hook_input)))
    monkeypatch.setattr(sys, "stdout", io.StringIO())

    ac.main()
    assert calls["build"] == 1


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
