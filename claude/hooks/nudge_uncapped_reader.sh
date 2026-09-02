#!/usr/bin/env bash
# PreToolUse(Bash) hook: reading a whole eval log costs order-30x the file size
# in RSS, so one uncapped reader can take the host down and every experiment
# running on it. `capped` applies the memory limit and an exclusive lock, and
# fails closed when it cannot.
#
# NUDGE only — never blocks, never exits non-zero. It fires when a command
# looks like a heavy log reader and carries no cap, and stays silent otherwise.
# Deliberately narrow: a false alarm on every python invocation would train the
# reader to ignore it.

# shellcheck disable=SC2016  # backticks in the nudge text are literal markdown
set -uo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
python3 "$HOOK_DIR/hook_feature.py" enabled nudges.uncapped-reader \
    >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Already capped, or the caller has deliberately opted out.
case "$CMD" in
    *capped*|*systemd-run*|*--no-caps*|*--no-resource-caps*) exit 0 ;;
esac

# Only the shapes that actually pull a whole log into memory.
FIRE=false
case "$CMD" in
    *read_eval_log*|*.eval*) FIRE=true ;;
    *impossiblebench_analysis*|*v2_rerun*|*nla_monitor.analysis*) FIRE=true ;;
esac
[ "$FIRE" = true ] || exit 0

# Cheap, safe reads of a log directory are not what this is about.
case "$CMD" in
    ls\ *|du\ *|find\ *|stat\ *|file\ *|*unzip\ -l*) exit 0 ;;
esac

MSG='This looks like it reads an eval log, which costs roughly 30x the file size in memory — a 500MB log needs well over 15GB. An uncapped reader has taken this host down before, killing the experiments running beside it.

Run it under a cap instead:

```bash
capped --mem 18G -- <your command>
```

`capped` sets `MemoryMax`, takes an exclusive lock so only one heavy reader runs at a time, and refuses to start rather than running uncapped. Pass `--no-caps` if you have decided an unbounded run is right.

Cheaper still, stream the log per sample (`read_eval_log_samples` with `exclude_fields`) instead of reading it whole.'

jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0
