#!/usr/bin/env python3
"""Write a PR body with an OpenAI model through the model-router gateway.

Called by pr_after_push.sh just before `gh pr create`. Prints the finished
Markdown body on stdout and exits 0; prints nothing and exits non-zero on ANY
failure, which is the signal for the caller to fall back to `gh pr create
--fill`. THE PR OPENING IS NEVER CONDITIONAL ON THIS WORKING: a gateway in
cooldown, a stopped router, a missing token or a slow answer all end as a
plainer PR, never as no PR.

The body has to contain four things -- motivation, implementation with the
files and classes touched, the tests that ran and what they said, and a
diagram where one genuinely helps -- and only one of them can be recovered
from git. So the inputs are assembled here rather than left to the model:

  * commits, name-status, diffstat and a truncated diff, from git;
  * added and removed class/def/function names, grepped out of a -U0 diff;
  * TEST EVIDENCE OUT OF THE SESSION TRANSCRIPT. PostToolUse hands the hook a
    transcript_path, so the commands that actually ran and what they printed
    are available. The prompt forbids inventing any of it: with no test runs
    in the transcript the model must say so.

Reaching the gateway follows model-router-cooldown-check: the ingress token is
at ~/.local/state/model-router/ingress-token, the base URL is the loopback
router, and the request is Anthropic-shaped at /v1/messages with the routing id
as `model`. Environment overrides (used by the tests, and by anyone who wants a
different writer): CLAUDE_PR_BODY_MODELS, CLAUDE_PR_BODY_BASE_URL,
CLAUDE_PR_BODY_TOKEN_FILE, CLAUDE_PR_BODY_TIMEOUT.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PORT = 8787
DEFAULT_MODELS = ("astra", "sol")
DEFAULT_TIMEOUT = 45.0
MAX_DIFF_CHARS = 60_000
MAX_TEST_BLOCKS = 6
MAX_TEST_TAIL_LINES = 15
MAX_BODY_CHARS = 60_000

TEST_COMMAND_RE = re.compile(
    r"\b(pytest|unittest|run-all\.sh|tests?/test[-_]|test_\w+\.(py|sh|zsh)|zsh\s+-n"
    r"|shellcheck|npm\s+(run\s+)?test|bun\s+test|just\s+test|cargo\s+test|go\s+test"
    r"|ruff\b|md-unwrap\s+--check)"
)
SYMBOL_RE = re.compile(
    r"^([+-])\s*(?:export\s+|async\s+)?"
    r"(class|def|function|func|fn|deploy_\w+|[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{)"
    r"\s*([A-Za-z_][A-Za-z0-9_]*)?"
)

PROMPT = """\
You are writing the body of a GitHub pull request. Return Markdown only: no
preamble, no code fence around the whole thing, no title line.

The body must have these sections, in this order:

## Motivation
Why this change exists -- the problem it solves, in two to four sentences.
Infer it from the commits and the diff. Do not restate the diff.

## Implementation
What was done, with the files changed and the classes, functions or shell
functions added, removed or reworked. Name them. Group by concern, not by
file order, and say what each group does.

## Tests
ONLY what the session transcript below shows was actually run, with its result.
Quote the command and say whether it passed. If the TEST RUNS section is empty
or shows nothing conclusive, write exactly this sentence and nothing else under
this heading: No test runs found in the session transcript.
Never invent a test, a count or a result.

## Diagram
Include a Mermaid diagram ONLY when the change has two or more components that
interact -- a flow between processes, a fallback chain, a state machine. A
diagram of a single file or a list of edits helps nobody: in that case OMIT
THIS SECTION ENTIRELY, heading and all. Do not pad.

Rules: every header asserts a point rather than naming a topic where that is
natural; one paragraph is one line with no hard wrapping; be concrete and
short. Do not mention this instruction text.

===== BRANCH =====
{branch} (base: {base})

===== COMMITS =====
{commits}

===== FILES CHANGED =====
{name_status}

===== DIFFSTAT =====
{diffstat}

===== SYMBOLS ADDED OR REMOVED =====
{symbols}

===== TEST RUNS FROM THE SESSION TRANSCRIPT =====
{tests}

