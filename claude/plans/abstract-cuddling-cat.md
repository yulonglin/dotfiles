# Plan: Split Global CLAUDE.md into Modular Rules + Optimize Context Budget

## Context

The global CLAUDE.md (~1034 lines, 12.6k tokens) has grown into a monolithic file mixing safety rules, Python conventions, tmux workflows, research methodology, and agent strategies. Combined with bloated skills (~9.9k tokens), Serena MCP (~6k tokens), and unused plugins, the total overhead before any conversation is **~48k tokens (24% of context)**.

**Goal**: Reduce always-loaded overhead by ~30%, improve maintainability, and create a modular system using `.claude/rules/`.

**Estimated savings**: ~12-15k tokens (from 48k → 33-36k)

---

## Phase 1: Restructure CLAUDE.md into Rules

### 1a. Slim down `claude/CLAUDE.md` to ~200 lines (core essentials only)

Keep ONLY:
- Zero Tolerance Rules table (13 lines) — the single most important section
- Default Behaviors checklist (16 lines) — brief workflow reminders
- File Creation Policy (10 lines) — critical safety
- Communication Style (14 lines) — always-relevant behavior
- Pointer to `rules/` for detailed guidance

**Remove from CLAUDE.md** (moved to rules/ or reference docs):
- Agent Spawning Fix → `rules/environment-setup.md`
- Machine-Specific Setup → `rules/environment-setup.md`
- AI Safety Research Context → project-level CLAUDE.md or `rules/research-context.md`
- Quick Reference subsections (shell, git, dates, output, context mgmt) → separate rule files
- Subagent/Delegation/Agent Team strategies → `rules/agents-and-delegation.md`
- Documentation Lookup → `rules/documentation-lookup.md`
- Research Methodology → `rules/research-methodology.md`
- Python Guidelines → `rules/coding-conventions.md`
- Performance section → split: principles in rules, code examples in reference docs
- File Organization → `rules/research-methodology.md`
- Tools & Environment → `rules/tools-and-environment.md`

### 1b. Create `claude/rules/` directory with modular rule files

Each rule file is auto-discovered and loaded. No path scoping (too fragile across repos).

