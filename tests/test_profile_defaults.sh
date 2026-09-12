#!/usr/bin/env bash
# shellcheck shell=bash
# Asserts what the profile/flag machinery PROMISES, never what it currently
# resolves to.
#
# This file used to diff every profile against a byte-for-byte fixture in
# tests/golden/. That pinned the answer rather than the rule: adding one line to
# DEPLOY_REGISTRY drifted all seven fixtures at once, so a single new component
# ("storage" on 2026-09-01, "dotfiles-sync" on 2026-09-04) turned into 15 red
# assertions carrying one bit of information, and any DELIBERATE profile change
# was reported as a regression. The fixtures are gone.
#
# What replaces them is live-against-live: the CLI path is diffed against the
# env path, and profiles against each other. Nothing here needs a captured
# value, so the whole file is platform-independent — the old sections 1 and 1b
# had to skip on macOS because the fixtures were Linux-resolved.
#
# Usage: tests/test_profile_defaults.sh
set -uo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUMP="$DOT_DIR/tests/dump_components.zsh"
DUMP_CLI="$DOT_DIR/tests/dump_components_cli.zsh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
declare -a FAILURES=()
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1)); FAILURES+=("$1")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '%s\n' "$2" | head -12
}

# Resolved component states through the PROFILE= env var, and through real CLI
# flags. Both print one VAR=value per line, LC_ALL=C sorted.
dump() { zsh "$DUMP" "$1" "$DOT_DIR"; }
dump_cli() { zsh "$DUMP_CLI" "$DOT_DIR" "$@"; }

enabled() { grep '=true$' | sed 's/=true$//' | LC_ALL=C sort; }
enabled_of() { dump "$1" | enabled; }
enabled_count() { dump "$1" | grep -c '=true'; }
is_on() { dump "$1" | grep -qx "$2=true"; }

# Members of A that are not in B. Empty output means A is a subset of B.
# LC_ALL=C is load-bearing twice over: the inputs are byte-sorted, and comm
# compares in the ambient locale unless told otherwise. Without it, en_US.UTF-8
# collation reads a byte-sorted file as unsorted (DEPLOY_GITUI before
# DEPLOY_GIT_CONFIG) and comm reports phantom differences.
not_in() { LC_ALL=C comm -23 "$1" "$2"; }

# Every component name in either registry, as the CLI spells it (lowercase,
# dashes). Read from config.sh so the loops below cannot drift from the registry.
component_names() {
    zsh -c '
        emulate -L zsh
        export DOT_DIR="$1" DOTFILES_SKIP_LOCAL_CONFIG=1
        source "$DOT_DIR/config.sh" >/dev/null 2>&1
        for e in "${INSTALL_REGISTRY[@]}" "${DEPLOY_REGISTRY[@]}"; do print -r -- "${e%%|*}"; done
    ' _ "$DOT_DIR" 2>/dev/null | LC_ALL=C sort -u
}

# The variable names one component owns: INSTALL_<X> and/or DEPLOY_<X>, keeping
# only the ones the registries actually declare (most components live in one).
vars_of() {
    local upper
    upper="$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
    printf 'INSTALL_%s\nDEPLOY_%s\n' "$upper" "$upper" \
        | grep -Fx -f "$TMP/all-vars" | LC_ALL=C sort
}

# Variables whose value differs between two dumps.
changed_vars() {
    diff "$1" "$2" | grep -E '^[<>]' | sed -e 's/^[<>] //' -e 's/=.*//' | LC_ALL=C sort -u
}

dump_cli > "$TMP/baseline"
dump_cli | cut -d= -f1 | LC_ALL=C sort > "$TMP/all-vars"
mapfile -t COMPONENTS < <(component_names)

# ─── 1. The CLI path resolves exactly like the env path ──────────────────────

# The blind spot that let a critical regression ship green. config.sh applies
# the default profile when sourced; a CLI flag then re-applies a profile on top
# of that already-mutated state, so the two paths can disagree — and did:
# `--devbox` resolved to 14 components while `PROFILE=devbox` gave 50, because
# the `personal)` case body was empty and assumed registry defaults were still
# live. Real invocations use flags, so the flag path is the one that matters.
# Diffing the two live dumps tests that agreement without pinning either.
test_cli_flags_match_env_profiles() {
    local -a cases=(
        "--personal:personal"
        "--devbox:devbox"
        "--standard:standard"
        "--agent:agent"
        "--bare:bare"
        "--server:server"
        "--profile=cloud:cloud"
    )
    local entry flags profile diff_out
    for entry in "${cases[@]}"; do
        flags="${entry%%:*}"
        profile="${entry##*:}"
        if diff_out=$(diff <(dump "$profile") <(dump_cli "$flags") 2>&1); then
            pass "CLI '$flags' resolves exactly like profile '$profile'"
        else
            fail "CLI '$flags' disagrees with profile '$profile'" "$diff_out"
        fi
    done
    # A bare invocation (no flags at all) is the default everyone gets.
    if diff_out=$(diff <(dump standard) <(dump_cli) 2>&1); then
        pass "a bare invocation resolves to 'standard'"
    else
        fail "a bare invocation does not resolve to 'standard'" "$diff_out"
    fi
}

