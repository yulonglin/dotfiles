# Delegation

Main context is for decomposition, dispatch, decisions and synthesis — not file dumps, search output, logs or diffs. Delegate anything whose tool output you need only the conclusion of, and reach for it before the first bulk read rather than after. When in doubt, spawn.

**Delegate**: wide sweeps over many files or unknown locations; bulk reads of logs, transcripts, long diffs, unbounded PDFs; scoped implementation chunks; verbose runs where you need only pass/fail plus failing lines; multi-page web research.

**Keep inline**: targeted edits and reads of paths you already know; short situational awareness (`git status`, `git log -5`); factual verification of anything you are about to state (a delegated lookup is exactly the hallucination vector `verify-before-instructing.md` closes); and the decision itself.

Every dispatch states TASK, CONTEXT with explicit paths (agents don't share your context), CONSTRAINTS, and an OUTPUT line capping what comes back. Launch independent agents in one message, one agent per job — never two at the same file. Use the returned result rather than grepping the `.output` file.

**Never spawn an agent to verify your own work**; self-correction happens anyway. A real second opinion means a different model family, briefed fresh and self-contained — see the `council` skill. Only when no other family's key resolves: a same-family agent given the artifact alone, no conversation, is weaker but beats skipping — name the reader you used. Non-Anthropic names in agent frontmatter resolve against api.anthropic.com only, so they silently answer from the default Claude model under the foreign label. A quota or sandbox failure is transient and owes no finding: retry without being asked, preferring another family.

**Never launch detached long-running work inside a subagent.** Its children are orphaned when the turn ends, yet the agent reports `completed` — so check the artifact on disk before relaying success. Launch it from main context as a backgrounded Task subagent; `run_in_background`, Monitor or `jexp` only when the worker is a process — an experiment or `codex`, never headless `claude -p` (it runs on the shell's `ANTHROPIC_API_KEY`, not the claude.ai login; retired 2026-09-02).

**`isolation: "worktree"` sets cwd but does not rewrite paths in your prompt**, so an absolute path in the brief silently sends writes to the main tree. Brief worktree agents with repo-relative paths and check `git -C <worktree> status` afterwards.

On a multi-step project or long session, take this posture from the first step rather than drifting into it once context is full: main context decomposes, dispatches and synthesizes; everything else is delegated. The keep-inline list stays intact — it is the whole exception, not a starting point to negotiate down.
