#!/usr/bin/env bash
# Global PreToolUse hook for the Artifact tool: BLOCKS publishing an HTML page
# that lacks the annotation layer.
#
# `rules/artifact-first-replies.md`: a page Yulong reviews must be annotatable
# (select text, attach a note, export as Markdown). md2review builds the layer
# in; a hand-built page gets it from `annotate-html <file>`. A page published
# without it cannot be argued with, so the publish is refused until it has one.
#
# Gated: only `action` absent or "publish", and only a `file_path` ending in
# .html. Markdown publishes and every other action (read, list, comments,
# reply, watch, upload_asset, ...) pass through untouched.
#
# Feature flag: guards.annotation-layer (features.conf; missing = on), read
# via `hook_feature.py enabled`. NOT via `hook_feature.sh run`: that launcher
# is fail-open by design (any non-zero exit becomes 0), which would turn this
# block into a no-op. Registered directly in settings.json:
#   bash $HOME/.claude/hooks/block_unannotated_artifact.sh
#
# The check itself is `annotate-html --check`; when that CLI cannot be found
# the hook falls back to grepping for the layer marker, so a missing PATH
# entry never turns into a silent allow.
#
# Reads the hook JSON from stdin. Exit 0 = allow, exit 2 = block.

set -uo pipefail

INPUT=$(cat)

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled guards.annotation-layer; then
    exit 0
fi

# One line: "<verdict>\t<file_path>", verdict in {skip, check}.
DECISION=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        raise ValueError
    name = d.get("tool_name")
    if name is not None and name != "Artifact":
        print("skip\t"); sys.exit(0)
    inp = d.get("tool_input") or {}
    if not isinstance(inp, dict):
        inp = {}
    action = inp.get("action") or "publish"
    path = inp.get("file_path") or ""
    if action != "publish" or not isinstance(path, str) or not path.lower().endswith(".html"):
        print("skip\t"); sys.exit(0)
    print("check\t" + path)
except Exception:
    print("skip\t")
' 2>/dev/null)

VERDICT="${DECISION%%$'\t'*}"
FILE="${DECISION#*$'\t'}"
[ "$VERDICT" = "check" ] && [ -n "$FILE" ] || exit 0

# A path that does not exist yet fails at publish time on its own; not ours.
[ -f "$FILE" ] || exit 0

CHECKER=""
if command -v annotate-html >/dev/null 2>&1; then
    CHECKER=$(command -v annotate-html)
elif [ -x "$HOOK_DIR/../../custom_bins/annotate-html" ]; then
    CHECKER="$HOOK_DIR/../../custom_bins/annotate-html"
elif [ -x "$HOME/code/dotfiles/custom_bins/annotate-html" ]; then
    CHECKER="$HOME/code/dotfiles/custom_bins/annotate-html"
fi

if [ -n "$CHECKER" ]; then
    python3 "$CHECKER" "$FILE" --check >/dev/null 2>&1
    RC=$?
    if [ "$RC" -eq 0 ]; then exit 0; fi
    if [ "$RC" -ne 2 ]; then
        # Checker errored (unreadable file, etc.): fall through to the grep.
        CHECKER=""
    fi
fi

if [ -z "$CHECKER" ]; then
    if grep -qE '<!--[[:space:]]*annotation-layer([[:space:]]+v[0-9]+)?[[:space:]]*-->|data-annotation-layer=' "$FILE"; then
        exit 0
    fi
fi

printf 'BLOCKED: Artifact page lacks the annotation layer — run: annotate-html %s\n' "$FILE" >&2
printf 'Reviewable pages must be annotatable (rules/artifact-first-replies.md). Markdown sources go through md2review instead.\n' >&2
exit 2
