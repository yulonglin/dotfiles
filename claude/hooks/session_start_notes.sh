#!/usr/bin/env bash
# Injects recent experiment log (NOTES.md) at session start.
# Only fires if NOTES.md exists in the current project directory.

PROJECT_NOTES="$(pwd)/NOTES.md"
[ -f "$PROJECT_NOTES" ] || exit 0

RECENT=$(tail -120 "$PROJECT_NOTES")

python3 -c "
import json, sys

content = '''=== RECENT EXPERIMENT LOG (NOTES.md last ~120 lines) ===
$RECENT
=== END LOG ==='''

output = {
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': content
    }
}
print(json.dumps(output))
"
