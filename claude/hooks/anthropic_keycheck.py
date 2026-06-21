#!/usr/bin/env python3
"""SessionStart hook: proactive Anthropic API key health check.

Pings the Anthropic API once at session start with a tiny request so the user
learns up front if the key is rejected or the workspace is over its usage
limit — instead of discovering it mid-task when auto_classify.py fails open.

Reuses the error parsing/classification logic from auto_classify.py.
Fails open on ANY unexpected error: exit 0, no output, never block the session.
Stays completely silent on success.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from auto_classify import (  # noqa: E402
    parse_anthropic_error,
    classify_api_problem,
    API_URL,
    build_warning_message,
)

PING_MODEL = "claude-haiku-4-5-20251001"
TIMEOUT_SECONDS = 8


def main() -> None:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        # PermissionRequest hook already warns about a missing key.
        return

    body = json.dumps({
        "model": PING_MODEL,
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "ping"}],
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
            resp.read()
        # HTTP 200 → key is healthy. Stay silent.
        return
    except urllib.error.HTTPError as e:
        error_type, message = parse_anthropic_error(e)
        warning = classify_api_problem(e.code, error_type, message)
        msg = build_warning_message(warning.headline, warning.details, warning.suggestion)
        json.dump({"systemMessage": msg}, sys.stdout)
    except Exception:
        # Network error, timeout, or anything unexpected — fail open silently.
        return


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Last-resort guard: never block session start.
        pass
