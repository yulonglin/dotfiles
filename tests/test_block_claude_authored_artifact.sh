#!/usr/bin/env bash
# shellcheck shell=bash
# Guards claude/hooks/block_claude_authored_artifact.sh.
#
# The hook is an honour-system check with teeth: it can only read the
# self-reported author_model in meta.yml. So both halves matter — it must
# refuse a missing field and every banned Claude writer (Opus 4.8, Opus 5,
# Fable), and it must let an honestly-labelled sol/astra/kimi/opus-5.5/opus-4.6
# page through, or it becomes a thing people route around by leaving meta.yml
# out.
#
# Fixtures: tests/fixtures/artifact-author/<case>/meta.yml. No mktemp: $TMPDIR
# is read-only under the sandbox, and a failed mktemp would leave an empty
# path that makes a test pass for the wrong reason. The one runtime directory
# (an untracked legacy page) goes under the gitignored tmp/ at the repo root.
#
# HOOK_BASH picks the shell that runs the hook; run the suite under both
# /bin/bash (3.2, stock macOS) and the PATH bash.

set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$REPO/claude/hooks/block_claude_authored_artifact.sh"
FIX="$REPO/tests/fixtures/artifact-author"
HOOK_BASH="${HOOK_BASH:-bash}"
# Fixtures were committed in September, so pin the cutover in the past unless
# a case overrides it; otherwise `legacy` would pass for every fixture.
export ARTIFACT_AUTHOR_CUTOVER=2000-01-01
PASS=0
FAIL=0

run() { # run <json> -> prints exit code
  printf '%s' "$1" | "$HOOK_BASH" "$HOOK" >/dev/null 2>&1
  echo $?
}

publish() { # publish <case-dir> [file] -> json
  printf '{"tool_name":"Artifact","tool_input":{"file_path":"%s/%s/%s"}}' "$FIX" "$1" "${2:-page.html}"
}

check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 — expected exit $2, got $3"
  fi
}

# --- blocks ---
check "fable" 2 "$(run "$(publish fable)")"
check "opus 5 dated id" 2 "$(run "$(publish opus5)")"
check "opus 4.8" 2 "$(run "$(publish opus48)")"
check "opus 5 bare id" 2 "$(run "$(publish opus5-bare)")"
check "opus 5 spaced" 2 "$(run "$(publish opus5-spaced)")"
check "opus 5 underscore" 2 "$(run "$(publish opus5-underscore)")"
check "legacy on a directory committed after the cutover" 2 "$(run "$(publish legacy)")"
check "bare 'claude' names no model" 2 "$(run "$(publish bare-claude)")"
check "field present but empty" 2 "$(run "$(publish empty-field)")"
check "field missing" 2 "$(run "$(publish missing-field)")"
check "no meta.yml beside the page" 2 "$(run "$(publish nometa)")"
check "markdown publish is checked too" 2 "$(run "$(publish fable spec.md)")"
check "explicit publish action still checked" 2 \
  "$(run "$(printf '{"tool_input":{"action":"publish","file_path":"%s/fable/page.html"}}' "$FIX")")"

# --- allows ---
check "sol" 0 "$(run "$(publish sol)")"
check "astra" 0 "$(run "$(publish astra)")"
check "kimi (OpenRouter fallback)" 0 "$(run "$(publish kimi)")"
check "opus 4.6 is not banned" 0 "$(run "$(publish opus46)")"
check "opus 5.5 id" 0 "$(run "$(publish opus55)")"
check "opus 5.5 spaced" 0 "$(run "$(publish opus55-spaced)")"
check "opus 5.5 hyphen and dot" 0 "$(run "$(publish opus55-dotted)")"
check "opus 5.5 dated id" 0 "$(run "$(publish opus55-dated)")"
check "legacy on a directory committed before the cutover" 0 \
  "$(ARTIFACT_AUTHOR_CUTOVER=2099-01-01 run "$(publish legacy)")"
check "asset upload is not prose" 0 \
  "$(run "$(printf '{"tool_input":{"url":"https://claude.ai/code/artifact/abc","asset":true,"file_path":"%s/fable/page.html"}}' "$FIX")")"
check "multi-file asset upload" 0 \
  "$(run "$(printf '{"tool_input":{"url":"https://claude.ai/code/artifact/abc","asset":true,"file_paths":["%s/fable/a.png"]}}' "$FIX")")"
check "asset copy from another artifact" 0 \
  "$(run '{"tool_input":{"url":"https://claude.ai/code/artifact/abc","asset":true,"from_url":"https://claude.ai/code/artifact/def","asset_ids":["0123456789abcdef0123456789abcdef"]}}')"
check "generated sentinel (script-built page)" 0 "$(run "$(publish generated)")"
check "quoted value with trailing comment" 0 "$(run "$(publish quoted)")"
check "page in build/ resolves to the parent meta.yml" 0 "$(run "$(publish sol build/page.html)")"
check "non-publish action" 0 \
  "$(run "$(printf '{"tool_input":{"action":"read","file_path":"%s/fable/page.html"}}' "$FIX")")"
