#!/usr/bin/env python3
"""Analyze Claude Code hook logs for insights"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import Counter, defaultdict
import argparse


def load_json_log(file_path):
    """Load JSON log file safely"""
    if not file_path.exists():
        return []

    try:
        with open(file_path, "r") as f:
            return json.load(f)
    except:
        return []


def analyze_tool_usage(logs_dir):
    """Analyze tool usage patterns"""
    post_log = load_json_log(logs_dir / "post_tool_use.json")

    if not post_log:
        print("No post-tool-use logs found")
        return

    # Count tool usage
    tool_counts = Counter(entry["tool_name"] for entry in post_log)

    # Count successes/failures
    success_counts = defaultdict(lambda: {"success": 0, "failure": 0})
    for entry in post_log:
        tool = entry["tool_name"]
        success = entry.get("tool_response", {}).get("success", True)
        if success:
            success_counts[tool]["success"] += 1
        else:
            success_counts[tool]["failure"] += 1

    print("\n=== Tool Usage Analysis ===")
    print(f"Total tool calls: {len(post_log)}")
    print("\nTool usage counts:")
    for tool, count in tool_counts.most_common():
        success = success_counts[tool]["success"]
        failure = success_counts[tool]["failure"]
        rate = (success / (success + failure) * 100) if (success + failure) > 0 else 0
        print(
            f"  {tool}: {count} calls ({success} success, {failure} failed, {rate:.1f}% success rate)"
        )


def analyze_file_operations(logs_dir):
    """Analyze file operation patterns"""
    post_log = load_json_log(logs_dir / "post_tool_use.json")

    file_ops = defaultdict(set)
    for entry in post_log:
        if entry["tool_name"] in ["Write", "Edit", "MultiEdit", "Read"]:
            file_path = entry.get("tool_input", {}).get("file_path", "")
            if file_path:
                file_ops[entry["tool_name"]].add(file_path)

    print("\n=== File Operations Analysis ===")
    for op, files in file_ops.items():
        print(f"\n{op} operations ({len(files)} unique files):")
        for file_path in sorted(files)[:10]:  # Show first 10
            print(f"  {file_path}")
        if len(files) > 10:
            print(f"  ... and {len(files) - 10} more files")


def analyze_security_blocks(logs_dir):
    """Analyze blocked operations"""
    pre_log = load_json_log(logs_dir / "pre_tool_use.json")

    # This is approximate - in practice you'd need to correlate with actual blocks
    sensitive_patterns = [".env", "password", "secret", ".key", ".pem"]
    dangerous_commands = ["rm -rf", "dd if=", "mkfs"]

    sensitive_attempts = []
    dangerous_attempts = []

    for entry in pre_log:
        tool = entry["tool_name"]
        if tool == "Bash":
            command = entry.get("tool_input", {}).get("command", "")
            for pattern in dangerous_commands:
                if pattern in command:
                    dangerous_attempts.append(command)
        elif tool in ["Read", "Write", "Edit"]:
            file_path = entry.get("tool_input", {}).get("file_path", "")
            for pattern in sensitive_patterns:
                if pattern in file_path:
                    sensitive_attempts.append(file_path)

    print("\n=== Security Analysis ===")
    print(f"Potential sensitive file access attempts: {len(sensitive_attempts)}")
    for attempt in sensitive_attempts[:5]:
        print(f"  {attempt}")

    print(f"\nPotential dangerous commands: {len(dangerous_attempts)}")
    for attempt in dangerous_attempts[:5]:
        print(f"  {attempt}")


def analyze_sessions(logs_dir):
    """Analyze session information"""
    latest_chat = logs_dir / "latest_chat.json"

    if not latest_chat.exists():
        print("\nNo session data found")
        return

    try:
        with open(latest_chat, "r") as f:
            session = json.load(f)
    except:
        print("\nCould not load session data")
        return

    print("\n=== Latest Session Analysis ===")
    print(f"Session ID: {session.get('session_id', 'Unknown')[:8]}")
    print(f"Timestamp: {session.get('timestamp', 'Unknown')}")
    print(f"Total messages: {session.get('message_count', 0)}")
    print(f"Tool calls: {session.get('tool_calls', 0)}")

    # Analyze message types
    messages = session.get("messages", [])
    msg_types = Counter(msg.get("type", "unknown") for msg in messages)
    print("\nMessage types:")
    for msg_type, count in msg_types.most_common():
        print(f"  {msg_type}: {count}")


def analyze_timeline(logs_dir):
    """Create activity timeline"""
    post_log = load_json_log(logs_dir / "post_tool_use.json")

    if not post_log:
        print("\nNo timeline data available")
        return

    # Get last 20 operations
    recent = sorted(post_log, key=lambda x: x.get("timestamp", ""))[-20:]

    print("\n=== Recent Activity Timeline ===")
    for entry in recent:
        timestamp = entry.get("timestamp", "Unknown")
        tool = entry["tool_name"]

        # Create summary
        summary = ""
        if tool == "Bash":
            summary = entry.get("tool_input", {}).get("command", "")[:50]
        elif tool in ["Write", "Edit", "Read"]:
            summary = entry.get("tool_input", {}).get("file_path", "")
        else:
            summary = str(entry.get("tool_input", ""))[:50]

        # Format timestamp
        try:
            dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            time_str = dt.strftime("%H:%M:%S")
        except:
            time_str = timestamp[:19]

        print(f"{time_str} | {tool:15} | {summary}")


def main():
    parser = argparse.ArgumentParser(description="Analyze Claude Code hook logs")
    parser.add_argument(
        "--logs-dir",
        default=".claude/logs",
        help="Path to logs directory (default: .claude/logs)",
    )
    parser.add_argument("--all", action="store_true", help="Run all analyses")
    parser.add_argument("--tools", action="store_true", help="Analyze tool usage")
    parser.add_argument("--files", action="store_true", help="Analyze file operations")
    parser.add_argument(
        "--security", action="store_true", help="Analyze security blocks"
    )
    parser.add_argument("--sessions", action="store_true", help="Analyze session data")
    parser.add_argument(
        "--timeline", action="store_true", help="Show activity timeline"
    )

    args = parser.parse_args()

    logs_dir = Path(args.logs_dir)
    if not logs_dir.exists():
        print(f"Error: Logs directory not found: {logs_dir}")
        sys.exit(1)

    # If no specific analysis requested, show summary
    if not any(
        [args.all, args.tools, args.files, args.security, args.sessions, args.timeline]
    ):
        args.tools = True
        args.timeline = True

    if args.all or args.tools:
        analyze_tool_usage(logs_dir)

    if args.all or args.files:
        analyze_file_operations(logs_dir)

    if args.all or args.security:
        analyze_security_blocks(logs_dir)

    if args.all or args.sessions:
        analyze_sessions(logs_dir)

    if args.all or args.timeline:
        analyze_timeline(logs_dir)


if __name__ == "__main__":
    main()
