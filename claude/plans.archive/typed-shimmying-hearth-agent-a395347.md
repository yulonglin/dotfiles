# Memory System Comparison: claude-mem vs supermemory vs beads

**Date**: 02-02-2026
**Agent**: typed-shimmying-hearth-agent-a395347
**Context**: User needs per-project plan/task tracking with auto-capture, mode-based organization, cost-consciousness, high visibility, and toggleability.

## Executive Summary

| System | Best For | Primary Gaps | Setup Effort | Cost |
|--------|----------|--------------|--------------|------|
| **claude-mem** | Auto-capturing "what worked/didn't" across sessions | No per-project isolation, no mode-based org | Low (plugin install) | Minimal (local LLM calls) |
| **supermemory** | Codebase structure indexing | Requires paid subscription, cloud-dependent | Medium (API setup) | **High** (subscription required) |
| **beads** | Hierarchical plans/tasks with dependency tracking | No auto-capture, no "learnings" storage | Low (global CLI) | **None** (zero LLM usage) |

**Recommendation**: **Hybrid approach** (beads for plans/tasks + claude-mem for learnings) addresses all needs with minimal cost.

---

## Detailed Analysis

### 1. claude-mem (Memory System)

#### Fits User Needs
| Need | Coverage | Notes |
|------|----------|-------|
| Per-project plans/tasks | ❌ **No** | Stores global memory across all sessions |
| Auto-capture learnings | ✅ **Yes** | PostToolUse hook captures tool outputs automatically |
| Mode-based organization | ⚠️ **Partial** | Can tag observations, but no built-in modes |
| Cost-conscious | ✅ **Yes** | Local processing, 10x token savings via progressive disclosure |
| High visibility | ✅ **Yes** | Web UI at localhost:37777 with real-time stream |
| Lost context capture | ✅ **Yes** | Hyperparams, failure modes stored as observations |

#### Key Gaps
1. **No project isolation**: All memory is global (`.claude-mem/` directory not per-project)
2. **No mode switching**: Can't toggle "research mode" vs "writing mode" memory contexts
3. **No hierarchical task structure**: Observations are flat, not nested like tasks/subtasks

#### Setup Effort
**Low** - Plugin installation via Claude Code marketplace:
```bash
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
# Restart Claude Code
```

Auto-installs dependencies (Bun, uv). No manual configuration required.

#### Integration with Dotfiles
**Option A**: Add to `deploy.sh --claude` component (symlink hooks):
```bash
# In deploy_claude()
if [[ -d "$DOTFILES_DIR/claude/hooks/claude-mem" ]]; then
    ln -sf "$DOTFILES_DIR/claude/hooks/claude-mem/"* ~/.claude/hooks/
fi
```

**Option B**: Document in `claude/README.md` as recommended plugin (user installs manually).

#### Cost
- **Monetary**: Zero (local processing, no API calls)
- **Time**: ~50-100 tokens per context injection (minimal context pollution)
- **LLM Usage**: Only for semantic summarization (runs locally via Claude API, controllable via settings)

#### Customization Needed
**Medium**:
1. Modify `SessionStart` hook to check for `.beads/` directory → inject project-specific context
2. Add mode tags to observations (e.g., `<mode:research>` in tool output)
3. Implement filter in web UI to show/hide by project or mode

---

### 2. supermemory (Cloud Memory)

#### Fits User Needs
| Need | Coverage | Notes |
|------|----------|-------|
| Per-project plans/tasks | ⚠️ **Partial** | Indexes per-project structure, but no task tracking |
| Auto-capture learnings | ✅ **Yes** | Captures conversation turns and tool executions |
| Mode-based organization | ❌ **No** | Flat memory structure |
| Cost-conscious | ❌ **No** | Requires **paid subscription** (Supermemory Pro+) |
| High visibility | ⚠️ **Partial** | No local UI, relies on cloud console |
| Lost context capture | ✅ **Yes** | Stores codebase structure and patterns |

#### Key Gaps
1. **Subscription cost**: Not free, defeats "cost-conscious" requirement
2. **Cloud dependency**: Requires internet, API keys, external service uptime
3. **No task/plan management**: Focuses on codebase indexing, not workflow tracking
4. **Low visibility**: No local dashboard (must check cloud console)

#### Setup Effort
**Medium**:
1. Sign up at console.supermemory.ai
2. Get API key (requires Pro tier purchase)
3. Install plugin: `/plugin install claude-supermemory`
4. Configure `~/.supermemory-claude/settings.json`
5. Run `/claude-supermemory:index` per project

#### Integration with Dotfiles
**Not recommended** due to subscription dependency. Could document as optional add-on:
```bash
# config/user.conf.example
# Optional: Supermemory API key
# SUPERMEMORY_CC_API_KEY=<your-key>
```

