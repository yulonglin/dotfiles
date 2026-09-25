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
if [[ "$1" == upgrade ]]; then
  print -r -- "  auto-update-off=${HOMEBREW_NO_AUTO_UPDATE:-no}" >> "$STUB_EVENTS"
fi
case "$1 $2" in
  "outdated --cask")
    if [[ "$*" == *--greedy* ]]; then
      print '{"formulae":[],"casks":[{"name":"telegram"},{"name":"zoom"},{"name":"slack"},{"name":"chatgpt"},{"name":"mystery"},{"name":"ghost"},{"name":"clitool"}]}'
    else
      print '{"formulae":[],"casks":[{"name":"telegram"},{"name":"slack"}]}'
    fi ;;
  "info --cask")
    [[ "${STUB_BREW_INFO_FAIL:-0}" == 1 ]] && exit 1
    print '{"casks":[
      {"token":"telegram","name":["Telegram for macOS"],"artifacts":[{"app":["Telegram.app"]}]},
      {"token":"zoom","name":["Zoom"],"artifacts":[{"uninstall":[{"quit":"us.zoom.xos","pkgutil":"us.zoom.pkg.videomeeting"}]},{"pkg":["zoomusInstallerFull.pkg"]}]},
      {"token":"clitool","name":["CLI Tool"],"artifacts":[{"binary":["bin/clitool"]}]},
      {"token":"mystery","name":["Mystery"],"artifacts":[{"uninstall":[{"pkgutil":["com.example.unknown"]}]},{"pkg":["Mystery.pkg"]}]},
      {"token":"slack","name":["Slack"],"artifacts":[{"app":["Slack.app"]}]},
      {"token":"chatgpt","name":["ChatGPT"],"artifacts":[{"app":["ChatGPT.app",{"target":"Utilities/ChatGPT Beta.app"}]}]}
    ]}' ;;
esac
EOF

# ps: right-aligned PIDs of mixed width, as the real `ps -Axo pid=,comm=` prints.
cat > "$BIN/ps" <<'EOF'
#!/bin/zsh
print ' 8737 /Applications/Telegram.app/Contents/MacOS/Telegram'
print '12969 /Applications/zoom.us.app/Contents/MacOS/zoom.us'
print '31737 /Applications/Utilities/ChatGPT Beta.app/Contents/MacOS/ChatGPT'
print '40001 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT'
print '40002 /Users/me/Apps/Slack.app/Contents/MacOS/Slack'
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
# pkgutil: Zoom's receipt installs /Applications/zoom.us.app; Mystery's has no bundle.
cat > "$BIN/pkgutil" <<'EOF'
#!/bin/zsh
if [[ "$1 $2" == "--files us.zoom.pkg.videomeeting" ]]; then
  print 'Applications/zoom.us.app'
  print 'Applications/zoom.us.app/Contents'
  print 'Applications/zoom.us.app/Contents/MacOS/zoom.us'
