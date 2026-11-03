#!/usr/bin/env zsh
# Fixture tests for custom_bins/brew-orphans and the _brew_tidy step of the
# brew() wrapper in config/aliases/brew.sh. brew is a stub serving canned JSON:
# nothing here reaches the real Homebrew or removes anything.

emulate -L zsh
setopt no_unset

REPO_ROOT="${0:A:h:h}"
HELPER="$REPO_ROOT/custom_bins/brew-orphans"
WRAPPER="$REPO_ROOT/config/aliases/brew.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/brew-orphans-test.XXXXXX")"
trap '/bin/rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); print "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); print -u2 "FAIL - $1"; }
has() { [[ "$2" == *"$3"* ]] && pass "$1" || fail "$1 (missing: $3)"; }
lacks() { [[ "$2" != *"$3"* ]] && pass "$1" || fail "$1 (unexpected: $3)"; }

BIN="$WORK/bin"
mkdir -p "$BIN"
EVENTS="$WORK/events"

# The 2026-10-30 case and its neighbours:
#   poppler (requested) declares harfbuzz; harfbuzz declares icu4c@79. poppler's
#     record still lists icu4c@78, so only a reinstall frees it.
#   libold nothing needs; libchain only libold needs: both plain orphans.
#   srcbuilt was built from source: brew keeps it and its build dep buildtool.
#   tapped has no formula definition (a removed tap): its record is trusted.
#   cask gtool needs py314, not installed; py314 declares mpdec, which is kept.
cat > "$WORK/installed.json" <<'EOF'
{"formulae":[
 {"name":"poppler","full_name":"poppler","dependencies":["harfbuzz"],"installed":[{"installed_on_request":true,"poured_from_bottle":true,"runtime_dependencies":[{"full_name":"harfbuzz"},{"full_name":"icu4c@79"},{"full_name":"icu4c@78"}]}]},
 {"name":"harfbuzz","full_name":"harfbuzz","dependencies":["icu4c@79"],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[{"full_name":"icu4c@79"}]}]},
 {"name":"icu4c@79","full_name":"icu4c@79","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]},
 {"name":"icu4c@78","full_name":"icu4c@78","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]},
 {"name":"libold","full_name":"libold","dependencies":["libchain"],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[{"full_name":"libchain"}]}]},
 {"name":"libchain","full_name":"libchain","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]},
 {"name":"srcbuilt","full_name":"srcbuilt","dependencies":[],"build_dependencies":["buildtool"],"installed":[{"installed_on_request":false,"poured_from_bottle":false,"runtime_dependencies":[]}]},
 {"name":"buildtool","full_name":"buildtool","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]},
 {"name":"tapped","full_name":"gone/tap/tapped","installed":[{"installed_on_request":true,"poured_from_bottle":true,"runtime_dependencies":[{"full_name":"libtap"}]}]},
 {"name":"libtap","full_name":"libtap","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]},
 {"name":"mpdec","full_name":"mpdec","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]}
],"casks":[
 {"token":"gtool","depends_on":{"formula":["py314"]}}
]}
EOF
cat > "$WORK/py314.json" <<'EOF'
{"formulae":[{"name":"py314","full_name":"py314","dependencies":["mpdec"],"installed":[]}],"casks":[]}
EOF
cat > "$WORK/clean.json" <<'EOF'
{"formulae":[
 {"name":"tool","full_name":"tool","dependencies":["lib"],"installed":[{"installed_on_request":true,"poured_from_bottle":true,"runtime_dependencies":[{"full_name":"lib"}]}]},
 {"name":"lib","full_name":"lib","dependencies":[],"installed":[{"installed_on_request":false,"poured_from_bottle":true,"runtime_dependencies":[]}]}
],"casks":[]}
EOF

# brew stub: `info --json=v2 --installed` serves $STUB_INSTALLED, `--formula py314`
# serves its definition; every other call is recorded and does nothing.
cat > "$BIN/brew" <<'EOF'
#!/bin/zsh
case "$*" in
  "info --json=v2 --installed") cat "$STUB_INSTALLED" ;;
  "info --json=v2 --formula py314") cat "$STUB_DIR/py314.json" ;;
  *) print -r -- "brew $*" >> "$STUB_EVENTS" ;;
esac
EOF
chmod +x "$BIN/brew"

run_helper() {
    STUB_INSTALLED="${STUB_INSTALLED:-$WORK/installed.json}" STUB_DIR="$WORK" STUB_EVENTS="$EVENTS" \
        BREW_ORPHANS_BREW="$BIN/brew" "$HELPER" "$@" 2>&1
}

