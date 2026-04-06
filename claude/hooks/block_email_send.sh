#!/usr/bin/env bash
# Global PreToolUse hook: BLOCKS all email sending.
# Emails are irreversible — only drafts are allowed, never sends.
#
# Blocks:
#   - gws gmail +send (without --draft)
#   - gws gmail users drafts send
#   - gws gmail users messages send
#   - gws gmail +reply/+reply-all/+forward (without --draft)
#   - Any of the above inside bash -c / sh -c wrappers
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

# Check if gws gmail appears anywhere in the command (catches bash -c wrappers too)
# If no gws gmail, this hook has nothing to check — allow
printf '%s' "$CMD" | grep -q 'gws.*gmail' || exit 0

# Allow --help ONLY if it's the last argument (not embedded in body text)
# Pattern: command ends with --help, possibly followed by whitespace
printf '%s' "$CMD" | grep -qE '\-\-help\s*$' && exit 0

# Allow --dry-run: gws treats it as a real flag regardless of position.
# Unlike --help, --dry-run is unlikely to appear in body text organically.
printf '%s' "$CMD" | grep -qE '(^|\s)--dry-run(\s|$)' && exit 0

# Block: gws gmail users drafts send (sends an existing draft)
if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*users.*drafts.*send'; then
    printf 'BLOCKED: Cannot send Gmail drafts programmatically.\n' >&2
    printf 'Emails are irreversible. Review and send manually from Spark/Gmail.\n' >&2
    exit 2
fi

# Block: gws gmail users messages send (raw API send)
if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*users.*messages.*send'; then
    printf 'BLOCKED: Cannot send emails via raw Gmail API.\n' >&2
    printf 'Emails are irreversible. Review and send manually from Spark/Gmail.\n' >&2
    exit 2
fi

# Block: gws gmail +send WITHOUT --draft flag
if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*\+send' && ! printf '%s' "$CMD" | grep -qE '(^|\s)--draft(\s|$)'; then
    printf 'BLOCKED: Cannot send emails directly.\n' >&2
    printf 'Use --draft flag to create a draft instead. Send manually from Spark/Gmail.\n' >&2
    exit 2
fi

# Block: gws gmail +reply, +reply-all, +forward (also sends)
if printf '%s' "$CMD" | grep -qE 'gws.*gmail.*\+(reply|reply-all|forward)' && ! printf '%s' "$CMD" | grep -qE '(^|\s)--draft(\s|$)'; then
    printf 'BLOCKED: Cannot send email replies/forwards programmatically.\n' >&2
    printf 'Use --draft flag to create a draft instead. Send manually from Spark/Gmail.\n' >&2
    exit 2
fi

exit 0