fi
EOF
chmod +x "$BIN"/*
export BRC_PKGUTIL_BIN="$BIN/pkgutil"

run_helper() {
    STUB_EVENTS="$EVENTS" BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" \
        BRC_PMSET_BIN="$BIN/pmset" BRC_APPS_DIR=/Applications "$HELPER" "$@" 2>&1
}

print "1. default (non-greedy) set: running Telegram found despite a 4-digit PID"
out="$(run_helper)"
has "telegram listed as running" "$out" $'telegram\t/Applications/Telegram.app\t8737\t-'
lacks "slack is not running (only a look-alike path)" "$out" "slack"

print "2. greedy set: pkg cask resolved from its receipt, audio flagged from pmset"
out="$(run_helper --greedy)"
has "zoom (pkg cask) found at its receipt path zoom.us.app and flagged audio" "$out" $'zoom\t/Applications/zoom.us.app\t12969\taudio'
has "pkg cask with no bundle in its receipt is unknown, not safe" "$out" $'mystery\t(bundle not found)\t?\tunknown'
has "cask missing from brew info is unknown, not safe" "$out" $'ghost\t(missing from brew info)\t?\tunknown'
has "chatgpt matched at its artifact target, not its source name" "$out" $'chatgpt\t/Applications/Utilities/ChatGPT Beta.app\t31737\t-'
lacks "a non-coreaudiod assertion PID is not flagged audio" "$out" $'31737\taudio'

print "3. --names and --outdated-names partition the outdated set"
has "--names lists running and unknown tokens" "$(run_helper --greedy --names)" $'telegram\nzoom\nchatgpt\nmystery\nghost'
[[ "$(run_helper --greedy --outdated-names)" == $'slack\nclitool' ]] \
    && pass "--outdated-names lists only the non-running cask" \
    || fail "--outdated-names was: $(run_helper --greedy --outdated-names)"

print "4. wrapper: skip path keeps flags and upgrades only non-running casks"
cat > "$BIN/brew-running-casks" <<EOF
#!/bin/zsh
exec env STUB_EVENTS="$EVENTS" BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" BRC_PMSET_BIN="$BIN/pmset" BRC_PKGUTIL_BIN="$BIN/pkgutil" "$HELPER" "\$@"
EOF
cat > "$BIN/reset-mac-media" <<EOF
#!/bin/zsh
print -r -- "reset-mac-media \$*" >> "$EVENTS"
EOF
chmod +x "$BIN/brew-running-casks" "$BIN/reset-mac-media"

run_wrapper() {
    : > "$EVENTS"
    print -r -- "$1" | PATH="$BIN:/usr/bin:/bin" OSTYPE=darwin25 STUB_EVENTS="$EVENTS" \
        HOMEBREW_NO_AUTO_UPDATE= zsh -fc "source '$WRAPPER'; brew ${2}" 2>&1
}

out="$(run_wrapper y 'upgrade --greedy --dry-run')"
ev="$(cat "$EVENTS")"
[[ "${ev%%$'\n'*}" == "brew update" ]] && pass "metadata refreshed before the scan" \
    || fail "first event was: ${ev%%$'\n'*}"
lacks "no upgrade may auto-update past the scan" "$ev" "auto-update-off=no"
has "prompt names the audio user" "$out" "zoom  (zoom.us.app)  <- using audio right now"
has "prompt flags apps it cannot place" "$out" "mystery  (bundle not found)  <- cannot tell if it is running"
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

print "8. wrapper: HOMEBREW_UPGRADE_GREEDY scans the greedy set"
out="$(HOMEBREW_UPGRADE_GREEDY=1 run_wrapper q 'upgrade')"
has "greedy env surfaces an auto_updates app" "$out" "zoom"
has "greedy env passes --greedy to the scan" "$(cat "$EVENTS")" "brew outdated --cask --json=v2 --greedy"

print "9. helper fails closed when a lookup fails"
STUB_BREW_INFO_FAIL=1 run_helper --greedy >/dev/null
rc=$?
(( rc == 1 )) && pass "brew info failure exits 1" || fail "brew info failure exited $rc"
out="$(STUB_EVENTS="$EVENTS" STUB_BREW_INFO_FAIL=1 BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" \
    BRC_PMSET_BIN="$BIN/pmset" "$HELPER" --greedy --outdated-names 2>/dev/null)"
[[ -z "$out" ]] && pass "failed lookup never reports casks as safe" || fail "failed lookup printed: $out"

print "10. wrapper fails closed when the scan fails"
out="$(STUB_BREW_INFO_FAIL=1 run_wrapper y 'upgrade --greedy')"
lacks "no upgrade runs after a failed scan" "$(cat "$EVENTS")" "brew upgrade"
has "failure is explained" "$out" "could not tell which apps are running"

print "11. wrapper keeps the exact greedy flag"
run_wrapper y 'upgrade --greedy-latest' >/dev/null
ev="$(cat "$EVENTS")"
has "scan uses --greedy-latest" "$ev" "brew outdated --cask --json=v2 --greedy-latest"
has "upgrade uses --greedy-latest" "$ev" "brew upgrade --cask --greedy-latest slack"
lacks "flag is not widened to --greedy" "$ev" "--greedy "

print "12. HOMEBREW_CASK_OPTS --appdir moves the app directory"
out="$(STUB_EVENTS="$EVENTS" BRC_BREW_BIN="$BIN/brew" BRC_PS_BIN="$BIN/ps" BRC_PMSET_BIN="$BIN/pmset" \
    HOMEBREW_CASK_OPTS="--no-quarantine --appdir=/Users/me/Apps" "$HELPER" 2>&1)"
has "slack found under the custom appdir" "$out" $'slack\t/Users/me/Apps/Slack.app\t40002'

print "13. wrapper keeps combined greedy flags"
run_wrapper y 'upgrade --greedy-latest --greedy-auto-updates' >/dev/null
ev="$(cat "$EVENTS")"
has "scan keeps both greedy flags" "$ev" "brew outdated --cask --json=v2 --greedy-latest --greedy-auto-updates"
has "upgrade keeps both greedy flags" "$ev" "brew upgrade --cask --greedy-latest --greedy-auto-updates slack"

print "14. wrapper treats -g as --greedy"
run_wrapper q 'upgrade -g' >/dev/null
has "-g scans the greedy set" "$(cat "$EVENTS")" "brew outdated --cask --json=v2 --greedy"

print "15. an --appdir saved at install time is honoured without HOMEBREW_CASK_OPTS"
mkdir -p "$WORK/Caskroom/slack/.metadata"
print '{"default":{"appdir":"/Applications"},"env":{},"explicit":{"appdir":"/Users/me/Apps"}}' \
    > "$WORK/Caskroom/slack/.metadata/config.json"
out="$(BRC_CASKROOM="$WORK/Caskroom" run_helper)"
has "slack found under its saved appdir" "$out" $'slack\t/Users/me/Apps/Slack.app\t40002'
has "casks without a saved appdir keep the default" "$out" $'telegram\t/Applications/Telegram.app\t8737'
print '{"default":{"appdir":"/Applications"},"env":{"appdir":"/Users/me/Apps"},"explicit":{}}' \
    > "$WORK/Caskroom/slack/.metadata/config.json"
out="$(BRC_CASKROOM="$WORK/Caskroom" run_helper)"
has "an appdir saved from the environment is honoured too" "$out" $'slack\t/Users/me/Apps/Slack.app\t40002'

print ""
print "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
