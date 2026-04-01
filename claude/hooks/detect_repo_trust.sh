#!/usr/bin/env bash
# SessionStart hook: cache repo trust level for auto_classify.py
# Writes JSON to ~/.cache/claude/repo-trust.json so auto_classify
# doesn't need to fork git on every PermissionRequest.

set -euo pipefail

TRUSTED_OWNERS="yulonglin anthropics alignment-research"
PERSONAL_USERS="yulonglin"
CACHE_DIR="$HOME/.cache/claude"
CACHE_FILE="$CACHE_DIR/repo-trust.json"
CWD="$(pwd)"

mkdir -p "$CACHE_DIR"

# Get remote URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

# Extract owner from github.com URLs
OWNER=""
if [[ "$REMOTE_URL" == *"github.com:"* ]]; then
  OWNER=$(echo "$REMOTE_URL" | sed 's/.*github.com://' | cut -d/ -f1)
elif [[ "$REMOTE_URL" == *"github.com/"* ]]; then
  OWNER=$(echo "$REMOTE_URL" | sed 's/.*github.com\///' | cut -d/ -f1)
fi

TRUSTED=false
PERSONAL=false
if [[ -n "$OWNER" ]]; then
  OWNER_LOWER=$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')
  for owner in $TRUSTED_OWNERS; do
    if [[ "$OWNER_LOWER" == "$owner" ]]; then
      TRUSTED=true
      break
    fi
  done
  for user in $PERSONAL_USERS; do
    if [[ "$OWNER_LOWER" == "$user" ]]; then
      PERSONAL=true
      break
    fi
  done
fi

cat > "$CACHE_FILE" <<ENDJSON
{"cwd": "$CWD", "remote_url": "$REMOTE_URL", "owner": "$OWNER", "trusted": $TRUSTED, "personal": $PERSONAL}
ENDJSON
