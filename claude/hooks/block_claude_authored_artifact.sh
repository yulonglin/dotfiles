#!/usr/bin/env bash
# Global PreToolUse hook for the Artifact tool: BLOCKS publishing a page whose
# meta.yml does not name an allowed author model for the prose.
#
# Yulong (2026-09-08): Opus 4.8, Opus 5 and Fable write prose he finds
# impenetrable, so pages he reads are drafted by the `writer-priority` model
# in config/model-router.toml; the procedure is the `write-prose` skill.
# Opus 5.5 is allowed (2026-10-12) and ranked after Sol and Astra there. The
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
# Opus 5 means 5 alone or 5 plus a date (claude-opus-5-20260601); a second
# `5` after a separator is Opus 5.5 and passes. Allowed: anything else that
# names a model — gpt-5.6-sol, gpt-6-astra, kimi-k3, claude-opus-5-5,
# claude-opus-4-6, ... — and two sentinels:
#   generated  a script emitted the page from structured data and no model
#              drafted prose (the hosted index under artifacts/index/).
#   legacy     the page predates this guard. Accepted only when the earliest
#              commit adding a file under the page's directory has an AUTHOR
#              date (%as, which survives rebase) before CUTOVER below. No git,
#              not a repo, or an untracked directory means not legacy, so a
#              new page cannot claim it. This lets an old page be republished
#              for a typo fix without pretending a writer model drafted it.
# A value that is only "claude", "opus", "inherit", "unknown", "tbd" or
# "pending" names no model and is refused.
#
# Gated: only `action` absent or "publish", and only when it sends a local
# source — `file_path` or a `files` entry; each source's directory is checked.
# Every other action (read, list, comments, reply, watch, ...) passes through
# untouched, as does a publish by `url` or `type_url` alone. Asset uploads
# (`asset: true`, `file_paths`, or `from_url`/`asset_ids`) are images, fonts
# and data rather than prose, so they pass too.
#
# CUTOVER is the day the guard shipped. ARTIFACT_AUTHOR_CUTOVER overrides it
# for the regression test only (tests/test_block_claude_authored_artifact.sh);
# it is the one bypass, and setting it in a session defeats the guard.
#
# Feature flag: guards.artifact-author (features.conf; missing = on), read via
# `hook_feature.py enabled`. NOT via `hook_feature.sh run`: that launcher is
# fail-open by design, which would turn this block into a no-op.
#
# Reads the hook JSON from stdin. Exit 0 = allow, exit 2 = block.

set -uo pipefail

CUTOVER="${ARTIFACT_AUTHOR_CUTOVER:-2026-10-12}"

INPUT=$(cat)
HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -x "$HOOK_DIR/hook_feature.py" ]]; then
  "$HOOK_DIR/hook_feature.py" enabled guards.artifact-author >/dev/null 2>&1 || exit 0
fi

# Prints the action, then one absolute path per local source the publish
# sends: file_path, and every `files` source (a string or {from: ...},
# resolved against `root` when given, else the working directory). Server-side
# copies ({artifact, path}) and removals (null) send no local text. Media and
# fonts are skipped: they carry no prose and often live outside the layout.
read_json() {
  python3 -c '
import json, os, sys
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
action = ti.get("action") or "publish"
if ti.get("asset") is True or ti.get("file_paths") or ti.get("from_url") or ti.get("asset_ids"):
    action = "asset"
print(action)
if action != "publish":
    sys.exit(0)
cwd = d.get("cwd") if isinstance(d.get("cwd"), str) else os.getcwd()
root = ti.get("root") if isinstance(ti.get("root"), str) else ""
base = os.path.join(cwd, root) if root else cwd
SKIP = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".pdf",
        ".mp4", ".webm", ".mov", ".mp3", ".wav", ".woff", ".woff2", ".ttf", ".otf"}
out = []
fp = ti.get("file_path")
if isinstance(fp, str) and fp:
    out.append(os.path.join(cwd, fp))
files = ti.get("files")
srcs = []
if isinstance(files, dict):
    for key, v in files.items():
        if isinstance(v, str):
            srcs.append(v)
        elif isinstance(v, dict) and isinstance(v.get("from"), str) and "artifact" not in v:
            srcs.append(v["from"])
