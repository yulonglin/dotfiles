#!/usr/bin/env bash
# SessionStart hook: empty rust-skills hook files.
# The plugin's UserPromptSubmit hook matcher is hyper-broad ("error", "async", "API",
# "implement", "explain", "how to", "why" — fires on most prompts and injects a
# ~100-line meta-cognition routing format). Decision: keep the plugin for on-demand
# skill content (/rust-skills:m01-ownership etc.), suppress the auto-routing hook.
# Re-empties on every session start so plugin version bumps and marketplace `git pull`
# don't reintroduce the hook.
PLUGINS_DIR="$HOME/.claude/plugins"
[ -d "$PLUGINS_DIR" ] || exit 0
for f in \
  "$PLUGINS_DIR"/cache/rust-skills/rust-skills/*/hooks/hooks.json \
  "$PLUGINS_DIR"/marketplaces/rust-skills/hooks/hooks.json
do
  [ -f "$f" ] || continue
  if ! grep -q '^{"hooks": {}}$' "$f" 2>/dev/null; then
    printf '{"hooks": {}}\n' > "$f"
  fi
done
exit 0