check "publish by url, no file_path" 0 \
  "$(run '{"tool_input":{"action":"publish","url":"https://claude.ai/code/artifact/abc"}}')"
check "list action" 0 "$(run '{"tool_input":{"action":"list"}}')"
check "another tool's payload is ignored" 0 \
  "$(run "$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/fable/page.html"}}' "$FIX")")"
check "malformed json does not block work" 0 "$(run 'not json at all')"

# --- publishes through `files` (no file_path) ---
U=https://claude.ai/code/artifact/abc
files_pub() { # files_pub <files-json> [extra-json-fields] -> json
  printf '{"tool_name":"Artifact","cwd":"%s","tool_input":{"url":"%s","files":%s%s}}' "$REPO" "$U" "$1" "${2:-}"
}
# Sources come from printf over single-quoted templates: bash 3.2 parses
# \" inside nested "$(...)" differently, which silently changed the JSON.
# shellcheck disable=SC2059  # the template is the format, by design
f1() { printf "$1" "$FIX"; }
# shellcheck disable=SC2059
f2() { printf "$1" "$FIX" "$FIX"; }
check "files: banned author" 2 "$(run "$(files_pub "$(f1 '{"p.html":"%s/fable/page.html"}')")")"
check "files: missing author" 2 "$(run "$(files_pub "$(f1 '{"p.html":"%s/missing-field/page.html"}')")")"
check "files: allowed author" 0 "$(run "$(files_pub "$(f1 '{"p.html":"%s/sol/page.html"}')")")"
check "files: {from:} object form, banned" 2 \
  "$(run "$(files_pub "$(f1 '{"p.html":{"from":"%s/fable/page.html","contentType":"text/html"}}')")")"
check "files: {from:} object form, allowed" 0 \
  "$(run "$(files_pub "$(f1 '{"p.html":{"from":"%s/astra/page.html"}}')")")"
check "files: root-relative source, banned" 2 \
  "$(run "$(files_pub '{"p.html":"fable/page.html"}' ',"root":"tests/fixtures/artifact-author"')")"
check "files: root-relative source, allowed" 0 \
  "$(run "$(files_pub '{"p.html":"kimi/page.html"}' ',"root":"tests/fixtures/artifact-author"')")"
check "files: cwd-relative source, banned" 2 \
  "$(run "$(files_pub '{"p.html":"tests/fixtures/artifact-author/fable/page.html"}')")"
check "files: one bad source among good ones" 2 \
  "$(run "$(files_pub "$(f2 '{"a.html":"%s/sol/page.html","b.json":"%s/fable/data.json"}')")")"
check "files: list form, banned" 2 \
  "$(run "$(files_pub "$(f1 '[{"path":"%s/fable/page.html"}]')")")"
check "files: {artifact,path} server-side copy" 0 \
  "$(run "$(files_pub '{"app.js":{"artifact":"https://claude.ai/code/artifact/def","path":"app.js"}}')")"
check "files: null removal" 0 "$(run "$(files_pub '{"old.html":null}')")"
check "files: png -> png key, no contentType, is not prose" 0 \
  "$(run "$(files_pub "$(f1 '{"fig.png":"%s/fable/fig.png"}')")")"
check "files: font -> font key, font/ contentType" 0 \
  "$(run "$(files_pub "$(f1 '{"f.woff2":{"from":"%s/fable/f.woff2","contentType":"font/woff2"}}')")")"
check "files: png source published as html" 2 \
  "$(run "$(files_pub "$(f1 '{"x.html":"%s/fable/page.png"}')")")"
check "files: png -> png key typed text/html" 2 \
  "$(run "$(files_pub "$(f1 '{"x.png":{"from":"%s/fable/page.png","contentType":"text/html"}}')")")"
check "files: svg is never exempt" 2 \
  "$(run "$(files_pub "$(f1 '{"fig.svg":"%s/fable/fig.svg"}')")")"
check "files: pdf is never exempt" 2 \
  "$(run "$(files_pub "$(f1 '{"doc.pdf":"%s/fable/doc.pdf"}')")")"
check "file_path and files both checked" 2 \
  "$(run "$(printf '{"tool_input":{"file_path":"%s/sol/page.html","files":{"b.html":"%s/opus5/page.html"}}}' "$FIX" "$FIX")")"
check "type_url create, no local source" 0 \
  "$(run '{"tool_input":{"type_url":"https://claude.ai/code/artifact-type/x","title":"T"}}')"

# An untracked directory cannot claim legacy, whatever the cutover.
UNTRACKED="$REPO/tmp/artifact-author-untracked"
mkdir -p "$UNTRACKED"
printf 'title: untracked\nauthor_model: legacy\n' >"$UNTRACKED/meta.yml"
check "legacy on an untracked directory" 2 \
  "$(ARTIFACT_AUTHOR_CUTOVER=2099-01-01 run "$(printf '{"tool_input":{"file_path":"%s/page.html"}}' "$UNTRACKED")")"
rm -rf "$UNTRACKED"

echo "passed $PASS, failed $FAIL ($HOOK_BASH)"
[[ $FAIL -eq 0 ]]