elif isinstance(files, list):
    for v in files:
        if isinstance(v, dict) and isinstance(v.get("path"), str):
            srcs.append(v["path"])
        elif isinstance(v, str):
            srcs.append(v)
for src in srcs:
    if os.path.splitext(src)[1].lower() in SKIP:
        continue
    out.append(os.path.join(base, src))
seen = set()
for path in out:
    path = os.path.normpath(path)
    if path not in seen:
        seen.add(path)
        print(path)
' <<<"$INPUT"
}

# Read line by line, without mapfile: stock macOS bash is 3.2 and has none.
SOURCES=()
{
  IFS= read -r ACTION || ACTION=""
  while IFS= read -r line; do
    [[ -n "$line" ]] && SOURCES+=("$line")
  done
} < <(read_json)

[[ "$ACTION" == "publish" ]] || exit 0
# Metadata-only and type_url-only publishes send no local text.
[[ ${#SOURCES[@]} -gt 0 ]] || exit 0

deny() {
  cat >&2 <<EOF
BLOCKED: this page has no allowed author_model, so it reads as drafted by a
Claude model.

  page:     $PAGE
  meta.yml: $META
  reason:   $1

Opus 4.8, Opus 5 and Fable do not write pages Yulong reads (2026-09-08);
Opus 5.5 may, after Sol and Astra. The prose is dispatched to the
writer-priority model in config/model-router.toml from a skeleton — the
procedure is the write-prose skill — and meta.yml then records who wrote it:

  author_model: gpt-5.6-sol

Do not set the field to satisfy the hook: the fix is the dispatch, and the
field is the record of it. The fallback order on quota or cooldown is the
writer-priority order in that config. A page a script emits from structured
data with no drafted prose (the hosted index) carries author_model: generated.
A page whose directory was committed before $CUTOVER, republished without
rewriting its prose, can carry author_model: legacy.
EOF
  exit 2
}

# check_page <abs path>: returns when allowed, exits 2 through deny otherwise.
check_page() {
  PAGE="$1"
  DIR=$(dirname "$PAGE")
  [[ "$(basename "$DIR")" == "build" ]] && DIR=$(dirname "$DIR")
  META="$DIR/meta.yml"

  [[ -f "$META" ]] || deny "no meta.yml beside the page (artifacts/README.md layout)"

  # First author_model line; strip quotes and a trailing comment.
  VALUE=$(sed -nE 's/^[[:space:]]*author_model[[:space:]]*:[[:space:]]*//p' "$META" | head -1 \
    | sed -E 's/[[:space:]]+#.*$//; s/^["'"'"']//; s/["'"'"']$//; s/[[:space:]]+$//')

  [[ -n "$VALUE" ]] || deny "meta.yml has no author_model (or it is empty)"

  LOWER=$(printf '%s' "$VALUE" | tr '[:upper:]' '[:lower:]')

  # A script emitted the page from structured data.
  [[ "$LOWER" == "generated" ]] && return 0

  if [[ "$LOWER" == "legacy" ]]; then
    # Earliest author date of any file added under the page's directory.
    FIRST=$(git -C "$DIR" log --diff-filter=A --format=%as -- . 2>/dev/null | sort | head -1)
    [[ -n "$FIRST" ]] || deny "author_model \"legacy\" but $DIR has no commit history"
    [[ "$FIRST" < "$CUTOVER" ]] && return 0
    deny "author_model \"legacy\" but $DIR was first committed $FIRST, not before $CUTOVER"
  fi

  case "$LOWER" in
    claude|opus|anthropic|inherit|unknown|tbd|pending|none|n/a)
      deny "author_model \"$VALUE\" names no specific model" ;;
  esac

  # Separators normalised to "-" first, so Opus 5 is `opus-?5` followed by the
  # end, or by a separator and anything but a second 5 (a date, a suffix).
  NORM=$(printf '%s' "$LOWER" | tr '_ .' '---')
  if printf '%s' "$NORM" | grep -qE 'opus-?4-?8|opus-?5($|-$|-[^5])|fable|mythos'; then
    deny "author_model \"$VALUE\" is a banned writer (Opus 4.8, Opus 5, Fable, Mythos)"
  fi
  return 0
}

for src in "${SOURCES[@]}"; do
  check_page "$src"
done

exit 0
