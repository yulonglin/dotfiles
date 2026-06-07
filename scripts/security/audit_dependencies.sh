#!/bin/bash
# Weekly dependency audit — scans repos for known-bad packages and filesystem IOCs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWN_BAD="$SCRIPT_DIR/known_bad_packages.txt"
REPORT_DIR="$HOME/.local/share/dep-audit"
REPORT_FILE="$REPORT_DIR/report-$(date +%Y%m%d).txt"
SCAN_DIRS=("${CODE_DIR:-$HOME/code}" "${SCRATCH_DIR:-$HOME/scratch}" "${WRITING_DIR:-$HOME/writing}")

mkdir -p "$REPORT_DIR"
issues_found=0
affected_pkgs=()  # unique "name@version" strings, for the notification summary

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$REPORT_FILE"; }
log "=== Dependency Audit $(date) ==="

# Record an affected package (deduped) for the notification summary.
record_pkg() {
    local pkg="$1" existing
    for existing in "${affected_pkgs[@]:-}"; do
        [[ "$existing" == "$pkg" ]] && return 0
    done
    affected_pkgs+=("$pkg")
}

# Build grep patterns from KNOWN_BAD once. Each npm/pypi entry keeps its
# "name@version" label and human-readable description for enriched reporting.
# npm entries:  "<regex>\t<name>@<ver>\t<desc>"
# pypi entries: "<name>:<ver>:<desc>"
npm_patterns=()
pypi_entries=()
while IFS=: read -r ecosystem name versions desc; do
    [[ "$ecosystem" =~ ^#.*$ || -z "$name" ]] && continue
    desc="${desc## }"; desc="${desc%% }"
    if [[ "$ecosystem" == "npm" ]]; then
        IFS=',' read -ra ver_list <<< "$versions"
        for ver in "${ver_list[@]}"; do
            ver="${ver## }"; ver="${ver%% }"
            npm_patterns+=("${name}@${ver}|\"$name\".*\"$ver\""$'\t'"${name}@${ver}"$'\t'"${desc}")
        done
    elif [[ "$ecosystem" == "pypi" ]]; then
        IFS=',' read -ra ver_list <<< "$versions"
        for ver in "${ver_list[@]}"; do
            ver="${ver## }"; ver="${ver%% }"
            pypi_entries+=("${name}:${ver}:${desc}")
        done
    elif [[ "$ecosystem" == "ioc" && -e "$name" ]]; then
        log "CRITICAL: IOC artifact found: $name ($versions)"
        issues_found=$((issues_found + 1))
    fi
done < "$KNOWN_BAD"

# Check whether a lockfile contains a known-bad pypi package AT the bad version.
# Echoes one of: critical | info | warning  (and never returns non-zero under set -e)
check_pypi_lockfile() {
    local lockfile="$1" name="$2" badver="$3"
    case "$lockfile" in
        *Pipfile.lock)
            # JSON: "<name>": { ... "version": "==<badver>" ... }
            if grep -qE "\"$name\"[[:space:]]*:" "$lockfile" 2>/dev/null; then
                if grep -qE "\"version\"[[:space:]]*:[[:space:]]*\"==$badver\"" "$lockfile" 2>/dev/null; then
                    echo critical
                else
                    echo info
                fi
            fi
            ;;
        *)
            # TOML (uv.lock / poetry.lock): name = "<name>" then version = "..." on a following line
            local block
            block=$(grep -A2 "^name = \"$name\"$" "$lockfile" 2>/dev/null || true)
            if [[ -n "$block" ]]; then
                if grep -qE "^version = \"$badver\"$" <<< "$block"; then
                    echo critical
                elif grep -qE "^version = " <<< "$block"; then
                    echo info
                else
                    # name present but version not where expected — fall back to warning
                    echo warning
                fi
            fi
            ;;
    esac
}

# Scan lockfiles
for dir in "${SCAN_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue
    log "Scanning $dir..."

    if [[ ${#npm_patterns[@]} -gt 0 ]]; then
        while IFS= read -r lockfile; do
            for npm_entry in "${npm_patterns[@]}"; do
                IFS=$'\t' read -r npm_regex npm_label npm_desc <<< "$npm_entry"
                if grep -qE "$npm_regex" "$lockfile" 2>/dev/null; then
                    log "CRITICAL: $lockfile pins known-bad $npm_label — $npm_desc"
                    issues_found=$((issues_found + 1))
                    record_pkg "$npm_label"
                fi
            done
        done < <(find "$dir" -maxdepth 4 \( -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" -o -name "bun.lockb" -o -name "bun.lock" \) -not -path "*/node_modules/*" 2>/dev/null)
    fi

    if [[ ${#pypi_entries[@]} -gt 0 ]]; then
        while IFS= read -r lockfile; do
            for entry in "${pypi_entries[@]}"; do
                IFS=':' read -r name badver desc <<< "$entry"
                result=$(check_pypi_lockfile "$lockfile" "$name" "$badver")
                case "$result" in
                    critical)
                        log "CRITICAL: $lockfile pins known-bad $name==$badver — $desc"
                        issues_found=$((issues_found + 1))
                        record_pkg "$name@$badver"
                        ;;
                    warning)
                        log "WARNING: $lockfile references $name (known-bad version $badver; could not parse locked version — verify manually)"
                        issues_found=$((issues_found + 1))
                        record_pkg "$name@$badver"
                        ;;
                    info)
                        log "INFO: $lockfile has $name at a non-flagged version (clean)"
                        ;;
                esac
            done
        done < <(find "$dir" -maxdepth 4 \( -name "uv.lock" -o -name "poetry.lock" -o -name "Pipfile.lock" \) -not -path "*/.venv/*" 2>/dev/null)
    fi
done

log "=== Audit complete: $issues_found issue(s) found ==="
if [[ $issues_found -gt 0 ]]; then
    log "Review: $REPORT_FILE"

    # Build a short summary: first 2-3 unique pkg@version, then "+k more".
    pkg_summary=""
    n_pkgs=${#affected_pkgs[@]}
    if [[ $n_pkgs -gt 0 ]]; then
        show=$(( n_pkgs < 3 ? n_pkgs : 3 ))
        for ((i = 0; i < show; i++)); do
            pkg_summary+="${pkg_summary:+, }${affected_pkgs[i]}"
        done
        [[ $n_pkgs -gt $show ]] && pkg_summary+=" +$((n_pkgs - show)) more"
    fi
    notif_msg="$issues_found issue(s)"
    [[ -n "$pkg_summary" ]] && notif_msg="$notif_msg: $pkg_summary"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v terminal-notifier &>/dev/null; then
            terminal-notifier -title "Dependency Audit" -message "$notif_msg" \
                -open "file://$REPORT_FILE" 2>/dev/null || true
        else
            osascript -e "display notification \"$notif_msg\" with title \"Dependency Audit\"" 2>/dev/null || true
        fi
    elif command -v notify-send &>/dev/null; then
        notify-send "Dependency Audit" "$notif_msg" 2>/dev/null || true
    fi
    exit 1
fi

# Clean old reports (keep last 30)
ls -t "$REPORT_DIR"/report-*.txt 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
