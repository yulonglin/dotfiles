#!/usr/bin/env bash
# PostToolUse(Bash) hook: after a successful `git push` of a non-default branch,
# make sure the branch has a pull request, then tell Claude what comes next.
#
# The flow this enforces (rules/coding-conventions.md § Any language): work is
# committed, a commit is pushed, a pushed branch has a PR, a PR is reviewed, and
# a reviewed PR is merged by Claude when it is simple or handed to the user when
# it is not. This hook covers the "pushed → PR" edge, which is the one a session
# most often forgets, and injects the review/merge instruction for the rest.
#
# Side effect: creates a DRAFT PR when the branch has no open PR. Draft, so
# nothing is requested of anyone. The body is written by an OpenAI model through
# the model-router gateway (pr_body_model.py, flag git.pr-after-push.model-body)
# and falls back to `--fill` from the commit messages whenever the gateway is
# unreachable, in cooldown or slow — the PR opens either way.
#
# Quiet when there is nothing to do: not a push, a push that failed, a push of
# main/master, a delete, a tags-only push, no gh, or no GitHub remote.
#
# Advisory: emits hookSpecificOutput.additionalContext and always exits 0.
# Feature flag: git.pr-after-push (features.conf); missing flags default on.
set -uo pipefail

INPUT=$(cat)

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled git.pr-after-push 2>/dev/null; then
    exit 0
fi

# "<cwd>\t<failed>" or empty when this is not a push worth acting on.
# shellcheck disable=SC2016  # single quotes protect the Python source, deliberately
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys

def bail():
    sys.exit(0)

try:
    p = json.load(sys.stdin)
except Exception:
    bail()
if not isinstance(p, dict):
    bail()
name = p.get("tool_name")
if name is not None and name != "Bash":
    bail()
ti = p.get("tool_input") if isinstance(p.get("tool_input"), dict) else {}
cmd = ti.get("command") or ""
# A push anywhere in a compound command counts: `git add && git commit && git
# push` is the common shape. Deletes and tags-only pushes create nothing to PR.
if not re.search(r"(^|[;&|\s(])git\s+(-C\s+\S+\s+)?push(\s|$)", cmd):
    bail()
if re.search(r"\s(--delete|-d|--tags)(\s|$)", cmd):
    bail()
resp = p.get("tool_response")
if resp is None:
    resp = p.get("tool_result")
rendered = json.dumps(resp) if resp is not None else ""
low = rendered.lower()
# No apostrophes in this block: it lives inside a single-quoted shell string.
failed = any(s in low for s in ("[rejected]", "fatal:", "error:", "permission denied",
                                "could not read from remote"))
for holder in (p, resp):
    if isinstance(holder, dict) and holder.get("is_error"):
        failed = True
cwd = p.get("cwd") or ""
tp = p.get("transcript_path") or ""
print("\t".join([cwd if isinstance(cwd, str) else "", "1" if failed else "0",
                 tp if isinstance(tp, str) else ""]))
' 2>/dev/null) || exit 0
[ -n "$PARSED" ] || exit 0

IFS=$'\t' read -r CWD FAILED TRANSCRIPT <<< "$PARSED"
[ "$FAILED" = "0" ] || exit 0

[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
case "$BRANCH" in
    ""|HEAD|main|master) exit 0 ;;
esac

command -v gh >/dev/null 2>&1 || exit 0
REMOTE=$(git -C "$CWD" remote get-url origin 2>/dev/null) || exit 0
grep -q github.com <<< "$REMOTE" || exit 0

emit() {
    python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read().strip(),
}}))' <<< "$1"
    exit 0
}

NEXT="Next, per coding-conventions: rewrite the PR body if --fill left it thin (what, why, review points), run a review (/code-review, or codex-companion review --base main), then merge it yourself with \`gh pr merge <n> --squash --delete-branch\` only if it is simple: docs, rules or a single file, tests green, nothing under claude/settings.json, claude/hooks/ or secrets. Otherwise ask the user with AskUserQuestion and put the merge command in the closing summary."

EXISTING=$(cd "$CWD" && gh pr list --head "$BRANCH" --state open --json number \
    --jq '.[0].number' 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    emit "Pushed $BRANCH; PR #$EXISTING is already open for it. $NEXT"
fi

# --fill takes the title from the commit only when the branch is exactly one
# commit ahead of base; with more commits it humanises the BRANCH NAME instead.
# That is how background jobs produced PRs titled "worktree agent <hex>" — and
# why any two-commit push got a title like "gateway dropin rebase". gh's own
# help: alongside --fill, a value given by --title takes precedence, so the body
# stays autofilled from the commits.
TITLE=$(git -C "$CWD" log -1 --format=%s 2>/dev/null)
TITLE_ARG=()
[ -n "$TITLE" ] && TITLE_ARG=(--title "$TITLE")

# The body is written by an OpenAI model through the model-router gateway
# (pr_body_model.py): motivation, implementation with the files and symbols
# touched, the tests the transcript shows actually ran, and a diagram when the
# change has interacting parts. The gateway is best-effort — a stopped router,
# a quota cooldown or a slow answer falls through to `--fill`, so the PR opens
# either way and the only difference is a plainer body.
BODY_FILE=""
BODY_SOURCE="the commit messages"
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   python3 "$HOOK_DIR/hook_feature.py" enabled git.pr-after-push.model-body 2>/dev/null; then
    TRANSCRIPT_ARG=()
    [ -n "${TRANSCRIPT:-}" ] && TRANSCRIPT_ARG=(--transcript "$TRANSCRIPT")
    CANDIDATE=$(mktemp "${TMPDIR:-/tmp}/pr-body.XXXXXX" 2>/dev/null) || CANDIDATE=""
    if [ -n "$CANDIDATE" ]; then
        if python3 "$HOOK_DIR/pr_body_model.py" --repo "$CWD" --branch "$BRANCH" \
               "${TRANSCRIPT_ARG[@]}" > "$CANDIDATE" 2>/dev/null \
           && [ -s "$CANDIDATE" ]; then
            BODY_FILE="$CANDIDATE"
            BODY_SOURCE="a model-written summary (motivation, implementation, tests)"
        else
            rm -f "$CANDIDATE"
        fi
    fi
fi

BODY_ARG=(--fill)
[ -n "$BODY_FILE" ] && BODY_ARG=(--body-file "$BODY_FILE")

if ! CREATED=$(cd "$CWD" && gh pr create --draft "${BODY_ARG[@]}" "${TITLE_ARG[@]}" --head "$BRANCH" 2>&1); then
    [ -n "$BODY_FILE" ] && rm -f "$BODY_FILE"
    emit "Pushed $BRANCH but no PR exists and \`gh pr create --draft\` failed: ${CREATED//$'\n'/ }. Open one with gh pr create (title + body), then: $NEXT"
fi
[ -n "$BODY_FILE" ] && rm -f "$BODY_FILE"
URL=$(grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' <<< "$CREATED" | head -1)
emit "Pushed $BRANCH and opened draft PR ${URL:-(url not parsed)} with $BODY_SOURCE. $NEXT"
