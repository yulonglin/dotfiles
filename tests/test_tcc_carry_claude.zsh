#!/usr/bin/env zsh
# Builds tools/tcc-carry-claude and runs it against a synthetic TCC database, never the live one.
# The versions directory holds symlinks to the installed Claude Code binary, so the signature
# check runs against a real Anthropic-signed file. macOS only; skips when that binary is absent.
set -uo pipefail

REPO="${0:A:h:h}"
CLAUDE_BIN="${$(readlink -f "$HOME/.local/bin/claude" 2>/dev/null):-}"
if [[ "$(uname -s)" != Darwin || ! -x "$CLAUDE_BIN" ]]; then
    print "SKIP: needs macOS and an installed native Claude Code"
    exit 0
fi

mkdir -p "$REPO/tmp" || { print -ru2 -- "FATAL: cannot create $REPO/tmp"; exit 1 }
WORK="$(mktemp -d "$REPO/tmp/tcc-carry-test.XXXXXX")" \
    || { print -ru2 -- "FATAL: mktemp -d under $REPO/tmp failed"; exit 1 }
[[ -n "$WORK" && -d "$WORK" && "$WORK" == "$REPO/tmp/"* ]] \
    || { print -ru2 -- "FATAL: work dir not under $REPO/tmp: ${WORK:-<empty>}"; exit 1 }
trap 'rm -rf "${WORK:?}"' EXIT
PASS=0 FAIL=0

check() {  # check <name> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        (( PASS++ ))
    else
        (( FAIL++ ))
        print -ru2 -- "FAIL: $1: expected [$2], got [$3]"
    fi
}

BIN="$WORK/tcc-carry-claude"
swiftc -O -o "$BIN" "$REPO/tools/tcc-carry-claude/main.swift" || { print -ru2 -- "FATAL: build failed"; exit 1 }

VERSIONS="$WORK/versions"
mkdir -p "$VERSIONS"
for v in 1.0.0 1.0.1 1.0.2; do ln -s "$CLAUDE_BIN" "$VERSIONS/$v"; done
print -n 'not a binary' > "$VERSIONS/9.9.9"

DB="$WORK/TCC.db"
sqlite3 "$DB" <<'SQL'
CREATE TABLE access (service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL,
  auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL, csreq BLOB,
  policy_id INTEGER, indirect_object_identifier_type INTEGER,
  indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB,
  flags INTEGER, last_modified INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
  pid INTEGER, pid_version INTEGER, boot_uuid TEXT NOT NULL DEFAULT 'UNUSED',
  last_reminded INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
  PRIMARY KEY (service, client, client_type, indirect_object_identifier));
SQL

row() {  # row <service> <version> <auth_value> <auth_reason> <last_modified> [target]
    sqlite3 "$DB" "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version,
      indirect_object_identifier, flags, last_modified, last_reminded)
      VALUES ('$1', '$VERSIONS/$2', 1, $3, $4, 1, '${6:-UNUSED}', 0, $5, 0);"
}
value() {  # value <service> <version> [target]
    sqlite3 "$DB" "SELECT auth_value || '@' || last_modified FROM access WHERE service = '$1'
      AND client = '$VERSIONS/$2' AND indirect_object_identifier = '${3:-UNUSED}';"
}

# Downloads: an allow and a later deny on different versions; the deny is the latest answer.
row kTCCServiceSystemPolicyDownloadsFolder 1.0.0 2 2 100
row kTCCServiceSystemPolicyDownloadsFolder 1.0.1 0 2 200
# Documents: allow and deny in the same second cannot be ordered, so the deny must win
# whichever row was inserted first.
row kTCCServiceSystemPolicyDocumentsFolder 1.0.0 2 2 300
row kTCCServiceSystemPolicyDocumentsFolder 1.0.1 0 2 300
# Apple Events, set in System Settings (reason 3), with a target app.
row kTCCServiceAppleEvents 1.0.0 2 3 400 com.apple.systemevents
# Desktop was allowed before, but is always denied.
row kTCCServiceSystemPolicyDesktopFolder 1.0.0 2 2 500
# Reason 4 is not a user answer and must not carry.
row kTCCServiceMediaLibrary 1.0.0 2 4 600
# 1.0.1 already answered Apple Events itself; that row must not change.
row kTCCServiceAppleEvents 1.0.1 0 2 50 com.apple.systemevents

out="$("$BIN" --db "$DB" --versions-dir "$VERSIONS")"
check "exit status" 0 $?

# "@200" also proves the copy kept the answer's own time, so it cannot outrank a later answer.
check "latest answer carries" "0@200" "$(value kTCCServiceSystemPolicyDownloadsFolder 1.0.2)"
check "same-second tie resolves to deny" "0@300" "$(value kTCCServiceSystemPolicyDocumentsFolder 1.0.2)"
check "reason-3 target carries" "2@400" "$(value kTCCServiceAppleEvents 1.0.2 com.apple.systemevents)"
check "desktop overridden to deny" "0@500" "$(value kTCCServiceSystemPolicyDesktopFolder 1.0.2)"
check "reason 4 not carried" "" "$(value kTCCServiceMediaLibrary 1.0.2)"
check "existing row untouched" "0@50" "$(value kTCCServiceAppleEvents 1.0.1 com.apple.systemevents)"
check "csreq written" 1 "$(sqlite3 "$DB" "SELECT count(DISTINCT csreq) FROM access WHERE client = '$VERSIONS/1.0.2'")"
check "unsigned file skipped" 1 "$(print -r -- "$out" | grep -c 'skip 9.9.9')"
check "unsigned file got no rows" 0 "$(sqlite3 "$DB" "SELECT count(*) FROM access WHERE client = '$VERSIONS/9.9.9'")"

before="$(sqlite3 "$DB" 'SELECT count(*) FROM access')"
"$BIN" --db "$DB" --versions-dir "$VERSIONS" >/dev/null
check "second run is a no-op" "$before" "$(sqlite3 "$DB" 'SELECT count(*) FROM access')"

print "tcc-carry-claude: $PASS passed, $FAIL failed"
(( FAIL == 0 ))
