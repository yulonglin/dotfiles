#!/usr/bin/env zsh
# Pins app-picker's registry semantics end to end: `default=exclude` rows never reach the
# Brewfile, `--installed` preselects from machine state, and the audit names what to
# uninstall. brew and the App Store are stubbed — a fake `brew` on PATH answers the four
# subcommands the picker calls, and APP_PICKER_APPS_DIR points at a fake /Applications
# with _MASReceipt markers — so this runs anywhere in seconds.
set -uo pipefail

REPO="${0:A:h:h}"
mkdir -p "$REPO/tmp" || { print -ru2 -- "FATAL: cannot create $REPO/tmp"; exit 1 }
WORK="$(mktemp -d "$REPO/tmp/app-picker-test.XXXXXX")" \
    || { print -ru2 -- "FATAL: mktemp -d under $REPO/tmp failed"; exit 1 }
[[ -n "$WORK" && -d "$WORK" && "$WORK" == "$REPO/tmp/"* ]] \
    || { print -ru2 -- "FATAL: work dir not under $REPO/tmp: ${WORK:-<empty>}"; exit 1 }
trap 'rm -rf "${WORK:?}"' EXIT
PASS=0 FAIL=0

check() {  # check <label> <haystack> <needle>
    if [[ "$2" == *"$3"* ]]; then print -r -- "  ok   $1"; (( PASS++ ))
    else print -r -- "  FAIL $1 -- expected to find: $3"; (( FAIL++ )); fi
}
check_not() {
    if [[ "$2" != *"$3"* ]]; then print -r -- "  ok   $1"; (( PASS++ ))
    else print -r -- "  FAIL $1 -- should NOT contain: $3"; (( FAIL++ )); fi
}

# ─── Fixture: registry, fake dotfiles root, fake brew, fake /Applications ─────
DOT="$WORK/dot"; mkdir -p "$DOT/config" "$DOT/scripts/shared" "$WORK/bin" "$WORK/apps"
CONF="$DOT/config/apps.conf"; BREWFILE="$DOT/config/Brewfile"
cat > "$CONF" <<'EOF'
# method | id | category | tier | default | name | description | auth
cask|alpha|misc|1|true|Alpha|Default on; installed|none
cask|beta|misc|2|false|Beta|Default off; installed|none
cask|gamma|misc|2|true|Gamma|Default on; NOT installed|login
cask|omega|misc|2|exclude|Omega|Excluded 2026-09-03 — still installed|none
brew|toolx|misc|2|true|ToolX|Formula; installed|none
mas|111|text|2|true|Notes App|Installed as "Notes App.app"|none
mas|222|text|2|true|Things 3|Installed as "Things.app" — first-word match|none
mas|333|text|2|exclude|OldMas|Excluded; installed|none
EOF
# config.sh names `declared-cli`, so the audit must not flag that cask or formula.
print -r -- 'PACKAGES_MACOS=("declared-cli")' > "$DOT/config.sh"
: > "$DOT/scripts/shared/helpers.sh"

cat > "$WORK/bin/brew" <<'EOF'
#!/usr/bin/env zsh
case "$1 $2" in
    "list --cask")  print -l alpha beta omega declared-cli stray-cask ;;
    "leaves --installed-on-request") print -l toolx declared-cli acme/tap/orphan ;;
    "tap ")         print -l homebrew/core homebrew/cask acme/tap ;;
    "desc --cask")  shift 2; for t in "$@"; do print -r -- "$t: (Desc) fake"; done ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/brew"
for app in "Notes App" "Things" "OldMas" "Mystery"; do
    mkdir -p "$WORK/apps/$app.app/Contents/_MASReceipt"; : > "$WORK/apps/$app.app/Contents/_MASReceipt/receipt"
done
mkdir -p "$WORK/apps/NotFromStore.app/Contents"

# Hardlink the real script so ${0:A:h} still resolves; DOT_DIR overrides its repo root.
ln "$REPO/custom_bins/app-picker" "$WORK/bin/app-picker" 2>/dev/null || cp "$REPO/custom_bins/app-picker" "$WORK/bin/app-picker"
run() { PATH="$WORK/bin:$PATH" DOT_DIR="$DOT" APP_PICKER_APPS_DIR="$WORK/apps" NON_INTERACTIVE=true \
        zsh "$WORK/bin/app-picker" --conf "$CONF" --file "$BREWFILE" "$@" 2>&1; }

# ─── 1. --defaults: excludes never emitted, default=false omitted ─────────────
print -r -- "1. --defaults --dry-run"
out="$(run --defaults --dry-run --no-audit)"
check    "default=true cask emitted"        "$out" 'cask "alpha"'
check    "default=true missing cask still emitted (install list)" "$out" 'cask "gamma"'
check_not "default=false cask omitted"      "$out" 'cask "beta"'
check_not "exclude cask never emitted"      "$out" 'cask "omega"'
check_not "exclude mas never emitted"       "$out" 'id: 333'
check    "mas line format"                  "$out" 'mas "Notes App", id: 111'
check    "brew mas prelude when mas rows"   "$out" 'brew "mas"'
[[ -f "$BREWFILE" ]] && { print -r -- "  FAIL --dry-run wrote a Brewfile"; (( FAIL++ )) } || { print -r -- "  ok   --dry-run writes nothing"; (( PASS++ )) }

