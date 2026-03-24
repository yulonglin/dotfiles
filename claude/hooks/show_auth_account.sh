#!/usr/bin/env bash
# Shows current Claude auth account at session start.

auth_json=$(claude auth status 2>&1) || true

account=$(echo "$auth_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    email = d.get('email')
    method = d.get('authMethod', 'unknown')
    source = d.get('apiKeySource', '')
    if email:
        print(f'{email} ({method})')
    elif source:
        print(f'{method} via {source}')
    else:
        print(method)
except:
    print('unknown')
" 2>/dev/null)

msg="Auth: ${account}"

python3 -c "
import json
output = {
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': '''$msg'''
    }
}
print(json.dumps(output))
"