#### Cost
- **Monetary**: **Requires Supermemory Pro subscription** (pricing not disclosed, likely $10-30/month)
- **Time**: API latency for cloud queries
- **LLM Usage**: Unknown (handled by cloud service)

#### Customization Needed
**High** - Would require forking plugin to:
1. Add per-project memory isolation
2. Implement mode-based filtering
3. Build local UI for visibility

**Verdict**: ❌ **Ruled out** due to mandatory subscription cost.

---

### 3. beads (Task Graph System)

#### Fits User Needs
| Need | Coverage | Notes |
|------|----------|-------|
| Per-project plans/tasks | ✅ **Yes** | `.beads/` directory per project |
| Auto-capture learnings | ❌ **No** | Manual task creation only |
| Mode-based organization | ⚠️ **Partial** | Can use tags/priorities, not built-in modes |
| Cost-conscious | ✅ **Yes** | **Zero LLM usage** - pure git/JSON |
| High visibility | ⚠️ **Partial** | CLI output, no UI (could build one) |
| Lost context capture | ❌ **No** | Tracks tasks, not "what worked/didn't" |

#### Key Gaps
1. **No auto-capture**: Requires manual `bd create` commands (agent could automate via hooks)
2. **No learnings storage**: Designed for tasks/plans, not experimental findings
3. **No built-in UI**: CLI-only (though JSON output enables custom dashboards)

#### Setup Effort
**Low** - Global CLI installation:
```bash
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
# Or: brew install beads
```

Per-project initialization:
```bash
cd your-project
bd init  # Creates .beads/ directory
```

#### Integration with Dotfiles
**Option A**: Install via `install.sh --ai-tools`:
```bash
# In install.sh, add to install_ai_tools()
if ! command -v bd &> /dev/null; then
    echo "Installing beads..."
    curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
fi
```

**Option B**: Add beads wrapper script to `custom_bins/`:
```bash
# custom_bins/bd-project
#!/bin/bash
# Auto-initialize beads in project if .git exists
[[ -d .git && ! -d .beads ]] && bd init --stealth
bd "$@"
```

#### Cost
- **Monetary**: Zero (no API calls)
- **Time**: Negligible (git/SQLite operations)
- **LLM Usage**: **Zero** (pure data structure management)

#### Customization Needed
**Low to Medium**:
1. Add Claude Code skill to create/update tasks via hooks:
   ```bash
   # claude/skills/beads-task
   # Auto-creates bd task when user says "track this" or on experiment completion
   ```
2. Add mode support via tags:
   ```bash
   bd create "Hyperparameter sweep" -p 1 --tag research
   bd create "Paper draft section 3" -p 0 --tag writing
   ```
3. Build simple TUI dashboard (optional):
   ```bash
   # custom_bins/bd-tui
   watch -n 5 'bd ready | jq .'  # Or use rich/textual for fancier UI
   ```

---

## Hybrid Approach (Recommended)

### Architecture
```
beads (tasks/plans)
  ↓ complements
claude-mem (learnings/failures)
  ↓ injects context to
Claude Code sessions
```

### How It Works

| Component | Responsibility | Storage |
|-----------|---------------|---------|
| **beads** | Plan/task tracking, dependency management | `.beads/` (per-project, git-tracked) |
| **claude-mem** | Auto-capture tool outputs, failure modes, hyperparams | `~/.claude-mem/` (global, SQLite + Chroma) |
| **Integration hook** | On experiment completion → create bd task + store claude-mem observation | `claude/hooks/experiment_complete.sh` |

### Addresses All Needs

| Need | Solution |
|------|----------|
| **Per-project plans/tasks** | beads `.beads/` directory per project |
| **Auto-capture learnings** | claude-mem PostToolUse hook stores observations |
| **Mode-based organization** | beads tags (`--tag research`) + claude-mem custom tags |
| **Cost-conscious** | beads: zero cost, claude-mem: minimal local LLM usage |
| **High visibility** | beads: `bd ready` CLI, claude-mem: localhost:37777 web UI |
| **Lost context** | claude-mem captures hyperparams/failures, beads tracks related tasks |

### Integration Steps

1. **Install both systems**:
   ```bash
   # beads (global CLI)
   curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

   # claude-mem (Claude Code plugin)
   /plugin marketplace add thedotmack/claude-mem
   /plugin install claude-mem
   ```

2. **Add beads to dotfiles**:
   ```bash
   # install.sh --ai-tools section
   if ! command -v bd &> /dev/null; then
       echo "Installing beads..."
       curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
   fi
   ```

