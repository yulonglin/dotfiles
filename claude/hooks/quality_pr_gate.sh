#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash): blocks `gh pr create` when the branch changes
# code files and the requesting-code-review skill has not run on this branch.
#
# Why a deny rather than a nudge. PreToolUse additionalContext is delivered
# alongside the tool result — i.e. after `gh pr create` has already opened the
# PR. A reminder at that point cannot stop un-reviewed code from being
# published, it can only ask for a follow-up commit. This is the one hard gate;
# the paired Stop hook (quality_stop_nudge.sh) stays a soft nudge.
#
# FAIL OPEN, deliberately. Every unresolvable condition — no jq, not a git repo,
# no base ref, unreadable diff — exits 0 and allows the PR. A quality gate that
# blocks PR creation because it could not compute a merge-base is strictly worse
# than one that occasionally misses. Do not "harden" this into a fail-closed
# check; that is a regression, not a fix.
#
# The ONE exception to fail-open is a command whose prefix invalidates the
# check itself (see "Compound commands" below). There, allowing would not be
# "occasionally missing" — it would be answering a question about the wrong
# repository or the wrong commit.
#
# Bypass: touch the marker file named in the deny message.
set -euo pipefail

GATE_SKILL="requesting-code-review"
CODE_EXT_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|rs|go|rb|sh|bash|zsh|c|cc|cpp|h|hpp|java|kt|swift|scala|php|cs|lua|sql)$'

LIB="$(dirname "$0")/lib/quality_gate_lib.sh"
[ -r "$LIB" ] || exit 0
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/quality_gate_lib.sh
. "$LIB"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

deny() {
    jq -n --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
}

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Split into shell segments so flags are read from the `gh pr create` invocation
# itself rather than from anywhere in the line. Order matters: the two-character
# operators must be replaced before their single-character prefixes.
SEG_ALL="$CMD"
SEG_ALL="${SEG_ALL//&&/$'\n'}"
SEG_ALL="${SEG_ALL//||/$'\n'}"
SEG_ALL="${SEG_ALL//;/$'\n'}"
SEG_ALL="${SEG_ALL//|/$'\n'}"
SEG_ALL="${SEG_ALL//&/$'\n'}"

TARGET_NQ=""
PREFIX=""
FOUND=0
while IFS= read -r seg; do
    if [ "$FOUND" -eq 0 ] \
       && [[ "$seg" =~ (^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
        # Strip quoted text before reading flags, so a title such as
        # --title "fix --help output" cannot be mistaken for a real option.
        seg_nq=$(printf '%s' "$seg" | sed -e 's/"[^"]*"/ /g' -e "s/'[^']*'/ /g")
        # `gh pr create --help` prints usage and creates nothing, so it is not
        # the invocation to gate — but keep scanning, because a real create may
        # still follow it on the same line. (`gh pr create` has no -h
        # shorthand, so only the long form is honoured here.)
        if [[ "$seg_nq" =~ (^|[[:space:]])--help([[:space:]]|$) ]]; then
            PREFIX="$PREFIX $seg"
            continue
        fi
        TARGET_NQ="$seg_nq"
        FOUND=1
    elif [ "$FOUND" -eq 0 ]; then
        PREFIX="$PREFIX $seg"
    fi
done < <(printf '%s\n' "$SEG_ALL")
[ "$FOUND" -eq 1 ] || exit 0

# Compound commands. The hook runs BEFORE the command does, so anything in the
# prefix that changes the repository or the working directory means the state we
# are about to inspect is not the state the PR will be created from:
#
#   cd other-repo && gh pr create      -> we read THIS repo's branch and marker
#   git commit -m x && gh pr create    -> we read the pre-commit diff
#
# Both would silently answer the wrong question, so they are refused rather than
# guessed at. The remedy is trivial and stated in the message: run `gh pr create`
# on its own, at which point the normal evaluation applies.
if [[ "$PREFIX" =~ (^|[[:space:]])cd([[:space:]]|$) ]]; then
    deny "This command changes directory before \`gh pr create\`, so the code-review gate would evaluate the wrong repository. Run \`gh pr create\` as its own command from the target repo."
fi
if [[ "$PREFIX" =~ (^|[[:space:]])git[[:space:]]+(commit|merge|rebase|cherry-pick|revert|reset|checkout|switch|am)([[:space:]]|$) ]]; then
    deny "This command rewrites the branch before \`gh pr create\`, so the code-review gate would evaluate the pre-commit state rather than what the PR would contain. Run \`gh pr create\` as its own command afterwards."
fi

MARKER=$(quality_gate_marker "$GATE_SKILL")
[ -n "$MARKER" ] || exit 0   # not a git repo, or key unavailable → allow
[ -f "$MARKER" ] && exit 0   # already reviewed on this branch → allow

# Base ref, in the order gh itself resolves it: an explicit --base/-B, then the
# branch's configured gh-merge-base, then origin/HEAD, then the usual names.
BASE=""
if [[ "$TARGET_NQ" =~ (--base|-B)[[:space:]=]+([^[:space:]]+) ]]; then
    BASE="${BASH_REMATCH[2]}"
fi
if [ -z "$BASE" ]; then
    CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || CUR=""
    if [ -n "$CUR" ]; then
        BASE=$(git config --get "branch.${CUR}.gh-merge-base" 2>/dev/null) || BASE=""
    fi
fi
if [ -z "$BASE" ]; then
    BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || BASE=""
fi
if [ -z "$BASE" ]; then
    for cand in origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
            BASE="$cand"
            break
        fi
    done
fi
[ -n "$BASE" ] || exit 0

# An explicit base names a GitHub branch, which may exist locally only as a
# remote-tracking ref (`--base develop` with just origin/develop on disk).
if ! git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
    if git rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1; then
        BASE="origin/$BASE"
    else
        exit 0
    fi
fi

CHANGED=$(git diff --name-only "$BASE...HEAD" 2>/dev/null) || exit 0
[ -n "$CHANGED" ] || exit 0

# is_code_file <path> — suffix match, or an extensionless executable/shebang
# file. The suffix list alone misses the dozens of extensionless scripts this
# repo tracks under custom_bins/, which are exactly the files worth reviewing.
is_code_file() {
    local f="$1" mode first
    if [[ "$f" =~ $CODE_EXT_RE ]]; then
        return 0
    fi
    # A file with some other suffix (.md, .json, .yaml) is not code.
    case "${f##*/}" in
        *.*) return 1 ;;
    esac
    mode=$(git ls-tree HEAD -- "$f" 2>/dev/null | awk '{print $1}') || mode=""
    if [ "$mode" = "100755" ]; then
        return 0
    fi
    first=$(git show "HEAD:$f" 2>/dev/null | head -1) || first=""
    case "$first" in
        '#!'*) return 0 ;;
    esac
    return 1
}

CODE_FILES=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_code_file "$f"; then
        CODE_FILES="${CODE_FILES}${f}"$'\n'
    fi
done < <(printf '%s\n' "$CHANGED")

[ -n "$CODE_FILES" ] || exit 0   # docs/config-only branch → nothing to review

COUNT=$(printf '%s' "$CODE_FILES" | grep -c . || true)
SAMPLE=$(printf '%s' "$CODE_FILES" | head -5 | tr '\n' ' ')

deny "This branch changes ${COUNT} code file(s) against ${BASE} (${SAMPLE}) and the ${GATE_SKILL} skill has not run on it yet. Run the Skill tool with skill: \"superpowers:${GATE_SKILL}\" over the branch diff, then re-run this command. If a review genuinely does not apply to this branch, bypass with: touch '${MARKER}'"
