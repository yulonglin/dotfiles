#!/usr/bin/env bash
# Global PreToolUse hook for the Artifact tool: BLOCKS publishing a page whose
# meta.yml does not name an allowed author model for the prose.
#
# Yulong (2026-09-08): Opus 4.8, Opus 5 and Fable write prose he finds
# impenetrable, so pages he reads are drafted by the `writer-priority` model
# in config/model-router.toml; the procedure is the `write-prose` skill. The
# hook cannot see which model wrote a file, so it reads the self-reported
# `author_model` field in the artifact's meta.yml and refuses when it is
# absent, empty, or names a banned Claude model. Honest provenance is the
# whole mechanism; the teeth are that a Claude-drafted page cannot be
# published by leaving the field out.
#
# meta.yml is looked up in the directory of `file_path`, or in its parent when
# the file sits in a `build/` directory (artifacts/README.md layout).
#
# Banned (case-insensitive, any separator): opus 4.8, opus 5, fable, mythos.
# Allowed: anything else that names a model — gpt-5.6-sol, gpt-6-astra,
# kimi-k3, claude-opus-4-6, ... — and the one sentinel `generated`, meaning a
# script emitted the page from structured data and no model drafted prose
# (the hosted index under artifacts/index/). A value that is only "claude",
# "opus", "inherit", "unknown", "tbd" or "pending" names no model and is
# refused.
#
# Gated: only `action` absent or "publish", and only when a `file_path` is
# present. Every other action (read, list, comments, reply, watch,
# upload_asset, ...) passes through untouched, as does a publish by `url`
# alone.
#
# Feature flag: guards.artifact-author (features.conf; missing = on), read via
# `hook_feature.py enabled`. NOT via `hook_feature.sh run`: that launcher is
# fail-open by design, which would turn this block into a no-op.
#
# Reads the hook JSON from stdin. Exit 0 = allow, exit 2 = block.

set -uo pipefail

INPUT=$(cat)
HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -x "$HOOK_DIR/hook_feature.py" ]]; then
  "$HOOK_DIR/hook_feature.py" enabled guards.artifact-author >/dev/null 2>&1 || exit 0
fi

read_json() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        raise ValueError
except Exception:
    sys.exit(0)
name = d.get("tool_name")
if name is not None and name != "Artifact":
    sys.exit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    ti = {}
print(ti.get("action") or "publish")
fp = ti.get("file_path") or ""
print(fp if isinstance(fp, str) else "")
' <<<"$INPUT"
}

mapfile -t FIELDS < <(read_json)
ACTION="${FIELDS[0]:-}"
FILE_PATH="${FIELDS[1]:-}"

[[ "$ACTION" == "publish" ]] || exit 0
[[ -n "$FILE_PATH" ]] || exit 0

ABS="$FILE_PATH"
[[ "$ABS" = /* ]] || ABS="$PWD/$FILE_PATH"

DIR=$(dirname "$ABS")
[[ "$(basename "$DIR")" == "build" ]] && DIR=$(dirname "$DIR")
META="$DIR/meta.yml"

deny() {
  cat >&2 <<EOF
BLOCKED: this page has no allowed author_model, so it reads as drafted by a
Claude model.

  page:     $FILE_PATH
  meta.yml: $META
  reason:   $1

Opus 4.8, Opus 5 and Fable do not write pages Yulong reads (2026-09-08). The
prose is dispatched to the writer-priority model in config/model-router.toml
from a skeleton — the procedure is the write-prose skill — and meta.yml then
records who wrote it:

  author_model: gpt-5.6-sol

Do not set the field to satisfy the hook: the fix is the dispatch, and the
field is the record of it. The fallback order on quota or cooldown is the
writer-priority order in that config. A page a script emits from structured
data with no drafted prose (the hosted index) carries author_model: generated.
EOF
  exit 2
}

[[ -f "$META" ]] || deny "no meta.yml beside the page (artifacts/README.md layout)"

# First author_model line; strip quotes and a trailing comment.
VALUE=$(sed -nE 's/^[[:space:]]*author_model[[:space:]]*:[[:space:]]*//p' "$META" | head -1 \
  | sed -E 's/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]+$//')

[[ -n "$VALUE" ]] || deny "meta.yml has no author_model (or it is empty)"

LOWER=$(printf '%s' "$VALUE" | tr '[:upper:]' '[:lower:]')

# The one non-model value: a script emitted the page from structured data.
[[ "$LOWER" == "generated" ]] && exit 0

case "$LOWER" in
  claude|opus|anthropic|inherit|unknown|tbd|pending|none|n/a)
    deny "author_model \"$VALUE\" names no specific model" ;;
esac

if printf '%s' "$LOWER" | grep -qE 'opus[-_ .]?4[-_.]?8|opus[-_ .]?5|fable|mythos'; then
  deny "author_model \"$VALUE\" is a banned writer (Opus 4.8, Opus 5, Fable, Mythos)"
fi

exit 0
