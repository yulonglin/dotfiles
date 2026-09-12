#!/usr/bin/env zsh
# Pins app-picker's registry semantics end to end: a row in config/apps-excluded.conf never
# reaches the picker or the Brewfile, `--installed` preselects from machine state, and the
# audit names what to uninstall. brew and the App Store are stubbed — a fake `brew` on PATH answers the four
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
CONF="$DOT/config/apps.conf"; BREWFILE="$DOT/config/Brewfile"; XCONF="$DOT/config/apps-excluded.conf"
cat > "$CONF" <<'EOF'
# method | id | category | tier | default | name | description | auth
cask|alpha|misc|1|true|Alpha|Default on; installed|none
cask|beta|misc|2|false|Beta|Default off; installed|none
cask|gamma|misc|2|true|Gamma|Default on; NOT installed|login
brew|toolx|misc|2|true|ToolX|Formula; installed|none
mas|111|text|2|true|Notes App|Installed as "Notes App.app"|none
mas|222|text|2|true|Things 3|Installed as "Things.app" — first-word match|none
EOF
cat > "$XCONF" <<'EOF'
# method | id | name | since | why
cask|omega|Omega|2026-09-03|Still installed; superseded by Alpha
mas|333|OldMas|2026-09-03|Still installed; nothing uses it
EOF
# config.sh names `declared-cli`, so the audit must not flag that cask or formula;
# it also declares ok/tap/keeper, which makes ok/tap a sanctioned tap.
print -r -- 'PACKAGES_MACOS=("declared-cli")' > "$DOT/config.sh"
print -r -- 'PACKAGES_TRIAL_MACOS=("ok/tap/keeper")' >> "$DOT/config.sh"
: > "$DOT/scripts/shared/helpers.sh"

cat > "$WORK/bin/brew" <<'EOF'
#!/usr/bin/env zsh
case "$1 $2" in
    "list --cask")  print -l alpha beta omega declared-cli stray-cask ;;
    "leaves --installed-on-request") print -l toolx declared-cli acme/tap/orphan ok/tap/keeper ;;
    "tap ")         print -l homebrew/core homebrew/cask acme/tap ok/tap ;;
    "desc --cask")  shift 2; for t in "$@"; do print -r -- "$t: (Desc) fake"; done ;;
    "info --json=v2") cat "$(dirname "$0")/installed.json" ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$WORK/bin/brew"
# Provenance fixture: toolx (requested, in the registry) needs libfoo; declared-cli
# (requested, named in config.sh) needs nothing; libbar is an orphaned dependency.
cat > "$WORK/bin/installed.json" <<'EOF'
{"formulae":[
 {"name":"toolx","full_name":"toolx","desc":"Tool X","installed":[{"installed_on_request":true,"runtime_dependencies":[{"full_name":"libfoo"}]}]},
 {"name":"declared-cli","full_name":"declared-cli","desc":"Declared","installed":[{"installed_on_request":true,"runtime_dependencies":[]}]},
 {"name":"libfoo","full_name":"libfoo","desc":"lib","installed":[{"installed_on_request":false,"runtime_dependencies":[]}]},
 {"name":"libbar","full_name":"libbar","desc":"lib","installed":[{"installed_on_request":false,"runtime_dependencies":[]}]}
],"casks":[]}
EOF
for app in "Notes App" "Things" "OldMas" "Mystery"; do
    mkdir -p "$WORK/apps/$app.app/Contents/_MASReceipt"; : > "$WORK/apps/$app.app/Contents/_MASReceipt/receipt"
done
mkdir -p "$WORK/apps/NotFromStore.app/Contents"

# Hardlink the real script so ${0:A:h} still resolves; DOT_DIR overrides its repo root.
ln "$REPO/custom_bins/app-picker" "$WORK/bin/app-picker" 2>/dev/null || cp "$REPO/custom_bins/app-picker" "$WORK/bin/app-picker"
DEPS_DOC="$DOT/docs/brew-formulae.md"
run() { PATH="$WORK/bin:$PATH" DOT_DIR="$DOT" APP_PICKER_APPS_DIR="$WORK/apps" APP_PICKER_DEPS_DOC="$DEPS_DOC" NON_INTERACTIVE=true \
        zsh "$WORK/bin/app-picker" --conf "$CONF" --file "$BREWFILE" "$@" 2>&1; }

# ─── 1. --defaults: rejected apps never emitted, default=false omitted ────────
print -r -- "1. --defaults --dry-run"
out="$(run --defaults --dry-run --no-audit)"
check    "default=true cask emitted"        "$out" 'cask "alpha"'
check    "default=true missing cask still emitted (install list)" "$out" 'cask "gamma"'
check_not "default=false cask omitted"      "$out" 'cask "beta"'
check_not "rejected cask never emitted"     "$out" 'cask "omega"'
check_not "rejected mas never emitted"      "$out" 'id: 333'
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
check_not "installed rejected cask still kept out" "$bf" 'cask "omega"'
check    "installed formula selected"       "$bf" 'brew "toolx"'
check    "mas exact-stem match"             "$bf" 'id: 111'
check    "mas first-word match (Things 3 ↔ Things.app)" "$bf" 'id: 222'
check_not "installed rejected mas still kept out" "$bf" 'id: 333'

