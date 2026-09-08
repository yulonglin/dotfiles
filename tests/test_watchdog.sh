#!/usr/bin/env bash
# Regression tests for deterministic watchdog warnings.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHDOG="$ROOT/claude/hooks/watchdog.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/watchdog-test.XXXXXX")" || exit 1
trap 'rm -r "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/date" <<'STUB'
#!/usr/bin/env bash
count=$(cat "$FAKE_DATE_CALLS" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_DATE_CALLS"
value=$(sed -n "${count}p" "$FAKE_DATES")
if [[ -z "$value" ]]; then
  value=$(tail -n 1 "$FAKE_DATES")
fi
printf '%s\n' "$value"
STUB

cat > "$BIN/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

cat > "$BIN/stat" <<'STUB'
#!/usr/bin/env bash
count=$(cat "$FAKE_STAT_CALLS" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_STAT_CALLS"
value=$(sed -n "${count}p" "$FAKE_MTIMES")
if [[ -z "$value" ]]; then
  value=$(tail -n 1 "$FAKE_MTIMES")
fi
printf '%s\n' "$value"
STUB

cat > "$BIN/ps" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_RSS_KB:-0}"
STUB

cat > "$BIN/terminal-notifier" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
STUB

cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$EFFECT_LOG"
cat >/dev/null
printf '%s\n' 'STUCK model verdict'
STUB

cat > "$BIN/timeout" <<'STUB'
#!/usr/bin/env bash
printf 'timeout %s\n' "$*" >> "$EFFECT_LOG"
shift
exec "$@"
STUB

cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$EFFECT_LOG"
exit 1
STUB

chmod +x "$BIN"/*

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }

assert_empty() {
  local desc=$1 file=$2
  if [[ ! -s "$file" ]]; then ok "$desc"; else fail "$desc"; fi
}

assert_count() {
  local desc=$1 expected=$2 file=$3
  local actual=0
  if [[ -f "$file" ]]; then actual=$(wc -l < "$file" | tr -d ' '); fi
  if [[ "$actual" == "$expected" ]]; then ok "$desc"; else fail "$desc (expected $expected, got $actual)"; fi
}

assert_contains() {
  local desc=$1 needle=$2 file=$3
  if grep -qF -- "$needle" "$file" 2>/dev/null; then ok "$desc"; else fail "$desc"; fi
}

run_case() {
  local name=$1 marker=$2 mtime=$3 rss=$4 pid=$5
  shift 5
  local dir="$TMP/$name"
  mkdir -p "$dir"
  printf '%s\n' '{"type":"assistant","message":"still working"}' > "$dir/transcript.jsonl"
  : > "$dir/notifications"
  : > "$dir/effects"
  printf '%s\n' "$mtime" | tr ',' '\n' > "$dir/mtimes"
  printf '%s\n' "$@" > "$dir/dates"
  if [[ "$marker" == working ]]; then
    : > "$dir/claude-watchdog-${name}.working"
  fi

  PATH="$BIN:/usr/bin:/bin" \
    TMPDIR="$dir" \
    FAKE_DATES="$dir/dates" \
    FAKE_DATE_CALLS="$dir/date-calls" \
    FAKE_MTIMES="$dir/mtimes" \
    FAKE_STAT_CALLS="$dir/stat-calls" \
    FAKE_RSS_KB="$rss" \
    NOTIFY_LOG="$dir/notifications" \
    EFFECT_LOG="$dir/effects" \
    CLAUDE_WATCHDOG_TIMEOUT=100 \
    CLAUDE_WATCHDOG_INTERVAL=1 \
    CLAUDE_WATCHDOG_MAX_LIFE=500 \
    CLAUDE_WATCHDOG_MEM_LIMIT_MB=100 \
    bash "$WATCHDOG" "$name" "$dir/transcript.jsonl" "/projects/example" "$pid"
}

echo '=== stale working session ==='
run_case stale working 900 0 '' 1000 1100 1150 2000
assert_empty "does not invoke claude, timeout, or curl" "$TMP/stale/effects"
assert_count "warns once during the inactivity cooldown" 1 "$TMP/stale/notifications"
assert_contains "warning describes uncertainty" \
  "No recent output for 3m — session may still be running or waiting" \
  "$TMP/stale/notifications"

run_case repeated working 900 0 '' 1000 1100 1150 1200 2000
assert_count "warns again when the inactivity cooldown expires" 2 "$TMP/repeated/notifications"
assert_empty "does not invoke external triage for repeated warnings" "$TMP/repeated/effects"

run_case recovered working 900,1240 0 '' 1000 1100 1250 2000
assert_count "does not warn again after transcript output resumes" 1 "$TMP/recovered/notifications"
assert_contains "checks transcript mtime again after the first warning" "2" "$TMP/recovered/stat-calls"
assert_empty "does not invoke external triage after output resumes" "$TMP/recovered/effects"

echo '=== active and idle states ==='
run_case active working 1099 0 '' 1000 1100 2000
assert_empty "does not warn when working transcript has new output" "$TMP/active/notifications"
assert_empty "does not run external triage for new output" "$TMP/active/effects"
run_case idle idle 900 0 '' 1000 1100 2000
assert_empty "does not warn while session is idle" "$TMP/idle/notifications"
assert_empty "does not run external triage while idle" "$TMP/idle/effects"

echo '=== process health ==='
run_case memory idle 1099 204800 "$$" 1000 1100 1150 2000
assert_count "retains one memory warning per threshold crossing" 1 "$TMP/memory/notifications"
assert_contains "memory warning reports measured RSS" "Memory: 200MB (limit: 100MB)" "$TMP/memory/notifications"
run_case dead idle 1099 0 99999999 1000 1100
assert_count "retains process-death warning" 1 "$TMP/dead/notifications"
assert_contains "process-death warning names the PID" "Claude process (PID 99999999) died" "$TMP/dead/notifications"

echo
printf 'passed: %s  failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
