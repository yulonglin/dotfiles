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
# ── The design rule, learned the hard way ────────────────────────────────────
#
# A PATTERN MATCH IN THIS FILE MAY ONLY EVER PRODUCE A DENY, NEVER AN ALLOW.
#
# Two adversarial review rounds found eight bypasses between them. Every single
# one was a regex whose match produced an allow: a `--help` token borrowed from
# a quoted title, a `--base "main"` whose value became `--draft` once quotes
# were stripped, a mutator prefix that `git -c x=y commit` slipped past. The
# common cause is not any individual regex — it is that regex-parsing an
# arbitrary shell command line to GRANT permission is unsound, and every round
# of "parse harder" plugs holes while opening new ones.
#
# So the parsing is gone. This file asks only questions whose wrong answer is a
# deny: does the command contain something we cannot safely reason about? Then
# refuse and say why. Everything the gate actually needs — branch, base, diff —
# is read from the repository, which cannot be spoofed by a command string.
#
# If you are here to fix a bypass: the fix is another deny, or a stricter shape
# for what counts as an ordinary invocation. It is never a new capture group.
#
# ── Fail open, deliberately ──────────────────────────────────────────────────
#
# Every unresolvable *repository* condition — no jq, not a git repo, no base
# ref, unreadable diff — exits 0 and allows the PR. A quality gate that blocks
# PR creation because it could not compute a merge-base is strictly worse than
# one that occasionally misses. Do not "harden" this into a fail-closed check.
#
# That is not in tension with the rule above: unreadable *repository* state
# allows, unparseable *command* state denies. The command is the part an
# attacker (or an unlucky quoting accident) controls.
#
# Bypass: run the mkdir+touch line printed in the deny message.
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

