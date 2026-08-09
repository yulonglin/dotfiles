#!/usr/bin/env bash
# Guards the spec-loop refinement prompts (claude/skills/spec-loop/prompts/).
# SPEC-A requires the write/clean/improve bodies VERBATIM from the round-1
# interview §Q5 — so the verbatim regions are pinned by sha256. Editing a
# body is a spec change: update the source interview note first, then the
# literal here. Addenda live OUTSIDE the verbatim markers and are checked
# structurally, not by hash.
# shellcheck disable=SC2015
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS="$ROOT/claude/skills/spec-loop/prompts"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# Canonical extraction: the lines strictly between the verbatim markers.
body_hash() {
  sed -n '/<!-- verbatim-begin -->/,/<!-- verbatim-end -->/p' "$1" |
    sed '1d;$d' | sha256sum | cut -d' ' -f1
}

check_hash() {
  local name=$1 expected=$2 file="$PROMPTS/$1.md" actual
  if [ ! -f "$file" ]; then fail "$name.md exists"; return; fi
  actual=$(body_hash "$file")
  [ "$actual" = "$expected" ] && ok "$name.md verbatim body sha256 unchanged" \
    || fail "$name.md verbatim body drifted (got $actual, want $expected — the body is VERBATIM from the §Q5 interview source; fix the file, don't casually update the hash)"
}

check_contains() {
  local desc=$1 file=$2 pattern=$3
  grep -qF -- "$pattern" "$file" && ok "$desc" || fail "$desc"
}

echo "=== verbatim bodies (sha256 vs interview round-1 §Q5) ==="
check_hash write-spec   1808869b21c242259fa228403bcbea27a0ad254609feeb53fa3ae6db091cdce1
check_hash clean-spec   37ce5d57667bc349c63e5347ef1fbbc79a889ac34a58f8c03234f65716313429
check_hash improve-spec 7989979792a29a6dcb8a8650c960b89654078d221ce669af4c8a6d014308bd0e

echo "=== structure: markers and addenda ==="
for name in write-spec clean-spec improve-spec; do
  f="$PROMPTS/$name.md"
  [ -f "$f" ] || { fail "$name.md exists"; continue; }
  [ "$(grep -c '<!-- verbatim-begin -->' "$f")" -eq 1 ] \
    && [ "$(grep -c '<!-- verbatim-end -->' "$f")" -eq 1 ] \
    && ok "$name.md has exactly one verbatim region" \
    || fail "$name.md has exactly one verbatim region"
  check_contains "$name.md addendum marked as non-verbatim" "$f" "not part of the verbatim"
done

echo "=== improve-spec: six §Q5 dimensions present ==="
IMPROVE="$PROMPTS/improve-spec.md"
for dim in "Purpose" "Open questions" "Consistency and precision" \
           "Implementation readiness" "Acceptance criteria" "Concision and structure"; do
  check_contains "improve-spec dimension: $dim" "$IMPROVE" "$dim"
done
check_contains "improve-spec keeps the /grill-me pointer" "$IMPROVE" "grill-me"
check_contains "write-spec keeps the /grill-me pointer" "$PROMPTS/write-spec.md" "grill-me"

echo "=== five-section template (addenda + spec-conventions.md) ==="
CONV="$ROOT/claude/rules/spec-conventions.md"
for h in "Goal" "Context" "Requirements" "Acceptance criteria" "Out of scope"; do
  check_contains "spec-conventions.md names section: $h" "$CONV" "$h"
done

# Each addendum (the text AFTER the verbatim region) must itself carry the
# five headings in order plus an affirmative mandate — a lone "five-section"
# substring or a truncated addendum must fail.
addendum() { sed -n '/<!-- verbatim-end -->/,$p' "$PROMPTS/$1.md" | sed '1d'; }
check_addendum_headings() {
  local name=$1
  addendum "$name" | tr '\n' ' ' |
    grep -q '# Goal.*# Context.*# Requirements.*# Acceptance criteria.*# Out of scope' \
    && ok "$name addendum lists all five headings in order" \
    || fail "$name addendum lists all five headings in order"
}
check_addendum_mandate() {
  local name=$1 phrase=$2
  addendum "$name" | grep -qF -- "$phrase" \
    && ok "$name addendum carries its affirmative mandate" \
    || fail "$name addendum carries its affirmative mandate (want: $phrase)"
}
for name in write-spec clean-spec improve-spec; do
  check_addendum_headings "$name"
done
check_addendum_mandate write-spec   "Write the specification in the five-section template"
check_addendum_mandate clean-spec   "Keep the five-section template intact"
check_addendum_mandate improve-spec "MUST use the five-section template"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
