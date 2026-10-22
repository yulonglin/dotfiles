#!/usr/bin/env zsh
# Runs custom_bins/enforce-timezone against a fake macOS: systemsetup, readlink,
# defaults, killall, logger and `date +%s` are stubbed, and its state files go to
# a temp dir through ENFORCE_TZ_STATE_DIR. That lets the travel scenario be
# replayed run by run, including the run the daemon's own revert triggers
# (WatchPaths fires on /etc/localtime, which the revert rewrites) — the run that
# used to wipe the sighting counter, so a flight was never auto-accepted.
#
# Usage: tests/test_enforce_timezone.zsh [path-to-script]  (default: the repo's)
set -uo pipefail
setopt null_glob

REPO="${0:A:h:h}"
SCRIPT="${1:-$REPO/custom_bins/enforce-timezone}"
mkdir -p "$REPO/tmp" || { print -ru2 -- "FATAL: cannot create $REPO/tmp"; exit 1 }
WORK="$(mktemp -d "$REPO/tmp/enforce-tz-test.XXXXXX")" \
    || { print -ru2 -- "FATAL: mktemp -d under $REPO/tmp failed"; exit 1 }
[[ -n "$WORK" && -d "$WORK" && "$WORK" == "$REPO/tmp/"* ]] \
    || { print -ru2 -- "FATAL: work dir not under $REPO/tmp: ${WORK:-<empty>}"; exit 1 }
trap 'rm -rf "${WORK:?}"' EXIT
BIN="$WORK/bin" FAKE="$WORK/fake" STATE="$WORK/state"
mkdir -p "$BIN" "$FAKE" "$STATE"
PASS=0 FAIL=0

eq() {  # eq <label> <got> <want>
    if [[ "$2" == "$3" ]]; then
        print -r -- "  ok   $1"; (( PASS++ ))
    else
        print -r -- "  FAIL $1 -- got '$2', want '$3'"; (( FAIL++ ))
    fi
}

# ─── Stubs: the fake system lives in $FAKE ───────────────────────────────────
stub() { print -r -- "#!/bin/sh" > "$BIN/$1"; print -r -- "$2" >> "$BIN/$1"; chmod +x "$BIN/$1"; }
stub readlink 'echo "/var/db/timezone/zoneinfo/$(cat "'$FAKE'/tz")"'
stub systemsetup 'case "$1" in
  -gettimezone) echo "Time Zone: $(cat "'$FAKE'/tz")" ;;
  -settimezone) echo "$2" > "'$FAKE'/tz" ;;
  -getusingnetworktime) echo "Network Time: On" ;;
esac'
stub defaults 'case "$1" in read) echo 1 ;; esac'
stub killall 'echo "$*" >> "'$FAKE'/killall"'
stub logger 'shift 2; echo "$*" >> "'$FAKE'/log"'
stub date 'if [ "$1" = "+%s" ]; then cat "'$FAKE'/now"; else exec /bin/date "$@"; fi'

reset() {  # reset <tz>: fresh machine, daemon's first run seeds the cache
    rm -f "$STATE"/* "$FAKE"/*
    print -r -- "$1" > "$FAKE/tz"
    print -r -- 1000000 > "$FAKE/now"
    daemon
}
daemon() { ENFORCE_TZ_STATE_DIR="$STATE" PATH="$BIN:$PATH" "$SCRIPT" >/dev/null 2>&1 }
tick() { print -r -- $(( $(<"$FAKE/now") + $1 )) > "$FAKE/now" }
os_sets() { print -r -- "$1" > "$FAKE/tz" }   # locationd (or a person) sets the TZ
tz() { cat "$FAKE/tz" }
cache() { cat "$STATE/enforce-timezone.last" 2>/dev/null }
count() { local n; n=$(grep -c -- "$2" "$FAKE/$1" 2>/dev/null); print -r -- "${n:-0}" }

print "enforce-timezone: $SCRIPT"

print "1. A flight is accepted on the third sighting, despite the revert's own run"
reset America/Los_Angeles
for _ in 1 2 3; do
    tick 30; os_sets Asia/Singapore; daemon   # locationd re-detects the new TZ
    tick 10; daemon                           # WatchPaths run caused by the revert
done
eq "timezone is the new one" "$(tz)" Asia/Singapore
eq "cache accepted the new one" "$(cache)" Asia/Singapore
eq "reverted twice before accepting" "$(count log Reverting)" 2
tick 30; daemon
eq "stays accepted on the next run" "$(tz)" Asia/Singapore

print "2. A one-off manual change is reverted and never accepted"
reset America/Los_Angeles
tick 30; os_sets Asia/Tokyo; daemon
for _ in 1 2 3 4; do tick 60; daemon; done
eq "timezone reverted" "$(tz)" America/Los_Angeles
eq "cache unchanged" "$(cache)" America/Los_Angeles
eq "no auto-accept" "$(count log Auto-accepting)" 0

print "3. Sightings further apart than the window do not add up"
reset America/Los_Angeles
for _ in 1 2 3; do
    tick 1900; os_sets Asia/Tokyo; daemon     # ~32 min apart
    tick 10; daemon
done
eq "timezone reverted" "$(tz)" America/Los_Angeles
eq "no auto-accept" "$(count log Auto-accepting)" 0

print "4. The restart rate limit holds across the revert's own runs"
reset America/Los_Angeles
for z in Asia/Tokyo Asia/Seoul Asia/Tokyo Asia/Seoul Asia/Tokyo Asia/Seoul Asia/Tokyo; do
    tick 30; os_sets "$z"; daemon             # alternating, so never accepted
    tick 10; daemon
done
eq "locationd restarted at most 5 times in 10 min" "$(count killall locationd)" 5
eq "rate limit logged" "$(( $(count log 'Rate limit hit') > 0 ))" 1

print "\npassed: $PASS   failed: $FAIL"
(( FAIL == 0 ))
