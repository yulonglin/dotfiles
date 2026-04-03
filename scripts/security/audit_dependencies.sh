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

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$REPORT_FILE"; }
log "=== Dependency Audit $(date) ==="

# Build grep patterns from KNOWN_BAD once
npm_patterns=()
pypi_names=()
while IFS=: read -r ecosystem name versions desc; do
    [[ "$ecosystem" =~ ^#.*$ || -z "$name" ]] && continue
    if [[ "$ecosystem" == "npm" ]]; then
        IFS=',' read -ra ver_list <<< "$versions"
        for ver in "${ver_list[@]}"; do
            ver="${ver## }"; ver="${ver%% }"
            npm_patterns+=("${name}@${ver}|\"$name\".*\"$ver\"")
        done
    elif [[ "$ecosystem" == "pypi" ]]; then
        pypi_names+=("$name")
    elif [[ "$ecosystem" == "ioc" && -e "$name" ]]; then
        log "CRITICAL: IOC artifact found: $name ($versions)"
        issues_found=$((issues_found + 1))
    fi
done < "$KNOWN_BAD"

# Scan lockfiles
for dir in "${SCAN_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue
    log "Scanning $dir..."

    if [[ ${#npm_patterns[@]} -gt 0 ]]; then
        npm_regex=$(IFS='|'; echo "${npm_patterns[*]}")
        while IFS= read -r lockfile; do
            matches=$(grep -cE "$npm_regex" "$lockfile" 2>/dev/null || true)
            if [[ "$matches" -gt 0 ]]; then
                log "CRITICAL: $lockfile has $matches known-bad package match(es)"
                issues_found=$((issues_found + matches))
            fi
        done < <(find "$dir" -maxdepth 4 \( -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" -o -name "bun.lockb" -o -name "bun.lock" \) -not -path "*/node_modules/*" 2>/dev/null)
    fi

    if [[ ${#pypi_names[@]} -gt 0 ]]; then
        pypi_regex=$(IFS='|'; echo "${pypi_names[*]}")
        while IFS= read -r lockfile; do
            if grep -qiE "$pypi_regex" "$lockfile" 2>/dev/null; then
                log "WARNING: $lockfile references a known-bad Python package (verify version)"
                issues_found=$((issues_found + 1))
            fi
        done < <(find "$dir" -maxdepth 4 \( -name "uv.lock" -o -name "poetry.lock" -o -name "Pipfile.lock" \) -not -path "*/.venv/*" 2>/dev/null)
    fi
done

log "=== Audit complete: $issues_found issue(s) found ==="
if [[ $issues_found -gt 0 ]]; then
    log "Review: $REPORT_FILE"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        osascript -e "display notification \"$issues_found supply chain issue(s) found\" with title \"Dependency Audit\"" 2>/dev/null || true
    elif command -v notify-send &>/dev/null; then
        notify-send "Dependency Audit" "$issues_found issue(s) found" 2>/dev/null || true
    fi
    exit 1
fi

# Clean old reports (keep last 30)
ls -t "$REPORT_DIR"/report-*.txt 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
