#!/usr/bin/env zsh
# Fixture tests for custom_bins/brew-running-casks and the brew() wrapper in
# config/aliases/brew.sh. Every external command is a stub: nothing here can
# reach the real Homebrew, and the recording `brew` stub never upgrades.

emulate -L zsh
setopt no_unset

REPO_ROOT="${0:A:h:h}"
HELPER="$REPO_ROOT/custom_bins/brew-running-casks"
WRAPPER="$REPO_ROOT/config/aliases/brew.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/brc-test.XXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); print "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); print -u2 "FAIL - $1"; }
has() { [[ "$2" == *"$3"* ]] && pass "$1" || fail "$1 (missing: $3)"; }
lacks() { [[ "$2" != *"$3"* ]] && pass "$1" || fail "$1 (unexpected: $3)"; }

BIN="$WORK/bin"
mkdir -p "$BIN"
EVENTS="$WORK/events"
: > "$EVENTS"

# brew stub: canned outdated/info JSON; records every call.
cat > "$BIN/brew" <<'EOF'
#!/bin/zsh
print -r -- "brew $*" >> "$STUB_EVENTS"
case "$1 $2" in
  "outdated --cask")
    if [[ "$*" == *--greedy* ]]; then
      print '{"formulae":[],"casks":[{"name":"telegram"},{"name":"zoom"},{"name":"slack"},{"name":"chatgpt"}]}'
    else
      print '{"formulae":[],"casks":[{"name":"telegram"},{"name":"slack"}]}'
    fi ;;
  "info --cask")
    print '{"casks":[
      {"token":"telegram","name":["Telegram for macOS"],"artifacts":[{"app":["Telegram.app"]}]},
      {"token":"zoom","name":["Zoom"],"artifacts":[{"pkg":["zoomusInstallerFull.pkg"]}]},
      {"token":"slack","name":["Slack"],"artifacts":[{"app":["Slack.app"]}]},
      {"token":"chatgpt","name":["ChatGPT"],"artifacts":[{"app":[["ChatGPT.app",{"target":"/Applications/ChatGPT.app"}]]}]}
    ]}' ;;
esac
EOF

# ps: right-aligned PIDs of mixed width, as the real `ps -Axo pid=,comm=` prints.
cat > "$BIN/ps" <<'EOF'
#!/bin/zsh
print ' 8737 /Applications/Telegram.app/Contents/MacOS/Telegram'
print '12969 /Applications/Zoom.app/Contents/MacOS/zoom.us'
print '31737 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT'
print '  421 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer'
print '  500 /Applications/Slack Helper.app/Contents/MacOS/Slack Helper'
EOF

# pmset: coreaudiod holds an audio session for Zoom (12969) only.
cat > "$BIN/pmset" <<'EOF'
#!/bin/zsh
print '   pid 718(sharingd): [0x1] 00:01:03 PreventUserIdleSystemSleep named: "Handoff"'
print '	Created for PID: 31737.'
print '   pid 91601(coreaudiod): [0x2] 00:00:23 PreventUserIdleSystemSleep named: "com.apple.audio.context"'
print '	Created for PID: 12969.'
print '	Resources: audio-out BuiltInSpeakerDevice'
print '   pid 362(powerd): [0x3] 00:01:53 PreventUserIdleSystemSleep named: "display"'
EOF
chmod +x "$BIN"/*

run_helper() {
    STUB_EVENTS="$EVENTS" BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" \
        BRC_PMSET_BIN="$BIN/pmset" BRC_APPS_DIR=/Applications "$HELPER" "$@" 2>&1
}

print "1. default (non-greedy) set: running Telegram found despite a 4-digit PID"
out="$(run_helper)"
has "telegram listed as running" "$out" $'telegram\t/Applications/Telegram.app\t8737\t-'
lacks "slack is not running (only a look-alike path)" "$out" "slack"

print "2. greedy set: pkg cask resolved by display name, audio flagged from pmset"
out="$(run_helper --greedy)"
has "zoom (pkg cask) mapped via /Applications/Zoom.app and flagged audio" "$out" $'zoom\t/Applications/Zoom.app\t12969\taudio'
has "chatgpt target-form app artifact resolved" "$out" $'chatgpt\t/Applications/ChatGPT.app\t31737\t-'
lacks "a non-coreaudiod assertion PID is not flagged audio" "$out" $'31737\taudio'

print "3. --names and --outdated-names partition the outdated set"
has "--names lists running tokens" "$(run_helper --greedy --names)" $'telegram\nzoom\nchatgpt'
[[ "$(run_helper --greedy --outdated-names)" == slack ]] \
    && pass "--outdated-names lists only the non-running cask" \
    || fail "--outdated-names was: $(run_helper --greedy --outdated-names)"

print "4. wrapper: skip path keeps flags and upgrades only non-running casks"
cat > "$BIN/brew-running-casks" <<EOF
#!/bin/zsh
exec env STUB_EVENTS="$EVENTS" BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" BRC_PMSET_BIN="$BIN/pmset" "$HELPER" "\$@"
EOF
cat > "$BIN/reset-mac-media" <<EOF
#!/bin/zsh
print -r -- "reset-mac-media \$*" >> "$EVENTS"
EOF
chmod +x "$BIN/brew-running-casks" "$BIN/reset-mac-media"

run_wrapper() {
    : > "$EVENTS"
    print -r -- "$1" | PATH="$BIN:/usr/bin:/bin" OSTYPE=darwin25 STUB_EVENTS="$EVENTS" \
        zsh -fc "source '$WRAPPER'; brew ${2}" 2>&1
}

out="$(run_wrapper y 'upgrade --greedy --dry-run')"
ev="$(cat "$EVENTS")"
has "prompt names the audio user" "$out" "zoom  (Zoom.app)  <- using audio right now"
has "formulae upgraded with the pass-through flag" "$ev" "brew upgrade --formula --dry-run"
has "only the non-running cask is upgraded, flags kept" "$ev" "brew upgrade --cask --greedy --dry-run slack"
lacks "running telegram is never upgraded" "$(print -r -- "$ev" | rg '^brew upgrade')" "telegram"
has "health check runs afterwards" "$ev" "reset-mac-media --check --since 15"

print "5. wrapper: q aborts before any upgrade"
out="$(run_wrapper q 'upgrade --greedy')"
lacks "no upgrade after q" "$(cat "$EVENTS")" "brew upgrade"

print "6. wrapper: named packages and other subcommands pass straight through"
run_wrapper '' 'upgrade --cask telegram' >/dev/null
has "named upgrade passes through untouched" "$(cat "$EVENTS")" "brew upgrade --cask telegram"
lacks "named upgrade skips the running-app scan" "$(cat "$EVENTS")" "outdated"
run_wrapper '' 'list --cask' >/dev/null
[[ "$(cat "$EVENTS")" == "brew list --cask" ]] && pass "non-upgrade subcommand passes through" \
    || fail "non-upgrade events: $(cat "$EVENTS")"

print "7. wrapper: nothing running means a plain upgrade"
out="$(run_wrapper '' 'upgrade --formula')"
has "formula-only upgrade runs as asked" "$(cat "$EVENTS")" "brew upgrade --formula"
lacks "formula-only upgrade skips the cask scan" "$(cat "$EVENTS")" "outdated --cask"

print ""
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
