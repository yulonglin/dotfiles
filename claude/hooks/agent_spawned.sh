#!/usr/bin/env bash
# PostToolUse(Task) hook: auto-save agent IDs after agent completes.
#
# Reads the PostToolUse JSON payload from stdin. Extracts the agentId and
# description, then saves to ~/.claude/saved_agents/ automatically.
# No user action needed — agents are saved for later resumption.

set -euo pipefail

input=$(cat)

# Extract agent description from tool_input
description=$(echo "$input" | jq -r '.tool_input.description // "unnamed"' | tr -d '\n' | head -c 80)
tool_result=$(echo "$input" | jq -r '.tool_result // ""')

# Try to extract agentId from tool_result
agent_id=""
if [[ "$tool_result" == *"agentId:"* ]]; then
  agent_id=$(echo "$tool_result" | grep -oE 'agentId: [a-zA-Z0-9_-]+' | head -1 | sed 's/agentId: //')
fi

# Also check tool_input for an explicit agent/session ID field
if [[ -z "$agent_id" ]]; then
  agent_id=$(echo "$input" | jq -r '.tool_input.agent_id // .tool_input.session_id // ""')
fi

# No agent ID found — nothing to save
[[ -z "$agent_id" ]] && exit 0

# Sanitize description for filename (lowercase, spaces/special -> dashes)
safe_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
[[ -z "$safe_desc" ]] && safe_desc="agent"

# Auto-save (same logic as claude-agent-save)
AGENT_DIR="$HOME/.claude/saved_agents"
mkdir -p "$AGENT_DIR"

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
NAME="${TIMESTAMP}_UTC_${safe_desc}"

echo "$agent_id" > "$AGENT_DIR/$NAME"
echo "$agent_id" > "$AGENT_DIR/last"

exit 0
