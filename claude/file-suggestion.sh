#!/bin/bash
# File suggestion for Claude Code @ picker
# Receives {"query": "..."} on stdin, returns filtered file paths
query=$(jq -r '.query // empty')
if [ -z "$query" ]; then
  fd --type f --hidden --exclude .git | head -50
else
  fd --type f --hidden --exclude .git | grep -iF "$query" | head -50
fi
