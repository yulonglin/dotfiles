# Skills Audit & Improvement Plan

## Context

Audit of 5 user-owned skills to identify what's working, what's stale, and what can be improved — potentially using the skill-creator's eval/iterate workflow for the most impactful ones.

## Audit Findings

### 1. `anthropic-style` — Stale, disconnected from actual usage
- **Purpose:** Anthropic brand colors/typography reference (copied from upstream)
- **Problem:** Describes pptx-level brand application with raw hex codes, but CLAUDE.md says to use `from anthro_colors import use_anthropic_defaults`. The skill doesn't mention the repo's own `anthro_colors.py`, `petriplot.py`, or matplotlib styles at all.
- **Recommendation:** **Rewrite** to be the authoritative reference for Anthropic visual style in this repo — covering matplotlib (primary), TikZ, HTML/CSS, and pptx. Pull color values from `lib/plotting/anthro_colors.py` (ground truth) instead of hardcoding hex.

### 2. `commit` — Works but inconsistent with safety rules
- **Purpose:** Simple git commit workflow
- **Problem:** Uses `git commit -m "..."` for multi-line messages, contradicting `rules/safety-and-git.md` which requires `printf > $TMPDIR/commit_msg.txt && git commit -F`. The sibling `commit-push-sync` skill gets this right.
- **Recommendation:** **Quick fix** — align commit message format with `commit-push-sync` and the safety rules. ~5 line change.

### 3. `commit-push-sync` — Excellent, minor bug
- **Purpose:** Full commit → sync → push workflow with smart merge strategy
- **Problem:** References `git stash --dry-run` which isn't a real git option. Otherwise the best-written skill in the set (397 lines, thorough edge case handling).
- **Recommendation:** **Quick fix** — remove the invalid `--dry-run` reference. Otherwise leave alone.

### 4. `llm-billing` — Hardcoded paths, not portable
- **Purpose:** Check LLM provider billing/credits
- **Problem:** Hardcodes `/Users/yulong/code/dotfiles` in both SKILL.md and references. Won't work on RunPod/Linux.
- **Recommendation:** **Quick fix** — replace with `$DOT_DIR` or `$HOME/code/dotfiles` with fallback.

### 5. `merge-worktree` — Good, minor ordering issue
- **Purpose:** Merge worktree branch back to parent with AI conflict resolution
- **Problem:** The "check for uncommitted changes in main tree" step is buried in the Important section instead of being in the numbered steps.
- **Recommendation:** **Quick fix** — promote the check to step 2.5 (before merge attempt).

### Bonus: `.migrated/` cleanup
- `strategic-communication` has a circular symlink back to the active version
- `insights-toolkit` has a broken nested structure
- **Recommendation:** Delete both (they're superseded by plugin versions)

## Delegation Agents (Confirmed Working)
All four delegation agents (`core:codex`, `core:gemini-cli`, `core:claude`, `code:plan-critic`) genuinely shell out to their respective CLIs via Bash. They are thin wrappers with `tools: ["Bash"]` only and CRITICAL CONSTRAINT clauses preventing direct answers. No changes needed.

## Plan

### Phase 1: Quick fixes (sequential, ~10 min)

1. **`commit`** — Replace `git commit -m "..."` pattern with sandbox-safe `printf > $TMPDIR/commit_msg.txt && git commit -F` pattern, matching `commit-push-sync`
   - File: `claude/skills/commit/SKILL.md`

2. **`commit-push-sync`** — Remove invalid `git stash --dry-run` reference
   - File: `claude/skills/commit-push-sync/SKILL.md`

3. **`llm-billing`** — Replace hardcoded `/Users/yulong/code/dotfiles` with `${DOT_DIR:-$HOME/code/dotfiles}`
   - Files: `claude/skills/llm-billing/SKILL.md` (symlink to `claude/agents/llm-billing.md`), `claude/skills/llm-billing/references/billing-process.md`

4. **`merge-worktree`** — Add uncommitted-changes-in-main-tree check as an explicit numbered step before the merge attempt
   - File: `claude/skills/merge-worktree/SKILL.md`

5. **`.migrated/` cleanup** — Remove circular symlink in `strategic-communication` and broken `insights-toolkit` structure
   - Path: `claude/skills/.migrated/`

### Phase 2: `anthropic-style` rewrite

This is the only skill that needs a substantial rewrite. The current version is a copy of an upstream skill that doesn't reflect how this repo actually uses Anthropic style.

**New structure:**
```
anthropic-style/
├── SKILL.md           # When to use, quick-start for each domain
└── references/
    ├── colors.md      # Color palette (sourced from anthro_colors.py)
    ├── matplotlib.md  # Python plotting (use_anthropic_defaults, style files)
    ├── web-css.md     # HTML/CSS patterns (spacing, fonts)
    └── tikz.md        # TikZ diagram style
```

**Key changes:**
- Description updated to trigger on any visual output task (plots, diagrams, slides, web)
- Quick-start: `from anthro_colors import use_anthropic_defaults; use_anthropic_defaults()`
- Colors pulled from `lib/plotting/anthro_colors.py` (ground truth), not hardcoded
- Covers all 4 domains: matplotlib (primary), TikZ, HTML/CSS, pptx
- References loaded on demand per domain

### Phase 3 (Optional): Run skill-creator eval loop on `anthropic-style`

If you want to validate the rewrite rigorously, we can use the skill-creator's test/eval workflow:
- Draft 2-3 test prompts ("create a bar chart comparing...", "generate a TikZ diagram of...")
- Run with-skill vs without-skill
- Grade and iterate

## Verification

- `commit`: Make a multi-line test commit to verify the `printf`+`git commit -F` pattern works
- `llm-billing`: Run `/llm-billing` and confirm it resolves the path correctly
- `merge-worktree`: Read the skill and verify step ordering
- `anthropic-style`: Invoke `/anthropic-style` in a test prompt asking for a plot, verify it references `anthro_colors.py`
