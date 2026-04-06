#!/usr/bin/env python3
"""PermissionRequest hook: LLM-based permission classifier.

Calls Haiku to classify tool actions as allow/deny, mimicking auto mode.
Fails open (exit 0 = normal prompt) on any error, but emits a loud warning
instead of failing silently when the hook is misconfigured or Anthropic rejects
the request.
Always active — no env var gate.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

RULES_PATH = os.path.join(os.path.dirname(__file__), "auto_classify_rules.md")
API_URL = "https://api.anthropic.com/v1/messages"
MODEL = "claude-haiku-4-5-20251001"
MAX_TOKENS = 100
TIMEOUT_SECONDS = 12
LOG_PATH = os.path.expanduser("~/.cache/claude/auto-classify.log")
MAX_INPUT_CHARS = 2000
MAX_LOG_BYTES = 1_000_000  # 1MB
MAX_USER_MSG_CHARS = 200  # Truncation limit for user message context

# GitHub owners (users + orgs) whose repos are trusted for relaxed permissions.
# Add orgs you work with regularly. Personal repos get extra relaxations.
TRUSTED_GITHUB_OWNERS = {"yulonglin", "anthropics", "alignment-research"}
PERSONAL_GITHUB_USERS = {"yulonglin"}

# Cache file written by SessionStart hook (detect_repo_trust.sh)
TRUST_CACHE = os.path.expanduser("~/.cache/claude/repo-trust.json")

# Feature flags (set via environment variables)
INCLUDE_USER_MESSAGE = os.environ.get("AUTO_CLASSIFY_USER_MESSAGE", "1") != "0"

ANSI_RESET = "\033[0m"
ANSI_RED = "\033[1;31m"
ANSI_YELLOW = "\033[1;33m"
ANSI_CYAN = "\033[1;36m"

# ── Fast-path allowlist ──────────────────────────────────────────────
# Patterns that bypass the API call entirely. These are commands where
# Haiku repeatedly hallucinates false positives despite explicit rules.
import re

# Commands that are always safe when run in a trusted/personal repo.
# Checked against the Bash tool's "command" field.
FAST_ALLOW_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # python -c / python3 -c with multiline code (Haiku false-positives on # comments)
    (re.compile(r"^(uv run\b.*\s+)?python3?\s+-c\s"), "python -c one-liner check"),
    # inspect eval/experiment commands (AI safety research tooling)
    (re.compile(r"^(uv run\b.*\s+)?inspect\s+(eval|run|log|list|info|view|score)\b"), "inspect eval/experiment"),
    (re.compile(r"^(uv run\b.*\s+)?python3?\s+-m\s+inspect_ai\b"), "inspect_ai module"),
    # .agent-claims/ operations (multi-agent coordination, ephemeral files only)
    (re.compile(r"\.agent-claims"), "agent claims coordination"),
]


def fast_classify_bash(command: str) -> str | None:
    """Return an allow reason if the command matches a known-safe pattern, else None."""
    cmd = command.strip()
    for pattern, reason in FAST_ALLOW_PATTERNS:
        if pattern.search(cmd):
            return reason
    return None


class AutoClassifyWarning(RuntimeError):
    """Fail-open warning that should be surfaced to the user."""

    def __init__(self, headline: str, details: str = "", suggestion: str = "") -> None:
        super().__init__(headline)
        self.headline = headline
        self.details = details
        self.suggestion = suggestion


def detect_repo_trust(cwd: str) -> dict:
    """Read cached repo trust level, falling back to git detection.

    The cache is written once per session by the SessionStart hook.
    This avoids a subprocess call on every PermissionRequest.
    """
    # Try cache first (written by SessionStart hook for the session's CWD)
    try:
        with open(TRUST_CACHE) as f:
            cached = json.load(f)
        if cached.get("cwd") == cwd:
            return cached
    except Exception:
        pass

    # Fallback: detect and cache
    import subprocess

    result = {"trusted": False, "personal": False, "remote_url": "", "owner": "", "cwd": cwd}
    try:
        proc = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode != 0:
            return result
        url = proc.stdout.strip()
        result["remote_url"] = url

        # Extract owner from github.com URLs
        # git@github.com:owner/repo.git or https://github.com/owner/repo.git
        owner = ""
        if "github.com:" in url:
            owner = url.split("github.com:")[1].split("/")[0]
        elif "github.com/" in url:
            owner = url.split("github.com/")[1].split("/")[0]

        result["owner"] = owner
        result["trusted"] = owner.lower() in {u.lower() for u in TRUSTED_GITHUB_OWNERS}
        result["personal"] = owner.lower() in {u.lower() for u in PERSONAL_GITHUB_USERS}

        # Cache for subsequent calls
        try:
            os.makedirs(os.path.dirname(TRUST_CACHE), exist_ok=True)
            with open(TRUST_CACHE, "w") as f:
                json.dump(result, f)
        except Exception:
            pass
    except Exception:
        pass
    return result


def log(msg: str) -> None:
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        # Rotate if log exceeds 1MB
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG_BYTES:
            with open(LOG_PATH, "r") as f:
                lines = f.readlines()
            with open(LOG_PATH, "w") as f:
                f.writelines(lines[len(lines) // 2 :])
        with open(LOG_PATH, "a") as f:
            from datetime import datetime, timezone
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            f.write(f"{ts} {msg}\n")
    except Exception:
        pass


def build_warning_message(headline: str, details: str = "", suggestion: str = "") -> str:
    lines = [f"{ANSI_RED}🚨 auto-classify problem:{ANSI_RESET} {headline}"]
    if details:
        lines.append(f"{ANSI_YELLOW}⚠ Details:{ANSI_RESET} {details}")
    if suggestion:
        lines.append(f"{ANSI_CYAN}💡 Action:{ANSI_RESET} {suggestion}")
    return "\n".join(lines)


def emit_warning(headline: str, details: str = "", suggestion: str = "") -> None:
    msg = build_warning_message(headline, details, suggestion)
    log(f"WARNING: {headline} — {details or 'no details'}")
    json.dump({"systemMessage": msg}, sys.stdout)


def parse_anthropic_error(exc: urllib.error.HTTPError) -> tuple[str, str]:
    raw = ""
    error_type = ""
    message = str(exc)

    try:
        raw = exc.read().decode("utf-8", errors="replace")
    except Exception:
        raw = ""

    if raw:
        try:
            payload = json.loads(raw)
            error = payload.get("error", {})
            if isinstance(error, dict):
                error_type = str(error.get("type", "") or "")
                message = str(error.get("message", "") or message)
        except Exception:
            message = raw[:500]

    return error_type.lower(), message


def classify_api_problem(status: int, error_type: str, message: str) -> AutoClassifyWarning:
    combined = f"{error_type} {message}".lower()

    if any(token in combined for token in ("credit", "balance", "quota", "billing", "payment")):
        return AutoClassifyWarning(
            "Anthropic API key appears to be out of credits.",
            f"HTTP {status}: {message}",
            "Top up Anthropic credits or switch to a funded key. Claude will fall back to the normal permission prompt until this is fixed.",
        )

    if status in (401, 403) or "authentication" in combined or "invalid x-api-key" in combined:
        return AutoClassifyWarning(
            "Anthropic API key was rejected.",
            f"HTTP {status}: {message}",
            "Check ANTHROPIC_API_KEY in dotfiles-secrets or the hook wrapper, then retry.",
        )

    if status == 429 or "rate limit" in combined:
        return AutoClassifyWarning(
            "Anthropic auto-classify is rate limited.",
            f"HTTP {status}: {message}",
            "Wait for the rate limit window to clear or use the normal permission prompt for now.",
        )

    return AutoClassifyWarning(
        "Anthropic auto-classify request failed.",
        f"HTTP {status}: {message}",
        "Check ~/.cache/claude/auto-classify.log for details. Claude will use the normal permission prompt.",
    )


def extract_last_user_message(transcript_path: str) -> str:
    """Extract the last user message from the transcript JSONL. Fails silently."""
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 20_000))
            tail = f.read().decode("utf-8", errors="replace")

        for line in reversed(tail.strip().splitlines()):
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") != "human":
                continue
            text = _extract_text(entry.get("message", ""))
            if text:
                return text[:MAX_USER_MSG_CHARS] + "..." if len(text) > MAX_USER_MSG_CHARS else text
    except Exception:
        pass
    return ""


def _extract_text(msg: str | dict | list) -> str:
    """Pull plain text from a transcript message field."""
    if isinstance(msg, str):
        return msg.strip()
    if isinstance(msg, dict):
        return _extract_text(msg.get("content", ""))
    if isinstance(msg, list):
        return " ".join(
            b.get("text", "") for b in msg if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
    return ""


def classify(tool_name: str, tool_input: dict, cwd: str, rules: str, user_message: str = "") -> dict | None:
    """Call Haiku to classify the action. Returns parsed response or None."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise AutoClassifyWarning(
            "ANTHROPIC_API_KEY is not set for the auto-classify hook.",
            "The hook cannot call Anthropic, so it is falling back to the normal permission prompt.",
            "Run `secrets-edit` / `setup-envrc`, or fix `with-anthropic-key.sh` so the hook gets a key.",
        )

    # Truncate large tool inputs (e.g., Write with full file content)
    input_str = json.dumps(tool_input, indent=2)
    if len(input_str) > MAX_INPUT_CHARS:
        input_str = input_str[:MAX_INPUT_CHARS] + "\n... (truncated)"

    user_msg = f"Tool: {tool_name}\nInput: {input_str}\nWorking directory: {cwd}"
    if user_message:
        user_msg += f"\nUser's request: {user_message}"

    body = json.dumps({
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "system": rules,
        "messages": [{"role": "user", "content": user_msg}],
    }).encode()

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            data = json.loads(resp.read())
        text = data["content"][0]["text"].strip()
        # Extract JSON robustly: find first { to last }
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1:
            raise AutoClassifyWarning(
                "Anthropic returned a malformed auto-classify response.",
                text[:200],
                "Check ~/.cache/claude/auto-classify.log. Claude will fall back to the normal permission prompt.",
            )
        return json.loads(text[start : end + 1])
    except urllib.error.HTTPError as e:
        error_type, message = parse_anthropic_error(e)
        raise classify_api_problem(e.code, error_type, message) from e
    except urllib.error.URLError as e:
        raise AutoClassifyWarning(
            "Anthropic auto-classify could not reach the API.",
            str(e.reason),
            "Check your network connection. Claude will fall back to the normal permission prompt.",
        ) from e
    except AutoClassifyWarning:
        raise
    except Exception as e:
        raise AutoClassifyWarning(
            "Anthropic auto-classify crashed unexpectedly.",
            str(e),
            "Check ~/.cache/claude/auto-classify.log. Claude will fall back to the normal permission prompt.",
        ) from e


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "unknown")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd", "")
    transcript_path = hook_input.get("transcript_path", "")

    # Fast-path: bypass API for known-safe Bash patterns
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        fast_reason = fast_classify_bash(cmd)
        if fast_reason:
            log(f"ALLOW (fast-path): {tool_name} — {fast_reason}")
            json.dump({
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "allow"},
                }
            }, sys.stdout)
            return

    try:
        with open(RULES_PATH) as f:
            rules = f.read()
    except Exception:
        emit_warning(
            "auto-classify rules file could not be read.",
            RULES_PATH,
            "Check the dotfiles checkout on this machine. Claude will use the normal permission prompt.",
        )
        return

    # Inject repo trust context into rules
    trust = detect_repo_trust(cwd)
    trust_section = f"""
## Repo Trust Context (auto-detected)

- **Remote URL**: {trust['remote_url'] or 'unknown'}
- **Owner**: {trust['owner'] or 'unknown'}
- **Trusted repo**: {trust['trusted']}
- **Personal repo**: {trust['personal']}
"""
    rules = rules.replace(
        "## Environment",
        f"## Environment\n{trust_section}",
    )

    user_message = ""
    if INCLUDE_USER_MESSAGE and transcript_path:
        user_message = extract_last_user_message(transcript_path)

    try:
        result = classify(tool_name, tool_input, cwd, rules, user_message)
    except AutoClassifyWarning as warning:
        emit_warning(warning.headline, warning.details, warning.suggestion)
        return

    decision = result.get("decision", "allow").lower()
    reason = result.get("reason", "")
    log(f"{decision.upper()}: {tool_name} — {reason}")

    if decision == "deny":
        # Show warning but don't block — let user decide
        suggestion = result.get("suggestion", "")
        msg = f"\033[1;33m⚠ auto-classify:\033[0m {reason}"
        if suggestion:
            msg += f"\n\033[1;36m💡 Suggestion:\033[0m {suggestion}"
        output = {
            "systemMessage": msg,
        }
        json.dump(output, sys.stdout)
        return
    else:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow",
                },
            }
        }

    json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
