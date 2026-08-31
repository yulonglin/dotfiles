#!/bin/bash
# Weekly staleness audit — re-verifies the dated factual claims in the auto-loaded
# instruction tier (claude/CLAUDE.md, claude/rules/*.md, repo CLAUDE.md).
#
# Every claim here corresponds to a dated line in one of those files. When a check
# reports DRIFT, fix the file by REMOVING the claim, not by updating the number —
# a claim that needs periodic updating does not belong in an auto-loaded file.
#
# Exit 0 = all checks OK or SKIP. Exit 1 = at least one DRIFT (matches
# scripts/security/audit_dependencies.sh, whose weekly wiring this mirrors).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/.." && cd .. && pwd)"
REPORT_DIR="${STALE_CLAIMS_REPORT_DIR:-$HOME/.local/share/stale-claims}"
REPORT_FILE="$REPORT_DIR/report-$(date +%Y%m%d).txt"

# Under cron/launchd we inherit the scheduler's minimal PATH, not the interactive
# one. That silently picks the wrong binary — system fzf 0.44 instead of the
# deployed 0.71 — or finds none at all, so the audit reports DRIFT/SKIP for a
# claim that is actually fine. A weekly false alarm is how an audit gets ignored.
# Listed LOWEST-priority first: each is prepended, so the last one processed ends
# up leftmost. Reversing this list silently inverts the precedence -- a stale
# /usr/local/bin/fzf would then outrank the mise shim and reproduce the exact
# false DRIFT this block exists to prevent.
for _d in /usr/local/bin /opt/homebrew/bin "$HOME/.cargo/bin" \
          "$HOME/.local/share/mise/shims" "$HOME/.local/bin"; do
    [[ -d "$_d" ]] || continue
    case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH

# Fail loudly rather than run to a green exit that wrote nothing. Under weekly
# cron an unwritable report dir (sandbox, read-only $HOME) would otherwise look
# identical to a clean audit.
if ! mkdir -p "$REPORT_DIR" 2>/dev/null || ! : >>"$REPORT_FILE"; then
    echo "stale-claims: cannot write report to $REPORT_FILE — refusing to run a silent audit." >&2
    echo "stale-claims: set STALE_CLAIMS_REPORT_DIR to a writable path." >&2
    exit 2
fi

drift_found=0
drifted=()

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$REPORT_FILE"; }

# ok/skip/drift <claim-location> <message>
ok()   { log "  OK    $1 — $2"; }
skip() { log "  SKIP  $1 — $2 (not verifiable here)"; }
drift() {
    log "  DRIFT $1 — $2"
    drifted+=("$1")
    drift_found=$((drift_found + 1))
}

log "=== Stale Claims Audit $(date) ==="

# Resolve a symlink chain. BSD readlink has no -f, so on stock macOS the bare
# `readlink -f` this used to call fails and every Claude-binary check logs SKIP.
resolve_link() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$1" 2>/dev/null
    elif readlink -f / >/dev/null 2>&1; then
        readlink -f "$1" 2>/dev/null
    else
        python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null
    fi
}

# Resolve the installed Claude Code binary. `command -v claude` is a shell alias in
# this setup and resolves to the dotfiles directory, so go to the versions dir.
claude_binary() {
    local launcher="$HOME/.local/bin/claude" real
    [[ -x "$launcher" ]] || return 1
    real="$(resolve_link "$launcher")"
    [[ -n "$real" && -f "$real" ]] || return 1
    printf '%s' "$real"
}

