# Beads Integration Evaluation for Research Workflows

**Date**: 2026-02-06
**Status**: Analysis complete

## Executive Summary

Beads is well-engineered for its intended use case (multi-agent coding task management), but it is **over-engineered for the stated problem** (tracking authoritative research state across sessions). The daemon, git hooks, dependency graph, and JSONL sync machinery solve coordination problems you don't have. A simpler solution would deliver 90% of the value at 10% of the complexity.

**Recommendation**: Don't integrate beads. Instead, create a structured YAML "research state" file per project, with a lightweight `/research-state` skill for Claude to read/update it.

---

## Detailed Analysis

### 1. Installation/Setup Friction

**macOS** (low friction):
- `brew install beads` or `npm install -g @beads/bd` -- straightforward
- Go binary, no runtime dependencies once installed
- Your `install.sh` already has the pattern for this (see gitleaks, atuin installs)

**Linux** (medium friction):
- `curl -fsSL .../install.sh | bash` works on standard distros
- Need to verify the install script handles `aarch64` (RunPod uses A100/H100 nodes, typically x86_64)
- No `apt` package; must use curl/npm/go install
- Your `install.sh` pattern with mise could work, but beads isn't in mise

**RunPod** (high friction -- this is the problem):
- RunPod pods are **ephemeral by default**. Docker images rebuild from scratch
- The daemon (`bd.sock`) dies when the pod restarts; daemon PID not preserved
- Git hooks in `.git/hooks/` are **not version-controlled** (they live in `.git/`, which isn't committed)
- Each new pod needs: install bd binary + `bd init` + hooks re-installation
- **Your cloud setup script** (`scripts/cloud/setup.sh`) would need a beads section
- The `.beads/` directory IS version-controlled (in the repo), but the daemon/hooks are not
- Net: every RunPod session starts with ~10-15s of setup overhead (install binary + init)

**Git hooks specifically**:
- 4 hooks: `pre-commit` (flush JSONL), `post-merge` (import after pull), `post-checkout` (import after checkout), `pre-push` (verify JSONL committed)
- Hooks are installed via `bd hooks install` or `bd init --quiet` (copies to `.git/hooks/`)
- **Not persisted across clones** -- every fresh clone needs `bd hooks install`
- The `pre-push` hook has an **interactive prompt** (`[y/N]`) which will break non-interactive pushes (though it detects non-TTY and skips)

### 2. CLI Usability for Claude via Bash

**Good**:
- Every command supports `--json` output -- excellent for agent parsing
- `bd ready --json` is exactly the pattern Claude needs (structured task list)
- Commands are fast (<100ms for typical usage) -- no meaningful latency
- `bd create`, `bd update`, `bd close` are simple, well-designed CLI verbs
- `bd prime` injects workflow context at session start (via plugin hooks)

**Concerns**:
- `bd edit` opens `$EDITOR` interactively -- agents must use `bd update --description` instead (documented)
- Error messages may not always be JSON -- need to handle stderr parsing
- The `--json` flag returns different schemas per command -- Claude needs to know each one
- Hash-based IDs (`bd-a1b2`) are less memorable than sequential IDs for humans reviewing Claude's work

**Token cost consideration** (from their own MCP docs):
> "CLI + hooks approach is recommended over MCP. It uses ~1-2k tokens vs 10-50k for MCP schemas"

This is honest and correct. Using `bd` via Bash costs ~1-2k tokens per invocation. Using the MCP server costs much more due to schema overhead. For a research workflow, you'd want the CLI approach.

### 3. Git Hooks During Rapid Commits

This is where things get **genuinely problematic** for your workflow.

**The pre-commit hook**:
```sh
bd sync --flush-only >/dev/null 2>&1
git add .beads/issues.jsonl .beads/deletions.jsonl
```

Every `git commit` now:
1. Calls `bd sync --flush-only` (daemon RPC or direct SQLite write)
2. Stages `.beads/*.jsonl` files
3. Adds ~50-200ms to each commit

**Impact on Claude Code's commit pattern**:
- Your CLAUDE.md says "Commit frequently after every meaningful change"
- Claude might commit 5-10 times in a session
- Each commit now has beads overhead
- The pre-push hook **blocks pushes** if JSONL is uncommitted -- this could cause confusing failures when Claude tries to push

**The 30-second debounce**:
- CRUD operations debounce JSONL export by 30 seconds
- If Claude does `bd create` then immediately `git commit`, the JSONL might not be flushed yet
- The pre-commit hook handles this by calling `bd sync --flush-only`, but it adds latency
- Race condition: daemon flush fires mid-commit (the hook exists specifically to prevent this, but it's defensive programming against a real risk)

**Multi-agent scenario**:
- If you spawn agent teams (your CLAUDE.md describes this), multiple agents could create beads issues concurrently
- "Last agent to export wins" -- no built-in locking
- Hash IDs prevent ID collisions, but simultaneous JSONL writes could conflict

**Verdict**: The hooks are well-written (they warn but don't block on failure, handle missing `bd`), but they add complexity to every git operation. For a solo researcher with Claude, this overhead is unnecessary.

### 4. Daemon Model in Ephemeral Environments

**How the daemon works**:
- Per-project daemon, communicates via Unix socket at `.beads/bd.sock`
- Auto-starts on first `bd` command
- Handles background JSONL sync (30s debounce), auto-import after git pull
- Socket file is gitignored (ephemeral)

**RunPod problems**:
- Pod restart = daemon dies, socket file stale
- `bd` auto-starts daemon on next command, but first command is slow (~500ms vs ~50ms)
- If filesystem is network-mounted (some RunPod configs), Unix sockets may not work
- `BEADS_NO_DAEMON=1` mode exists (worktree workaround) but disables background sync

**Workaround**: Set `BEADS_NO_DAEMON=1` on RunPod. All operations become synchronous (slightly slower but reliable). This is documented for git worktrees but applies to any ephemeral environment.

**The real issue**: The daemon solves a problem you don't have. You're not doing concurrent multi-agent beads writes across branches. The daemon's value is in background sync -- but for a research state tracker, explicit reads at session start and writes at session end are sufficient.

### 5. Simpler Alternatives

**The core problem restated**: Claude picks up stale values because there's no single authoritative source for research state. You need:
1. A canonical location for current hyperparameters, experiment status, methodology decisions
2. A changelog showing when/why things changed
3. Claude reads it at session start
4. Claude updates it when things change

**Alternative A: Structured YAML file** (recommended)

```yaml
# .claude/research-state.yaml
# AUTHORITATIVE source for current research parameters
# Last updated: 2026-02-06T14:30:00Z by Claude (session abc123)

experiments:
  active:
    - name: "probe_training_v3"
      status: running
      started: 2026-02-04
      model: gpt2-small
      hyperparameters:
        learning_rate: 0.001
        batch_size: 32
        epochs: 50
        probe_type: "linear"
      notes: "Switched from 0.01 LR on Feb 5 after divergence"

  completed:
    - name: "baseline_accuracy"
      status: done
      result: "78.3% +/- 1.2% (N=100)"

methodology:
  plotting_style: "anthropic"
  confidence_intervals: true
  min_samples: 100
  significance_threshold: 0.05

changelog:
  - date: 2026-02-06
    change: "Reduced LR from 0.01 to 0.001"
    reason: "Training loss diverging after epoch 15"
    who: "claude-session-xyz"
  - date: 2026-02-04
    change: "Started probe_training_v3"
    reason: "v2 had data contamination (canary found in test set)"
    who: "yulong"
```

**Why this is better than beads for your use case**:

| Dimension | Beads | YAML file |
|-----------|-------|-----------|
| Setup | Install binary + init + hooks + daemon | Create one file |
| Cross-platform | Need binary on every machine | Works everywhere (git-tracked text) |
| Claude reads it | `bd list --json` (1-2k tokens, daemon overhead) | `cat .claude/research-state.yaml` (0 overhead) |
| Claude updates it | `bd create/update/close` (multiple commands) | Edit one file (one operation) |
| Changelog | Comments on issues (scattered) | Inline changelog section (one place) |
| Git integration | 4 hooks, JSONL sync, daemon | Normal git add/commit (no hooks) |
| Ephemeral envs | Needs binary install + init | Just `git pull` |
| Human readability | `bd list`/`bd show` commands | Open file in any editor |
| Dependencies | Go binary, SQLite, daemon | None |
| Failure modes | Daemon crash, stale socket, hook failures, JSONL conflicts | File merge conflicts (standard git) |

**Alternative B: TOML file** (if you prefer typed schemas)
Same as YAML but with TOML syntax. Slightly more formal, less flexible for nested structures.

**Alternative C: Beads for task tracking, YAML for state** (hybrid)
Use beads for experiment *tasks* (what to do next) but YAML for *state* (current parameters). This is over-engineering for a solo researcher.

### 6. What a `/beads` Skill Would Look Like

If you did proceed with beads, here's the concrete skill design:

```markdown
---
name: beads
description: Track research tasks and experiments with beads (bd CLI). Use when starting a session, creating experiments, or updating experiment status.
---

# Beads Research Tracker

## Session Start
Run automatically or when asked to check research status:

```bash
bd ready --json 2>/dev/null || echo '{"error": "beads not initialized"}'
```

## Create Experiment Task
```bash
bd create "$TITLE" -t task -p $PRIORITY --description "$DESCRIPTION" --json
```

## Update Experiment Status
```bash
bd update $ID --status in_progress --json
# or
bd close $ID --reason "$REASON" --json
```

## Add Note/Decision
```bash
bd comment $ID "$COMMENT" --json
```

## View Full Context
```bash
bd show $ID --json
```

## Important
- Always use `--json` flag for structured output
- Never use `bd edit` (opens interactive editor)
- Check `bd ready` at session start for unblocked work
- Close completed experiments with `bd close`
```

**However**, the recommended `/research-state` skill would be simpler:

```markdown
---
name: research-state
description: Read and update the authoritative research state file. Run at session start to avoid using stale parameters.
---

# Research State Management

## Session Start (ALWAYS RUN FIRST)
```bash
cat .claude/research-state.yaml
```

Review the state file. Use these values as authoritative for:
- Hyperparameters (override any defaults in code or Hydra configs)
- Experiment status (don't re-run completed experiments)
- Methodology decisions (plotting style, significance thresholds)

## Update State
When changing hyperparameters, starting/completing experiments, or making methodology decisions, update the state file:
1. Edit the relevant section
2. Add a changelog entry with date, change, reason, and session ID
3. Commit the change

## Conflict Resolution
If code defaults disagree with research-state.yaml, the YAML file wins.
If Hydra configs disagree with research-state.yaml, the YAML file wins.
If CLAUDE.md disagrees with research-state.yaml, ask the user.
```

### 7. Summary of Gotchas (If You Proceed with Beads)

1. **Binary distribution**: No apt package. Need curl/npm/go on every machine. Your `install.sh` needs a new section.
2. **Git hooks not version-controlled**: Every clone needs `bd hooks install`. Easy to forget on RunPod.
3. **Daemon on RunPod**: Socket dies on restart. Use `BEADS_NO_DAEMON=1`.
4. **Pre-push hook blocks**: If JSONL is uncommitted, push fails. Claude Code doesn't expect this.
5. **30s debounce race**: Create issue then immediately commit = possible stale JSONL (mitigated by pre-commit hook but adds latency).
6. **Alpha software (v0.9.11)**: API may change before 1.0. Your workflow would depend on unstable interfaces.
7. **Hooks conflict with existing hooks**: If your repos use husky, pre-commit, or other hook managers, beads hooks need integration.
8. **Plugin system is Claude-specific**: The `.claude-plugin/plugin.json` with SessionStart hooks is specific to Claude Code's plugin API. Good if you're all-in on Claude Code, but not portable.
9. **Token overhead**: Even at 1-2k tokens per CLI call, reading task lists with `bd list --json` on a repo with 50+ issues could dump significant context.
10. **Overkill for single-researcher workflow**: The entire dependency graph / ready-work / multi-agent-coordination architecture solves problems that don't exist in a solo research setup.

---

## Recommendation

**Don't adopt beads for research state tracking.** Instead:

1. Create `.claude/research-state.yaml` in each research repo
2. Create a `/research-state` skill that reads it at session start
3. Add a CLAUDE.md instruction: "Run `/research-state` at session start"
4. Let Claude update the YAML when parameters change
5. Commit the YAML like any other file (no hooks, no daemon, no binary)

**If you later need task/issue tracking** (not just state tracking), reconsider beads at v1.0 when the API is stable and the installation story is smoother.

**If you want changelog-style tracking specifically**, add a `CHANGELOG.md` or use the YAML changelog section. Git blame on the YAML file also gives you full history for free.
