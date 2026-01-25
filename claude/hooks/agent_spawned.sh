#!/bin/bash
# Hook: Remind user to save agent IDs when spawned
# Triggers: After agent spawn (when agentId appears in output)
#
# This hook monitors Claude's output for agent spawns and reminds
# the user to save the agent ID for later resuming.

set -e

# This hook is designed to be called with agent output
# Check if output contains agent ID
if [ -z "$1" ]; then
  # No argument provided, this might be called differently
  # Try to read from stdin
  output=$(cat)
else
  output="$1"
fi

# Extract agent ID from output (macOS compatible)
if echo "$output" | grep -q "agentId:"; then
  agent_id=$(echo "$output" | grep -oE 'agentId: [a-zA-Z0-9]+' | sed 's/agentId: //')

  if [ -n "$agent_id" ]; then
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "🤖 Agent Spawned: $agent_id"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "💾 Save this agent for later:"
    echo "   claude-agent-save $agent_id <description>"
    echo ""
    echo "📋 Example:"
    echo "   claude-agent-save $agent_id oauth-experiments"
    echo ""
    echo "📊 Monitor progress: Press Ctrl+T"
    echo "═══════════════════════════════════════════════════"
    echo ""
  fi
fi