# ─── 3. --audit against that Brewfile ─────────────────────────────────────────
print -r -- "3. --audit"
print -r -- 'cask "gamma"' >> "$BREWFILE"     # selected by hand, not installed → must show as missing
out="$(run --audit)"
check_not "Brewfile lines all resolve to registry rows" "$out" "no registry row"
check_not "selected+installed cask gets no uninstall cmd" "$out" "brew uninstall --cask alpha"
check_not "selected+installed formula gets no uninstall cmd" "$out" "brew uninstall toolx"
check    "selected but absent cask → install hint"  "$out" "Gamma (gamma)"
check    "rejected+installed cask → uninstall cmd" "$out" "brew uninstall --cask omega"
check    "rejected section names the file"         "$out" "Rejected in apps-excluded.conf, still installed"
check    "rejected reason carries its date"        "$out" "2026-09-03 — Still installed; superseded by Alpha"
check_not "rejected cask not also called unregistered" "$out" "omega:"
check    "rejected+installed mas → uninstall cmd"  "$out" "sudo mas uninstall 333"
check    "unregistered cask reported"       "$out" "stray-cask"
check_not "cask declared in config.sh not reported" "$out" "declared-cli:"
check    "unregistered App Store app → row template" "$out" "mas|?|<category>|2|false|Mystery|"
check_not "non-store app ignored"           "$out" "NotFromStore"
check    "orphan formula reported with tap prefix" "$out" "acme/tap/orphan"
check    "third-party tap reported"         "$out" $'\n  acme/tap'
check    "sanctioned tap listed as exception" "$out" "exception on record"
check_not "sanctioned tap not under policy breach" "$out" $'policy: none'$'\n  ok/tap'
check_not "declared tap formula not an orphan" "$out" "ok/tap/keeper"$'\n'
check_not "core taps not reported"          "$out" "homebrew/core"
check_not "no cleanup advice"               "$out" "bundle cleanup"
check_not "no stray zsh 'local' echo"       "$out" $'\ns='

# ─── 4. Deselect via a hand-trimmed Brewfile → audit says uninstall ──────────
print -r -- "4. --audit after dropping beta from the Brewfile"
grep -v 'cask "beta"' "$BREWFILE" > "$BREWFILE.tmp" && mv "$BREWFILE.tmp" "$BREWFILE"
out="$(run --audit)"
check    "installed-but-unselected → uninstall cmd" "$out" "brew uninstall --cask beta"

# ─── 4b. --deps provenance doc: written by --audit, printed by --deps ──────────
print -r -- "4b. --deps"
[[ -f "$DEPS_DOC" ]] && { print -r -- "  ok   --audit regenerated the provenance doc"; (( PASS++ )) } \
                     || { print -r -- "  FAIL --audit did not write $DEPS_DOC"; (( FAIL++ )) }
out="$(run --deps)"
check    "requested formula declared in registry"  "$out" "| toolx | apps.conf |"
check    "requested formula declared in config.sh" "$out" "| declared-cli | config.sh |"
check    "dependency traced to its requester"      "$out" "| libfoo | toolx |"
check    "orphaned dependency named"               "$out" "Orphaned dependencies: libbar"
check    "doc says it is generated"                "$out" "GENERATED by"
[[ "$(<"$DEPS_DOC")" == "$out" ]] && { print -r -- "  ok   --deps prints exactly the written doc"; (( PASS++ )) } \
                                   || { print -r -- "  FAIL --deps output differs from the doc"; (( FAIL++ )) }

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
    check_not "rejected mas row not queued"      "$out" "(333)"
    out="$(PATH="$WORK/bin:$PATH" DOT_DIR="$DOT" zsh "$WORK/bin/mas-get" --conf "$CONF" --file "$WORK/no-such-brewfile" --dry-run 2>&1)"
    check    "no Brewfile → warns"               "$out" "No Brewfile"
    check    "no Brewfile → default=true rows"   "$out" "(222)"
    check_not "no Brewfile → rejected still skipped" "$out" "(333)"
fi

# ─── 6. --excluded: the rejected list as one screen ──────────────────────────
print -r -- "6. --excluded"
out="$(run --excluded)"
check    "names the rejected app"           "$out" "Omega"
check    "carries the decision date"        "$out" "2026-09-03"
check    "carries the reason"               "$out" "superseded by Alpha"
check    "flags one still on disk"          "$out" "STILL INSTALLED"
check    "offers the uninstall command"     "$out" "brew uninstall --cask omega"
check    "says how to reinstate"            "$out" "delete its line"
check_not "an installed non-rejected app is absent" "$out" "Beta"

# ─── 7. An id in both files is refused, not silently resolved ────────────────
print -r -- "7. same id in both files"
print -r -- 'cask|omega|misc|2|true|Omega|Now also in the registry|none' >> "$CONF"
out="$(run --defaults --dry-run --no-audit)"
check    "clash refused"                    "$out" "in BOTH"
check    "clash names the id"               "$out" "cask:omega"
check_not "clash writes no Brewfile lines"  "$out" 'cask "alpha"'
grep -v 'Now also in the registry' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"

print -r -- ""
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
