#!/usr/bin/env bash
# Pins the guards that keep install.sh / deploy.sh hands-off.
#
# tests/test_install_deploy_no_stall.py proves the scripts terminate today by
# running them. This file is the cheap companion: it names each specific guard
# that makes that true, so a regression is reported as "you removed the TTY
# check on the component menu" instead of as a 240-second timeout in CI.
#
# Every assertion here is about *not prompting*. A prompt in an unattended run
# is not a failure — it is a hang, which is worse, because it looks like work.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
DEPLOY_SH="$REPO_ROOT/deploy.sh"
HELPERS_SH="$REPO_ROOT/scripts/shared/helpers.sh"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "  ok   $*"; }

# Every assertion below is driven by a grep. A grep that suddenly matches
# nothing — because the code moved, was renamed, or was deleted — would make a
# `while read` loop run zero times and report a confident pass over an empty
# set. Route every such search through here so a vanished target fails loudly
# instead of silently blessing whatever replaced it.
# Returns 1 and prints nothing when the search comes up empty; the CALLER
# reports it. It must not call fail() itself: every call site captures its
# output with $(...), which is a subshell, so an increment to `failures` there
# would be discarded and the suite would exit 0 with the message printed. That
# is the same silent-pass bug this helper exists to prevent.
# Usage: hits="$(require_hits <grep args...>)" || fail "found no X to check…"
require_hits() {
    local out
    out="$(grep "$@" || true)"
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}

# Wraps the pattern above so each call site is one line.
# Usage: hits="$(hits_or_fail <description> <grep args...>)"
missing_target() {
    fail "found no $1 to check — has it been renamed, moved or removed? (without this check the guard below would pass over an empty set)"
}

# ── The component menu is the only prompt either script has ──────────────────
# It must bow out when there is nobody to answer: no TTY (cron, CI, a Docker
# build) or an explicit --non-interactive.
echo "Component menu bows out when unattended:"
menu_body="$(awk '/^show_component_menu\(\)/,/^}/' "$HELPERS_SH")"
if grep -q 'NON_INTERACTIVE' <<<"$menu_body" && grep -q '\-t 0' <<<"$menu_body"; then
    pass "show_component_menu checks both NON_INTERACTIVE and -t 0"
else
    fail "show_component_menu no longer skips on NON_INTERACTIVE and/or a missing TTY — an unattended run will hang on the TUI"
fi
if grep -qE '^[[:space:]]*return( 0)?[[:space:]]*$' <<<"$menu_body"; then
    pass "show_component_menu has an early return"
else
    fail "show_component_menu lost its early return"
fi

# ── sudo is cached up front, and only where a password can be typed ──────────
echo "sudo caching only happens on a TTY:"
sudo_body="$(awk '/^front_load_sudo\(\)/,/^}/' "$HELPERS_SH")"
if grep -q '\[\[ -t 0 \]\] || return 0' <<<"$sudo_body"; then
    pass "front_load_sudo returns immediately without a TTY"
else
    fail "front_load_sudo no longer returns early without a TTY — 'sudo -v' will block or abort in CI"
fi
# The TTY check alone is NOT enough, and this assertion used to pin only that —
# blessing the bug. On a real terminal --non-interactive still reached 'sudo -v'
# and waited forever for a password.
if grep -q 'NON_INTERACTIVE' <<<"$sudo_body"; then
    pass "front_load_sudo also honours --non-interactive"
else
    fail "front_load_sudo ignores NON_INTERACTIVE — on a TTY, --non-interactive will still stop at a sudo password prompt"
fi
if grep -q 'sudo -n true' <<<"$sudo_body"; then
    pass "front_load_sudo short-circuits when sudo is already cached"
else
    fail "front_load_sudo lost its 'sudo -n true' fast path"
fi

# ── --non-interactive must exist and reach child processes ───────────────────
echo "--non-interactive is wired up:"
if grep -q -- '--non-interactive)' "$HELPERS_SH" \
   && awk '/--non-interactive\)/,/;;/' "$HELPERS_SH" | grep -q 'export NON_INTERACTIVE'; then
    pass "parse_args sets and exports NON_INTERACTIVE"
