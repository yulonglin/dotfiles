#!/usr/bin/env python3
"""Post-tool-use hook for observability and logging"""

import json
import sys
from pathlib import Path
from datetime import datetime
from hook_utils import find_claude_dir


def main():
    try:
        # Read JSON input from stdin
        input_data = json.load(sys.stdin)

        # Log to comprehensive JSON file
        log_dir = find_claude_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / "post_tool_use.json"

        # Read existing log data
        log_data = []
        if log_path.exists():
            with open(log_path, "r") as f:
                try:
                    log_data = json.load(f)
                except:
                    pass

        # Add timestamp and append
        log_entry = input_data.copy()
        log_entry["timestamp"] = datetime.now().isoformat()
        log_data.append(log_entry)

        # Keep only last 1000 entries
        if len(log_data) > 1000:
            log_data = log_data[-1000:]

        # Write back to file
        with open(log_path, "w") as f:
            json.dump(log_data, f, indent=2)

        # Simple activity log for quick reference
        tool_name = input_data.get("tool_name", "")
        tool_input = input_data.get("tool_input", {})
        tool_response = input_data.get("tool_response", {})
        session_id = input_data.get("session_id", "")[:8]

        # Create summary for activity log
        summary = ""
        if tool_name == "Bash":
            command = tool_input.get("command", "")
            success = tool_response.get("success", False)
            summary = f"{command} ({'SUCCESS' if success else 'FAILED'})"
        elif tool_name in ["Write", "Edit", "MultiEdit"]:
            file_path = tool_input.get("file_path", "")
            success = tool_response.get("success", False)
            summary = f"{file_path} ({'MODIFIED' if success else 'FAILED'})"
        elif tool_name == "Read":
            file_path = tool_input.get("file_path", "")
            summary = f"{file_path} (READ)"

        # Write to activity log
        activity_log = Path.home() / ".claude" / "research-activity-detailed.log"
        activity_log.parent.mkdir(exist_ok=True)

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(activity_log, "a") as f:
            f.write(f"[{timestamp}] [{session_id}] POST {tool_name}: {summary}\n")

        sys.exit(0)

    except:
        sys.exit(0)


if __name__ == "__main__":
    main()
