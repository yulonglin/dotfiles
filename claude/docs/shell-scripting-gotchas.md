# Shell Scripting Gotchas (zsh)

On-demand reference for zsh-specific footguns. Loaded on demand, not auto-loaded — see `rules/coding-conventions.md` § Shell Scripts for the pointer.

**`local` inside a loop prints existing values (zsh):**
In zsh, `local var` is `typeset var`. Re-declaring an already-existing typeset variable
prints its current value. Since a `for` loop re-runs the body, `local` inside a loop
leaks the previous iteration's value on iterations 2+. Declare loop-scoped temporaries
*before* the loop, or use `if var=$(cmd); then` to combine capture + exit-code check:

```bash
# BAD — leaks prev value from iteration 2 onwards
for ...; do
    local tmp
    tmp=$(some_cmd)
done

# GOOD — declare once before the loop
local tmp
for ...; do
    tmp=$(some_cmd)   # plain assignment inside loop
done

# ALSO GOOD — combined capture + exit-code check in one expression
local tmp
for ...; do
    if tmp=$(some_cmd); then ...
    fi
done
```

**`set -e` + arithmetic footgun:**
`(( expr ))` exits with code 1 when the expression evaluates to 0 (falsy), which trips
`set -e` / `set -euo pipefail` silently. The value that matters is the *expression result*,
not the variable after the operation:

| Form | Expression value | Dangerous when |
|------|-----------------|----------------|
| `(( n++ ))` | old `n` (before increment) | `n` starts at 0 |
| `(( ++n ))` | new `n` (after increment) | `n` would reach 0 (impossible for pure counters) |
| `(( n-- ))` | old `n` (before decrement) | `n` starts at 0 |
| `(( --n ))` | new `n` (after decrement) | `n` is 1 (result is 0) |

For **counters that start at 0 and only go up**, `(( ++n ))` is always safe. For anything
else (decrement, values that can reach 0), use `n=$(( n + 1 ))` — no exit-code trap:

```bash
# BAD — exits when ok=0 under set -e (first iteration of a loop)
(( ok++ ))

# GOOD for up-only counters starting at 0
(( ++ok ))

# ALWAYS safe — no arithmetic exit-code semantics
ok=$(( ok + 1 ))
```