3. **Create integration hook**:
   ```bash
   # claude/hooks/experiment_complete.sh
   #!/bin/bash
   # When experiment finishes, create bd task and tag claude-mem observation

   EXPERIMENT_NAME="$1"
   RESULTS_PATH="$2"

   # Create beads task
   if [[ -d .beads ]]; then
       bd create "Review results: $EXPERIMENT_NAME" -p 1 --tag research
   fi

   # Tag observation for claude-mem (via custom observation injection)
   # Details depend on claude-mem API (could POST to localhost:37777)
   ```

4. **Add mode aliases**:
   ```bash
   # config/aliases.sh
   alias bd-research='bd ready --tag research'
   alias bd-writing='bd ready --tag writing'
   alias bd-code='bd ready --tag code'
   ```

5. **Add visibility dashboard**:
   ```bash
   # custom_bins/project-status
   #!/bin/bash
   echo "=== Tasks (beads) ==="
   bd ready | head -10
   echo -e "\n=== Recent Learnings (claude-mem) ==="
   curl -s http://localhost:37777/api/recent | jq '.[:5]'
   ```

### Cost Analysis
- **beads**: $0 (no LLM calls)
- **claude-mem**: ~50-100 tokens per session (local processing)
- **Total monthly cost**: Effectively $0 (ignores negligible local inference cost)

### Toggle Mechanism
```bash
# Disable claude-mem (stop worker)
pkill -f claude-mem-worker

# Disable beads (skip hook)
export BEADS_DISABLED=1

# Re-enable (restart Claude Code for claude-mem, unset for beads)
unset BEADS_DISABLED
```

---

## Alternative: "Just Fix Plans/Tasks, Skip .memory"

If the hybrid approach feels too complex, the **pragmatic choice** is:

### Fix Existing `.claude/plans/` and `.claude/tasks/`

**Current problems**:
1. Plans scattered across projects, not easily searchable
2. Tasks lack dependency tracking
3. No auto-generation from experiments
4. No mode-based filtering

**Minimal solution** (no new tools):
1. **Standardize plan naming**: Use UTC timestamps (already in CLAUDE.md)
   ```bash
   # Already implemented
   20260125_143022_UTC_oauth_refactor.md
   ```

2. **Add task metadata**:
   ```bash
   # claude/tasks/20260125_143022_UTC_oauth_refactor/metadata.json
   {
     "mode": "code",
     "priority": 1,
     "dependencies": ["20260120_100000_UTC_jwt_setup"],
     "status": "active"
   }
   ```

3. **Create task CLI wrapper**:
   ```bash
   # custom_bins/task-list
   #!/bin/bash
   # Lists tasks with mode filtering
   MODE="${1:-all}"
   for task in ~/.claude/tasks/*/metadata.json; do
       if [[ "$MODE" == "all" ]] || jq -e ".mode == \"$MODE\"" "$task" > /dev/null; then
           jq -r '.status + " | " + .priority + " | " + (.dependencies // []) | @csv' "$task"
       fi
   done
   ```

4. **Add auto-capture hook**:
   ```bash
   # claude/hooks/auto_log.sh (modify existing)
   # On experiment completion, append to NOTES.md with timestamp + hyperparams
   ```

**Pros**:
- Zero new dependencies
- Works with existing dotfiles structure
- Minimal learning curve

**Cons**:
- No graph visualization (vs beads)
- No semantic search (vs claude-mem)
- Manual maintenance overhead

---

## Final Recommendation

### For Immediate Productivity (Next 7 Days)
**Just use beads** for plans/tasks:
- Solves dependency tracking, per-project isolation
- Zero cost, zero LLM usage
- 30-minute setup
- Can add claude-mem later if auto-capture proves valuable

### For Long-Term Research Workflow (Next 3+ Months)
**Hybrid: beads + claude-mem**:
- beads handles structured work (tasks, plans, dependencies)
- claude-mem captures organic learnings (failures, hyperparams, insights)
- Combined cost: effectively $0
- High visibility via dual dashboards

### If Minimalism Preferred
**Fix existing .claude/plans + .claude/tasks**:
- Add metadata.json to tasks
- Create simple CLI wrappers
- Enhance auto_log.sh hook
- No new tools, works with current dotfiles

---

## Next Steps

1. **Decision point**: Which approach aligns with your workflow?
   - Immediate: beads only
   - Comprehensive: beads + claude-mem
   - Minimal: enhance existing system

2. **Prototype phase** (if choosing hybrid):
   - Install beads, test on one project for 3 days
   - Install claude-mem, verify auto-capture works
   - Build integration hook (experiment_complete.sh)
   - Create dashboard script (project-status)

3. **Deployment integration**:
   - Update `install.sh --ai-tools` to include beads
   - Document in `claude/README.md`
   - Add aliases to `config/aliases.sh`
   - Create skill for bd task creation (`claude/skills/beads-task/`)

Would you like me to implement any of these approaches?
