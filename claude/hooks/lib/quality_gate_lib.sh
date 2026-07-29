# shellcheck shell=bash
# Shared marker-key logic for the code-quality gate hooks.
#
# quality_pr_gate.sh READS these markers; quality_mark_skill_ran.sh WRITES them.
# The two must agree on the key exactly — if they ever disagree the gate can
# never clear and `gh pr create` is blocked forever. Hence one file, sourced by
# both, rather than the key logic duplicated in each.
#
# Markers live under the user cache (not $TMPDIR) because a branch outlives a
# reboot: reviewing a branch on Monday should still count on Tuesday.

quality_gate_dir() {
    printf '%s/claude/quality-gate' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# quality_gate_marker <skill> — absolute marker path for <skill> on the current
# repo+branch. Prints nothing (and returns 0) when the key cannot be computed;
# both callers treat an empty result as "allow / do nothing", never as an error.
#
# Keyed on --git-common-dir rather than --show-toplevel so every worktree of a
# repo shares one identity, with the branch name doing the discriminating. A
# review run in a worktree therefore counts for that branch anywhere.
#
# Keyed on BRANCH, never on HEAD sha: a sha key would go stale the instant the
# review pass commits anything, re-arming the gate and looping.
quality_gate_marker() {
    local skill="$1"
    local common_dir repo_id branch slug

    common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
    [ -n "$common_dir" ] || return 0
    common_dir=$(cd "$common_dir" 2>/dev/null && pwd) || return 0

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    [ -n "$branch" ] || return 0

    repo_id=$(quality_gate_hash "$common_dir")
    [ -n "$repo_id" ] || return 0

    # Branch names carry '/' and skills carry ':' — both would create stray
    # subdirectories, so fold everything outside the safe set to '-'.
    slug=$(printf '%s-%s' "$branch" "$skill" | tr -c 'A-Za-z0-9._-' '-')

    printf '%s/%s-%s' "$(quality_gate_dir)" "$repo_id" "$slug"
}

# quality_gate_hash <string> — short stable digest. shasum ships with macOS and
# most Linux; cksum is the POSIX fallback. Prints nothing if neither exists.
quality_gate_hash() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum 2>/dev/null | cut -c1-12
    elif command -v cksum >/dev/null 2>&1; then
        printf '%s' "$1" | cksum 2>/dev/null | cut -d' ' -f1
    fi
}
