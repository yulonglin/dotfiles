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
# NUDGE only -- never blocks, never exits non-zero.
#
# THE CENTRAL RULE, learned by getting it wrong twice: fire on an EXECUTION
# SHAPE, never on a word appearing somewhere in the command. A first draft fired
# on `*watchdog*` anywhere and skipped only when the first word was a reader,
# which fires on `mv watchdog.sh archive/`, `docker logs watchdog`, `mkdir
# keepalive` and `uv run python analyze_watchdog.py` -- everyday commands that
# would have trained the ignore reflex within a week. So: a segment fires only
# when the thing being EXECUTED is named like a poller, i.e. the command word
# itself, or the script argument of bash/sh/zsh.
#
# Two further rules, both from review:
#   - A deadline must bound the WHOLE poller. `--connect-timeout 5` and a
#     `timeout 5` around one call inside the loop both leave the loop endless,
#     so boundedness means the command STARTS with timeout/gtimeout.
#   - Exemptions apply per shell segment. Otherwise `pkill -f watchdog; nohup
#     bash watchdog.sh &` is exempted by its own first word while relaunching.

# shellcheck disable=SC2016  # backticks in the nudge text are literal markdown
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Wrappers that transparently precede the real command. sudo and time are here
# so `sudo systemctl restart watchdog.service` is judged on systemctl, not sudo.
strip_wrappers() {
    local s="$1" prev=""
    while [ "$s" != "$prev" ]; do
        prev="$s"
        s="${s#"${s%%[![:space:]]*}"}"
        case "$s" in
            nohup\ *) s="${s#nohup }" ;;
            exec\ *) s="${s#exec }" ;;
            command\ *) s="${s#command }" ;;
            setsid\ *) s="${s#setsid }" ;;
            sudo\ *) s="${s#sudo }" ;;
            time\ *) s="${s#time }" ;;
            # Launchers that run a payload behind their own options. Strip the
            # launcher and its flags so the payload is what gets judged --
            # `jexp bash ./watchdog.sh` is still starting a watchdog. They cap
            # resources, not lifetime, so they are not exemptions by
            # themselves; a real deadline still has to appear (RuntimeMaxSec,
            # or a timeout wrapping the payload).
            systemd-run\ *|jexp\ *|srun\ *|nice\ *|ionice\ *)
                s="${s#* }"
                while [ "${s#-}" != "$s" ]; do s="${s#* }"; done ;;
        esac
    done
    printf '%s' "$s"
}

# The file or program actually being executed: the command word, or the script
# argument when it is run through an interpreter.
execution_target() {
    local s first second rest
    s=$(strip_wrappers "$1")
    read -r first second rest <<<"$s"
    case "$first" in
        bash|sh|zsh|dash|ksh)
            # Skip interpreter options to reach the script name.
            case "$second" in
                -*) printf '%s' "$first" ;;
                *) printf '%s' "$second" ;;
            esac ;;
        *) printf '%s' "$first" ;;
    esac
}

looks_like_poller() {
    case "$1" in
        *watchdog*|*keep-warm*|*keep_warm*|*keepalive*|*keep-alive*) return 0 ;;
    esac
    return 1
}

# A deadline that bounds everything after it, anchored to command position. An
# unanchored match would let `echo "timeout waiting"` or `--connect-timeout 5`
# silence the nudge.
starts_bounded() {
    case "$(strip_wrappers "$1")" in
        timeout\ *|gtimeout\ *) return 0 ;;
    esac
    return 1
}

# An explicit lifetime flag, checked only on the segment that would fire, so a
# mention elsewhere in the command cannot mask a real poller.
has_lifetime_flag() {
    case "$1" in
        *--max-age*|*--deadline*|*--max-runtime*|*--no-deadline*|*RuntimeMaxSec*) return 0 ;;
    esac
    return 1
}

FIRE=false

# Case 1: an endless loop, or `watch`, which is the textbook unbounded poller.
# Checked against the whole command because splitting on `;` would tear
# `while true; do ...; sleep 180; done` into harmless-looking pieces. A loop
# counts as polling when it sleeps or makes a request.
if ! starts_bounded "$CMD" && ! has_lifetime_flag "$CMD"; then
    case "$CMD" in
        *"while true"*|*"while :"*|*"while ["*|*"until "*)
            # `do ` must be present too, so prose like `echo "wait until done"`
            # alongside an unrelated sleep is not read as a loop.
            case "$CMD" in
                *"do "*)
                    case "$CMD" in
                        *sleep*|*curl*|*wget*) FIRE=true ;;
                    esac ;;
            esac ;;
    esac
    case "$(strip_wrappers "$CMD")" in
        watch\ *) FIRE=true ;;
    esac
fi

# Case 2: executing something named like a poller, judged per shell segment.
if [ "$FIRE" = false ]; then
    while IFS= read -r seg; do
        [ -n "$seg" ] || continue
        looks_like_poller "$(execution_target "$seg")" || continue
        starts_bounded "$seg" && continue
        has_lifetime_flag "$seg" && continue
        FIRE=true
        break
    done <<EOF
$(printf '%s' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|&]/\n/g')
EOF
fi

[ "$FIRE" = true ] || exit 0

# The feature gate runs LAST, not first. It costs a python startup (~30-50ms),
# and paying that on every Bash call in the session to answer a question that
# the cheap string matching above has already made moot is the wrong trade.
HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
python3 "$HOOK_DIR/hook_feature.py" enabled nudges.undeadlined-poller \
    >/dev/null 2>&1 || exit 0

MSG='This looks like a polling loop with no deadline. A poller that outlives the run it was written for keeps whatever it polls alive: in 2026-08 a health-check watchdog polled a Modal endpoint every 180s against a 300s `scaledown_window`, so the GPU could never scale to zero. It ran for 31 days and cost $3,060.

Give it an end:

```bash
timeout 12h <your command>
```

The deadline has to wrap the whole poller. A per-request `--connect-timeout`, or a `timeout` around one call inside the loop, bounds one request and leaves the loop endless.

Two things worth checking before you start it:

- **Is the poll interval shorter than the idle timeout of the thing being polled?** If so it is a keep-alive, not a health check. Poll slower than the scaledown window, or read the state through the provider API instead of touching the endpoint.
- **Will it still be wanted tomorrow?** A watchdog written for one run should end with that run.

Pass `--no-deadline` in the command if an unbounded run is genuinely right. Flat daily spend gets caught a few days later by `cloud-spend-check`, but that is the backstop, not the fix.'

# Both fields, per the convention in anthropic_keycheck.py: systemMessage shows
# the user, additionalContext is what actually reaches Claude. A nudge meant to
# change what the agent does next needs the second one.
jq -n --arg msg "$MSG" '{
    systemMessage: $msg,
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $msg
    }
}'
exit 0
