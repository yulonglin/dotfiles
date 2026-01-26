#!/bin/bash
# Weekly cleanup of old Claude Code tmpdir files
# Deletes files older than 7 days from ~/tmp/claude

set -e

CLAUDE_TMPDIR="${CLAUDE_CODE_TMPDIR:-$HOME/tmp/claude}"
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Normalize DRY_RUN
case "$DRY_RUN" in
    [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]|[Yy]) DRY_RUN=true ;;
    *) DRY_RUN=false ;;
esac

if [[ ! -d "$CLAUDE_TMPDIR" ]]; then
    echo "Directory does not exist: $CLAUDE_TMPDIR"
    exit 0
fi

echo "Cleaning files older than $RETENTION_DAYS days from: $CLAUDE_TMPDIR"

# Find and delete old files
count=0
while IFS= read -r -d '' file; do
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would delete: $file"
    else
        rm -rf "$file"
        echo "  Deleted: $file"
    fi
    ((count++)) || true
done < <(find "$CLAUDE_TMPDIR" -mindepth 1 -mtime +$RETENTION_DAYS -print0 2>/dev/null)

echo "Cleaned $count items"
