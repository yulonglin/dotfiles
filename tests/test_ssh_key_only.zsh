#!/usr/bin/env zsh
# Pins custom_bins/ssh-key-only: how `check` reads the server's offered methods,
# and the lockout guard in `install --dry-run`.
#
# check must treat keyboard-interactive as a password method: on macOS that is how
# a password arrives (through PAM), so a server offering only it still takes
# passwords. The guard must refuse when authorized_keys holds no key, because a
# key-only sshd on such a machine locks its owner out.
#
# A fake `ssh` on PATH prints canned server answers, so nothing here connects.
emulate -L zsh
setopt pipe_fail

REPO_ROOT=${0:A:h:h}
BIN="$REPO_ROOT/custom_bins/ssh-key-only"
TMP=$(mktemp -d) || { print -u2 "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
fails=0
fail() { print -u2 "FAIL: $1"; (( fails++ )); }
ok()   { print "  ok   $1"; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/ssh" <<'EOF'
#!/usr/bin/env zsh
print -u2 -r -- "$FAKE_SSH_OUT"
exit 255
EOF
chmod +x "$TMP/bin/ssh"

expect_check() {
  local want=$1 answer=$2 label=$3 rc=0
  FAKE_SSH_OUT=$answer PATH="$TMP/bin:$PATH" NO_COLOR=1 "$BIN" check >/dev/null 2>&1 || rc=$?
  if (( rc == want )); then ok "$label → $rc"; else fail "$label: want $want, got $rc"; fi
}

expect_check 0 'yulong@localhost: Permission denied (publickey).' "publickey only"
expect_check 1 'yulong@localhost: Permission denied (publickey,password,keyboard-interactive).' "password offered"
expect_check 1 'root@localhost: Permission denied (publickey,keyboard-interactive).' "keyboard-interactive alone counts as a password"
expect_check 3 'ssh: connect to host localhost port 22: Connection refused' "no server"
expect_check 2 'kex_exchange_identification: read: Connection reset by peer' "unreadable answer"

# --- lockout guard ----------------------------------------------------------
home="$TMP/home"; mkdir -p "$home/.ssh"
rc=0; HOME=$home NO_COLOR=1 "$BIN" install --dry-run >/dev/null 2>&1 || rc=$?
(( rc == 1 )) && ok "dry-run refuses with no authorized_keys" || fail "dry-run without keys: want 1, got $rc"

print '# just a comment' > "$home/.ssh/authorized_keys"
rc=0; HOME=$home NO_COLOR=1 "$BIN" install --dry-run >/dev/null 2>&1 || rc=$?
(( rc == 1 )) && ok "dry-run refuses with only comments" || fail "dry-run with comments: want 1, got $rc"

print 'from="100.64.0.0/10" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotARealKey test' > "$home/.ssh/authorized_keys"
rc=0; HOME=$home NO_COLOR=1 "$BIN" install --dry-run >/dev/null 2>&1 || rc=$?
(( rc == 0 )) && ok "dry-run passes with an optioned key" || fail "dry-run with a key: want 0, got $rc"

# The drop-in must switch off both password paths.
grep -qx 'PasswordAuthentication no' "$REPO_ROOT/config/sshd/01-key-only.conf" \
  && grep -qx 'KbdInteractiveAuthentication no' "$REPO_ROOT/config/sshd/01-key-only.conf" \
  && ok "drop-in turns off password and keyboard-interactive" \
  || fail "drop-in is missing one of the two lines"

(( fails == 0 )) && print "PASS" || { print -u2 "$fails failure(s)"; exit 1; }
