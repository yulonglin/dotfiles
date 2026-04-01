#!/usr/bin/env bash
# Shows current Claude auth account and usage warning at session start.

auth_json=$(claude auth status 2>&1) || true

msg=$(echo "$auth_json" | python3 -c "
import json, sys, os, subprocess

# Parse auth info
try:
    d = json.load(sys.stdin)
    email = d.get('email')
    method = d.get('authMethod', 'unknown')
    source = d.get('apiKeySource', '')
    if email:
        auth = f'{email} ({method})'
    elif source:
        auth = f'{method} via {source}'
    else:
        auth = method
except:
    auth = 'unknown'

parts = [f'Auth: {auth}']

# Check usage — warn if near limit
try:
    token = subprocess.check_output(
        ['claude', 'auth', 'token'], stderr=subprocess.DEVNULL, text=True
    ).strip()
    if token:
        import urllib.request
        req = urllib.request.Request(
            'https://api.anthropic.com/api/oauth/usage',
            headers={'Authorization': f'Bearer {token}'}
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            usage = json.loads(resp.read())
        five_pct = round(usage.get('five_hour', {}).get('utilization', 0))
        seven_pct = round(usage.get('seven_day', {}).get('utilization', 0))
        if five_pct >= 95 or seven_pct >= 95:
            parts.append(f'Near limit (5h:{five_pct}% 7d:{seven_pct}%)! \`claude-switch\` to logout+login — restart alone won\\'t clear cached usage')
except:
    pass

print('\\n'.join(parts))
" 2>/dev/null)

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
