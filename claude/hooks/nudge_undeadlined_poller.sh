#!/usr/bin/env bash
# PreToolUse(Bash) hook: a polling loop with no deadline outlives the run it was
# written for. In 2026-08 a vLLM health-check watchdog was left running in a
# tmux pane; it polled every 180s against a 300s scaledown_window, so a Modal
# H100 could never scale to zero. It ran 31 days and cost $3,060.
#
# The mechanism to fix it already exists -- coreutils `timeout` -- so this
# nudges toward it rather than shipping another wrapper.
#
# NUDGE only -- never blocks, never exits non-zero.
#
# Three rules, each learned by getting it wrong and having a reviewer catch it:
#
# 1. Fire on an EXECUTION SHAPE, never on a word appearing somewhere. Firing on
#    `*watchdog*` anywhere nags on `mv watchdog.sh archive/`, `docker logs
#    watchdog`, `mkdir keepalive` and `pip install watchdog` -- and `watchdog`
#    is a ~200M-download PyPI package, so that last one alone would have killed
#    the hook in a week.
#
# 2. The cost being guarded against is a REMOTE resource held awake, so a loop
#    only counts when it makes a network request. `watch -n 1 nvidia-smi` and
#    `while true; do echo .; sleep 1; done` cost nothing and must stay silent.
#
# 3. `while <check>` and `until <check>` are OPPOSITES. `while curl -sf $U;
#    do sleep 180; done` keeps going while the endpoint is up -- that is the
#    keep-alive. `until curl -sf $U; do sleep 60; done` STOPS when it comes up:
#    it is wait-for-ready, it terminates by construction, and nudging about it
#    is pure noise. `until` is deliberately absent from the fire list.
#
# Known and accepted limitation: `timeout 1 true; while true; do curl ...; done`
# reads as bounded, because the deadline is judged on the whole command. Someone
# writing that is evading the nudge, not tripping over it.

# shellcheck disable=SC2016  # backticks in the nudge text are literal markdown
set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# The explicit opt-out, honoured everywhere.
case "$CMD" in *--no-deadline*) exit 0 ;; esac

# Something that reaches the network. Without one of these in the loop, whatever
# is being polled is local and costs nothing to keep awake.
NET_RE='curl|wget|http|ssh |nc |modal |aws |gcloud |kubectl |az '

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
            # Launchers that run a payload behind their own options. Options may
            # take a separate value word (`jexp --mem 8G bash x.sh`), so a word
            # following a value-less option is consumed too.
            systemd-run\ *|jexp\ *|srun\ *|nice\ *|ionice\ *)
                s="${s#* }"
                while :; do
                    case "$s" in
                        -*=*\ *) s="${s#* }" ;;
                        -*\ *) s="${s#* }"; s="${s#* }" ;;
                        *) break ;;
                    esac
                done ;;
            *)
                # A leading VAR=value assignment: `timeout=60 bash x.sh` is not
                # a deadline, and `WATCHDOG=1 ./keep-warm.sh` is still a poller.
                case "${s%% *}" in
                    [A-Za-z_]*=*) s="${s#* }" ;;
                esac ;;
        esac
    done
    printf '%s' "$s"
}

# The file or program actually executed, seeing past an interpreter and its
# flags so `bash -x ./watchdog.sh` is not read as a command called "bash".
execution_target() {
    local s rest word
    s=$(strip_wrappers "$1")
    word="${s%% *}"
    case "${word##*/}" in
        bash|sh|zsh|dash|ksh|python|python3|node|ruby|perl)
            rest="${s#* }"
            while :; do
                case "$rest" in
                    -c\ *|-*\ *) rest="${rest#* }" ;;
                    *) break ;;
                esac
            done
            printf '%s' "${rest%% *}" ;;
        *) printf '%s' "$word" ;;
    esac
}

