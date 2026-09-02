#!/usr/bin/env bash
# shellcheck shell=bash
# Guards claude/hooks/block_throwaway_artifact_path.sh.
#
# The hook exists because a page built in tmp/ publishes perfectly and looks
# finished; the loss is invisible until the worktree is deleted or the org
# changes. So both halves matter: it must block a throwaway path, and it must
# not block an ordinary committed one, or it becomes a thing people route
# around.

set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude/hooks/block_throwaway_artifact_path.sh"
PASS=0
FAIL=0

run() { # run <json> -> prints exit code
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 — expected exit $2, got $3"
  fi
}

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# No mktemp: $TMPDIR is read-only under the sandbox, and a failed mktemp would
# leave an empty path that makes a test pass for the wrong reason.

# --- blocks ---
check "literal /tmp path" 2 \
  "$(run '{"tool_input":{"file_path":"/tmp/page.html"}}')"
check "repo tmp/ dir (gitignored)" 2 \
  "$(run "{\"tool_input\":{\"file_path\":\"$REPO/tmp/page.html\"}}")"
check "scratch dir" 2 \
  "$(run '{"tool_input":{"file_path":"/home/u/scratch/page.html"}}')"
check "explicit publish action still blocked" 2 \
  "$(run '{"tool_input":{"action":"publish","file_path":"/tmp/x.html"}}')"

# --- allows ---
check "committed artifacts/ path" 0 \
  "$(run "{\"tool_input\":{\"file_path\":\"$REPO/artifacts/context-ledger/page.html\"}}")"
check "non-publish action with a tmp path" 0 \
  "$(run '{"tool_input":{"action":"read","file_path":"/tmp/x.html"}}')"
check "publish by url, no file_path" 0 \
  "$(run '{"tool_input":{"action":"publish","url":"https://claude.ai/code/artifact/abc"}}')"
check "list action" 0 \
  "$(run '{"tool_input":{"action":"list"}}')"
check "path outside any repo is not blocked" 0 \
  "$(run '{"tool_input":{"file_path":"/nonexistent-root/elsewhere/page.html"}}')"
check "malformed json does not block work" 0 \
  "$(run 'not json at all')"

echo "passed $PASS, failed $FAIL"
[[ $FAIL -eq 0 ]]