# Not a PR creation at all → not our business. (`gh pr` has exactly one
# creating subcommand; `create` has no alias — verified against `gh pr --help`.)
#
# The boundaries are any non-word character rather than whitespace, so that
# `(gh pr create)`, `$(gh pr create)` and `/opt/homebrew/bin/gh pr create` are
# all detected. Widening detection is always safe here: reaching this line only
# makes a deny possible, never an allow, and the "is it ordinary?" test below
# decides what actually happens. Narrowing it is how a bypass gets in — an
# earlier boundary of `[^[:alnum:]_./-]` silently missed every absolute path.
[[ "$CMD" =~ (^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([^[:alnum:]_-]|$) ]] || exit 0

# Whitespace-normalised form, used ONLY for whole-string comparisons below.
NORM=$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')
NORM="${NORM# }"
NORM="${NORM% }"

# `gh pr create --help` prints usage and creates nothing. This is the one
# allow-producing match left in the file, so it is whole-string equality rather
# than a search for a `--help` token: with no other tokens present, `--help`
# cannot be the value of a preceding flag or the contents of a quoted title,
# which is exactly how the previous two versions of this check were bypassed.
[ "$NORM" = "gh pr create --help" ] && exit 0

# The command must BE a PR creation, not merely contain one. The hook runs
# before the command does, so any prefix that changes the working directory or
# the branch means the state inspected here is not the state the PR is created
# from:
#
#   cd other-repo && gh pr create     -> reads THIS repo's branch and marker
#   git commit -m x && gh pr create   -> reads the pre-commit diff
#
# Rather than enumerate which prefixes mutate — the enumeration is what the
# `git -c … commit` and `pushd` bypasses walked through — nothing may precede
# the creation. Suffixes are unrestricted: they run after the PR exists, from
# the state that was inspected, so they cannot invalidate the answer.
# An absolute or relative path to the gh binary is an ordinary invocation, not
# a prefix — `/opt/homebrew/bin/gh pr create` changes nothing about the state
# being inspected, so it must not be refused as though it were a `cd`.
if ! [[ "$NORM" =~ ^([^[:space:]]*/)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
    deny "\`gh pr create\` must be its own command — the code-review gate runs before the command does, so anything preceding the create (a \`cd\`, a commit, a subshell) would have it inspect a different repository or a different commit than the PR is made from. Run the preceding steps first, then \`gh pr create\` on its own line."
fi

# --head names a branch other than the checked-out one, so a marker for the
# current branch would prove nothing about the branch being published. Refused
# rather than resolved: resolving means parsing the value, which is the class
# of bug this rewrite exists to remove. Checked before the marker for that
# reason — a marker cannot vouch for a branch we are not standing on.
if [[ "$NORM" =~ (^|[[:space:]])(--head|-H) ]]; then
    deny "\`gh pr create --head\` publishes a branch other than the checked-out one, and the code-review gate can only vouch for the branch it is standing on. Check out the head branch and run \`gh pr create\` from there."
fi

MARKER=$(quality_gate_marker "$GATE_SKILL")
[ -n "$MARKER" ] || exit 0   # not a git repo, or key unavailable → allow
[ -f "$MARKER" ] && exit 0   # already reviewed on this branch → allow

BYPASS="mkdir -p '$(quality_gate_dir)' && touch '${MARKER}'"

# An explicit base changes which diff the PR contains, and reading its value
# means parsing the command line. `--base "main" --draft` is the exact form
# that used to capture `--draft` as the base, fail to resolve it, and allow.
# So the flag is refused unreviewed rather than interpreted. Deliberately AFTER
# the marker check: a reviewed branch may target any base it likes, because the
# marker is about the branch, not about the base.
#
# Known false positive: an inline --body whose text quotes `--base` or `--head`
# is denied too. It errs toward review, the marker clears it, and detecting the
# difference would mean parsing quoting — the thing that keeps breaking.
if [[ "$NORM" =~ (^|[[:space:]])(--base|-B) ]]; then
    deny "This branch changes code and the ${GATE_SKILL} skill has not run on it, and an explicit \`--base\` means the gate cannot determine the PR's diff without parsing the command line. Run the Skill tool with skill: \"superpowers:${GATE_SKILL}\" over the branch diff, then re-run this command — the base is unrestricted once the branch has been reviewed. To skip the review: ${BYPASS}"
fi

# Base ref, from repository state only — never from the command line.
BASE=""
CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || CUR=""
if [ -n "$CUR" ]; then
    BASE=$(git config --get "branch.${CUR}.gh-merge-base" 2>/dev/null) || BASE=""
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
git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || exit 0

CHANGED=$(git diff --name-only "$BASE...HEAD" 2>/dev/null) || exit 0
[ -n "$CHANGED" ] || exit 0

# is_code_file <path> — suffix match, or an extensionless executable/shebang
# file. The suffix list alone misses the dozens of extensionless scripts this
# repo tracks under custom_bins/, which are exactly the files worth reviewing.
#
# Both endpoints are probed. A file DELETED on this branch has no blob at HEAD,
# so a HEAD-only probe classified every removed script as non-code — deleting
# custom_bins/foo could ship unreviewed.
is_code_file() {
    local f="$1" rev mode first
    if [[ "$f" =~ $CODE_EXT_RE ]]; then
        return 0
    fi
    # A file with some other suffix (.md, .json, .yaml) is not code.
    case "${f##*/}" in
        *.*) return 1 ;;
    esac
    for rev in HEAD "$BASE"; do
        mode=$(git ls-tree "$rev" -- "$f" 2>/dev/null | awk '{print $1}') || mode=""
        if [ "$mode" = "100755" ]; then
            return 0
        fi
        first=$(git show "${rev}:${f}" 2>/dev/null | head -1) || first=""
        case "$first" in
            '#!'*) return 0 ;;
        esac
    done
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

deny "This branch changes ${COUNT} code file(s) against ${BASE} (${SAMPLE}) and the ${GATE_SKILL} skill has not run on it yet. Run the Skill tool with skill: \"superpowers:${GATE_SKILL}\" over the branch diff, then re-run this command. If a review genuinely does not apply to this branch, bypass with: ${BYPASS}"
