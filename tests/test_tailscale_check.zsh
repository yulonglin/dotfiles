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
cat "$SHIM_DIR/ifconfig.txt"
EOF
# The interfaces as they stood that night; utun8 is Tailscale's own.
ifconfig_default() {
  print -r -- 'lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
	inet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 172.21.49.213 netmask 0xfffffe00 broadcast 172.21.49.255
utun8: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1280
	inet 100.80.44.37 --> 100.80.44.37 netmask 0xffffffff
utun9: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
	inet 10.100.0.2 --> 10.100.0.2 netmask 0xfffff000
en9: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 172.21.33.137 netmask 0xfffffe00 broadcast 172.21.33.255'
}
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

OFFLINE='{"BackendState":"Running","Self":{"Online":false,"TailscaleIPs":["100.80.44.37"]},"Health":["no network map"]}'
ifconfig_default >$shims/ifconfig.txt

# 1. The 2026-09-30 failure: offline, every dial from en0 stuck in SYN_SENT.
print -r -- $OFFLINE >$shims/status.json
{ sock 172.21.49.213.61898 SYN_SENT; sock 172.21.49.213.62095 SYN_SENT; } >$shims/netstat.txt
print en0 >$shims/dead_ifcs
out=$(run); rc=$?
[[ $rc == 1 && $out == *"STUCK: Tailscale dials out from en0"* ]] && ok "stuck on en0 -> STUCK, exit 1" || fail "stuck scenario: rc=$rc
$out"
[[ $out != *utun8* ]] && ok "Tailscale's own utun is not probed" || fail "probed Tailscale's own interface"

# 1b. An old ESTABLISHED socket on the dead link does not hide the stuck dials.
{ sock 172.21.49.213.61000 ESTABLISHED; sock 172.21.49.213.61898 SYN_SENT; } >$shims/netstat.txt
out=$(run); rc=$?
[[ $rc == 1 && $out == *"STUCK: Tailscale dials out from en0"* ]] && ok "stale ESTABLISHED on en0 -> still STUCK" || fail "stale-established scenario: rc=$rc
$out"

# 1c. Offline, but Tailscale also has a live connection through a working link: not STUCK.
{ sock 172.21.49.213.61898 SYN_SENT; sock 172.21.33.137.62000 ESTABLISHED; } >$shims/netstat.txt
out=$(run); rc=$?
[[ $rc == 1 && $out != *STUCK* ]] && ok "working path elsewhere -> not STUCK" || fail "path-elsewhere scenario: rc=$rc
$out"

# 1d. Online with an unrelated warning and a dead en0: not STUCK.
print '{"BackendState":"Running","Self":{"Online":true,"TailscaleIPs":["100.80.44.37"]},"Health":["some DNS warning"]}' >$shims/status.json
sock 172.21.49.213.61898 SYN_SENT >$shims/netstat.txt
out=$(run); rc=$?
[[ $rc == 1 && $out != *STUCK* ]] && ok "online with a warning -> not STUCK" || fail "online-warning scenario: rc=$rc
$out"

# 1e. A real link holding a CGNAT 100.x address is probed, not mistaken for Tailscale's.
ifconfig_default | sed 's/172\.21\.33\.137/100.70.1.5/' >$shims/ifconfig.txt
print -r -- $OFFLINE >$shims/status.json
sock 172.21.49.213.61898 SYN_SENT >$shims/netstat.txt
out=$(run); rc=$?
[[ $out == *"en9      yes"* && $out == *STUCK* ]] && ok "CGNAT upstream address still probed" || fail "cgnat scenario: rc=$rc
$out"
ifconfig_default >$shims/ifconfig.txt

# 2. After the restart: online, dials established through utun9; en0 still dead.
print '{"BackendState":"Running","Self":{"Online":true,"TailscaleIPs":["100.80.44.37"]},"Health":[]}' >$shims/status.json
sock 10.100.0.2.62589 ESTABLISHED >$shims/netstat.txt
out=$(run); rc=$?
[[ $rc == 0 && $out == *"OK: online"* ]] && ok "healthy -> OK, exit 0" || fail "healthy scenario: rc=$rc
$out"

# 3. No IPv4 interface reaches the control plane.
print -r -- $OFFLINE >$shims/status.json
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