# Matched on the basename, so /opt/watchdog/bin/run.sh is judged on run.sh, and
# either bare or hyphen-separated, which is the shell convention for a running
# poller: vllm-endpoint-watchdog.sh, endpoint-keepalive.sh. `mywatchdog` and
# `watchdogd` deliberately do not match.
#
# UNDERSCORE-separated names with a prefix are deliberately NOT matched, and
# that is a judgement call rather than a rule: `analyze_watchdog.py` is an
# analysis script run daily, while `endpoint-watchdog.sh` is the poller. The two
# are indistinguishable by name, so the separator is used as a weak proxy --
# python modules take underscores, shell pollers take hyphens. The cost is that
# a real `poll_watchdog.py` is missed; the benefit is not nagging on every
# analysis run, which is what kills a hook that fires on every Bash call.
looks_like_poller() {
    case "${1##*/}" in
        watchdog|watchdog.*|*-watchdog|*-watchdog.*) return 0 ;;
        keepalive|keepalive.*|*-keepalive|*-keepalive.*) return 0 ;;
        keep-alive*|*-keep-alive*) return 0 ;;
        keep-warm*|*-keep-warm*) return 0 ;;
        keep_alive*|keep_warm*) return 0 ;;
    esac
    return 1
}

# A launcher's options cannot be parsed reliably -- `--user` takes no value and
# `--mem 8G` does, and nothing in the string says which -- so for those the
# payload is found by scanning every word rather than by counting flags.
segment_launches_poller() {
    local seg="$1" trimmed w
    trimmed="${seg#"${seg%%[![:space:]]*}"}"
    case "$trimmed" in
        systemd-run\ *|jexp\ *|srun\ *)
            # shellcheck disable=SC2086  # word splitting is the point here
            for w in $seg; do
                looks_like_poller "$w" && return 0
            done
            return 1 ;;
    esac
    looks_like_poller "$(execution_target "$seg")"
}

# A deadline anchored to command position, basename-matched so /usr/bin/timeout
# counts. An unanchored match would let `--connect-timeout 5` silence the nudge.
starts_bounded() {
    local s word
    s=$(strip_wrappers "$1")
    word="${s%% *}"
    case "${word##*/}" in
        timeout|gtimeout) [ "$word" != "$s" ] && return 0 ;;
    esac
    return 1
}

has_lifetime_flag() {
    case "$1" in
        *--max-age*|*--deadline*|*--max-runtime*|*RuntimeMaxSec*) return 0 ;;
    esac
    return 1
}

FIRE=false

# Case 1: a loop or `watch` that polls something over the network, unbounded.
# Note `until` is absent by design -- see rule 3 in the header.
if ! starts_bounded "$CMD"; then
    if printf '%s' "$CMD" | grep -qE "$NET_RE"; then
        case "$CMD" in
            *"while true"*|*"while :"*|*"while ["*|*"while sleep"*|*"while curl"*|*"while wget"*)
                case "$CMD" in *"do "*) FIRE=true ;; esac ;;
        esac
        case "$(strip_wrappers "$CMD")" in
            watch\ *) FIRE=true ;;
        esac
    fi
fi

# Case 2: executing something named like a poller, judged per shell segment so
# one exempt command cannot cover a launch that follows it.
if [ "$FIRE" = false ]; then
    while IFS= read -r seg; do
        [ -n "$seg" ] || continue
        case "$seg" in *\ --help*|*\ --version*|*\ -h|*\ -h\ *) continue ;; esac
        segment_launches_poller "$seg" || continue
        starts_bounded "$seg" && continue
        has_lifetime_flag "$seg" && continue
        FIRE=true
        break
    done <<EOF
$(printf '%s' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|&]/\n/g')
EOF
fi

[ "$FIRE" = true ] || exit 0

# The feature gate runs LAST: it costs a python startup (~30-50ms), and paying
# that on every Bash call to answer a question the cheap matching above has
# already made moot is the wrong trade.
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
# the user, additionalContext is what actually reaches Claude.
jq -n --arg msg "$MSG" '{
    systemMessage: $msg,
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $msg
    }
}'
exit 0