else
    fail "parse_args no longer exports NON_INTERACTIVE — child processes (app-picker, cleanup/install.sh) will prompt"
fi
for f in "$INSTALL_SH" "$DEPLOY_SH"; do
    if grep -q -- '--non-interactive' "$f"; then
        pass "$(basename "$f") documents --non-interactive"
    else
        fail "$(basename "$f") no longer mentions --non-interactive"
    fi
done

# ── Every prompting read is guarded ──────────────────────────────────────────
# zsh's prompting form is `read -r "var?prompt"`. Each one must sit behind a
# NON_INTERACTIVE / TTY check, with a default chosen for the unattended case.
echo "Interactive reads are guarded:"
# Covers zsh's `read -r "var?prompt"`, the single-quoted form, and the bare
# `read "?prompt"` that reads into $REPLY.
prompt_reads="$(grep -nE 'read [^|]*["'"'"'][A-Za-z_0-9]*\?' "$INSTALL_SH" "$DEPLOY_SH" || true)"
if [[ -z "$prompt_reads" ]]; then
    pass "no prompting reads at all"
else
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
        start=$(( line > 20 ? line - 20 : 1 ))
        # Strip comments first: a comment *mentioning* NON_INTERACTIVE is not a
        # guard, and without this the check passes on a prompt with none.
        if sed -n "${start},${line}p" "$file" | sed 's/#.*//' | grep -q 'NON_INTERACTIVE\|-t 0'; then
            pass "$(basename "$file"):$line prompt is behind a guard"
        else
            fail "$(basename "$file"):$line prompts for input with no NON_INTERACTIVE / TTY guard above it"
        fi
    done <<<"$prompt_reads"
fi

# ── Third-party installers get their own non-interactive flags ───────────────
# These prompt by default and do not honour ours.
echo "Vendored installers are told not to prompt:"
if grep -q 'NONINTERACTIVE=1 /bin/bash -c .*Homebrew/install' "$INSTALL_SH"; then
    pass "Homebrew installer runs with NONINTERACTIVE=1"
else
    fail "the Homebrew installer lost NONINTERACTIVE=1 — it blocks on 'Press RETURN to continue' on a fresh Mac"
fi
rustup_hits="$(require_hits -n 'sh.rustup.rs' "$INSTALL_SH" "$HELPERS_SH")" \
    || missing_target "rustup installer invocation"
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    if grep -qE -- '(^|[[:space:]])-y([[:space:]]|$)' <<<"$hit"; then
        pass "rustup installer passes -y (${hit%%:*}:$(cut -d: -f2 <<<"$hit"))"
    else
        fail "rustup installer without -y: $hit"
    fi
done <<<"$rustup_hits"

brew_hits="$(require_hits -nE '^[^#]*[^[:alnum:]_-]brew bundle ' "$INSTALL_SH")" \
    || missing_target "brew bundle invocation"
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    if grep -q '</dev/null' <<<"$hit"; then
        pass "brew bundle reads from /dev/null"
    else
        fail "brew bundle without </dev/null: $hit — mas' internal sudo will block on it"
    fi
done <<<"$brew_hits"

# app-picker is a gum TUI; it must only run when someone can drive it.
echo "app-picker only runs interactively:"
picker_line="$(grep -n 'app-picker"' "$INSTALL_SH" | head -1 | cut -d: -f1)"
if [[ -z "$picker_line" ]]; then
    fail "found no app-picker invocation to check — has it been renamed or removed?"
else
    start=$(( picker_line > 15 ? picker_line - 15 : 1 ))
    if sed -n "${start},${picker_line}p" "$INSTALL_SH" | grep -q 'NON_INTERACTIVE\|-t 0'; then
        pass "app-picker invocation is behind a NON_INTERACTIVE / TTY guard"
    else
        fail "app-picker (a gum TUI) is invoked without an interactivity guard"
    fi
fi

