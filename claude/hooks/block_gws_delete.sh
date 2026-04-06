#!/usr/bin/env bash
# Global PreToolUse hook: BLOCKS permanent deletions via gws CLI.
# Deletions are irreversible across Google Workspace. Archiving/trashing is fine.
#
# Blocks across ALL gws services:
#   - gmail:    users messages delete, batchDelete, threads delete
#   - drive:    files delete, files emptyTrash, comments delete, drives delete,
#               permissions delete, replies delete, revisions delete, teamdrives delete
#   - calendar: acl delete, calendarList delete, calendars delete, calendars clear,
#               events delete
#   - tasks:    tasklists delete, tasks delete
#   - docs/sheets/slides/chat: any delete subcommand
#
# ALLOWS:
#   - trash/untrash (gmail, drive)
#   - modify/archive (gmail labels)
#   - --dry-run (any service)
#   - --help (at end of command)
#
# Reads Bash tool_input JSON from stdin, checks the command field.
# Exit 0 = allow, Exit 2 = block.

set -euo pipefail

INPUT=$(cat)

# Extract the command from tool_input
CMD=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d)
    print(inp.get('command', ''))
except:
    print('')
" 2>/dev/null) || exit 0

# No command = not a Bash tool call, allow
[ -z "$CMD" ] && exit 0

# Check if gws appears anywhere in the command (catches bash -c wrappers too)
printf '%s' "$CMD" | grep -q 'gws' || exit 0

# Allow --help at end of command
printf '%s' "$CMD" | grep -qE '\-\-help\s*$' && exit 0

# Allow --dry-run
printf '%s' "$CMD" | grep -qE '(^|\s)--dry-run(\s|$)' && exit 0

# --- Gmail permanent deletions ---

if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*users.*(messages|threads)\s+delete'; then
    printf 'BLOCKED: Permanent Gmail deletion not allowed.\n' >&2
    printf 'Use "trash" instead of "delete" to move to trash.\n' >&2
    exit 2
fi

if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*users.*messages\s+batchDelete'; then
    printf 'BLOCKED: Permanent Gmail batch deletion not allowed.\n' >&2
    printf 'Use "batchModify" to move messages to trash instead.\n' >&2
    exit 2
fi

# --- Drive permanent deletions ---

if printf '%s' "$CMD" | grep -qE 'gws.*drive.*files\s+(delete|emptyTrash)'; then
    printf 'BLOCKED: Permanent Drive file deletion not allowed.\n' >&2
    printf 'Use Drive UI to trash files, or "files update" with trashed=true.\n' >&2
    exit 2
fi

if printf '%s' "$CMD" | grep -qE 'gws.*drive.*(comments|drives|permissions|replies|revisions|teamdrives)\s+delete'; then
    printf 'BLOCKED: Permanent Drive resource deletion not allowed.\n' >&2
    printf 'Deletions are irreversible. Manage via Drive UI instead.\n' >&2
    exit 2
fi

# --- Calendar deletions ---

if printf '%s' "$CMD" | grep -qE 'gws.*calendar.*(acl|calendarList|calendars|events)\s+delete'; then
    printf 'BLOCKED: Calendar deletion not allowed.\n' >&2
    printf 'Manage calendar deletions via Calendar UI instead.\n' >&2
    exit 2
fi

if printf '%s' "$CMD" | grep -qE 'gws.*calendar.*calendars\s+clear'; then
    printf 'BLOCKED: Calendar clear (delete all events) not allowed.\n' >&2
    printf 'This would delete ALL events. Manage via Calendar UI instead.\n' >&2
    exit 2
fi

# --- Tasks deletions ---

if printf '%s' "$CMD" | grep -qE 'gws.*tasks.*(tasklists|tasks)\s+delete'; then
    printf 'BLOCKED: Task deletion not allowed.\n' >&2
    printf 'Manage task deletions via Tasks UI instead.\n' >&2
    exit 2
fi

# --- Catch-all for any other gws service + delete ---
# Covers docs, sheets, slides, chat, and future services

if printf '%s' "$CMD" | grep -qE 'gws\s+\S+.*\bdelete\b'; then
    printf 'BLOCKED: Deletion via gws CLI not allowed.\n' >&2
    printf 'Deletions are irreversible. Manage via the Google Workspace UI.\n' >&2
    exit 2
fi

exit 0
