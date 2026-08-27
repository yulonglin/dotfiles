# Agents & Delegation

## The Main Agent Is An Orchestrator

Main context is for decomposition, dispatch, decisions, and synthesis — not for holding file dumps, search output, logs, or diffs. The default is to delegate: any work whose tool output you need only the *conclusion* of goes to a subagent, and the finding comes back instead of the raw bytes. Reach for delegation before the first bulk read, not after context is already polluted.

**Delegate aggressively — Yulong's standing instruction (2026-08-26).** When in doubt, spawn: data parsing and tallies over a file, Granola/Slack/Gmail context pulls, cross-referencing two sources, building and publishing an artifact from a written brief, any multi-step Bash investigation. Main context should read like a log of decisions and findings, not of tool calls. Launch independent agents in one message so they run in parallel.

Delegate by default:

- **Wide sweeps** — many files, unknown location, several naming conventions → `Explore` / `core:efficient-explorer`. A single-pattern Grep whose target you can name stays inline (`rules/context-management.md`).
- **Bulk reads** — reads spanning files you'd have to discover, logs, transcripts, unbounded PDFs, long diffs → a reader agent that returns a summary sized to the question.
- **Scoped implementation** — a settled chunk of the *current* task touching several files → an in-session implementation agent (worktree-isolated when parallel writers are possible). A whole spec whose execution is its own engagement is not a chunk — that goes through the handoff section below, brief written, session Yulong starts.
- **Short verbose runs** — a test suite or build whose output you need only pass/fail plus the failing lines from → an agent. Long-running ones (experiments, full builds) go to Bash `run_in_background` from main context instead — never inside a subagent, per the detached-jobs section below.
- **Web research** — multi-page reading → `general-purpose` / `research:literature-scout`.

Keep inline (delegating these wastes a round-trip and loses nothing):

- A targeted edit, or reads of files whose paths you already know — a fresh agent would just re-read them.
- Short situational awareness — `git status`, `git log -5`, `git diff --stat`.
- Factual verification of claims you're about to state — `rules/verify-before-instructing.md`; an agent lookup is exactly the hallucination vector that rule exists to close.
- The decision itself. Judgment, trade-offs, and anything needing conversation context stay in main context.

## Big Or Long Work Engages Full Orchestrator Mode

For multi-step projects, long sessions, or anything expected to spawn several agents, invoke `core:orchestrate` at the start — it delegates *all* implementation, keeping main context purely coordinative (its soft-warning guard hook lives in the **workflow** plugin, so it only fires when that plugin is enabled). The graduated default above is for ordinary tasks; orchestrator mode is the ceiling, not a different philosophy — and the keep-inline list above, especially factual verification, survives inside it.

## Briefs Cap What Comes Back

Context is preserved only if the agent's return is compact. Every dispatch states TASK / CONTEXT (explicit file paths — agents don't share your context) / CONSTRAINTS / OUTPUT, and the OUTPUT line caps the return ("3-bullet summary", "pass/fail + failing test names"). Launch independent agents in one message so they run in parallel — but one agent per job: parallelism is for independent work, not redundancy, and when one agent can do the job, send one rather than a fleet. Never give two agents the same file to edit.

**Never spawn an agent to verify or double-check your own work.** Self-correction already happens without being asked; a verifier agent on top of it burns tokens and latency without buying accuracy. A second opinion is a different thing — that means a different model family and it has its own rule (`rules/second-opinions.md`).

## Never Run Detached Long-Jobs Inside a Subagent

When a subagent's turn ends, any process it backgrounded or detached is orphaned: nothing re-notifies the parent, the job dies or runs to no effect, and the agent reports `completed` anyway. (Real failure, 2026-06-15: `core:codex` backgrounded `codex exec` — burned hours, wrote nothing.) A subagent is not a durable host for background work. Launch long-running jobs from a harness-tracked mechanism that survives the launching context: `codex-companion` via the Monitor tool for Codex work, Bash `run_in_background` from *main* context, or tmux.

**A `completed` status means the subagent's turn ended, not that its child did anything.** When an agent claims it ran a detached job, check the artifact on disk before relaying success.

## CLI-Backed Agents Answer Instead of Delegating

`core:claude` and `core:gemini-cli` are Claude instances that will answer from their own reasoning rather than invoke the CLI, unless the prompt contains the literal command: `You MUST use the Bash tool to run: gemini -p "<prompt>"`, or `claude -p --model <model> --permission-mode bypassPermissions "<prompt>"`. A question-shaped prompt gets a text answer, not a delegation. `core:claude` draws on the API-billed pool — use sparingly.

Never delegate factual verification — `rules/verify-before-instructing.md`.

## Worktree Isolation Breaks on Absolute Paths

`isolation: "worktree"` sets the agent's cwd but does not rewrite paths inside the prompt — an absolute path in the brief sends the agent's writes to the main tree, silently defeating the isolation. Brief worktree agents with repo-relative paths only, and explicitly mark any genuinely-external absolute path read-only. Verify afterwards with `git -C <worktree> status`.

## Implementation Handoffs Go To A Full Interactive Session, Never Headless

This governs a *whole prepared spec* whose execution is its own engagement — not in-session delegation of scoped chunks of the current task, which the orchestrator section above covers. When such a spec is ready and the next step is *executing* it, hand it to a **full interactive Claude session that Yulong starts**, not to `claude -p`. Write the brief to a file, tell him the command, and stop. Do not auto-launch the executor.

Headless is not merely worse here, it is **broken for execution**: a `claude -p` child launched from this environment comes up in **coordinator mode** and has no `Read`/`Bash`/`Write` at all — it fails with *"Read is not available to you as the coordinator — run it from a worker via the Agent tool instead."* Unsetting `CLAUDE_CODE_COORDINATOR_MODE`, `CLAUDE_CODE_AGENT` and the child-session markers does **not** clear it, because it also comes from config. Every step is then forced through subagents, which is exactly where detached long jobs get orphaned (see above). Measured 2026-08-19: two launches, ~$0.80 burned, zero work done.

Two further traps from the same session, both of which cost a restart:

- **A detached launch dies with the tool call's process group.** `nohup ... &` and `setsid nohup ... &` from inside a Bash tool call are killed when the call returns — this silently killed several OpenRouter jobs and the first executor. tmux is the only durable host.
- **`.claude/` may be git-excluded**, so a rule written in a worktree never reaches the checkout the executor runs in. Verify the executor can actually read every file the brief cites, from *its* working directory, before handing off.

## Agent Results

Use the Agent tool's returned result; don't grep the `.output` file — long lines come back as `[Omitted long matching line]`.