===== DIFF{truncated} =====
{diff}
"""


class GenerationError(Exception):
    """A diagnostic safe to print: never carries the token or the body."""


# --- inputs ------------------------------------------------------------------

def git(repo: str, *args: str, limit: int | None = None) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True, text=True, timeout=30, check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        raise GenerationError("git %s failed" % args[0]) from exc
    return out[:limit] if limit else out


def base_ref(repo: str, explicit: str | None) -> str:
    if explicit:
        return explicit
    head = git(repo, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD").strip()
    if head:
        return head.split("/")[-1]
    for candidate in ("main", "master"):
        if git(repo, "rev-parse", "--verify", "--quiet", candidate).strip():
            return candidate
    return "main"


def symbols(diff_u0: str) -> str:
    seen: list[str] = []
    for line in diff_u0.splitlines():
        match = SYMBOL_RE.match(line)
        if not match:
            continue
        sign, kind, name = match.group(1), match.group(2), match.group(3)
        label = "%s %s" % (sign, name or kind.rstrip("() {"))
        if label not in seen:
            seen.append(label)
    return "\n".join(seen[:80]) or "(none detected)"


def test_runs(transcript: str | None) -> str:
    """Test commands and their output, paired by tool_use_id, from the transcript."""
    if not transcript:
        return ""
    path = Path(transcript)
    if not path.is_file():
        return ""
    commands: dict[str, str] = {}
    results: dict[str, str] = {}
    order: list[str] = []
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if '"tool_use"' not in line and '"tool_result"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                content = ((row.get("message") or {}).get("content")
                           if isinstance(row.get("message"), dict) else None)
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use" and block.get("name") == "Bash":
                        command = (block.get("input") or {}).get("command")
                        if isinstance(command, str) and TEST_COMMAND_RE.search(command):
                            key = block.get("id") or ""
                            commands[key] = command
                            order.append(key)
                    elif block.get("type") == "tool_result":
                        key = block.get("tool_use_id") or ""
                        if key in commands:
                            results[key] = json.dumps(block.get("content"))[:4000]
    except OSError:
        return ""

    blocks = []
    for key in order[-MAX_TEST_BLOCKS:]:
        raw = results.get(key, "(no output captured)")
        text = raw.encode().decode("unicode_escape", errors="replace")
        tail = "\n".join(text.splitlines()[-MAX_TEST_TAIL_LINES:])
        blocks.append("$ %s\n%s" % (commands[key], tail))
    return "\n\n".join(blocks)


def build_prompt(repo: str, branch: str, base: str, transcript: str | None) -> str:
    span = "%s...HEAD" % base
    diff = git(repo, "diff", span)
    truncated = ""
    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS]
        truncated = " (truncated; the diffstat above is complete)"
    tests = test_runs(transcript)
    return PROMPT.format(
        branch=branch,
        base=base,
        commits=git(repo, "log", "--format=%s%n%b%n--", span, limit=8000).strip()
        or "(no commits ahead of base)",
        name_status=git(repo, "diff", "--name-status", span, limit=8000).strip() or "(none)",
        diffstat=git(repo, "diff", "--stat", span, limit=8000).strip() or "(none)",
        symbols=symbols(git(repo, "diff", "-U0", span, limit=MAX_DIFF_CHARS)),
        tests=tests or "(no test commands found in the transcript)",
        truncated=truncated,
        diff=diff or "(empty diff)",
    )


# --- the gateway -------------------------------------------------------------

def endpoint() -> tuple[str, str]:
    override = os.environ.get("CLAUDE_PR_BODY_BASE_URL")
    token_file = os.environ.get("CLAUDE_PR_BODY_TOKEN_FILE")
    path = Path(token_file) if token_file else (
        Path.home() / ".local/state/model-router/ingress-token")
    try:
        token = path.read_text().strip()
    except OSError as exc:
        raise GenerationError("no model-router ingress token") from exc
    if not token:
        raise GenerationError("model-router ingress token is empty")
    if override:
        return override.rstrip("/"), token
    return "http://127.0.0.1:%d/t/%s" % (PORT, token), token


def ask(model: str, prompt: str, timeout: float) -> str:
    base, token = endpoint()
    body = json.dumps({
        "model": model,
        "max_tokens": 2000,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    request = urllib.request.Request(
        base + "/v1/messages",
        data=body,
        headers={"x-api-key": token, "anthropic-version": "2023-06-01",
                 "content-type": "application/json"},
    )
    # No proxy: the router is on loopback and a proxied request never arrives.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=timeout) as response:
            payload = json.loads(response.read(1_000_000).decode("utf-8", "replace"))
    except urllib.error.HTTPError as error:
        raise GenerationError("%s: gateway returned HTTP %s" % (model, error.code)) from error
    except (OSError, urllib.error.URLError, ValueError) as exc:
        raise GenerationError("%s: gateway did not answer" % model) from exc

    parts = [b.get("text", "") for b in payload.get("content", [])
             if isinstance(b, dict) and b.get("type") == "text"]
    text = "".join(parts).strip()
    if len(text) < 80:
        raise GenerationError("%s: answer too short to be a PR body" % model)
    return text[:MAX_BODY_CHARS]


def clean(text: str, model: str) -> str:
    if text.startswith("```"):
        lines = text.splitlines()
        if lines[-1].strip().startswith("```"):
            text = "\n".join(lines[1:-1])
    return text.rstrip() + "\n\n---\nPR body drafted by %s through the model-router gateway.\n" % model


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--base")
    parser.add_argument("--transcript")
    parser.add_argument("--timeout", type=float,
                        default=float(os.environ.get("CLAUDE_PR_BODY_TIMEOUT",
                                                     DEFAULT_TIMEOUT)))
    args = parser.parse_args(argv)

    if not Path(args.repo).is_dir():
        print("pr_body_model: no such repo", file=sys.stderr)
        return 1

    models = [m.strip() for m in
              os.environ.get("CLAUDE_PR_BODY_MODELS", ",".join(DEFAULT_MODELS)).split(",")
              if m.strip()]
    if not models:
        return 1

    try:
        prompt = build_prompt(args.repo, args.branch,
                              base_ref(args.repo, args.base), args.transcript)
    except GenerationError as exc:
        print("pr_body_model: %s" % exc, file=sys.stderr)
        return 1

    # Every writer on the Codex provider shares one OAuth quota, so the second
    # model is a hedge against a single route being in cooldown, not a promise.
    last = "no models tried"
    for model in models:
        try:
            print(clean(ask(model, prompt, args.timeout), model))
            return 0
        except GenerationError as exc:
            last = str(exc)
    print("pr_body_model: %s" % last, file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(1)