test_every_profile_declares_every_component() {
    # A profile that leaves a component undeclared trips `set -u` in whichever
    # deploy block reads it. Comparing the variable NAMES (never their values)
    # is what the fixtures' completeness check was actually worth.
    local profile names
    for profile in personal devbox standard agent bare server cloud minimal; do
        names=$(dump "$profile" | cut -d= -f1 | LC_ALL=C sort)
        if [[ "$names" == "$(cat "$TMP/all-vars")" ]]; then
            pass "profile '$profile' declares every registry component"
        else
            fail "profile '$profile' is missing or inventing components" \
                 "$(diff <(cat "$TMP/all-vars") <(printf '%s\n' "$names"))"
        fi
    done
}

# ─── 2. The relationships the profiles promise each other ────────────────────

test_devbox_is_personal() {
    # `devbox` is documented as a synonym; its case body delegates to personal
    # and only relabels. If it ever stops being a synonym, the docs are wrong.
    local diff_out
    if diff_out=$(diff <(dump personal) <(dump devbox) 2>&1); then
        pass "'devbox' and 'personal' are the same set"
    else
        fail "'devbox' is no longer a synonym for 'personal'" "$diff_out"
    fi
}

test_personal_is_the_full_set() {
    # personal starts from the registry defaults; every other profile is built
    # by subtracting from that or by adding to minimal. So nothing may enable a
    # component personal leaves off — that would be a component no full install
    # gets.
    local profile extra
    enabled_of personal > "$TMP/personal"
    for profile in standard agent bare server cloud minimal; do
        enabled_of "$profile" > "$TMP/other"
        extra=$(not_in "$TMP/other" "$TMP/personal")
        if [[ -z "$extra" ]]; then
            pass "profile '$profile' enables nothing 'personal' leaves off"
        else
            fail "profile '$profile' enables what 'personal' does not" "$extra"
        fi
    done
}

