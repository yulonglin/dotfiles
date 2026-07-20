#!/usr/bin/env python3
"""Git clean filters that strip machine-local personal inventories before staging.

Codex and Zed write live state (trusted project paths, recent SSH connections)
into their symlinked config files. Those inventories reveal private project
names and paths, so they must never reach the public repo. Registered as git
clean filters (see .gitattributes + deploy.sh); a pre-commit guard backstops
machines where the filter isn't registered.

Usage (stdin -> stdout, as git invokes filters):
    strip_personal.py codex-projects   # drop [projects."..."] tables from codex/config.toml
    strip_personal.py zed-ssh          # empty the "ssh_connections" array in zed settings.json

Both modes are idempotent: already-clean content passes through unchanged.
"""

import sys


def strip_codex_projects(text: str) -> str:
    """Remove every [projects."..."] table (header + body) from a TOML document."""
    out: list[str] = []
    skipping = False
    for line in text.splitlines(keepends=True):
        is_header = line.lstrip().startswith("[")
        is_projects_header = line.lstrip().startswith('[projects."') or line.lstrip().startswith("[projects.")
        if is_projects_header:
            # Drop blank lines that preceded this block so removal leaves no gap
            while out and out[-1].strip() == "":
                out.pop()
            skipping = True
            continue
        if skipping:
            if is_header:
                skipping = False
                # Restore a single blank separator before the next kept section
                if out and out[-1].strip() != "":
                    out.append("\n")
                out.append(line)
            continue
        out.append(line)
    return "".join(out)


def strip_zed_ssh(text: str) -> str:
    """Replace the top-level "ssh_connections" array's contents with []."""
    key = '"ssh_connections"'
    key_pos = text.find(key)
    if key_pos == -1:
        return text
    open_pos = text.find("[", key_pos)
    if open_pos == -1:
        return text
    # Bracket-match to find the array's closing ] (comments/strings inside are
    # only SSH hosts and paths — no brackets in strings expected, but handle
    # strings defensively)
    depth = 0
    in_string = False
    escape = False
    for i in range(open_pos, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return text[:open_pos] + "[]" + text[i + 1 :]
    return text  # unbalanced — pass through rather than corrupt


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("codex-projects", "zed-ssh"):
        sys.stderr.write("usage: strip_personal.py {codex-projects|zed-ssh}\n")
        return 2
    text = sys.stdin.read()
    if sys.argv[1] == "codex-projects":
        sys.stdout.write(strip_codex_projects(text))
    else:
        sys.stdout.write(strip_zed_ssh(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
