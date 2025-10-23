#!/usr/bin/env python3
"""
Validation hook to prevent mock data usage in research code
Blocks writes that contain common mock data patterns
"""

import json
import sys
import re

# Patterns that indicate mock data
MOCK_PATTERNS = [
    r"\bmock\b",
    r"\bfake\b",
    r"\bdummy\b",
    r"\bplaceholder\b",
    r"\bexample\.com\b",
    r"\btest@example\b",
    r'\bfoo\s*=\s*["\']bar["\']',
    r"\bjohn\s*doe\b",
    r"\bjane\s*doe\b",
    r"lorem\s*ipsum",
    r"# TODO:?\s*implement",
    r"# FIXME:?\s*implement",
    r"raise\s+NotImplementedError",
    r"pass\s*#\s*TODO",
    r"return\s+None\s*#\s*TODO",
]

# Compile patterns for efficiency
COMPILED_PATTERNS = [re.compile(pattern, re.IGNORECASE) for pattern in MOCK_PATTERNS]

# Files to skip validation
SKIP_FILES = {
    "test_",
    "_test.py",
    "mock_",
    "_mock.py",
    "example_",
    "_example.py",
    "demo_",
    "_demo.py",
}

# Extensions to skip validation
SKIP_EXTENSIONS = {".md", ".txt", ".rst", ".json", ".yaml", ".yml"}


def should_skip_file(file_path):
    """Check if file should be skipped"""
    file_name = file_path.split("/")[-1].lower()

    # Check file extension
    for ext in SKIP_EXTENSIONS:
        if file_path.lower().endswith(ext):
            return True

    # Check file name patterns
    return any(skip in file_name for skip in SKIP_FILES)


def validate_content(content):
    """Check content for mock data patterns"""
    issues = []

    lines = content.split("\n")
    for i, line in enumerate(lines, 1):
        for pattern in COMPILED_PATTERNS:
            if pattern.search(line):
                issues.append(
                    f"Line {i}: Found potential mock data pattern: {pattern.pattern}"
                )

    return issues


def main():
    try:
        # Read input from Claude Code
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    # Only check Write and Edit operations
    tool_name = input_data.get("tool_name", "")
    if tool_name not in ["Write", "Edit", "MultiEdit"]:
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})

    # Extract file path and content
    file_path = tool_input.get("file_path", "")

    # Skip validation for test/example files
    if should_skip_file(file_path):
        sys.exit(0)

    # Get content to validate
    content = ""
    if tool_name == "Write":
        content = tool_input.get("content", "")
    elif tool_name == "Edit":
        content = tool_input.get("new_string", "")
    elif tool_name == "MultiEdit":
        # Check all edits
        edits = tool_input.get("edits", [])
        content = "\n".join(edit.get("new_string", "") for edit in edits)

    # Validate content
    issues = validate_content(content)

    if issues:
        print(
            "Mock data detected! Research code should use real data.", file=sys.stderr
        )
        print("\nFound the following issues:", file=sys.stderr)
        for issue in issues[:5]:  # Show first 5 issues
            print(f"• {issue}", file=sys.stderr)
        if len(issues) > 5:
            print(f"• ... and {len(issues) - 5} more issues", file=sys.stderr)
        print(
            "\nPlease use actual data, configurations, or implementations instead of placeholders.",
            file=sys.stderr,
        )
        sys.exit(2)  # Exit code 2 blocks the operation

    sys.exit(0)


if __name__ == "__main__":
    main()
