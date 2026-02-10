# Plan: Update Claude Code post and recommendations

## Context

The Claude Code blog post links to the generic GitHub issues page for destructive command problems. There are ~15 specific issues that document this. The "refusal alternatives" bullet conflates two topics (ambiguity resolution + deny lists) and doesn't mention the actual sandbox/allow/deny/ask configuration. The recommendations page still lists Warp alongside Ghostty.

## Changes

### A. Specific GitHub issue links (`claude-code.md` line 72)

**Old:**
```
There's also a [known issue](https://github.com/anthropics/claude-code/issues) where it can run destructive commands while in plan mode.
```

**New:**
```
More concerning: plan mode has no tool-level enforcement, so Claude can and does run destructive commands while nominally in read-only mode — `rm -rf` ([#6608](https://github.com/anthropics/claude-code/issues/6608), [#24196](https://github.com/anthropics/claude-code/issues/24196)), `git reset --hard` ([#17190](https://github.com/anthropics/claude-code/issues/17190)), `git checkout` that discards uncommitted work ([#11821](https://github.com/anthropics/claude-code/issues/11821)), and bypassing deny rules through flag reordering ([#18613](https://github.com/anthropics/claude-code/issues/18613)). The sandbox and deny list (below) are the real safety net, not plan mode.
```

5 issues across 4 categories: rm -rf (#6608, #24196), destructive git (#17190, #11821), permission bypass (#18613).

---

### B. Split "refusal alternatives" bullet into two (`claude-code.md` line 43)

**Old (single bullet):**
```
- **Refusal alternatives** *(specification)* — the #1 friction pattern is Claude confidently misinterpreting ambiguous instructions. The rule says: on any task touching 3+ files, state your interpretation before writing code. A related insight: if you tell Claude to *never* do something, give it an alternative action, otherwise it gets stuck
```

**New (two bullets):**
```
- **Command guardrails** *(context)* — Claude Code runs in a sandbox with allow/deny/ask command lists in [`settings.json`](https://github.com/yulonglin/dotfiles/tree/main/claude). Destructive commands (`rm -rf`, `git reset --hard`, `git push --force`, `dd`, etc.) are denied outright; commands like `kill` require confirmation. Shell hooks add defense-in-depth — catching `sudo rm`, `xargs kill`, and other compound patterns that bypass the deny list. The important complement to denying commands is providing alternatives: when `rm` is blocked, the [rules](https://github.com/yulonglin/dotfiles/tree/main/claude) tell Claude to use `trash` (macOS), `mv` to `.bak`, or move to `archive/` instead. Without explicit alternatives, Claude gets stuck in a retry loop
- **Ambiguity resolution** *(specification)* — the most common friction pattern is Claude confidently misinterpreting ambiguous instructions. The rule: on any task touching 3+ files, state your interpretation before writing code. One sentence is enough
```

Rationale: The original conflated two unrelated topics. Command guardrails is *(context)* (what Claude sees); ambiguity resolution is *(specification)* (how requirements are communicated). The post organises around this taxonomy.

---

### C. Replace Warp with Ghostty-only (`recommendations.md` line 30)

**Old:**
```
- [Warp](https://www.warp.dev/) or [Ghostty](https://ghostty.org/) — Modern terminals
```

**New:**
```
- [Ghostty](https://ghostty.org/) — Fast, native terminal. Replaced Warp and iTerm2 after extended use of both
```

---

## Files modified

- `src/content/writing/claude-code.md` — 2 edits (lines 43, 72)
- `src/content/writing/recommendations.md` — 1 edit (line 30)

## Verification

1. `bun run build` — ensure no build errors
2. `bun dev` — check both posts render correctly in browser
3. Verify all 5 GitHub issue links resolve (spot-check 2-3)
