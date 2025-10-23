#!/usr/bin/env python3
"""
Hook to ensure markdown and test files are created in the appropriate directories.
Blocks creation of these files in the project root and provides guidance.
"""

import json
import os
import sys


def main():
    try:
        # Read input from stdin
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only check Write, Edit, and MultiEdit tools
    if tool_name not in ["Write", "Edit", "MultiEdit"]:
        sys.exit(0)

    # Get file path(s)
    file_paths = []
    if tool_name == "Write":
        file_path = tool_input.get("file_path", "")
        if file_path:
            file_paths.append(file_path)
    elif tool_name in ["Edit", "MultiEdit"]:
        file_path = tool_input.get("file_path", "")
        if file_path:
            file_paths.append(file_path)

    # Check each file path
    for file_path in file_paths:
        if not file_path:
            continue

        # Normalize the path
        abs_path = os.path.abspath(file_path)
        base_name = os.path.basename(abs_path)
        dir_name = os.path.dirname(abs_path)

        # Get the project root (where .claude directory is)
        project_root = os.getcwd()

        # Check if file is being created in project root
        if os.path.dirname(abs_path) == project_root:
            # Check for markdown files (excluding README.md and CLAUDE.md)
            if base_name.endswith(".md") and base_name.upper() not in ["README.MD", "CLAUDE.MD"]:
                print(
                    f"❌ Markdown files should not be created in the project root.",
                    file=sys.stderr,
                )
                print(f"Please use one of these locations instead:", file=sys.stderr)
                print(
                    f"  • Implementation logs → ai_docs/cc_implementation_logs/{base_name}",
                    file=sys.stderr,
                )
                print(f"  • User guides → docs/guides/{base_name}", file=sys.stderr)
                print(
                    f"  • Reference docs → docs/reference/{base_name}", file=sys.stderr
                )
                print(f"  • Templates → docs/templates/{base_name}", file=sys.stderr)
                print(f"  • Planning docs → docs/{base_name}", file=sys.stderr)
                print(
                    f"\nSuggested action: Create the file in ai_docs/cc_implementation_logs/{base_name}",
                    file=sys.stderr,
                )
                sys.exit(2)  # Exit code 2 blocks the tool and shows error to Claude

            # Check for test files
            test_patterns = [
                "test_",
                "_test.py",
                ".test.js",
                ".test.ts",
                ".test.jsx",
                ".test.tsx",
                "spec.js",
                "spec.ts",
                "_spec.py",
                "_test.go",
                "_test.rb",
            ]
            is_test_file = any(
                pattern in base_name.lower() for pattern in test_patterns
            )

            if is_test_file:
                print(
                    f"❌ Test files should not be created in the project root.",
                    file=sys.stderr,
                )
                print(
                    f"Please create the test file in: tests/{base_name}",
                    file=sys.stderr,
                )
                print(
                    f"\nSuggested action: Create the file at tests/{base_name}",
                    file=sys.stderr,
                )
                sys.exit(2)  # Exit code 2 blocks the tool and shows error to Claude

    # If we get here, the file placement is acceptable
    sys.exit(0)


if __name__ == "__main__":
    main()
