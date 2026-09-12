#!/usr/bin/env bash
# Pins the two-phase wiring in custom_bins/model-router-wire.
#
# The gateway keys live in a root-owned managed drop-in, so `apply` cannot
# install them itself. It stages the file, prints the sudo line, and only
# strips the keys from the user settings file once the managed copy matches
# the staged one -- otherwise every session between the two steps would run
# without the gateway. Everything here runs against temp paths with a stub
# bootstrap, so no router, no sudo and no live settings file are touched.
# The token in the fixture is synthetic; never paste a live one here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIRE="$REPO_ROOT/custom_bins/model-router-wire"
# Under the repo's gitignored tmp/, not $TMPDIR: the Claude Code sandbox refuses
# to execute a script written under /var/folders, and the stub bootstrap must run.
mkdir -p "$REPO_ROOT/tmp"
WORK="$(mktemp -d "$REPO_ROOT/tmp/wire-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
has_key() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d.get("env",{}) else 1)' "$1" "$2"; }
has_top() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d else 1)' "$1" "$2"; }

cat >"$WORK/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  doctor) echo '{"base_url":"http://127.0.0.1:8787/t/0123456789abcdef0123456789abcdef","version":"test","checks":[{"name":"router","ok":true}]}' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bootstrap.sh"
mkdir -p "$WORK/agents"
# The pre-migration shape: the user file carries the gateway keys and picker rows.
cat >"$WORK/settings.json" <<'EOF'
{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:8787/t/0123456789abcdef0123456789abcdef","_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL":"1","ENABLE_TOOL_SEARCH":"1","TMPDIR":"/tmp/claude"},"modelPicker":{"options":[{"model":"old","label":"Old"}]},"statusLine":{},"hooks":{},"permissions":{}}
EOF

export MODEL_ROUTER_BOOTSTRAP="$WORK/bootstrap.sh"
export CLAUDE_SETTINGS="$WORK/settings.json"
export MODEL_ROUTER_CONFIG="$WORK/config.toml"
export MODEL_ROUTER_MANAGED="$WORK/managed.d/50-model-router.json"
export MODEL_ROUTER_STAGED="$WORK/staged.json"
export MODEL_ROUTER_AGENTS="$WORK/agents"

# --- Phase 1: stage, print the sudo line, leave the user file alone ----------
out="$("$WIRE" apply --no-restart)"
[ -f "$MODEL_ROUTER_STAGED" ] || fail "apply did not stage $MODEL_ROUTER_STAGED"
# GNU stat -f means "filesystem status" and SUCCEEDS while printing the wrong
# thing, so the GNU form has to come first or the BSD branch always wins here
mode="$(stat -c '%a' "$MODEL_ROUTER_STAGED" 2>/dev/null || stat -f '%Lp' "$MODEL_ROUTER_STAGED")"
[ "$mode" = "600" ] || fail "staged file mode is $mode, expected 600"
has_key "$MODEL_ROUTER_STAGED" ANTHROPIC_BASE_URL || fail "staged file lacks ANTHROPIC_BASE_URL"
has_key "$MODEL_ROUTER_STAGED" _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL || fail "staged file lacks the first-party flag"
has_top "$MODEL_ROUTER_STAGED" modelPicker || fail "staged file lacks modelPicker"
has_top "$MODEL_ROUTER_STAGED" permissions && fail "staged file carries a personal key (permissions)"
printf '%s' "$out" | grep -q 'sudo install -d -m 0755' || fail "apply did not print the sudo install line: $out"
printf '%s' "$out" | grep -q -- "-o root -g" || fail "sudo line does not set root ownership: $out"
# shellcheck disable=SC2016  # the backticks are literal text in the tool's output
printf '%s' "$out" | grep -q 'rerun `model-router-wire apply`' || fail "apply did not say to rerun after the sudo step"
has_key "$CLAUDE_SETTINGS" ANTHROPIC_BASE_URL || fail "phase 1 stripped the user file before the managed drop-in existed"
has_top "$CLAUDE_SETTINGS" modelPicker || fail "phase 1 removed modelPicker before the managed drop-in existed"
[ -f "$MODEL_ROUTER_CONFIG" ] || fail "router config not rendered"
[ -f "$MODEL_ROUTER_MANAGED" ] && fail "apply wrote the managed path itself (it must go through sudo)"

# --check reports the missing drop-in as drift
if "$WIRE" apply --check >"$WORK/check1.txt" 2>&1; then fail "--check passed with no managed drop-in installed"; fi
grep -q 'not installed' "$WORK/check1.txt" || fail "--check did not name the missing drop-in: $(cat "$WORK/check1.txt")"

# --- Phase 2: the sudo step (simulated), then apply strips the user file -----
mkdir -p "$(dirname "$MODEL_ROUTER_MANAGED")"
cp "$MODEL_ROUTER_STAGED" "$MODEL_ROUTER_MANAGED"
out="$("$WIRE" apply --no-restart)"
printf '%s' "$out" | grep -q 'committable again' || fail "phase 2 did not report the strip: $out"
has_key "$CLAUDE_SETTINGS" ANTHROPIC_BASE_URL && fail "phase 2 left ANTHROPIC_BASE_URL in the user file"
has_key "$CLAUDE_SETTINGS" _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL && fail "phase 2 left the first-party flag in the user file"
has_top "$CLAUDE_SETTINGS" modelPicker && fail "phase 2 left modelPicker in the user file"
has_key "$CLAUDE_SETTINGS" TMPDIR || fail "phase 2 removed an unrelated env key"
has_key "$CLAUDE_SETTINGS" ENABLE_TOOL_SEARCH || fail "phase 2 removed ENABLE_TOOL_SEARCH, which the committed user file legitimately carries"
has_top "$CLAUDE_SETTINGS" statusLine || fail "phase 2 removed a top-level user key"
"$WIRE" apply --check >/dev/null 2>&1 || fail "--check fails after both phases: $("$WIRE" apply --check 2>&1)"
"$WIRE" status | grep -q 'WARNING' && fail "status warns after a clean migration"
"$WIRE" status | grep -q 'installed; staged copy present' || fail "status does not report the installed drop-in"

# A second apply is a no-op on the user file
before="$(cat "$CLAUDE_SETTINGS")"
"$WIRE" apply --no-restart >/dev/null
[ "$before" = "$(cat "$CLAUDE_SETTINGS")" ] || fail "a repeat apply changed the user file"

# --- Tampered drop-in is drift, not silently accepted -----------------------
python3 - "$MODEL_ROUTER_MANAGED" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["env"]["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:1/t/stale"; json.dump(d, open(p, "w"))
PY
if "$WIRE" apply --check >"$WORK/check2.txt" 2>&1; then fail "--check passed with a drop-in that differs from the render"; fi
grep -q 'differs' "$WORK/check2.txt" || fail "--check did not say the drop-in differs: $(cat "$WORK/check2.txt")"
cp "$MODEL_ROUTER_STAGED" "$MODEL_ROUTER_MANAGED"

# --- off: strip the user file, drop the staged copy, print the sudo rm ------
python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["env"]["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:8787/t/0123456789abcdef0123456789abcdef"; json.dump(d, open(p, "w"))
PY
out="$("$WIRE" off)"
has_key "$CLAUDE_SETTINGS" ANTHROPIC_BASE_URL && fail "off left ANTHROPIC_BASE_URL in the user file"
[ -f "$MODEL_ROUTER_STAGED" ] && fail "off left the staged file"
printf '%s' "$out" | grep -q 'sudo rm -f' || fail "off did not print the sudo rm line while the drop-in exists: $out"
[ -f "$MODEL_ROUTER_MANAGED" ] || fail "off removed the managed path itself"

echo "PASS: model-router-wire stages, waits for the sudo step, then strips the user file"