# ─── 2. --installed: preselect from machine state ─────────────────────────────
print -r -- "2. --installed"
out="$(run --installed --no-audit)"
check    "wrote Brewfile"                   "$out" "Wrote"
bf="$(<"$BREWFILE")"
check    "installed default=false cask selected" "$bf" 'cask "beta"'
check_not "default=true but absent cask NOT selected" "$bf" 'cask "gamma"'
check_not "installed exclude cask still excluded" "$bf" 'cask "omega"'
check    "installed formula selected"       "$bf" 'brew "toolx"'
check    "mas exact-stem match"             "$bf" 'id: 111'
check    "mas first-word match (Things 3 ↔ Things.app)" "$bf" 'id: 222'
check_not "installed exclude mas still excluded" "$bf" 'id: 333'

# ─── 3. --audit against that Brewfile ─────────────────────────────────────────
print -r -- "3. --audit"
print -r -- 'cask "gamma"' >> "$BREWFILE"     # selected by hand, not installed → must show as missing
out="$(run --audit)"
check_not "Brewfile lines all resolve to registry rows" "$out" "no registry row"
check_not "selected+installed cask gets no uninstall cmd" "$out" "brew uninstall --cask alpha"
check_not "selected+installed formula gets no uninstall cmd" "$out" "brew uninstall toolx"
check    "selected but absent cask → install hint"  "$out" "Gamma (gamma)"
check    "excluded+installed cask → uninstall cmd" "$out" "brew uninstall --cask omega"
check    "excluded+installed mas → uninstall cmd"  "$out" "sudo mas uninstall 333"
check    "unregistered cask reported"       "$out" "stray-cask"
check_not "cask declared in config.sh not reported" "$out" "declared-cli:"
check    "unregistered App Store app → row template" "$out" "mas|?|<category>|2|false|Mystery|"
check_not "non-store app ignored"           "$out" "NotFromStore"
check    "orphan formula reported with tap prefix" "$out" "acme/tap/orphan"
check    "third-party tap reported"         "$out" "acme/tap"
check_not "core taps not reported"          "$out" "homebrew/core"
check_not "no cleanup advice"               "$out" "bundle cleanup"
check_not "no stray zsh 'local' echo"       "$out" $'\ns='

# ─── 4. Deselect via a hand-trimmed Brewfile → audit says uninstall ──────────
print -r -- "4. --audit after dropping beta from the Brewfile"
grep -v 'cask "beta"' "$BREWFILE" > "$BREWFILE.tmp" && mv "$BREWFILE.tmp" "$BREWFILE"
out="$(run --audit)"
check    "installed-but-unselected → uninstall cmd" "$out" "brew uninstall --cask beta"

# ─── 5. mas-get acquires only what the Brewfile selects (macOS: mas-get refuses elsewhere) ──
if [[ "$(uname -s)" == "Darwin" ]]; then
    print -r -- "5. mas-get --dry-run against the Brewfile"
    cat > "$WORK/bin/mas" <<'EOF'
#!/usr/bin/env zsh
case "$1" in list) exit 0 ;; *) exit 0 ;; esac
EOF
    chmod +x "$WORK/bin/mas"
    ln "$REPO/custom_bins/mas-get" "$WORK/bin/mas-get" 2>/dev/null || cp "$REPO/custom_bins/mas-get" "$WORK/bin/mas-get"
    # Brewfile from step 4 still selects 111 and 222; drop 222 to simulate a deselect.
    grep -v 'id: 222' "$BREWFILE" > "$BREWFILE.tmp" && mv "$BREWFILE.tmp" "$BREWFILE"
    out="$(PATH="$WORK/bin:$PATH" DOT_DIR="$DOT" zsh "$WORK/bin/mas-get" --conf "$CONF" --file "$BREWFILE" --dry-run 2>&1)"
    check    "selected mas row queued"           "$out" "Notes App (111)"
    check_not "deselected mas row not queued"    "$out" "(222)"
    check_not "excluded mas row not queued"      "$out" "(333)"
    out="$(PATH="$WORK/bin:$PATH" DOT_DIR="$DOT" zsh "$WORK/bin/mas-get" --conf "$CONF" --file "$WORK/no-such-brewfile" --dry-run 2>&1)"
    check    "no Brewfile → warns"               "$out" "No Brewfile"
    check    "no Brewfile → default=true rows"   "$out" "(222)"
    check_not "no Brewfile → exclude still skipped" "$out" "(333)"
fi

print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
