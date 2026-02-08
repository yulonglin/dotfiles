#!/usr/bin/env bash
# Remove plugin-created symlinks from ~/.claude/skills/ that cause
# every plugin skill to appear twice in the slash command picker.
# Runs async on SessionStart so it doesn't block conversation.
# See: https://github.com/anthropics/claude-code/issues/14549

SKILLS_DIR="${HOME}/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

count=0
while IFS= read -r -d '' link; do
  rm "$link"
  count=$((count + 1))
done < <(find "$SKILLS_DIR" -maxdepth 1 -type l -print0)

exit 0
