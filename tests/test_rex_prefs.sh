#!/usr/bin/env zsh
# Pins rex-prefs' custom-theme sync against a scratch defaults domain, never the live Rex one.
#
# Covers: capture writes Rex's themes to the JSON file; capture merges by id (a theme only in the
# file survives); apply writes the file's themes back as plist data without dropping a Rex-only
# theme; check reports drift and exits 0 when in sync.
set -euo pipefail

if [[ $(uname) != Darwin ]]; then
    print "SKIP: rex-prefs is macOS only"
    exit 0
fi

REPO_ROOT=${0:A:h:h}
BIN=$REPO_ROOT/custom_bins/rex-prefs
export REX_PREFS_DOMAIN="com.superlogical.rex.test-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rex-prefs-test.XXXXXX")
TSV=$WORK/ui-prefs.tsv
THEMES=$WORK/themes.json

cleanup() {
    defaults delete "$REX_PREFS_DOMAIN" >/dev/null 2>&1 || true
    rm -rf -- "$WORK" ~/Library/Preferences/"$REX_PREFS_DOMAIN".plist
}
trap cleanup EXIT

fail() {
    print -u2 "FAIL: $*"
    exit 1
}

write_live_themes() {  # JSON array -> Rex-style plist data
    defaults write "$REX_PREFS_DOMAIN" Workspace.customThemes -data "$(print -rn -- "$1" | xxd -p | tr -d '\n')"
}

live_theme_ids() {
    defaults export "$REX_PREFS_DOMAIN" - | python3 -c '
import json, plistlib, sys
print(" ".join(sorted(t["id"] for t in json.loads(plistlib.loads(sys.stdin.buffer.read())["Workspace.customThemes"]))))'
}

file_theme_ids() {
    python3 -c 'import json, sys; print(" ".join(sorted(t["id"] for t in json.load(open(sys.argv[1])))))' "$THEMES"
}

run() { "$BIN" --file "$TSV" --themes-file "$THEMES" "$@"; }

defaults write "$REX_PREFS_DOMAIN" Workspace.tabStyle -string horizontal
write_live_themes '[{"id":"a","name":"A","palette":{"background":"#000"}}]'

# 1. capture creates the themes file from Rex
run capture --quiet
[[ $(file_theme_ids) == "a" ]] || fail "capture did not write theme a (got: $(file_theme_ids))"
grep -q $'^tabStyle\tstring\thorizontal$' "$TSV" || fail "capture lost the scalar row"
run check >/dev/null || fail "check not in sync right after capture"

# 2. a theme only in the file survives capture (merge by id), and check flags it
python3 - "$THEMES" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.append({"id": "b", "name": "B", "palette": {"background": "#fff"}})
json.dump(d, open(p, "w"))
PY
run capture --quiet
[[ $(file_theme_ids) == "a b" ]] || fail "capture dropped file-only theme b (got: $(file_theme_ids))"
if run check >/dev/null; then fail "check missed theme b being absent from Rex"; fi

# 3. apply writes file themes into Rex as data and keeps a Rex-only theme
write_live_themes '[{"id":"a","name":"A","palette":{"background":"#000"}},{"id":"c","name":"C","palette":{}}]'
run apply >/dev/null
[[ $(defaults read-type "$REX_PREFS_DOMAIN" Workspace.customThemes) == "Type is data" ]] || fail "apply did not store themes as data"
[[ $(live_theme_ids) == "a b c" ]] || fail "apply result wrong (got: $(live_theme_ids))"

# 4. after capture, file and Rex agree
run capture --quiet
run check >/dev/null || fail "check not in sync after apply + capture"

print "PASS: rex-prefs custom-theme sync"
