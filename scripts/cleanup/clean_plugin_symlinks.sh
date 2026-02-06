#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Clean Plugin Symlinks from Claude Code Skills Directory
# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code's plugin system creates symlinks in ~/.claude/skills/ pointing to
# plugins/cache/ and plugins/marketplaces/. These cause every plugin skill to
# appear twice in the slash command picker: once as "(user)" from the symlink,
# once as "(plugin-name)" from the plugin registry.
#
# This script removes those symlinks. Plugin skills are still discovered via
# the plugin registry (installed_plugins.json), so nothing is lost.
#
# Safe: only removes symlinks, never real directories (user-authored skills).
#
# Usage:
#   bash scripts/cleanup/clean_plugin_symlinks.sh            # remove symlinks
#   bash scripts/cleanup/clean_plugin_symlinks.sh --dry-run  # preview only
#
# See: https://github.com/anthropics/claude-code/issues/14549
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--dry-run]"
      echo "Remove plugin-created symlinks from ~/.claude/skills/"
      exit 0
      ;;
  esac
done

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "Skills directory not found: $SKILLS_DIR"
  exit 0
fi

count=0
while IFS= read -r -d '' link; do
  name=$(basename "$link")
  target=$(readlink "$link" 2>/dev/null || echo "broken")

  if $DRY_RUN; then
    echo "Would remove: $name -> $target"
  else
    rm "$link"
  fi
  ((count++))
done < <(find "$SKILLS_DIR" -maxdepth 1 -type l -print0)

if [[ $count -eq 0 ]]; then
  echo "No plugin symlinks found in $SKILLS_DIR"
elif $DRY_RUN; then
  echo "Would remove $count symlink(s). Run without --dry-run to execute."
else
  echo "Removed $count plugin symlink(s) from $SKILLS_DIR"
fi