test_ladder_is_ordered() {
    # bare ⊂ standard ⊆ agent ⊂ devbox, as SETS. The old version compared only
    # counts, which two disjoint profiles of the same size would satisfy.
    local a b extra
    local -a rungs=(bare standard agent devbox)
    local i
    for (( i = 0; i < ${#rungs[@]} - 1; i++ )); do
        a="${rungs[i]}"; b="${rungs[i+1]}"
        enabled_of "$a" > "$TMP/lower"
        enabled_of "$b" > "$TMP/upper"
        extra=$(not_in "$TMP/lower" "$TMP/upper")
        if [[ -z "$extra" ]]; then
            pass "ladder: '$a' is a subset of '$b'"
        else
            fail "ladder broken: '$a' enables what '$b' does not" "$extra"
        fi
    done
    # And the flip itself: the default must be strictly narrower than the full set.
    local std full
    std=$(enabled_count standard); full=$(enabled_count devbox)
    if (( std < full )); then
        pass "default 'standard' ($std enabled) is strictly smaller than 'devbox' ($full)"
    else
        fail "default profile is not narrower than devbox" "standard=$std devbox=$full"
    fi
}

test_cloud_only_subtracts_from_server() {
    # cloud delegates to server and then turns things off; it never adds.
    local extra sc cc
    enabled_of cloud > "$TMP/cloud"
    enabled_of server > "$TMP/server"
    extra=$(not_in "$TMP/cloud" "$TMP/server")
    sc=$(wc -l < "$TMP/server"); cc=$(wc -l < "$TMP/cloud")
    if [[ -z "$extra" ]] && (( cc < sc )); then
        pass "'cloud' is 'server' minus something (cloud=$cc < server=$sc)"
    else
        fail "'cloud' is not a strict subset of 'server'" "extra: $extra (cloud=$cc server=$sc)"
    fi
}

# ─── 3. Flag algebra: what README.md promises about flags ────────────────────

test_minimal_disables_everything() {
    # README: "--minimal disables all defaults". `--only X` is built on it, so
    # a leak here is how `install.sh --only vim` once ran create_dev_user —
    # useradd, NOPASSWD:ALL in /etc/sudoers.d, and a copy of /root/.ssh.
    local n
    n=$(dump_cli --minimal | grep -c '=true' || true)
    if [[ "$n" == "0" ]]; then
        pass "--minimal enables nothing at all"
    else
        fail "--minimal enabled $n component(s)" "$(dump_cli --minimal | grep '=true')"
    fi

    n=$(dump_cli --only vim | grep -c '=true' || true)
    if [[ "$n" == "1" ]]; then
        pass "--only vim enables exactly the one component named"
    else
        fail "--only vim enabled $n component(s), not 1" "$(dump_cli --only vim | grep '=true')"
    fi
}

# A flag is surgical if it moves only the variables its own component owns.
# Checked from THREE baselines, because a bleed is invisible against a baseline
# that already holds the value being bled. Measured: with only the default
# baseline, a deliberate `--no-<anything>` that also sets DEPLOY_ZED=false went
# undetected, because `standard` leaves zed off anyway. `--devbox` (nearly all
# on) exposes a bleed to false, `--minimal` (all off) exposes a bleed to true,
# and the bare default is the invocation people actually type.
BASELINES=("" "--devbox" "--minimal")

check_surgical() {   # $1 = flag prefix ("--no-" or "--"), $2 = expected value
    local prefix="$1" want="$2" comp base label bad="" v
    for base in "${BASELINES[@]}"; do
        label="${base:-<default>}"
        # shellcheck disable=SC2086  # $base is one flag or empty, deliberately split
        dump_cli $base > "$TMP/base"
        for comp in "${COMPONENTS[@]}"; do
            # shellcheck disable=SC2086
            dump_cli $base "${prefix}${comp}" > "$TMP/variant"
            vars_of "$comp" > "$TMP/owned"
            # Every variable that moved must belong to this component…
            while read -r v; do
                [[ -z "$v" ]] && continue
                grep -qFx "$v" "$TMP/owned" || bad+="$label ${prefix}${comp} moved $v; "
            done < <(changed_vars "$TMP/base" "$TMP/variant")
            # …and the component's own variables must have landed on $want.
            while read -r v; do
                [[ -z "$v" ]] && continue
                grep -qx "$v=$want" "$TMP/variant" || bad+="$label ${prefix}${comp} left $v not $want; "
            done < "$TMP/owned"
        done
    done
    printf '%s' "$bad"
}

test_no_flag_disables_exactly_one_component() {
    # README: flags are additive to the defaults. `--no-X` therefore has to be
    # surgical — it may turn X off and touch nothing else. Untested until now,
    # and the whole reason the additive promise is safe to rely on.
    local bad
    bad=$(check_surgical "--no-" false)
    if [[ -z "$bad" ]]; then
        pass "--no-<component> disables exactly that component (${#COMPONENTS[@]} components x ${#BASELINES[@]} baselines)"
    else
        fail "--no-<component> is not surgical" "$bad"
    fi
}

test_component_flag_enables_exactly_one_component() {
    # The mirror: `--X` adds X to whatever is already selected, and subtracts
    # nothing. This is the "additive" in "flags are ADDITIVE to defaults".
    local bad
    bad=$(check_surgical "--" true)
    if [[ -z "$bad" ]]; then
        pass "--<component> enables exactly that component (${#COMPONENTS[@]} components x ${#BASELINES[@]} baselines)"
    else
        fail "--<component> is not surgical" "$bad"
    fi
}

test_minimal_plus_one_flag_is_one_component() {
    # The documented recipe: "--minimal disables all defaults, then specify only
    # what you want" (README). Composing the two must give exactly what you named.
    local comp bad="" got want
    for comp in "${COMPONENTS[@]}"; do
        got=$(dump_cli --minimal "--$comp" | enabled)
        want=$(vars_of "$comp")
        [[ "$got" == "$want" ]] || bad+="--minimal --$comp gave [${got//$'\n'/ }] want [${want//$'\n'/ }]; "
    done
    if [[ -z "$bad" ]]; then
        pass "--minimal --<component> enables exactly that component, for all ${#COMPONENTS[@]} of them"
    else
        fail "--minimal --<component> does not resolve to one component" "$bad"
    fi
}

test_modifiers_change_no_components() {
    # --append, --ascii and --force are modifiers, not components: CLAUDE.md
    # says they "don't affect defaults". --ascii in particular now writes a
    # per-machine config/start.txt, so it must not perturb the component set.
    local -a mods=("--append" "--ascii=cat" "--ascii=none" "--force" "--force-reinstall")
    local m diff_out
    for m in "${mods[@]}"; do
        if diff_out=$(diff "$TMP/baseline" <(dump_cli "$m") 2>&1); then
            pass "modifier '$m' changes no component"
        else
            fail "modifier '$m' changed the component set" "$diff_out"
        fi
    done
    # Together, and on top of a profile flag rather than the default.
    if diff_out=$(diff <(dump_cli --server) <(dump_cli --server --append --ascii=dog --force) 2>&1); then
        pass "modifiers stacked on '--server' change no component"
    else
        fail "stacked modifiers changed the component set" "$diff_out"
    fi
}

# ─── 4. Safety invariants that no profile may break ──────────────────────────

test_defenses_are_never_opt_in() {
    # A defense you must remember to enable is not a defense. Every profile that
    # deploys any config at all must carry the secret-scan hook and the
    # package-manager quarantine.
    for profile in standard agent devbox; do
        if is_on "$profile" DEPLOY_GIT_HOOKS && is_on "$profile" DEPLOY_PKG_CONFIGS; then
            pass "profile '$profile' keeps git-hooks + pkg-configs enabled"
        else
            fail "profile '$profile' makes a security defense opt-in" \
                 "git-hooks and pkg-configs must be on"
        fi
    done
}

test_no_scheduled_jobs_in_ephemeral_profiles() {
    # Nothing on a throwaway box should install launchd/cron jobs.
    local scheduled=(DEPLOY_CLEANUP DEPLOY_CLAUDE_CLEANUP DEPLOY_AI_UPDATE
                     DEPLOY_BREW_UPDATE DEPLOY_USAGE_PING DEPLOY_TMUX_RESUME
                     DEPLOY_MCP_SYNC DEPLOY_DEP_AUDIT DEPLOY_STALE_CLAIMS
                     DEPLOY_SECRETS DEPLOY_DOTFILES_SYNC)
    for profile in standard agent bare; do
        local bad=""
        for var in "${scheduled[@]}"; do
            is_on "$profile" "$var" && bad+="$var "
        done
        if [[ -z "$bad" ]]; then
            pass "profile '$profile' schedules no background jobs"
        else
            fail "profile '$profile' schedules background jobs" "$bad"
        fi
    done
}

test_agent_can_actually_code() {
    # The profile exists to run Claude Code with per-project secrets.
    local need=(INSTALL_AI_TOOLS DEPLOY_CLAUDE DEPLOY_CODEX DEPLOY_TMUX
                DEPLOY_GIT_CONFIG DEPLOY_SECRETS_ENV DEPLOY_BWS)
    local missing=""
    for var in "${need[@]}"; do
        is_on agent "$var" || missing+="$var "
    done
    if [[ -z "$missing" ]]; then
        pass "profile 'agent' carries what coding on a throwaway box needs"
    else
        fail "profile 'agent' is missing coding essentials" "$missing"
    fi
}

test_bare_installs_no_ai_tools() {
    if ! is_on bare INSTALL_AI_TOOLS && ! is_on bare DEPLOY_CLAUDE; then
        pass "profile 'bare' installs no AI tooling"
    else
        fail "profile 'bare' pulls in AI tooling" "it is the no-coding profile"
    fi
}

test_unknown_profile_fails_closed() {
    # It used to warn and fall back to `personal`, so `--profile=servre`
    # resolved to the FULL 50-component devbox install and exited 0 — a typo
    # meant for a shared server produced the most invasive setup available,
    # with one warning line as the only signal. It must now refuse.
    local out
    out=$(zsh -c "
        DOT_DIR='$DOT_DIR'; PROFILE=not-a-profile
        source '$DOT_DIR/config.sh'
    " 2>&1 >/dev/null)
    if [[ "$out" == *"Unknown profile"* ]]; then
        pass "an unknown profile says so instead of being silent"
    else
        fail "unknown profile is silent" "$out"
    fi

    # And says so by refusing, not by installing everything.
    local n
    n=$(dump_cli --profile=servre 2>/dev/null | grep -c '=true' || true)
    if [[ "$n" == "0" ]]; then
        pass "a misspelled profile enables nothing (fails closed)"
    else
        fail "a misspelled profile resolved to $n components" \
             "$(dump_cli --profile=servre 2>/dev/null | grep '=true' | head -5)"
    fi
}

test_minimal_overrides_local_config_positives() {
    # config.local.sh sits after the profile in the precedence chain, so
    # re-applying it inside apply_profile (needed so `--server` cannot
    # resurrect a component the machine disabled) also let a POSITIVE local
    # override survive `--minimal`, which promises to suppress everything.
    # Measured before the guard: --minimal left MCP=true OBSIDIAN=true.
    local local_cfg="$DOT_DIR/config.local.sh"
    if [[ -e "$local_cfg" ]]; then
        echo "  SKIP minimal-vs-local (a real config.local.sh exists)"
        return
    fi
    printf 'DEPLOY_MCP_SYNC=true\nDEPLOY_OBSIDIAN_SYNC=true\n' > "$local_cfg"
    local out
    out=$(zsh -c '
        emulate -L zsh; set -uo pipefail
        export DOT_DIR="$1"
        source "$DOT_DIR/config.sh" >/dev/null 2>&1
        source "$DOT_DIR/scripts/shared/helpers.sh" >/dev/null 2>&1
        show_help() { : }
        parse_args --minimal >/dev/null 2>&1
        print "$DEPLOY_MCP_SYNC $DEPLOY_OBSIDIAN_SYNC"
    ' _ "$DOT_DIR" 2>/dev/null || true)
    rm -f "$local_cfg"
    if [[ "$out" == "false false" ]]; then
        pass "--minimal suppresses even a positive config.local.sh override"
    else
        fail "--minimal left locally-enabled components on" "got: $out"
    fi
}

test_explicit_flag_beats_platform_override() {
    # Platform facts outrank the profile; they must NOT outrank the user. The
    # overrides run last, so without an exemption they silently reverse the
    # flag the user just typed.
    local out
    out=$(dump_cli --devbox --no-create-user | grep CREATE_USER || true)
    if [[ "$out" == *"=false" ]]; then
        pass "--no-create-user survives the end-of-profile platform overrides"
    else
        fail "--no-create-user was reversed by a platform override" "$out"
    fi

    out=$(dump_cli --no-create-user --minimal | grep CREATE_USER || true)
    if [[ "$out" == *"=false" ]]; then
        pass "--no-create-user holds even when a later flag resets the profile"
    else
        fail "--no-create-user lost to a later profile reset" "$out"
    fi
}

test_local_config_survives_a_profile_flag() {
    # Documented precedence is profile -> config.local.sh -> CLI flags. A
    # profile flag re-runs apply_profile, which resets the registry; without
    # re-applying local config that reset discards the machine's own opt-outs.
    # obsidian-sync is the component this repo lost 135 files to, so
    # resurrecting it is the direction that costs data.
    local local_cfg="$DOT_DIR/config.local.sh"
    if [[ -e "$local_cfg" ]]; then
        echo "  SKIP config.local.sh precedence (a real one exists; not overwriting)"
        return
    fi
    printf 'DEPLOY_OBSIDIAN_SYNC=false\n' > "$local_cfg"
    local out
    out=$(zsh -c '
        emulate -L zsh; set -uo pipefail
        export DOT_DIR="$1"
        source "$DOT_DIR/config.sh" >/dev/null 2>&1
        source "$DOT_DIR/scripts/shared/helpers.sh" >/dev/null 2>&1
        show_help() { : }
        parse_args --server >/dev/null 2>&1
        print -r -- "DEPLOY_OBSIDIAN_SYNC=$DEPLOY_OBSIDIAN_SYNC"
    ' _ "$DOT_DIR" 2>/dev/null || true)
    rm -f "$local_cfg"
    if [[ "$out" == *"=false" ]]; then
        pass "config.local.sh opt-out survives a profile flag"
    else
        fail "a profile flag resurrected a component config.local.sh disabled" "$out"
    fi
}

# ─── Run ─────────────────────────────────────────────────────────────────────

echo "Profile defaults — invariants of the profile and flag machinery"
echo ""
echo "1. The CLI path agrees with the env path"
test_cli_flags_match_env_profiles
test_every_profile_declares_every_component
echo ""
echo "2. Relationships between profiles"
test_devbox_is_personal
test_personal_is_the_full_set
test_ladder_is_ordered
test_cloud_only_subtracts_from_server
echo ""
echo "3. Flag algebra"
test_minimal_disables_everything
test_no_flag_disables_exactly_one_component
test_component_flag_enables_exactly_one_component
test_minimal_plus_one_flag_is_one_component
test_modifiers_change_no_components
echo ""
echo "4. Safety invariants"
test_defenses_are_never_opt_in
test_no_scheduled_jobs_in_ephemeral_profiles
test_agent_can_actually_code
test_bare_installs_no_ai_tools
test_unknown_profile_fails_closed
test_minimal_overrides_local_config_positives
test_explicit_flag_beats_platform_override
test_local_config_survives_a_profile_flag

echo ""
echo "─────────────────────────────────────────"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf 'failures:\n'
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    exit 1
fi
exit 0
