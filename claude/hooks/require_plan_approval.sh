#!/usr/bin/env bash
# PreToolUse hook for EnterPlanMode: require explicit user approval before planning.
# Outputs a systemMessage reminding Claude to confirm with the user.
# Gate: set SKIP_PLAN_APPROVAL=1 to bypass.

[[ "${SKIP_PLAN_APPROVAL:-}" == "1" ]] && exit 0

cat <<'JSON'
{"systemMessage": "\u001b[1;33m⚠ Plan approval required:\u001b[0m Ask the user before entering plan mode. State what you intend to plan and why, then wait for approval."}
JSON
