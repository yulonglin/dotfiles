#!/usr/bin/env python3
"""
Activity logging hook for research tracking
Logs Claude Code operations to a file for later analysis
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path

LOG_FILE = Path.home() / ".claude" / "research-activity.log"


def main():
    try:
        # Read input from Claude Code
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Not JSON input, exit quietly
        sys.exit(0)

    # Extract relevant information
    session_id = input_data.get("session_id", "unknown")[:8]
    tool_name = input_data.get("tool_name", "unknown")
    tool_input = input_data.get("tool_input", {})

    # Determine what to log based on tool
    log_detail = ""
    if tool_name == "Bash":
        log_detail = tool_input.get("command", "")
    elif tool_name in ["Write", "Edit", "MultiEdit"]:
        log_detail = tool_input.get("file_path", "")
    elif tool_name == "Task":
        log_detail = tool_input.get("prompt", "")[:100] + "..."
    else:
        # For other tools, convert to string and truncate
        log_detail = str(tool_input)[:100]

    # Create log entry
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] [{session_id}] {tool_name}: {log_detail}\n"

    # Ensure log directory exists
    LOG_FILE.parent.mkdir(exist_ok=True)

    # Append to log file
    with open(LOG_FILE, "a") as f:
        f.write(log_entry)

    sys.exit(0)


if __name__ == "__main__":
    main()
