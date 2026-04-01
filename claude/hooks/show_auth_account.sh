#!/usr/bin/env bash
# Shows current Claude auth account and usage warning at session start.

auth_json=$(claude auth status 2>&1) || true

account=$(echo "$auth_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    email = d.get('email')
    method = d.get('authMethod', 'unknown')
    source = d.get('apiKeySource', '')
    if email: print(f'{email} ({method})')
    elif source: print(f'{method} via {source}')
    else: print(method)
except: print('unknown')
" 2>/dev/null)

msg="Auth: ${account}"

# Check cached usage for near-limit warning
cache_file="${TMPDIR:-/tmp/claude}/claude-statusline-usage.json"
if [[ -f "$cache_file" ]]; then
  read -r five_pct seven_pct < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(round(d.get('five_hour',{}).get('utilization',0)), round(d.get('seven_day',{}).get('utilization',0)))
" "$cache_file" 2>/dev/null) || true
  if [[ "${five_pct:-0}" -ge 95 ]] 2>/dev/null || [[ "${seven_pct:-0}" -ge 95 ]] 2>/dev/null; then
    msg="${msg}
Near limit (5h:${five_pct}% 7d:${seven_pct}%)! \`claude-switch\` to logout+login — restart alone won't clear cached usage"
  fi
fi

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.stdin.read().strip()}}))" <<< "$msg"
