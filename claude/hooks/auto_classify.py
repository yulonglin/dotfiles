#!/usr/bin/env python3
"""PermissionRequest hook: LLM-based permission classifier.

Calls Haiku to classify tool actions as allow/deny, mimicking auto mode.
Fails open (exit 0 = normal prompt) on any error.
Always active — no env var gate.
"""
from __future__ import annotations

import json
import os
import sys
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
        log("SKIP: ANTHROPIC_API_KEY not set")
        return None

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
            log(f"No JSON found in response: {text[:200]}")
            return None
        return json.loads(text[start : end + 1])
    except Exception as e:
        log(f"API error: {e}")
        return None



def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "unknown")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd", "")
    transcript_path = hook_input.get("transcript_path", "")

    try:
        with open(RULES_PATH) as f:
            rules = f.read()
    except Exception:
        log("Cannot read rules file")
        sys.exit(0)

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

    result = classify(tool_name, tool_input, cwd, rules, user_message)
    if result is None:
        sys.exit(0)

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