# ── Package managers never ask for confirmation ──────────────────────────────
echo "Package installs are non-interactive:"
apt_missing=0
apt_hits="$(require_hits -nE 'apt(-get)? install ' "$INSTALL_SH" "$DEPLOY_SH" "$HELPERS_SH")" \
    || { missing_target "apt/apt-get install invocation"; apt_missing=1; }
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    # Drop commented-out examples. The old filter was '^\s*#', which never
    # matched: grep -n output always begins "path:lineno:".
    [[ "$hit" =~ ^[^:]*:[0-9]+:[[:space:]]*# ]] && continue
    # A whole word, not a substring: '-y' alone also matches "python3-yaml".
    grep -qE -- '(^|[[:space:]])(-y|--yes|--assume-yes)([[:space:]]|$)' <<<"$hit" \
        || { fail "apt install without -y: $hit"; apt_missing=1; }
done <<<"$apt_hits"
[[ $apt_missing -eq 0 ]] && pass "every apt/apt-get install passes -y"

# ── Best-effort probes must not abort the run ────────────────────────────────
# `set -euo pipefail` turns a probe for a tool that is simply absent into a
# hard exit, which skips every component below it. Each of these had exactly
# that bug; the `|| true` is what keeps the fallback on the next line reachable.
echo "Optional-tool probes cannot abort the run:"
probe_guard() { # file, pattern, description
    if grep -qE "$2" "$1"; then
        pass "$3"
    else
        fail "$3 — lost its '|| true'; a missing tool will abort the whole run under 'set -euo pipefail'"
    fi
}
probe_guard "$DEPLOY_SH"  'BWS_INSTALLED_VERSION=.*\|\| true' \
    "deploy.sh: bws version probe tolerates bws being absent"
probe_guard "$DEPLOY_SH"  'loginctl enable-linger .*\|\| true' \
    "deploy.sh: loginctl enable-linger tolerates a box without logind"
probe_guard "$HELPERS_SH" 'r\[.lts.\]\)\[1:\]\.split.*\|\| true' \
    "helpers.sh: Node LTS lookup tolerates no network"

# `$SUDO` as a scalar cannot hold "sudo -E" in zsh (no word splitting) and
# vanishes entirely as root, which left a bare `-E` as the command name.
echo "Privilege escalation composes as root:"
if grep -q 'local -a SUDO=()' "$HELPERS_SH" && ! grep -qE '\$SUDO -E' "$HELPERS_SH"; then
    pass "install_node builds its sudo prefix as an array"
else
    fail "install_node uses a scalar \$SUDO with -E — running as root this becomes the command '-E'"
fi

# ── Credential prompts that are not sudo's own ───────────────────────────────
# chsh authenticates through PAM on stdin, so a bare call blocks in an
# unattended run even where sudo is already cached.
echo "Shell change does not open a PAM prompt:"
if grep -qE '^[[:space:]]*sudo chsh ' "$HELPERS_SH" && ! grep -qE '^[[:space:]]*chsh -s' "$HELPERS_SH"; then
    pass "set_zsh_default changes the shell via sudo, not a bare chsh"
else
    fail "set_zsh_default calls chsh directly — it will block on a PAM password prompt with nobody to answer"
fi

# The App Store credential prewarm had the same TTY-only guard as front_load_sudo.
echo "App Store credential prewarm is skippable:"
mas_ctx="$(require_hits -B3 "App Store installs (mas) need sudo" "$INSTALL_SH")" \
    || missing_target "mas sudo prewarm"
if [[ -n "$mas_ctx" ]] && sed 's/#.*//' <<<"$mas_ctx" | grep -q 'NON_INTERACTIVE'; then
    pass "mas sudo prewarm is behind a NON_INTERACTIVE guard"
else
    fail "the mas sudo prewarm is TTY-guarded only — --non-interactive on a terminal will stop at a password prompt"
fi

echo ""
if [[ $failures -gt 0 ]]; then
    echo "$failures guard(s) failed."
    exit 1
fi
echo "All stall guards intact."
