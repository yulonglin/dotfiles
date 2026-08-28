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
if grep -qE '^\s*(return 0|return)\s*$' <<<"$menu_body"; then
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
prompt_reads="$(grep -nE 'read .*"[A-Za-z_][A-Za-z_0-9]*\?' "$INSTALL_SH" "$DEPLOY_SH" || true)"
if [[ -z "$prompt_reads" ]]; then
    pass "no prompting reads at all"
else
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
        start=$(( line > 20 ? line - 20 : 1 ))
        if sed -n "${start},${line}p" "$file" | grep -q 'NON_INTERACTIVE\|-t 0'; then
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
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    if grep -q -- '-y' <<<"$hit"; then
        pass "rustup installer passes -y (${hit%%:*}:$(cut -d: -f2 <<<"$hit"))"
    else
        fail "rustup installer without -y: $hit"
    fi
done <<<"$(grep -n 'sh.rustup.rs' "$INSTALL_SH" "$HELPERS_SH" || true)"

while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    if grep -q '</dev/null' <<<"$hit"; then
        pass "brew bundle reads from /dev/null"
    else
        fail "brew bundle without </dev/null: $hit — mas' internal sudo will block on it"
    fi
done <<<"$(grep -nE '^[^#]*[^[:alnum:]_-]brew bundle ' "$INSTALL_SH" || true)"

# app-picker is a gum TUI; it must only run when someone can drive it.
echo "app-picker only runs interactively:"
picker_line="$(grep -n 'app-picker"' "$INSTALL_SH" | head -1 | cut -d: -f1)"
if [[ -n "$picker_line" ]]; then
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
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    grep -q -- '-y' <<<"$hit" || { fail "apt install without -y: $hit"; apt_missing=1; }
done <<<"$(grep -nE 'apt(-get)? install ' "$INSTALL_SH" "$DEPLOY_SH" "$HELPERS_SH" | grep -v '^\s*#' || true)"
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

echo ""
if [[ $failures -gt 0 ]]; then
    echo "$failures guard(s) failed."
    exit 1
fi
echo "All stall guards intact."
