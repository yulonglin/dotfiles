#!/usr/bin/env python3
"""List all accessible BWS secrets through concurrent project-scoped reads."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any


def run_bws(*args: str) -> list[dict[str, Any]]:
    for attempt in range(3):
        result = subprocess.run(
            ["bws", "--color", "no", *args],
            check=False,
            capture_output=True,
            text=True,
            env=os.environ,
        )
        if result.returncode == 0:
            break
        message = result.stderr.strip() or f"bws exited {result.returncode}"
        if "429 Too Many Requests" not in message or attempt == 2:
            raise RuntimeError(message)
        match = re.search(r"Try again in (\d+)s", message)
        delay = int(match.group(1)) if match else 1
        time.sleep(min(5, max(0, delay)))
    else:
        raise RuntimeError("bws retry loop exhausted")

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid JSON from bws: {error}") from error
    if not isinstance(data, list) or not all(isinstance(item, dict) for item in data):
        raise RuntimeError("unexpected bws output: expected a JSON array of objects")
    return data


def main() -> int:
    try:
        projects = run_bws("project", "list")
        project_ids = [project.get("id") for project in projects]
        if any(not isinstance(project_id, str) or not project_id for project_id in project_ids):
            raise RuntimeError("unexpected bws project: missing id")

        with ThreadPoolExecutor(max_workers=min(8, max(1, len(project_ids)))) as executor:
            batches = list(
                executor.map(
                    lambda project_id: run_bws("secret", "list", project_id),
                    project_ids,
                )
            )
        json.dump([secret for batch in batches for secret in batch], sys.stdout)
        sys.stdout.write("\n")
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
