#!/usr/bin/env bash
# PreToolUse(Bash) hook: block destructive git commands outright.
#
# Contract (same as block_secret_expansion.sh / block_unsafe_install.py):
#   exit 0 = allow.  exit 2 = block, reason on stderr.
#
# BLOCK-ALWAYS, no approval bypass — the precedent is the install gate
# (commit 841cffd). The agent cannot talk its way past this hook; if the
# command is genuinely wanted, the human runs it themselves.
#
# Blocked forms:
#   git reset --hard              (discards working tree + index)
#   git checkout -- <path>        (discards working-tree changes)
#   git checkout .                (same, positional form)
#   git clean -f[d...]            (deletes untracked files)
#   git stash                     (bare — stack is shared across worktrees)
#   git stash pop                 (may pop another session's entry)
#
# Deliberately NOT blocked: git checkout <branch>, git checkout -b <new>,
# git stash push/apply/list/show, git reset (bare), --soft, --mixed,
# git clean -n/--dry-run. `git stash drop` and `git stash clear` are also
# unguarded — out of scope for this hook, still covered by prose.
#
# Known limitation: an unquoted-looking separator inside a quoted string
# (e.g. -m "fix; git reset --hard") can split a segment and trigger a
# false block. That fails safe — the human rephrases or runs it directly.

# shellcheck disable=SC2016  # backticks in denial text are literal markdown
set -uo pipefail

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -z "$command" ] && exit 0

# --- split on separators that are not inside quotes --------------------------
segments=()
split_segments() {
    local s="$1" cur="" q="" c i
    segments=()
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        if [ -n "$q" ]; then
            cur+="$c"
            [ "$c" = "$q" ] && q=""
            continue
        fi
        case "$c" in
            "'"|'"') q="$c"; cur+="$c" ;;
            ';'|'&'|'|'|$'\n') segments+=("$cur"); cur="" ;;
            *) cur+="$c" ;;
        esac
    done
    segments+=("$cur")
}

FOOTER='If this is genuinely the right command, do not work around the hook — ask the user to run it themselves. In Claude Code they can type `! <command>` to run it in this session.'

deny() {
    printf 'BLOCKED — destructive git command\n\n%s\n\nSafe alternative: %s\n\n%s\n' \
        "$1" "$2" "$FOOTER" >&2
    exit 2
}

split_segments "$command"

for seg in "${segments[@]}"; do
    # strip leading whitespace, env assignments, sudo
    seg="${seg#"${seg%%[![:space:]]*}"}"
    while [[ "$seg" =~ ^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|command)[[:space:]]+ ]]; do
        seg="${seg#"${BASH_REMATCH[0]}"}"
    done

    # shellcheck disable=SC2206  # deliberate word-splitting of the segment
    words=($seg)
    [ "${#words[@]}" -ge 2 ] || continue

    base="${words[0]##*/}"
    [ "$base" = "git" ] || continue

    # skip git's global options to reach the subcommand
    idx=1
    while [ "$idx" -lt "${#words[@]}" ]; do
        case "${words[$idx]}" in
            -C|-c|--exec-path|--namespace) idx=$((idx + 2)) ;;
            --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*) idx=$((idx + 1)) ;;
            --no-pager|-P|--no-replace-objects|--literal-pathspecs|--bare) idx=$((idx + 1)) ;;
            -*) idx=$((idx + 1)) ;;
            *) break ;;
        esac
    done
    [ "$idx" -lt "${#words[@]}" ] || continue

    sub="${words[$idx]}"
    args=("${words[@]:$((idx + 1))}")

    case "$sub" in
        reset)
            for a in ${args+"${args[@]}"}; do
                [ "$a" = "--hard" ] && deny \
                    'git reset --hard discards every uncommitted change in the working tree and index — there is no undo for unstaged work.' \
                    'set work aside with a WIP commit (`git commit -am wip`), or `git stash push -u -m "<unique-tag>"`. To move only the branch pointer, `git reset --soft` keeps your changes.'
            done
            ;;
        checkout)
            for a in ${args+"${args[@]}"}; do
                [ "$a" = "--" ] && deny \
                    'git checkout -- <path> overwrites the working-tree copy with HEAD, discarding your edits to those files.' \
                    'inspect first with `git diff -- <path>`, then keep what you want. To set changes aside instead of destroying them, make a WIP commit.'
            done
            for a in ${args+"${args[@]}"}; do
                case "$a" in
                    -*) continue ;;
                    .|./) deny \
                        'git checkout . discards working-tree changes across the whole current directory.' \
                        'inspect first with `git diff`, then keep what you want. To set changes aside instead of destroying them, make a WIP commit.' ;;
                    *) break ;;
                esac
            done
            ;;
        clean)
            for a in ${args+"${args[@]}"}; do
                case "$a" in
                    --force) deny \
                        'git clean --force permanently deletes untracked files — they were never in git, so nothing can recover them.' \
                        'preview with `git clean -n` first, then remove specific files with `trash <path>` (recoverable).' ;;
                    --*) continue ;;
                    -*[fF]*) deny \
                        'git clean -f permanently deletes untracked files — they were never in git, so nothing can recover them.' \
                        'preview with `git clean -n` first, then remove specific files with `trash <path>` (recoverable).' ;;
                esac
            done
            ;;
        stash)
            positional=""
            for a in ${args+"${args[@]}"}; do
                case "$a" in
                    -*) continue ;;
                    *) positional="$a"; break ;;
                esac
            done
            case "$positional" in
                "") deny \
                    'bare `git stash` pushes onto a stack shared by every worktree and other Claude sessions, with no label to find it again.' \
                    'use `git stash push -u -m "<unique-tag>"`, capture the SHA from `git stash list --format="%H %gs"`, and restore with `git stash apply <sha>`. A WIP commit is safer still.' ;;
                pop) deny \
                    'git stash pop takes the top of a stack shared across worktrees — it can restore and then delete another session'"'"'s work.' \
                    'find your own entry by tag in `git stash list --format="%H %gs"`, then `git stash apply <sha>` (apply, never pop) and drop it explicitly afterwards.' ;;
            esac
            ;;
    esac
done

exit 0
