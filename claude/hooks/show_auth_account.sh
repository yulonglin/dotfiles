#!/usr/bin/env bash
# Shows current Claude auth account and usage warning at session start.
#
# The account line is fixed for the life of a session, so it is dropped after a
# compaction. The near-limit warning is NOT fixed - it is recomputed from a
# mutable usage cache and can newly become true mid-session - so it still fires
# on compact. That split is why this hook runs on every source rather than
# being excluded in settings.json: one of its two outputs is live.
#
# An unreadable source, or a missing jq, leaves QUIET false and yields exactly
# the previous behaviour - the fallback is the status quo, never a silent skip.
if [ -t 0 ]; then
    hook_input=""
else
    hook_input=$(cat)
fi
session_source=$(printf '%s' "$hook_input" | jq -r '.source // ""' 2>/dev/null || echo "")
QUIET=false
[ "$session_source" = "compact" ] && QUIET=true

msg=""
if [[ "$QUIET" == false ]]; then
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
fi

# The near-limit usage warning used to be appended here. It has been removed
# deliberately: usage quota is Yulong's to manage, not the assistant's, and
# putting it in the model's context made it act on the number. Observed
# 2026-08-13 -- it read "7d:96%" as its own context filling up, then spent a
# session rushing, delegating work it could have done inline, and repeatedly
# announcing it was about to run out. None of that was true or useful.
#
# The signal is not lost. `claude-tools statusline` still renders it in the
# terminal, where the person who can act on it will see it.

# On compact with no near-limit warning there is nothing live to report, so emit
# no JSON at all rather than an empty additionalContext - that is the whole point
# of the split. The .strip() below also absorbs the leading newline the warning
# carries when it is the only content.
[[ -z "${msg//[[:space:]]/}" ]] && exit 0

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.stdin.read().strip()}}))" <<< "$msg"
