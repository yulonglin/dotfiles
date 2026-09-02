#!/usr/bin/env bash
# Stop hook: cheap structural lint over ~/vault. Soft nudge only — emits a
# systemMessage and always exits 0; never blocks the stop. Only fires for
# sessions whose cwd is inside the vault.
#
# Bounded by construction: two shallow directory scans plus ONE find pass with
# .obsidian/.git/archive pruned, capped by `timeout 1` where timeout exists.
# Well under a second on the real vault.
#
# Four signals, same conf files as block_vault_structure.sh:
#   1. top-level entries outside conf/vault-root-allowlist.conf;
#   2. research/<topic>/ entries outside conf/vault-topic-allowlist.conf;
#   3. bloat and sync artifacts: node_modules/, __pycache__/, .cache/,
#      *.log over 1MB, Untitled*, *Conflicted copy* (outside .obsidian/ and
#      archive/);
#   4. conf/vault-symlink-repos.conf dirs that are real directories again.
# shellcheck disable=SC2088  # "~/" in finding text is display prose, not a path
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
VAULT="${VAULT_STRUCTURE_VAULT:-$HOME/vault}"
case "$cwd" in "$VAULT"|"$VAULT"/*) ;; *) exit 0 ;; esac
[ -d "$VAULT" ] || exit 0

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
CONF_DIR="${VAULT_STRUCTURE_CONF_DIR:-$HOOK_DIR/conf}"
CODE_DIR="${VAULT_STRUCTURE_CODE_DIR:-$HOME/code}"

conf_entries() {
  [ -f "$1" ] || return 1
  sed -e 's/[[:space:]]*#.*$//' -e 's|/$||' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

FINDINGS=()

# 1. vault-root drift (globs skip dot-entries by default, which is the policy)
ROOT_LIST=$(conf_entries "$CONF_DIR/vault-root-allowlist.conf") || ROOT_LIST=""
if [ -n "$ROOT_LIST" ]; then
  for p in "$VAULT"/*; do
    [ -e "$p" ] || continue
    name=$(basename "$p")
    if [ -d "$p" ]; then
      printf '%s\n' "$ROOT_LIST" | grep -qxF "$name" || FINDINGS+=("unexpected top-level dir: $name/")
    else
      FINDINGS+=("loose top-level file: $name")
    fi
  done
fi

# 2. research/<topic>/ drift
TOPIC_LIST=$(conf_entries "$CONF_DIR/vault-topic-allowlist.conf") || TOPIC_LIST=""
if [ -n "$TOPIC_LIST" ] && [ -d "$VAULT/research" ]; then
  for t in "$VAULT"/research/*/; do
    [ -d "$t" ] || continue
    tname=$(basename "$t")
    for e in "$t"*; do
      [ -e "$e" ] || continue
      ename=$(basename "$e")
      printf '%s\n' "$TOPIC_LIST" | grep -qxF "$ename" || \
        FINDINGS+=("research/$tname/$ename outside canonical topic layout")
    done
  done
fi

# 3. bloat + sync artifacts (one pruned find pass; bloat dirs print then prune)
FIND_CMD=(find "$VAULT"
  \( -name .obsidian -o -name .git -o -name archive \) -prune -o
  -type d \( -name node_modules -o -name __pycache__ -o -name .cache \) -print -prune -o
  \( \( -type f -name '*.log' -size +1M \) -o -name 'Untitled*' -o -name '*Conflicted copy*' \) -print)
command -v timeout >/dev/null 2>&1 && FIND_CMD=(timeout 1 "${FIND_CMD[@]}")
BLOAT=$({ "${FIND_CMD[@]}" 2>/dev/null || true; } | head -20)
if [ -n "$BLOAT" ]; then
  while IFS= read -r b; do
    FINDINGS+=("bloat/sync artifact: ${b#"$VAULT"/}")
  done <<< "$BLOAT"
fi

# 4. repo symlink drift
REPO_CONF=$(conf_entries "$CONF_DIR/vault-symlink-repos.conf") || REPO_CONF=""
if [ -n "$REPO_CONF" ]; then
  while IFS=: read -r repo dirs; do
    repo=$(printf '%s' "$repo" | tr -d '[:space:]')
    [ -n "$repo" ] || continue
    for d in $dirs; do
      target="$CODE_DIR/$repo/$d"
      if [ -d "$target" ] && [ ! -L "$target" ]; then
        FINDINGS+=("~/code/$repo/$d/ is a real directory again — should be a symlink into ~/vault/tooling/$repo/$d/")
      fi
    done
  done <<< "$REPO_CONF"
fi

[ ${#FINDINGS[@]} -eq 0 ] && exit 0

MSG="Vault structure lint — ${#FINDINGS[@]} finding(s):"
n=0
for f in "${FINDINGS[@]}"; do
  n=$((n + 1))
  [ "$n" -gt 20 ] && { MSG+=$'\n'"… and $((${#FINDINGS[@]} - 20)) more"; break; }
  MSG+=$'\n'"- $f"
done
MSG+=$'\n'"Canonical homes: docs → docs/, runs → runs/, superseded → archive/ (REASON.txt), see ~/.claude/hooks/conf/vault-*.conf."
jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0
