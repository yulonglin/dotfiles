#!/usr/bin/env python3
"""Stop hook for chat transcript capture and session summary"""

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

        session_id = input_data.get("session_id", "")
        stop_hook_active = input_data.get("stop_hook_active", False)
        transcript_path = input_data.get("transcript_path", "")

        # Log stop event
        log_dir = find_claude_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)

        # Log stop event to JSON
        stop_log_path = log_dir / "stop_events.json"
        stop_log_data = []
        if stop_log_path.exists():
            with open(stop_log_path, "r") as f:
                try:
                    stop_log_data = json.load(f)
                except:
                    pass

        stop_entry = {
            "session_id": session_id,
            "timestamp": datetime.now().isoformat(),
            "stop_hook_active": stop_hook_active,
        }
        stop_log_data.append(stop_entry)

        # Keep last 100 stop events
        stop_log_data = stop_log_data[-100:]

        with open(stop_log_path, "w") as f:
            json.dump(stop_log_data, f, indent=2)

        # Capture full chat transcript if available
        if transcript_path and os.path.exists(transcript_path):
            chat_data = []
            try:
                with open(transcript_path, "r") as f:
                    for line in f:
                        line = line.strip()
                        if line:
                            try:
                                chat_data.append(json.loads(line))
                            except json.JSONDecodeError:
                                pass

                # Save chat transcript with session ID
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                chat_file = log_dir / f"chat_{session_id[:8]}_{timestamp}.json"

                # Also save as latest chat for easy access
                latest_chat_file = log_dir / "latest_chat.json"

                # Enrich with metadata
                chat_export = {
                    "session_id": session_id,
                    "timestamp": datetime.now().isoformat(),
                    "messages": chat_data,
                    "message_count": len(chat_data),
                    "tool_calls": len(
                        [m for m in chat_data if m.get("type") == "tool_use"]
                    ),
                }

                # Save both files
                with open(chat_file, "w") as f:
                    json.dump(chat_export, f, indent=2)

                with open(latest_chat_file, "w") as f:
                    json.dump(chat_export, f, indent=2)

                # Create session summary
                summary_lines = [
                    f"\n{'=' * 60}",
                    f"Session Complete: {session_id[:8]}",
                    f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                    f"Messages: {len(chat_data)}",
                    f"Tool Calls: {chat_export['tool_calls']}",
                    f"Chat saved to: {chat_file.name}",
                    f"{'=' * 60}\n",
                ]

                # Write summary to activity log
                activity_log = Path.home() / ".claude" / "research-sessions.log"
                activity_log.parent.mkdir(exist_ok=True)

                with open(activity_log, "a") as f:
                    f.write("\n".join(summary_lines))

            except Exception as e:
                # Log error but don't fail
                pass

        # Run existing auto-commit if configured
        auto_commit_script = find_claude_dir() / "scripts" / "auto-commit-research.py"
        if auto_commit_script.exists() and not stop_hook_active:
            import subprocess

            try:
                # Pass the input data to the auto-commit script
                result = subprocess.run(
                    ["python3", str(auto_commit_script)],
                    input=json.dumps(input_data),
                    text=True,
                    capture_output=True,
                    timeout=10,
                )
            except:
                pass

        sys.exit(0)

    except:
        sys.exit(0)


if __name__ == "__main__":
    main()
