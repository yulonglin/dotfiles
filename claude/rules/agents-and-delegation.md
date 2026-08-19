# Agents & Delegation

## Spawn Fewer Than You Want To

Current models reach for delegation more readily than the work justifies, so the default is a cap, not an invitation. Delegate for large, genuinely independent, parallelisable tracks — a wide multi-file investigation, several unrelated subsystems. Don't delegate what you can finish in a handful of tool calls yourself, and when one agent can do the job, send one rather than a fleet.

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

When a spec is ready and the next step is *executing* it, hand it to a **full interactive Claude session that Yulong starts**, not to `claude -p`. Write the brief to a file, tell him the command, and stop. Do not auto-launch the executor.

Headless is not merely worse here, it is **broken for execution**: a `claude -p` child launched from this environment comes up in **coordinator mode** and has no `Read`/`Bash`/`Write` at all — it fails with *"Read is not available to you as the coordinator — run it from a worker via the Agent tool instead."* Unsetting `CLAUDE_CODE_COORDINATOR_MODE`, `CLAUDE_CODE_AGENT` and the child-session markers does **not** clear it, because it also comes from config. Every step is then forced through subagents, which is exactly where detached long jobs get orphaned (see above). Measured 2026-08-19: two launches, ~$0.80 burned, zero work done.

Two further traps from the same session, both of which cost a restart:

- **A detached launch dies with the tool call's process group.** `nohup ... &` and `setsid nohup ... &` from inside a Bash tool call are killed when the call returns — this silently killed several OpenRouter jobs and the first executor. tmux is the only durable host.
- **`.claude/` may be git-excluded**, so a rule written in a worktree never reaches the checkout the executor runs in. Verify the executor can actually read every file the brief cites, from *its* working directory, before handing off.

## Agent Results

Use the Agent tool's returned result; don't grep the `.output` file — long lines come back as `[Omitted long matching line]`.
