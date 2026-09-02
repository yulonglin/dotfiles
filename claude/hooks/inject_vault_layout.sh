#!/usr/bin/env bash
# SessionStart hook: when the session starts inside ~/vault, print a compact
# layout summary so sessions place files correctly without rediscovering the
# rules. Built from the same conf files block_vault_structure.sh enforces, so
# the summary and the enforcement cannot drift apart.
#
# SessionStart stdout becomes session context — plain echo is the channel.
# Fail-quiet on any error; never blocks.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
VAULT="${VAULT_STRUCTURE_VAULT:-$HOME/vault}"
case "$cwd" in "$VAULT"|"$VAULT"/*) ;; *) exit 0 ;; esac

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
CONF_DIR="${VAULT_STRUCTURE_CONF_DIR:-$HOOK_DIR/conf}"

conf_entries() {
  [ -f "$1" ] || return 1
  sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

roots=$(conf_entries "$CONF_DIR/vault-root-allowlist.conf" | sed 's|$|/|' | tr '\n' ' ') || exit 0
topic=$(conf_entries "$CONF_DIR/vault-topic-allowlist.conf" | tr '\n' ' ') || exit 0
[ -n "$roots" ] && [ -n "$topic" ] || exit 0

cat <<EOF
=== VAULT LAYOUT (enforced by block_vault_structure.sh) ===
Top-level dirs: ${roots}(+ dot-config entries). New top-level dirs and loose root files are denied at write time.
research/<topic>/ top level: ${topic}— nothing else. Loose docs → docs/, run outputs → runs/<YYYY-MM-DD-slug>/, superseded → archive/ (with REASON.txt), images → assets/.
tooling/<repo>/ mirrors a code repo's non-code artifacts (specs/, plans/, ...); e.g. tooling/dotfiles/ backs the specs/ and plans/ symlinks in ~/code/dotfiles.
Never delete: superseded content moves to the owning archive/ with a REASON.txt.
Drift is nudged at stop time (nudge_vault_lint.sh). Allowlists: ~/.claude/hooks/conf/vault-*.conf.
EOF
exit 0
