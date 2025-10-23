#!/usr/bin/env python3
"""Test script to debug commit message generation"""

import subprocess
import tempfile
import os


def test_claude_commit_message():
    # Test data
    diff_content = """diff --git a/test.py b/test.py
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/test.py
@@ -0,0 +1,10 @@
+def hello_world():
+    print("Hello, World!")
+
+if __name__ == "__main__":
+    hello_world()"""

    status_summary = "A  test.py"

    # Create prompt
    prompt = f"""You are a skilled developer creating a git commit message. Analyze the following git diff and status to create a clear, informative commit message.

Follow these guidelines:
- Use conventional commit format (feat:, fix:, docs:, refactor:, etc.)
- Be specific about what was changed/added/fixed
- Keep the first line under 50 characters when possible
- Add a detailed description if the changes are significant
- Focus on the "why" and "what" rather than just "how"

Git Status:
{status_summary}

Git Diff:
{diff_content}

Generate a commit message that accurately describes these changes:"""

    try:
        # Write prompt to temp file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write(prompt)
            prompt_file = f.name

        print(f"Prompt file: {prompt_file}")
        print(f"Prompt content length: {len(prompt)}")

        # Test claude command
        result = subprocess.run(
            ["claude", "--file", prompt_file, "--quiet"],
            capture_output=True,
            text=True,
            timeout=30,
        )

        print(f"Return code: {result.returncode}")
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")

        # Clean up
        os.unlink(prompt_file)

        if result.returncode == 0:
            commit_message = result.stdout.strip()
            commit_message = commit_message.replace("```", "").strip()
            print(f"Generated message: {commit_message}")
        else:
            print("Claude command failed")

    except subprocess.TimeoutExpired:
        print("Claude command timed out")
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    test_claude_commit_message()
