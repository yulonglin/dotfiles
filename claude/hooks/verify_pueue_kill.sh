#!/bin/bash
set -euo pipefail

# PostToolUse(Bash): `pueue kill` does NOT stop a task whose command is
# `systemd-run ... -- <payload>`.
#
# systemd-run hands the payload to a transient unit that systemd owns. pueue
# signals only its own child -- the systemd-run client -- then reports the task
# "Killed". The unit and the real workload survive, reparented to the user
# systemd manager and outside pueue's process tree entirely.
#
# Cost of learning this the hard way (2026-08-12): a run believed killed at
# 22:32 was still running at 23:54, had completed two full evaluation splits in
# the meantime, and monopolised a single-replica GPU endpoint so that every
# later attempt lost its capability probe to the queue. About ninety minutes
# went into diagnosing "why is the endpoint busy". It was busy with us.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

[[ -z "$command" ]] && exit 0
[[ "$command" =~ pueue[[:space:]]+kill ]] || exit 0

command -v systemctl >/dev/null 2>&1 || exit 0

# Give the signal a moment to land before judging what survived.
sleep 2

units=$(systemctl --user list-units 'run-u*.service' --no-legend --no-pager 2>/dev/null \
  | awk '$3 == "active" {print $1}' || true)

[[ -z "$units" ]] && exit 0

count=$(echo "$units" | wc -l | tr -d ' ')
first=$(echo "$units" | head -1)

cat <<MSG
[verify_pueue_kill] pueue reported the task killed, but ${count} transient systemd unit(s) are STILL ACTIVE:

$(echo "$units" | sed 's/^/  /')

If the pueue command wrapped the payload in \`systemd-run\`, the kill stopped only
the systemd-run client. The real workload is still running and still holding
whatever it holds -- GPU endpoint slots, containers, network connections, output
directories.

Verify, then stop it for real:
  ps -eo pid,etime,cmd | grep <your entrypoint>   # elapsed time gives it away
  systemctl --user stop ${first}

Do not conclude anything about endpoint contention or resource pressure until
this is resolved -- the leading suspect is your own supposedly-dead job.
MSG
exit 0
