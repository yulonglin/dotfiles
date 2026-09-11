#!/usr/bin/env bash
# Guards against CLAUDE_CODE_ATTRIBUTION_HEADER=0 returning to settings.
#
# Why this exists: the opt-out silently broke auto mode behind the gateway.
# Claude Code re-adds the billing attribution block for classifier calls only
# when ANTHROPIC_BASE_URL is unset or api.anthropic.com; behind the model-router
# the opt-out is honoured and every classifier request comes back a bare 429.
# Measured 8 Sep 2026: 15 requests, 15 x 429, every Bash call denied. Removed in
# b2868c8; artifacts/auto-mode-classifier-429/report.md has the mechanism.
#
# The failure leaves no local log line, so nothing surfaces it except a session
# that stops working. Hence a test rather than a note.
#
# Both copies are checked because they differ by design: the deployed file is
# claude/settings.json through the ~/.claude symlink, and it carries local
# gateway keys the committed copy must never have. The bug lived in that gap.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KEY="CLAUDE_CODE_ATTRIBUTION_HEADER"
# Overridable so the test can be pointed at a fixture and shown to fail; a test
# that has only ever passed has not been tested.
DEPLOYED="${CLAUDE_SETTINGS_DEPLOYED:-$HOME/.claude/settings.json}"
COMMITTED="${CLAUDE_SETTINGS_COMMITTED:-$REPO_ROOT/claude/settings.json}"

fails=0
checked=0

report_fail() {
    printf 'FAIL: %s\n' "$1"
    fails=$((fails + 1))
}

# Reads the key out of the env block only. A grep would also match the word in a
# comment or in this file's own path, and jq is not guaranteed present.
env_value() {
    python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as fh:
        settings = json.load(fh)
except FileNotFoundError:
    print("ABSENT-FILE"); sys.exit(0)
except json.JSONDecodeError as exc:
    print("BAD-JSON " + str(exc)); sys.exit(0)
env = settings.get("env")
if not isinstance(env, dict):
    print("NO-ENV"); sys.exit(0)
print(env.get(sys.argv[2], "UNSET"))
' "$1" "$2"
}

check_file() {
    local label="$1" path="$2" required="$3" value
    value=$(env_value "$path" "$KEY")
    case "$value" in
        ABSENT-FILE)
            if [ "$required" = "required" ]; then
                report_fail "$label missing at $path"
            else
                printf 'skip: %s not present at %s\n' "$label" "$path"
            fi
            return ;;
        BAD-JSON*)
            report_fail "$label is not valid JSON at $path: ${value#BAD-JSON }" ; return ;;
        UNSET|NO-ENV)
            checked=$((checked + 1))
            printf 'ok:   %s carries no %s\n' "$label" "$KEY" ; return ;;
        *)
            checked=$((checked + 1))
            report_fail "$label sets $KEY=$value at $path — this breaks the auto-mode classifier behind the gateway (see artifacts/auto-mode-classifier-429/report.md). Remove the key."
            return ;;
    esac
}

check_file "committed settings" "$COMMITTED" required
# Optional: a fresh clone or a CI checkout has no deployed copy to inspect.
check_file "deployed settings" "$DEPLOYED" optional

if [ "$fails" -ne 0 ]; then
    printf '\n%d check(s) failed\n' "$fails"
    exit 1
fi
printf '\nPASS: %d settings file(s) carry no %s\n' "$checked" "$KEY"
