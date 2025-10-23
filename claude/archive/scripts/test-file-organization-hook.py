#!/usr/bin/env python3
"""
Test script for the file organization validation hook.
Run this to verify the hook is working correctly.
"""

import json
import subprocess
import sys


def test_hook(test_name, tool_name, file_path, should_block=False):
    """Test the hook with given parameters."""
    test_input = {"tool_name": tool_name, "tool_input": {"file_path": file_path}}

    print(f"\n{'=' * 60}")
    print(f"Test: {test_name}")
    print(f"Tool: {tool_name}, File: {file_path}")
    print(f"Expected: {'BLOCK' if should_block else 'ALLOW'}")

    try:
        result = subprocess.run(
            ["python3", ".claude/scripts/validate-file-organization.py"],
            input=json.dumps(test_input),
            text=True,
            capture_output=True,
        )

        if result.returncode == 0:
            print("Result: ALLOWED ✅")
        elif result.returncode == 2:
            print("Result: BLOCKED ❌")
            print("Error message:")
            print(result.stderr)
        else:
            print(f"Result: ERROR (exit code {result.returncode})")
            print("Error:", result.stderr)

        # Check if result matches expectation
        if should_block and result.returncode != 2:
            print("⚠️  FAILED: Expected block but was allowed")
        elif not should_block and result.returncode == 2:
            print("⚠️  FAILED: Expected allow but was blocked")
        else:
            print("✅ PASSED")

    except Exception as e:
        print(f"Exception: {e}")


def main():
    print("Testing File Organization Validation Hook")
    print("========================================")

    # Test cases
    tests = [
        # Markdown files in root (should block except README.md)
        ("Markdown in root", "Write", "test.md", True),
        ("README.md in root", "Write", "README.md", False),
        ("Markdown in docs", "Write", "docs/guide.md", False),
        (
            "Markdown in ai_docs",
            "Write",
            "ai_docs/cc_implementation_logs/impl.md",
            False,
        ),
        # Test files in root (should block)
        ("Python test in root", "Write", "test_example.py", True),
        ("JS test in root", "Write", "example.test.js", True),
        ("Test file in tests dir", "Write", "tests/test_example.py", False),
        # Regular files (should allow)
        ("Python file in root", "Write", "main.py", False),
        ("Python file in utils", "Write", "utils/helper.py", False),
        # Edit operations
        ("Edit markdown in root", "Edit", "existing.md", True),
        ("Edit test in root", "Edit", "test_existing.py", True),
        # Other tools (should be ignored)
        ("Read operation", "Read", "test.md", False),
        ("Bash operation", "Bash", "test.md", False),
    ]

    for test_args in tests:
        test_hook(*test_args)

    print(f"\n{'=' * 60}")
    print("Testing complete!")


if __name__ == "__main__":
    main()
