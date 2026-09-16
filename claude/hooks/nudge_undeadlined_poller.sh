#!/usr/bin/env bash
# PreToolUse(Bash) hook: a polling loop with no deadline outlives the run it was
# written for. In 2026-08 a vLLM health-check watchdog was left running in a
# tmux pane; it polled every 180s against a 300s scaledown_window, so a Modal
# H100 could never scale to zero. It ran 31 days and cost $3,060. The poller was
# correct; it simply had no reason to ever stop.
#
# The mechanism to fix it already exists -- coreutils `timeout` -- so this
# nudges toward it rather than shipping another wrapper.
#
# NUDGE only -- never blocks, never exits non-zero. It fires when a command
# looks like an unbounded poller and carries no deadline, and stays silent
# otherwise. Deliberately narrow: a false alarm on every loop would train the
# reader to ignore it.

# shellcheck disable=SC2016  # backticks in the nudge text are literal markdown
set -uo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
python3 "$HOOK_DIR/hook_feature.py" enabled nudges.undeadlined-poller \
    >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Already bounded, or the caller has deliberately opted out. systemd-run carries
# RuntimeMaxSec and jexp carries the queue's caps, so both count as bounded.
case "$CMD" in
    # *timeout * also covers gtimeout, the macOS coreutils name.
    *timeout\ *|*systemd-run*|*jexp\ *) exit 0 ;;
    *--max-age*|*--deadline*|*--max-runtime*|*--no-deadline*) exit 0 ;;
esac

# Only the shapes that actually poll forever.
FIRE=false
case "$CMD" in
    *watchdog*|*keep-warm*|*keep_warm*|*keepalive*|*keep-alive*) FIRE=true ;;
    *"while true"*|*"while :"*|*"while [ 1 ]"*)
        case "$CMD" in *sleep*) FIRE=true ;; esac ;;
esac
[ "$FIRE" = true ] || exit 0

# Reading, searching or killing something with one of those words in its name is
# not what this is about. Nor is tailing a local log, which costs nothing.
case "$CMD" in
    ls\ *|cat\ *|bat\ *|grep\ *|rg\ *|fd\ *|find\ *|stat\ *|file\ *|wc\ *) exit 0 ;;
    ps\ *|pgrep\ *|pkill\ *|kill\ *|systemctl\ *|journalctl\ *) exit 0 ;;
    git\ *|gh\ *|vim\ *|nvim\ *|less\ *|head\ *|tail\ *|shellcheck\ *|echo\ *) exit 0 ;;
esac

MSG='This looks like a polling loop with no deadline. A poller that outlives the run it was written for keeps whatever it polls alive: in 2026-08 a health-check watchdog polled a Modal endpoint every 180s against a 300s `scaledown_window`, so the GPU could never scale to zero. It ran for 31 days and cost $3,060.

Give it an end:

```bash
timeout 12h <your command>
```

Two things worth checking before you start it:

- **Is the poll interval shorter than the idle timeout of the thing being polled?** If so it is a keep-alive, not a health check. Poll slower than the scaledown window, or read the state through the provider API instead of touching the endpoint.
- **Will it still be wanted tomorrow?** A watchdog written for one run should end with that run. `timeout` is the cheapest way to promise that.

Pass `--no-deadline` in the command if an unbounded run is genuinely right. Flat daily spend gets caught a few days later by `cloud-spend-check`, but that is the backstop, not the fix.'

jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0
