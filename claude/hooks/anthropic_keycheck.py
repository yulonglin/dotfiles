#!/usr/bin/env python3
"""SessionStart hook: proactive Anthropic API key health check.

Pings the Anthropic API once at session start with a tiny request so the user
learns up front if the key is rejected or the workspace is over its usage
limit — instead of discovering it mid-task when approval_classifier.py fails open.

Reuses the error parsing/classification logic from approval_classifier.py.
Fails open on ANY unexpected error: exit 0, no output, never block the session.
Stays completely silent on success. Results are cached for 1 hour.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error

PING_MODEL = "claude-haiku-4-5-20251001"
TIMEOUT_SECONDS = 8
# This hook's OWN deadline. MUST match the SessionStart "timeout" for the
# anthropic_keycheck.py entry in claude/settings.json (pinned by
# tests/test_anthropic_key_retry.py). It is NOT the classifier's 30s
# PermissionRequest budget: the 401 retry inside post_anthropic is gated on
# whatever budget it is given, and handing it the classifier's 26s let this hook
# plan a refresh-plus-retry that could only end in Claude killing it at 10s —
# no health file written, no warning printed, a silent stall at session start.
HOOK_TIMEOUT_SECONDS = 10
# write the cache file / render and flush the warning JSON
EPILOGUE_RESERVE_SECONDS = 1.5
TOTAL_BUDGET_SECONDS = HOOK_TIMEOUT_SECONDS - EPILOGUE_RESERVE_SECONDS
CACHE_FILE = os.path.expanduser("~/.cache/claude/keycheck-ok")
CACHE_TTL_SECONDS = 3600  # 1 hour — re-check at most once per hour


def _is_cache_fresh() -> bool:
    try:
        return (time.time() - os.path.getmtime(CACHE_FILE)) < CACHE_TTL_SECONDS
    except OSError:
        return False


def _mark_cache_ok() -> None:
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        open(CACHE_FILE, "w").close()
    except Exception:
        pass


def main() -> None:
    # Import from sibling module — done inside main() to avoid module-level sys.path mutation
    # (CLAUDE.md: "NEVER use sys.path.insert directly" at module level)
    hooks_dir = os.path.dirname(os.path.abspath(__file__))
    if hooks_dir not in sys.path:
        sys.path.insert(0, hooks_dir)
    from approval_classifier import (  # noqa: E402
        parse_anthropic_error,
        classify_api_problem,
        build_warning_message,
        budget_clock,
        post_anthropic,
    )

    # Started here rather than at import so it measures this invocation even if
    # the module is already cached; the wrapper's pre-Python time counts too.
    remaining = budget_clock(TOTAL_BUDGET_SECONDS)

    if _is_cache_fresh():
        return

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        # PermissionRequest hook already warns about a missing key.
        return

    body = json.dumps({
        "model": PING_MODEL,
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "ping"}],
    }).encode()
    try:
        # Shared with approval_classifier.classify(): a 401 here re-resolves the
        # key from dotfiles-secrets and retries once, so a session holding a
        # pre-rotation key from its direnv snapshot recovers instead of warning.
        # The retry is gated on THIS hook's countdown, so every stage — helper
        # call and retried request alike — is clamped to what is left of the 10s.
        post_anthropic(body, timeout=TIMEOUT_SECONDS, remaining=remaining)
        # HTTP 200 → key is healthy. Cache the result and stay silent.
        _mark_cache_ok()
        return
    except urllib.error.HTTPError as e:
        error_type, message = parse_anthropic_error(e)
        warning = classify_api_problem(e.code, error_type, message)
        msg = build_warning_message(warning.headline, warning.details, warning.suggestion)
        # Emit both: systemMessage surfaces the warning directly to the user (a top-level
        # field shown to the user on any event, per the hooks docs), and
        # hookSpecificOutput.additionalContext adds it to Claude's context so it can offer
        # to help. Mirrors approval_classifier.py's emit_warning, which sets both fields.
        print(json.dumps({
            "systemMessage": msg,
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": msg,
            },
        }))
    except Exception:
        # Network error, timeout, or anything unexpected — fail open silently.
        return


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Last-resort guard: never block session start.
        pass
