#!/bin/bash
# shellcheck shell=bash
# Dotfiles repo pre-commit hook: auto-updates SKILL.md symlink deny list
# in claude/skills/.gitignore to prevent non-portable absolute-path symlinks
# from being committed.
#
# Called by the global pre-commit hook via .git/hooks/pre-commit.local
# Safe to run standalone for testing.

set -euo pipefail

# ── Guard: only run in the dotfiles repo ──

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
GITIGNORE="$REPO_ROOT/claude/skills/.gitignore"

if [[ -z "$REPO_ROOT" ]] || [[ ! -f "$GITIGNORE" ]]; then
    exit 0
fi

# ── Find all SKILL.md symlinks (non-portable, must be ignored) ──

SYMLINKS=""
while IFS= read -r link; do
    # Strip repo prefix to get path relative to claude/skills/
    relative="${link#"$REPO_ROOT"/claude/skills/}"
    if [[ -n "$SYMLINKS" ]]; then
        SYMLINKS="$SYMLINKS"$'\n'"$relative"
    else
        SYMLINKS="$relative"
    fi
done < <(find "$REPO_ROOT/claude/skills" -maxdepth 2 -name "SKILL.md" -type l | sort)

# ── Optional: warn about extensionless non-symlink files ──
# These would be silently ignored by the !**/*.* strategy.

while IFS= read -r -d '' file; do
    basename_file=$(basename "$file")
    # Skip if it's a symlink (self-referencing symlinks are expected)
    [[ -L "$file" ]] && continue
    # Skip known extensionless files (e.g., .codex-system-skills.marker is dot-prefixed)
    [[ "$basename_file" == .* ]] && continue
    # Check if file has no extension
    if [[ "$basename_file" != *.* ]]; then
        echo "warning: extensionless non-symlink file will be silently ignored: $file"
    fi
done < <(find "$REPO_ROOT/claude/skills" -maxdepth 2 -type f -print0 2>/dev/null)

# ── Build the new auto-generated block ──

BEGIN_MARKER="# AUTO-GENERATED: SKILL.md symlinks with non-portable absolute paths (do not edit manually)"
END_MARKER="# END AUTO-GENERATED"

NEW_BLOCK="$BEGIN_MARKER"
NEW_BLOCK="$NEW_BLOCK"$'\n'"# Updated by scripts/hooks/dotfiles-pre-commit.sh"
if [[ -n "$SYMLINKS" ]]; then
    NEW_BLOCK="$NEW_BLOCK"$'\n'"$SYMLINKS"
fi
NEW_BLOCK="$NEW_BLOCK"$'\n'"$END_MARKER"

# ── Replace the auto-generated section ──
# Write new block to a temp file, then use awk to splice it in.
# awk's -v can't hold newlines, so we read the block from a file instead.
# Uses index() instead of regex to avoid metacharacter issues in paths.

TMPDIR_HOOK="${TMPDIR:-/tmp/claude}"
mkdir -p "$TMPDIR_HOOK"
BLOCK_FILE="$TMPDIR_HOOK/gitignore-block.$$.tmp"
TMPFILE="$TMPDIR_HOOK/gitignore-hook.$$.tmp"

printf '%s\n' "$NEW_BLOCK" > "$BLOCK_FILE"

awk -v begin_marker="$BEGIN_MARKER" -v end_marker="$END_MARKER" -v block_file="$BLOCK_FILE" '
BEGIN { in_block = 0; replaced = 0 }
index($0, begin_marker) == 1 {
    in_block = 1
    while ((getline line < block_file) > 0) print line
    close(block_file)
    replaced = 1
    next
}
index($0, end_marker) == 1 {
    in_block = 0
    next
}
!in_block { print }
END {
    if (!replaced) {
        print "warning: auto-generated markers not found in .gitignore, appending" > "/dev/stderr"
        print ""
        while ((getline line < block_file) > 0) print line
        close(block_file)
    }
}
' "$GITIGNORE" > "$TMPFILE"

rm -f "$BLOCK_FILE"

# ── Atomic write: only update if changed ──

if ! diff -q "$GITIGNORE" "$TMPFILE" > /dev/null 2>&1; then
    mv "$TMPFILE" "$GITIGNORE"
    git add "$GITIGNORE"
    echo "pre-commit: updated SKILL.md symlink deny list in claude/skills/.gitignore"
else
    rm -f "$TMPFILE"
fi

exit 0
