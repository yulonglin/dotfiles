#!/usr/bin/env bash
# Structural guard for the spec-loop refinement prompts
# (claude/skills/spec-loop/prompts/). The prompts are plain editable text —
# reword them freely. These checks pin only the structure the skill relies
# on: the five-section template mandate in each prompt, the six improve-spec
# review dimensions, the /grill-me pointers, and clean-spec's cleaning
# guidance (opt-in process artifacts, signposting over prose walls).
# shellcheck disable=SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS="$ROOT/claude/skills/spec-loop/prompts"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

check_contains() {
  local desc=$1 file=$2 pattern=$3
  grep -qF -- "$pattern" "$file" && ok "$desc" || fail "$desc"
}

echo "=== files exist ==="
for name in write-spec clean-spec improve-spec; do
  [ -f "$PROMPTS/$name.md" ] && ok "$name.md exists" || fail "$name.md exists"
done

echo "=== improve-spec: six review dimensions ==="
IMPROVE="$PROMPTS/improve-spec.md"
for dim in "Purpose" "Open questions" "Consistency and precision" \
           "Implementation readiness" "Acceptance criteria" "Concision and structure"; do
  check_contains "improve-spec dimension: $dim" "$IMPROVE" "$dim"
done
check_contains "improve-spec keeps the /grill-me pointer" "$IMPROVE" "grill-me"
check_contains "write-spec keeps the /grill-me pointer" "$PROMPTS/write-spec.md" "grill-me"

echo "=== five-section template (prompts + spec-conventions.md) ==="
CONV="$ROOT/claude/rules/spec-conventions.md"
for h in "Goal" "Context" "Requirements" "Acceptance criteria" "Out of scope"; do
  check_contains "spec-conventions.md names section: $h" "$CONV" "$h"
done

# Each prompt must name the five headings in order plus an affirmative
# mandate — a lone "five-section" substring must not pass.
check_headings() {
  local name=$1
  tr '\n' ' ' < "$PROMPTS/$name.md" |
    grep -q '# Goal.*# Context.*# Requirements.*# Acceptance criteria.*# Out of scope' \
    && ok "$name lists all five headings in order" \
    || fail "$name lists all five headings in order"
}
for name in write-spec clean-spec improve-spec; do
  check_headings "$name"
done
check_contains "write-spec template mandate"   "$PROMPTS/write-spec.md"   "Write the specification in the five-section template"
check_contains "clean-spec template mandate"   "$PROMPTS/clean-spec.md"   "Keep the five-section template intact"
check_contains "improve-spec template mandate" "$IMPROVE"                 "MUST use the five-section template"

echo "=== clean-spec: cleaning guidance ==="
check_contains "clean-spec: process artifacts (audit trails) are opt-in" "$PROMPTS/clean-spec.md" "audit trails"
check_contains "clean-spec: signposting/bullets over walls of text"      "$PROMPTS/clean-spec.md" "signposting"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