| Rule File | Content (from CLAUDE.md) | Est. Lines | Est. Tokens |
|-----------|-------------------------|-----------|-------------|
| `safety-and-git.md` | Zero tolerance details, git workflow, destructive commands, file creation | ~60 | ~800 |
| `context-management.md` | Large files, PDFs, codebase exploration, verbose output, bulk edits (condensed — no verbose bash examples) | ~80 | ~1k |
| `agents-and-delegation.md` | Subagent strategy, task delegation decision tree, agent teams (condensed — composition patterns → reference doc) | ~60 | ~800 |
| `coding-conventions.md` | Python basics, shell conventions, date/timestamp formatting, general programming | ~50 | ~700 |
| `research-methodology.md` | Core principles, correctness, workflow, running experiments (condensed — verbose DO/DON'T → reference doc), file organization, Hydra | ~80 | ~1k |
| `task-organization.md` | Plan/task naming, agent tracking, timestamps, per-project conventions | ~50 | ~700 |
| `tools-and-environment.md` | CLI tools list, package managers, tmux essentials (quick ref only, full guide → reference doc) | ~30 | ~400 |
| `documentation-lookup.md` | Priority order, Context7 workflow, GitHub CLI, verified repos, decision tree | ~40 | ~500 |
| `environment-setup.md` | Agent spawning fix, machine-specific setup (condensed) | ~20 | ~300 |

**Total rules**: ~470 lines, ~6.2k tokens
**Slim CLAUDE.md**: ~200 lines, ~2.5k tokens
**Combined**: ~8.7k tokens (down from 12.6k = **~4k tokens saved**)

### 1c. Create reference docs for verbose content (NOT always loaded)

Move to `claude/ai_docs/` (loaded by skills on demand):

| Reference Doc | Content Moved | Lines Saved |
|--------------|---------------|-------------|
| `tmux-reference.md` | Full tmux setup, workflow examples, inside/outside tmux, quick ref copy-paste | ~80 |
| `async-and-performance.md` | Async patterns, caching code, batch API examples, memory check scripts | ~100 |
| `agent-teams-guide.md` | Team composition patterns, communication details, known limitations | ~40 |
| `experiment-examples.md` | Detailed DO/DON'T code examples for running experiments | ~30 |

These are loaded ONLY when relevant skills are invoked (e.g., `/run-experiment` loads `async-and-performance.md`).

---

## Phase 2: Clean Up Skills

### 2a. Remove redundant user skills

| Skill | Action | Reason | Tokens Saved |
|-------|--------|--------|-------------|
| `claude/skills/codex-cli/` | **DELETE** | Exact duplicate of `code-toolkit:codex-cli` plugin skill | ~220 |
| `claude/skills/claude-code/` | **DELETE** | Exact duplicate of `code-toolkit:claude-code` plugin skill | ~120 |

### 2b. Optimize remaining user skills

| Skill | Current Tokens | Action | Target |
|-------|---------------|--------|--------|
| `gemini-cli` | 1.1k (skill) + 956 (agent) | Extract CLI syntax/workflow to `references/gemini-syntax.md`, keep trigger + decision table in SKILL.md | ~400 (skill) + 400 (agent) |
| `llm-billing` | 254 (skill) + 249 (agent) | Extract process details to reference doc, keep trigger description | ~100 (skill) + 100 (agent) |
| `strategic-communication` | 100 (skill) | Already optimized with reference docs — no change | 100 |

**Skill savings**: ~340 (removed) + ~700 (optimized) = ~1k tokens

---

## Phase 3: Plugin & MCP Pruning

### 3a. Disable Serena plugin

**Action**: Set `"serena@claude-plugins-official": false` in `settings.json`

**Saves**: ~6k tokens (35+ MCP tools removed from context)

**Rationale**: Serena's tools (read_file, search_for_pattern, find_symbol, replace_content) overlap heavily with built-in tools (Read, Grep, Glob, Edit). The unique LSP features (rename_symbol, find_referencing_symbols) are rarely used and can be re-enabled per-project when needed.

### 3b. Disable rarely-used plugins

| Plugin | Action | Rationale |
|--------|--------|-----------|
| `feature-dev@claude-plugins-official` | **Disable** | Recently added, not established in workflow |
| `ralph-loop@claude-plugins-official` | **Disable** | Niche use case, re-enable when needed |
| `pyright-lsp@claude-plugins-official` | **Disable** | LSP features overlap with Serena (also being disabled) |

**Estimated savings**: ~500-1k tokens from skills/agents these plugins contribute

### 3c. Keep these plugins (justified)

- `context7` — essential for documentation lookup
- `superpowers` — core workflow skills (brainstorming, TDD, debugging, etc.)
- `hookify` — hook creation/management
- `learning-output-style` — active output style
- `plugin-dev` — skill/agent/plugin development
- `commit-commands` — git workflow
- `code-review` — CodeRabbit integration
- `security-guidance` — security best practices
- `code-simplifier` — code cleanup
- `research-toolkit@local-marketplace` — research experiment tools
- `writing-toolkit@local-marketplace` — writing/review tools
- `code-toolkit@local-marketplace` — codex/claude agents, debugging, performance

---

## Phase 4: Update Skill References

Skills that reference verbose content should load reference docs when invoked:

| Skill | Should Load Reference Doc |
|-------|--------------------------|
| `/run-experiment` | `ai_docs/async-and-performance.md`, `ai_docs/experiment-examples.md` |
| `/agent-teams` | `ai_docs/agent-teams-guide.md` |
| `gemini-cli` agent | `skills/gemini-cli/references/gemini-syntax.md` |
| `llm-billing` agent | `skills/llm-billing/references/billing-process.md` |

---

## Token Budget Summary

| Category | Before | After | Saved |
|----------|--------|-------|-------|
| CLAUDE.md + rules | 12.6k | ~8.7k | ~3.9k |
| Skills | 9.9k | ~8.6k | ~1.3k |
| MCP tools (Serena) | 17.5k | ~11.5k | ~6k |
| Plugins overhead | (in skills) | (reduced) | ~0.5k |
| **Total** | **~48k** | **~36k** | **~12k (25%)** |

Free space increases from 95k to ~107k tokens.

---

## Files to Modify

**Create**:
- `claude/rules/safety-and-git.md`
- `claude/rules/context-management.md`
- `claude/rules/agents-and-delegation.md`
- `claude/rules/coding-conventions.md`
- `claude/rules/research-methodology.md`
- `claude/rules/task-organization.md`
- `claude/rules/tools-and-environment.md`
- `claude/rules/documentation-lookup.md`
- `claude/rules/environment-setup.md`
- `claude/ai_docs/tmux-reference.md`
- `claude/ai_docs/async-and-performance.md`
- `claude/ai_docs/agent-teams-guide.md`
- `claude/ai_docs/experiment-examples.md`

**Edit**:
- `claude/CLAUDE.md` — slim down to ~200 lines
- `claude/skills/gemini-cli/SKILL.md` — extract CLI syntax to reference
- `claude/agents/gemini-cli.md` — slim down agent definition
- `claude/skills/llm-billing/SKILL.md` — extract process to reference
- `claude/agents/llm-billing.md` — slim down agent definition
- `claude/settings.json` — disable Serena, feature-dev, ralph-loop, pyright-lsp

**Delete**:
- `claude/skills/codex-cli/` — redundant with code-toolkit plugin
- `claude/skills/claude-code/` — redundant with code-toolkit plugin

---

## Verification

1. **Token count**: Run `/context` to verify total overhead dropped from ~48k to ~36k
2. **Rules loading**: Start new session, verify rules load (check that safety rules still appear in context)
3. **Skill invocation**: Test `/run-experiment`, `/agent-teams` to verify reference docs load correctly
4. **No regressions**: Verify `gemini-cli` and `llm-billing` agents still work after optimization
5. **Plugin state**: Verify disabled plugins don't appear in `/context` output

---

## Execution Order

1. Create `claude/rules/` directory and write all rule files (Phase 1b)
2. Create reference docs in `claude/ai_docs/` (Phase 1c)
3. Slim down `claude/CLAUDE.md` (Phase 1a) — do this AFTER rules exist
4. Remove redundant skills (Phase 2a)
5. Optimize remaining skills (Phase 2b)
6. Update `claude/settings.json` to disable plugins (Phase 3)
7. Test and verify (Phase 4)
