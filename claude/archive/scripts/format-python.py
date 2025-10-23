#!/usr/bin/env python3
"""
Python code formatter hook for Claude Code
Automatically formats Python files after edit/write operations
"""

import json
import sys
import subprocess
import os
from pathlib import Path

def main():
    try:
        # Read input from Claude Code
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Not JSON input, exit quietly
        sys.exit(0)
    
    # Extract file path from tool input
    tool_input = input_data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")
    
    # Only process Python files
    if not file_path.endswith(".py"):
        sys.exit(0)
    
    # Check if file exists
    if not os.path.exists(file_path):
        sys.exit(0)
    
    # Check for formatters in order of preference
    formatters = [
        ("ruff", ["ruff", "format", file_path]),
        ("black", ["black", "-q", file_path]),
        ("autopep8", ["autopep8", "-i", file_path])
    ]
    
    for formatter_name, cmd in formatters:
        try:
            # Try to run the formatter
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                print(f"Formatted {Path(file_path).name} with {formatter_name}")
                sys.exit(0)
        except FileNotFoundError:
            # Formatter not installed, try next
            continue
    
    # No formatter found, exit quietly
    sys.exit(0)

if __name__ == "__main__":
    main()