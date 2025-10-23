#!/usr/bin/env python3
"""Enhanced notification hook with logging"""

import json
import sys
import os
from pathlib import Path
from datetime import datetime
from hook_utils import find_claude_dir


def main():
    try:
        # Read JSON input from stdin
        input_data = json.load(sys.stdin)

        message = input_data.get("message", "")
        session_id = input_data.get("session_id", "")[:8]

        # Log notification
        log_dir = find_claude_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)

        notification_log = log_dir / "notifications.json"
        notifications = []

        if notification_log.exists():
            with open(notification_log, "r") as f:
                try:
                    notifications = json.load(f)
                except:
                    pass

        # Add new notification
        notification_entry = {
            "session_id": session_id,
            "timestamp": datetime.now().isoformat(),
            "message": message,
        }
        notifications.append(notification_entry)

        # Keep last 100 notifications
        notifications = notifications[-100:]

        with open(notification_log, "w") as f:
            json.dump(notifications, f, indent=2)

        # Run original notify script if it exists
        notify_script = find_claude_dir() / "scripts" / "notify.py"
        if notify_script.exists():
            import subprocess

            try:
                result = subprocess.run(
                    ["python3", str(notify_script)],
                    input=json.dumps(input_data),
                    text=True,
                    capture_output=True,
                    timeout=5,
                )
            except:
                pass

        # Simple console notification
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"\n[{timestamp}] Claude needs your input: {message}\n")

        sys.exit(0)

    except:
        sys.exit(0)


if __name__ == "__main__":
    main()
