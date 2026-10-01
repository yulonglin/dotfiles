#!/usr/bin/env zsh
# Pins custom_bins/tailscale-check's verdicts against the state captured on
# 2026-09-30, when Tailscale kept dialling from a dead Wi-Fi link (en0) while
# Ethernet (en9) and the NordVPN tunnel (utun9) reached the control plane fine.
#
# The live failure cannot be produced on demand, so tailscale, ifconfig, netstat
# and curl are replaced by shims on PATH that replay that state. The socket
# section is macOS-only (netstat -anv), so the test is skipped elsewhere.
emulate -L zsh

REPO_ROOT=${0:A:h:h}
SCRIPT=$REPO_ROOT/custom_bins/tailscale-check
fails=0
fail() { print -u2 "FAIL: $1"; (( fails++ )); }
ok() { print "  ok   $1"; }

if [[ $OSTYPE != darwin* ]]; then
  print "skip: tailscale-check reads sockets with macOS netstat"
  exit 77
fi

shims=$(mktemp -d "${TMPDIR:-/tmp}/ts-check-test.XXXXXX")
trap 'rm -rf "$shims"' EXIT

# Shims read the scenario from files the test writes before each run.
cat >"$shims/tailscale" <<'EOF'
#!/bin/sh
cat "$SHIM_DIR/status.json"
EOF
cat >"$shims/ifconfig" <<'EOF'
#!/bin/sh
cat <<'IF'
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 172.21.49.213 netmask 0xfffffe00 broadcast 172.21.49.255
utun8: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1280
	inet 100.80.44.37 --> 100.80.44.37 netmask 0xffffffff
utun9: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
	inet 10.100.0.2 --> 10.100.0.2 netmask 0xfffff000
en9: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 172.21.33.137 netmask 0xfffffe00 broadcast 172.21.33.255
IF
EOF
cat >"$shims/netstat" <<'EOF'
#!/bin/sh
cat "$SHIM_DIR/netstat.txt"
EOF
cat >"$shims/curl" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  [ "$1" = --interface ] && ifc=$2
  shift
done
if grep -qx "$ifc" "$SHIM_DIR/dead_ifcs"; then printf 000; else printf 200; fi
EOF
chmod +x $shims/*
export SHIM_DIR=$shims

run() { PATH=$shims:$PATH $SCRIPT 2>&1; }
sock() { print "tcp4       0      0  $1    192.200.0.109.443      $2               0            0  131072  131072 io.tailscale.ipn:1875   00184 00000000 000000000065e297 00000080 04000900      2      0 000000"; }

# 1. The 2026-09-30 failure: offline, every dial from en0 stuck in SYN_SENT.
print '{"BackendState":"Running","Self":{"Online":false},"Health":["Tailscale hasn'"'"'t received a network map from the coordination server in 2m10s."]}' >$shims/status.json
{ sock 172.21.49.213.61898 SYN_SENT; sock 172.21.49.213.62095 SYN_SENT; } >$shims/netstat.txt
print en0 >$shims/dead_ifcs
out=$(run); rc=$?
[[ $rc == 1 && $out == *"STUCK: Tailscale dials out from en0"* ]] && ok "stuck on en0 -> STUCK, exit 1" || fail "stuck scenario: rc=$rc
$out"
[[ $out != *utun8* ]] && ok "Tailscale's own utun is not probed" || fail "probed Tailscale's own interface"

# 2. After the restart: online, dials established through utun9; en0 still dead.
print '{"BackendState":"Running","Self":{"Online":true},"Health":[]}' >$shims/status.json
sock 10.100.0.2.62589 ESTABLISHED >$shims/netstat.txt
out=$(run); rc=$?
[[ $rc == 0 && $out == *"OK: online"* ]] && ok "healthy -> OK, exit 0" || fail "healthy scenario: rc=$rc
$out"

# 3. Nothing reaches the control plane: the network is down, not Tailscale.
print '{"BackendState":"Running","Self":{"Online":false},"Health":["no network map"]}' >$shims/status.json
sock 172.21.49.213.61898 SYN_SENT >$shims/netstat.txt
print -l en0 en9 utun9 >$shims/dead_ifcs
out=$(run); rc=$?
[[ $rc == 1 && $out == *"NO EGRESS"* ]] && ok "no egress -> NO EGRESS, exit 1" || fail "no-egress scenario: rc=$rc
$out"

# 4. Backend not running.
print '{"BackendState":"Stopped"}' >$shims/status.json
out=$(run); rc=$?
[[ $rc == 2 ]] && ok "stopped backend -> exit 2" || fail "stopped scenario: rc=$rc
$out"

(( fails == 0 )) && print "PASS" || { print -u2 "$fails failure(s)"; exit 1; }