# Compare dotted versions without GNU `sort -V`, which BSD/macOS sort lacks —
# there it exits non-zero and a perfectly current fzf gets reported as below the
# floor. Returns 0 when $1 >= $2.
ver_ge() {
    local IFS=. i x y
    # shellcheck disable=SC2206  # deliberate word-split on IFS=.
    local a=($1) b=($2)
    for ((i = 0; i < ${#b[@]}; i++)); do
        x="${a[i]:-0}"; x="${x//[!0-9]/}"
        y="${b[i]:-0}"; y="${y//[!0-9]/}"
        ((10#${x:-0} > 10#${y:-0})) && return 0
        ((10#${x:-0} < 10#${y:-0})) && return 1
    done
    return 0
}

# Count literal occurrences of a pattern in a (large, binary) file.
# rg exits 1 for "no match" and >=2 for a real error (missing binary, unreadable
# file). Collapsing both to 0 made a broken audit indistinguishable from a clean
# one — the caller would report OK/DRIFT having measured nothing. Fail instead.
count_in() {
    local out rc
    out="$(rg -aoc "$1" "$2" 2>/dev/null)"; rc=$?
    case "$rc" in
        0) printf '%s' "$out" ;;
        1) printf '0' ;;
        *) return 1 ;;
    esac
}

# --- claude/CLAUDE.md: "Tasks — per-project not yet supported (as of 2026-07-27)"
check_tasks_directory() {
    local loc="claude/CLAUDE.md: per-project tasks unsupported" bin n
    if ! bin="$(claude_binary)"; then
        skip "$loc" "Claude Code binary not found"
        return
    fi
    if ! n="$(count_in 'tasksDirectory' "$bin")"; then
        skip "$loc" "ripgrep could not scan $(basename "$bin")"
        return
    fi
    if [[ "$n" -gt 0 ]]; then
        drift "$loc" "tasksDirectory now appears in the binary ($n hits) — the claim is obsolete"
    else
        ok "$loc" "tasksDirectory still absent from $(basename "$bin")"
    fi
}

# --- claude/rules/delegation.md: the 500-line bar is ours, not the harness's
check_read_threshold() {
    local loc="claude/rules/delegation.md: 500-line bar is convention" bin n
    if ! bin="$(claude_binary)"; then
        skip "$loc" "Claude Code binary not found"
        return
    fi
    if ! n="$(count_in 'READ_THRESHOLD' "$bin")"; then
        skip "$loc" "ripgrep could not scan $(basename "$bin")"
        return
    fi
    if [[ "$n" -gt 0 ]]; then
        drift "$loc" "a READ_THRESHOLD env var now exists ($n hits) — the bar may be configurable again"
    else
        ok "$loc" "no READ_THRESHOLD env var in the harness"
    fi
}

# --- claude/rules/delegation.md: the Fable channel's model family exists
check_fable_model() {
    local loc="claude/rules/delegation.md: Fable family available" bin n
    if ! bin="$(claude_binary)"; then
        skip "$loc" "Claude Code binary not found"
        return
    fi
    if ! n="$(count_in 'claude-fable-5' "$bin")"; then
        skip "$loc" "ripgrep could not scan $(basename "$bin")"
        return
    fi
    if [[ "$n" -gt 0 ]]; then
        ok "$loc" "claude-fable-5 present ($n hits)"
    else
        drift "$loc" "claude-fable-5 gone — drop the Fable channel from the rule (codex-companion may still stand); do not rename the model"
    fi
}

# --- claude/rules/safety.md: UV_MALWARE_CHECK, lockfile-only, undocumented
check_uv_malware() {
    local loc="claude/rules/safety.md: UV_MALWARE_CHECK" uv n
    if ! uv="$(command -v uv)"; then
        skip "$loc" "uv not installed"
        return
    fi
    if ! n="$(count_in 'UV_MALWARE_CHECK' "$uv")"; then
        skip "$loc" "ripgrep could not scan $(basename "$uv")"
        return
    fi
    if [[ "$n" -eq 0 ]]; then
        drift "$loc" "UV_MALWARE_CHECK absent from $(uv --version) — the guard may have been renamed or removed"
        return
    fi
    if uv help 2>/dev/null | rg -q 'UV_MALWARE_CHECK'; then
        drift "$loc" "UV_MALWARE_CHECK is now documented in \`uv help\` — re-read the docs for its real coverage"
    else
        ok "$loc" "present in the binary ($n hits), still undocumented in \`uv help\`"
    fi
}

# --- claude/rules/coding-conventions.md: ty is beta as of 2026-07-27
check_ty_beta() {
    local loc="claude/rules/coding-conventions.md: ty is beta" json status
    if ! command -v curl >/dev/null 2>&1; then
        skip "$loc" "curl not available"
        return
    fi
    json="$(curl -fsS --max-time 15 https://pypi.org/pypi/ty/json 2>/dev/null)" || {
        skip "$loc" "PyPI unreachable"
        return
    }
    status="$(printf '%s' "$json" | python3 -c \
        "import json,sys; print(next((c for c in json.load(sys.stdin)['info']['classifiers'] if 'Development Status' in c), 'unknown'))" 2>/dev/null)"
    case "$status" in
        *Beta*) ok "$loc" "PyPI classifier: $status" ;;
        unknown|"") skip "$loc" "could not read the PyPI classifier" ;;
        *) drift "$loc" "PyPI classifier is now '$status' — drop the beta caveat" ;;
    esac
}

# --- claude/rules/coding-conventions.md: fzf >=0.54 for `load:pos(N)+select`
check_fzf_version() {
    local loc="claude/rules/coding-conventions.md: fzf >=0.54" ver
    if ! command -v fzf >/dev/null 2>&1; then
        skip "$loc" "fzf not installed"
        return
    fi
    ver="$(fzf --version 2>/dev/null | awk '{print $1}')"
    if [[ -z "$ver" ]]; then
        skip "$loc" "could not read \`fzf --version\`"
        return
    fi
    if ver_ge "$ver" 0.54; then
        ok "$loc" "installed fzf $ver meets the floor"
    else
        drift "$loc" "installed fzf $ver is below 0.54 — the documented binding will not work here"
    fi
}

# --- CLAUDE.md: the context profiles named as examples actually exist
# --- plugin manifest: the seven retired plugins carry `false` tombstones, every other
# --- entry is `true`. The tombstones are load-bearing — a marketplace declaration is
# --- not the enable gate, so a retired plugin with a surviving install record keeps
# --- loading unless enabledPlugins says false. See docs/plugin-management.md.
check_plugin_manifest() {
    local loc="claude/settings.json: enabledPlugins tombstone manifest" json result
    json="$DOT_DIR/claude/settings.json"
    if [[ ! -f "$json" ]]; then
        skip "$loc" "settings.json not found"
        return
    fi
    result=$(python3 -c '
import json, sys
RETIRED = {
    "code@ai-safety-plugins", "core@ai-safety-plugins", "research@ai-safety-plugins",
    "viz@ai-safety-plugins", "workflow@ai-safety-plugins", "writing@ai-safety-plugins",
    "dev-browser@dev-browser-marketplace",
}
d = json.load(open(sys.argv[1])).get("enabledPlugins", {})
problems = []
missing = sorted(k for k in RETIRED if k not in d)
if missing:
    problems.append("retired plugin lost its false tombstone: " + " ".join(missing))
live = sorted(k for k in RETIRED if k in d and d[k] is not False)
if live:
    problems.append("retired plugin not set to false: " + " ".join(live))
bad = sorted(k for k, v in d.items() if k not in RETIRED and v is not True)
if bad:
    problems.append("non-retired entry is not true: " + " ".join(bad))
print("; ".join(problems))
' "$json" 2>/dev/null) || { skip "$loc" "could not parse settings.json"; return; }
    if [[ -z "$result" ]]; then
        ok "$loc" "seven retired plugins tombstoned false, every other entry true"
    else
        drift "$loc" "$result"
    fi
}

# --- claude/rules/experiments.md: `clean-skill-dupes` still resolves
check_clean_skill_dupes() {
    local loc="claude/rules/experiments.md: clean-skill-dupes" target
    target="$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"
    if [[ -x "$target" ]]; then
        ok "$loc" "alias target present"
    else
        drift "$loc" "$target is missing — the remedy no longer exists"
    fi
}

# --- Counts must never be asserted in the auto-loaded tier (spec R10, AC9).
# A lint, not a fact check: it catches count-shaped claims being (re-)introduced.
# Deliberately narrow — it targets counts of things that change WITHOUT anyone
# touching the file (inventory sizes, a file's line count). Numeric thresholds
# that are policy ("files >500 lines", "past ~50 lines") are rules, not counts,
# and must not be flagged; a missed catch is cheaper than a lint nobody trusts.
check_no_counts() {
    local loc="auto-loaded tier: no hardcoded counts" targets hits inventory sizes
    targets=("$DOT_DIR/claude/CLAUDE.md" "$DOT_DIR/CLAUDE.md" "$DOT_DIR/claude/rules")

    # Inventory counts: "18 plugins", "12 rules", "7 skills".
    inventory="$(rg -n '\b[0-9]+ (plugins|rules|docs|skills|agents|profiles|hooks)\b' \
        "${targets[@]}" 2>/dev/null || true)"
    # A file's own current size: "slim ~120 lines". The qualifier is what separates
    # a description of the artifact from a threshold ("past ~50 lines").
    sizes="$(rg -n '\b(slim|currently|now|about|roughly|approximately|around) ~?[0-9]+ lines' \
        "${targets[@]}" 2>/dev/null || true)"

    hits="$(printf '%s\n%s' "$inventory" "$sizes" | rg -v '^$' || true)"
    if [[ -z "$hits" ]]; then
        ok "$loc" "no count-shaped claims"
    else
        drift "$loc" "count-shaped claims found (name the thing and the command that counts it, don't state a number):"$'\n'"$hits"
    fi
}

check_tasks_directory
check_read_threshold
check_fable_model
check_uv_malware
check_ty_beta
check_fzf_version
check_plugin_manifest
check_clean_skill_dupes
check_no_counts

log "=== Audit complete: $drift_found drifted claim(s) ==="

if [[ $drift_found -gt 0 ]]; then
    log "Review: $REPORT_FILE"
    notif_msg="$drift_found stale claim(s): ${drifted[0]}"
    [[ $drift_found -gt 1 ]] && notif_msg="$notif_msg +$((drift_found - 1)) more"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v terminal-notifier &>/dev/null; then
            terminal-notifier -title "Stale Claims Audit" -message "$notif_msg" \
                -open "file://$REPORT_FILE" 2>/dev/null || true
        else
            osascript -e "display notification \"$notif_msg\" with title \"Stale Claims Audit\"" 2>/dev/null || true
        fi
    elif command -v notify-send &>/dev/null; then
        notify-send "Stale Claims Audit" "$notif_msg" 2>/dev/null || true
    fi
    exit 1
fi

# Clean old reports (keep last 30)
# shellcheck disable=SC2012  # filenames are ours (report-YYYYMMDD.txt), no special chars
ls -t "$REPORT_DIR"/report-*.txt 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
