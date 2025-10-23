#!/usr/bin/env python3
"""Subagent stop hook for tracking parallel agent completions"""

import json
import sys
from pathlib import Path
from datetime import datetime
from hook_utils import find_claude_dir


def main():
    try:
        # Read JSON input from stdin
        input_data = json.load(sys.stdin)

        session_id = input_data.get("session_id", "")[:8]
        stop_hook_active = input_data.get("stop_hook_active", False)

        # Log subagent completion
        log_dir = find_claude_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)

        subagent_log = log_dir / "subagent_completions.json"
        completions = []

        if subagent_log.exists():
            with open(subagent_log, "r") as f:
                try:
                    completions = json.load(f)
                except:
                    pass

        # Add completion entry
        completion_entry = {
            "session_id": session_id,
            "timestamp": datetime.now().isoformat(),
            "stop_hook_active": stop_hook_active,
        }
        completions.append(completion_entry)

        # Keep last 200 completions
        completions = completions[-200:]

        with open(subagent_log, "w") as f:
            json.dump(completions, f, indent=2)

        # Quick summary to activity log
        activity_log = Path.home() / ".claude" / "research-activity.log"
        activity_log.parent.mkdir(exist_ok=True)

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(activity_log, "a") as f:
            f.write(f"[{timestamp}] [{session_id}] SUBAGENT: Task completed\n")

        sys.exit(0)

    except:
        sys.exit(0)


if __name__ == "__main__":
    main()
