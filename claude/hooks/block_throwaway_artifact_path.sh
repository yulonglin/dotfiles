#!/usr/bin/env bash
# Global PreToolUse hook for the Artifact tool: BLOCKS publishing a page whose
# source sits in a throwaway path.
#
# A published Artifact lives on someone else's server, under an org you may
# leave, so the local source is the durable copy — see artifacts/README.md. A
# page built in tmp/ publishes perfectly and looks finished; the loss shows up
# only when the worktree is deleted or the account changes, long after anyone
# would connect the two. ARTIFACTS.md carries eight rows that cannot be rebuilt
# for exactly this reason.
#
# Blocked: paths under a gitignored directory, $TMPDIR, /tmp, or a path
# containing /tmp/ or /scratch/. Allowed: anything git tracks or would track.
#
# Gated: only `action` absent or "publish", and only when a `file_path` is
# present. Every other action (read, list, comments, reply, watch,
# upload_asset, ...) passes through untouched, as does a publish by `url`
# alone.
#
# Feature flag: guards.artifact-source-path (features.conf; missing = on), read
# via `hook_feature.py enabled`. NOT via `hook_feature.sh run`: that launcher is
# fail-open by design, which would turn this block into a no-op.
#
# Reads the hook JSON from stdin. Exit 0 = allow, exit 2 = block.

set -uo pipefail

INPUT=$(cat)
HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -x "$HOOK_DIR/hook_feature.py" ]]; then
  "$HOOK_DIR/hook_feature.py" enabled guards.artifact-source-path >/dev/null 2>&1 || exit 0
fi

read_json() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("action") or "publish")
print(ti.get("file_path") or "")
' <<<"$INPUT"
}

mapfile -t FIELDS < <(read_json)
ACTION="${FIELDS[0]:-publish}"
FILE_PATH="${FIELDS[1]:-}"

[[ "$ACTION" == "publish" ]] || exit 0
[[ -n "$FILE_PATH" ]] || exit 0

ABS="$FILE_PATH"
[[ "$ABS" = /* ]] || ABS="$PWD/$FILE_PATH"

deny() {
  cat >&2 <<EOF
BLOCKED: the Artifact source is in a throwaway path, so publishing it would
leave nothing that can rebuild the page.

  $FILE_PATH
  reason: $1

A published page can become unreachable without anything local changing — an
account switch, an org's External-sharing toggle, a plan change. The committed
source is the durable copy.

Move the source under artifacts/<slug>/ and commit it, then publish. Build
output may live in artifacts/<slug>/build/, which is gitignored. See
artifacts/README.md, and record the row in ARTIFACTS.md.
EOF
  exit 2
}

case "$ABS" in
  /tmp/*|*/tmp/*|*/scratch/*) deny "under a temporary directory" ;;
esac
if [[ -n "${TMPDIR:-}" && "$ABS" == "${TMPDIR%/}/"* ]]; then
  deny "under \$TMPDIR"
fi

# Gitignored is the general case: it catches tmp/, out/, build/ and anything
# else the repo has already declared disposable. Outside a repo, git errors and
# we fall through to allow rather than block work in a non-repo directory.
DIR=$(dirname "$ABS")
if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$DIR" check-ignore -q "$ABS" 2>/dev/null; then
    deny "gitignored, so it is not version-controlled"
  fi
fi

exit 0
