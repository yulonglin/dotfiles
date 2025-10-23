#!/usr/bin/env python3
"""
Notification hook for Claude Code
Shows a visual notification when Claude needs attention
"""

import json
import sys
import subprocess
import platform


def notify_macos(message):
    """Show macOS notification"""
    script = f'''
    display notification "{message}" with title "Claude Code" sound name "Pop"
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True)


def notify_terminal(message):
    """Show terminal notification"""
    # ANSI escape codes for bright yellow text
    yellow = "\033[1;33m"
    reset = "\033[0m"
    print(f"\n{yellow}⚡ {message}{reset}\n", file=sys.stderr)


def main():
    try:
        # Read input from Claude Code
        input_data = json.load(sys.stdin)
        message = input_data.get("message", "Claude Code needs your attention")
    except:
        message = "Claude Code needs your attention"

    # Always show terminal notification
    notify_terminal(message)

    # Try macOS notification if available
    if platform.system() == "Darwin":
        try:
            notify_macos(message)
        except:
            pass  # Fall back to terminal only

    sys.exit(0)


if __name__ == "__main__":
    main()
