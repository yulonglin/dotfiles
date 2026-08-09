#!/usr/bin/env bash
# PreToolUse hook (Write|Edit|NotebookEdit): keep ~/vault's structure canonical
# at write time, and keep repo dirs that should be vault symlinks from silently
# regrowing as real directories.
#
# Three checks, all on the target path only — file content and anything below
# the checked level are never inspected (Bash-created drift is
# nudge_vault_lint.sh's job, not this hook's):
#
#   1. vault root: new top-level entries must be in conf/vault-root-allowlist.conf;
#   2. research/<topic>/ top level: entries must be in conf/vault-topic-allowlist.conf;
#   3. repos in conf/vault-symlink-repos.conf: writes under a listed dir are
#      denied while it is a REAL directory (the symlink into the vault was
#      lost) and pass through when it is the intended symlink.
#
# Dot-entries (.git/, .obsidian/, .gitignore, ...) always pass at every level.
# Fail-open on missing jq or conf: wedging every file write is worse than
# letting drift through — the stop-time lint catches what slips past.
# shellcheck disable=SC2088  # "~/" in deny messages is display prose, not a path
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
CONF_DIR="${VAULT_STRUCTURE_CONF_DIR:-$HOOK_DIR/conf}"
VAULT="${VAULT_STRUCTURE_VAULT:-$HOME/vault}"
CODE_DIR="${VAULT_STRUCTURE_CODE_DIR:-$HOME/code}"

path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0

# comment/blank stripping shared by all three conf files; trailing / dropped so
# dir entries compare as bare names
conf_entries() {
  [ -f "$1" ] || return 1
  sed -e 's/[[:space:]]*#.*$//' -e 's|/$||' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- 3. repo symlink guard ----------------------------------------------------
REPO_CONF=$(conf_entries "$CONF_DIR/vault-symlink-repos.conf") || REPO_CONF=""
if [ -n "$REPO_CONF" ]; then
  while IFS=: read -r repo dirs; do
    repo=$(printf '%s' "$repo" | tr -d '[:space:]')
    [ -n "$repo" ] || continue
    for d in $dirs; do
      target="$CODE_DIR/$repo/$d"
      case "$path" in
        "$target"/*)
          if [ -d "$target" ] && [ ! -L "$target" ]; then
            deny "~/code/$repo/$d/ is supposed to be a symlink into ~/vault/tooling/$repo/$d/ but is a real directory again — the symlink was lost, and writing here would fork content from the vault. Write to $VAULT/tooling/$repo/$d/ instead, then restore the symlink."
          fi
          ;;
      esac
    done
  done <<< "$REPO_CONF"
fi

# --- vault checks -------------------------------------------------------------
case "$path" in
  "$VAULT"/*) ;;
  *) exit 0 ;;
esac
rel="${path#"$VAULT"/}"
top="${rel%%/*}"
case "$top" in .*) exit 0 ;; esac

ROOT_LIST=$(conf_entries "$CONF_DIR/vault-root-allowlist.conf") || exit 0
[ -n "$ROOT_LIST" ] || exit 0
ROOT_FLAT=$(printf '%s' "$ROOT_LIST" | tr '\n' ' ')

# 1a. loose file at the vault root
if [ "$rel" = "$top" ]; then
  deny "Loose files are not allowed at the top level of ~/vault (dot-config files excepted). Put it inside one of: $ROOT_FLAT."
fi

# 1b. new top-level directory
printf '%s\n' "$ROOT_LIST" | grep -qxF "$top" || \
  deny "~/vault/$top/ is not an allowed top-level directory (allowed: $ROOT_FLAT). Research goes in research/<topic>/, repo artifacts in tooling/<repo>/, drafts and scratch work in scratch/."

# --- 2. research/<topic>/ top level -------------------------------------------
if [ "$top" = "research" ]; then
  rest="${rel#research/}"
  # research/<file> directly (no topic) is not this hook's call — lint territory
  case "$rest" in */*) ;; *) exit 0 ;; esac
  topic="${rest%%/*}"
  sub="${rest#*/}"
  entry="${sub%%/*}"
  case "$entry" in .*) exit 0 ;; esac
  TOPIC_LIST=$(conf_entries "$CONF_DIR/vault-topic-allowlist.conf") || exit 0
  [ -n "$TOPIC_LIST" ] || exit 0
  printf '%s\n' "$TOPIC_LIST" | grep -qxF "$entry" || \
    deny "research/$topic/$entry is outside the canonical topic layout ($(printf '%s' "$TOPIC_LIST" | tr '\n' ' ')). Loose docs go in docs/, run outputs in runs/<date-slug>/, superseded content in archive/ (with a REASON.txt), images in assets/."
fi

exit 0
