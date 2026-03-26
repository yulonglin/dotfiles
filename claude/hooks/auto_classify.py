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
# Denial escalation: after too many denials, fall back to showing the prompt
MAX_CONSECUTIVE_DENIALS = 3
MAX_TOTAL_DENIALS = 20
DENIAL_STATE_PATH = os.path.expanduser("~/.cache/claude/auto-classify-denials.json")


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


def classify(tool_name: str, tool_input: dict, cwd: str, rules: str) -> dict | None:
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


def load_denial_state() -> dict:
    """Load denial counters. Returns {consecutive: int, total: int, session: str}."""
    try:
        with open(DENIAL_STATE_PATH) as f:
            return json.load(f)
    except Exception:
        return {"consecutive": 0, "total": 0, "session": ""}


def save_denial_state(state: dict) -> None:
    try:
        os.makedirs(os.path.dirname(DENIAL_STATE_PATH), exist_ok=True)
        with open(DENIAL_STATE_PATH, "w") as f:
            json.dump(state, f)
    except Exception:
        pass


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "unknown")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "")

    # Check denial escalation — too many denials → fall back to normal prompt
    state = load_denial_state()
    if state.get("session") != session_id:
        state = {"consecutive": 0, "total": 0, "session": session_id}
    if state["consecutive"] >= MAX_CONSECUTIVE_DENIALS or state["total"] >= MAX_TOTAL_DENIALS:
        log(f"ESCALATE: too many denials (consecutive={state['consecutive']}, total={state['total']}), showing prompt")
        sys.exit(0)

    try:
        with open(RULES_PATH) as f:
            rules = f.read()
    except Exception:
        log("Cannot read rules file")
        sys.exit(0)

    result = classify(tool_name, tool_input, cwd, rules)
    if result is None:
        sys.exit(0)

    decision = result.get("decision", "allow").lower()
    reason = result.get("reason", "")
    log(f"{decision.upper()}: {tool_name} — {reason}")

    if decision == "deny":
        state["consecutive"] += 1
        state["total"] += 1
        save_denial_state(state)
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": f"Auto-classifier denied: {reason}. Use a different approach or ask the user.",
                    "interrupt": False,
                },
            }
        }
    else:
        state["consecutive"] = 0  # Reset consecutive on allow
        save_denial_state(state)
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