print "1. report: plain orphans and a dependency held by a stale record"
out="$(run_helper --color=never)"
rc=$?
(( rc == 1 )) && pass "exit 1 when something can be removed" || fail "exit was $rc"
has "stale-record dep named with its holder" "$out" "icu4c@78  listed only in the install record of poppler, whose current formula no longer needs it"
has "plain orphan" "$out" "libold    no installed formula or cask needs it"
has "orphan of an orphan" "$out" "libchain  needed only by libold, also removed"
has "fix reinstalls the holder" "$out" "  brew reinstall poppler"
has "then autoremoves" "$out" "  brew autoremove"
lacks "a missing cask dependency is not reported" "$out" "py314"
lacks "needed dep is never listed" "$out" "icu4c@79"
lacks "source build kept" "$out" "srcbuilt"
lacks "build dep of a source build kept" "$out" "buildtool"
lacks "record trusted when no definition" "$out" "libtap"
lacks "dep of a missing cask dep kept, as brew does" "$out" "mpdec "
lacks "plain output has no escape codes" "$out" $'\e['

print "2. --reinstall-names and --json"
[[ "$(run_helper --reinstall-names)" == poppler ]] && pass "--reinstall-names lists only poppler" \
    || fail "--reinstall-names was: $(run_helper --reinstall-names)"
json="$(run_helper --json)"
has "json orphans" "$json" '"libchain",'
has "json freed" "$json" '"icu4c@78"'
has "json still lists the missing cask dependency" "$json" '"py314": ['

print "3. colour only when asked or on a terminal, never under NO_COLOR"
has "--color=always paints" "$(run_helper --color=always)" $'\e[1m'
lacks "NO_COLOR wins over always" "$(NO_COLOR=1 run_helper --color=always)" $'\e['

print "4. clean install"
out="$(STUB_INSTALLED="$WORK/clean.json" run_helper)"
rc=$?
(( rc == 0 )) && pass "exit 0 when clean" || fail "clean exit was $rc"
has "says so" "$out" "every installed formula is needed"

print "5. brew failure exits 2"
STUB_INSTALLED="$WORK/absent.json" run_helper >/dev/null
rc=$?
(( rc == 2 )) && pass "unreadable brew output exits 2" || fail "failure exit was $rc"

print "6. wrapper: a formula upgrade offers the tidy, and yes runs it"
cat > "$BIN/brew-orphans" <<EOF
#!/bin/zsh
exec env STUB_INSTALLED="\${STUB_INSTALLED:-$WORK/installed.json}" STUB_DIR="$WORK" STUB_EVENTS="$EVENTS" BREW_ORPHANS_BREW="$BIN/brew" "$HELPER" "\$@"
EOF
: > "$BIN/reset-mac-media"
chmod +x "$BIN/brew-orphans" "$BIN/reset-mac-media"
# brew-running-casks must exist for the wrapper to engage; --formula skips its scan.
: > "$BIN/brew-running-casks"; chmod +x "$BIN/brew-running-casks"
run_wrapper() {  # run_wrapper <stdin> <brew args>
    : > "$EVENTS"
    print -rn -- "$1" | PATH="$BIN:/usr/bin:/bin" OSTYPE=darwin25 STUB_EVENTS="$EVENTS" \
        HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_AUTOREMOVE="${NOAR:-}" zsh -fc "source '$WRAPPER'; brew $2" 2>&1
}
out="$(run_wrapper $'\n' 'upgrade --formula')"
ev="$(cat "$EVENTS")"
has "report shown after the upgrade" "$out" "icu4c@78"
has "holder reinstalled" "$ev" "brew reinstall poppler"
has "autoremove run" "$ev" "brew autoremove"

print "7. wrapper: no, end of input, opt-out and cask-only upgrades never remove"
run_wrapper $'n\n' 'upgrade --formula' >/dev/null
lacks "no declines" "$(cat "$EVENTS")" "autoremove"
run_wrapper '' 'upgrade --formula' >/dev/null
lacks "end of input declines" "$(cat "$EVENTS")" "autoremove"
out="$(NOAR=1 run_wrapper $'\n' 'upgrade --formula')"
lacks "HOMEBREW_NO_AUTOREMOVE skips the step" "$out" "brew-orphans"
lacks "HOMEBREW_NO_AUTOREMOVE removes nothing" "$(cat "$EVENTS")" "autoremove"
out="$(run_wrapper $'\n' 'upgrade --cask')"
lacks "cask-only upgrade skips the step" "$out" "brew-orphans"
out="$(STUB_INSTALLED="$WORK/clean.json" run_wrapper $'\n' 'upgrade --formula')"
lacks "clean install prints nothing" "$out" "brew-orphans"

print
print "passed $PASS, failed $FAIL"
(( FAIL == 0 ))
