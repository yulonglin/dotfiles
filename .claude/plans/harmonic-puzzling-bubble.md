# Plan: Extract Plugin Marketplace to GitHub Repo

## Context

The 5 custom plugins in `claude/local-marketplace/` are currently embedded in the dotfiles repo, installed via filesystem path.

**Problems with current structure:**
1. **Not shareable** — filesystem-based marketplace can't be installed by others
2. **Hidden cross-dependencies** — marketplace plugins silently depend on global agents (`codex`, `gemini-cli`, `context-summariser`, `efficient-explorer`) that live outside the marketplace in `claude/agents/`. Another researcher installing just `code-toolkit` would find that `plan-critic` and `codex-reviewer` agents fail because the `codex` agent doesn't exist on their machine.
3. **No onboarding** — no dependency docs, no setup guide, no graceful degradation
4. **Coupled to dotfiles** — plugin changes require dotfiles commits

**Goals:**
- Extract into standalone GitHub repo at `github.com/yulonglin/ai-safety-plugins`
- Create a new `core-toolkit` plugin for foundational agents/skills other plugins depend on
- Document all dependencies per-plugin with clear onboarding for AI safety researchers
- One-command install: `/plugin marketplace add yulonglin/ai-safety-plugins`

**Decisions:**
- Repo & marketplace name: `ai-safety-plugins`
- All 5 existing plugins + new `core-toolkit` = 6 plugins total
- Personal GitHub account (yulonglin)
- MIT license

---

## Step 1: Backup & commit current dotfiles changes

### 1a. Backup local marketplace + agents/skills/hooks

Before any destructive changes, archive the current state:
```bash
tar czf ~/code/dotfiles-marketplace-backup-$(date +%Y%m%d).tar.gz \
  claude/local-marketplace/ claude/agents/ claude/skills/ claude/hooks/
```

This is belt-and-suspenders — git history preserves everything, but an explicit archive protects against mistakes during the migration.

### 1b. Stage and commit pending changes
- `claude/chrome/chrome-native-host` (modified)
- `claude/local-marketplace/plugins/code-toolkit/agents/codex.md` (deleted — moved to global)
- `claude/settings.json` (modified)
- `claude/agents/codex.md` (new — codex agent moved to global agents)
- `claude/hooks/task_force_background.sh` (new — forces Task calls to background)

Skip: `claude/tasks/` directory (runtime).

---

## Step 2: Create `core-toolkit` plugin

### Why

Multiple marketplace plugins depend on global agents that live outside the marketplace:

| Global agent/skill | Used by |
|---|---|
| `codex` agent | code-toolkit (plan-critic, codex-reviewer, codex-cli skill) |
| `gemini-cli` agent | code-toolkit (claude agent), workflow-toolkit (insights skill) |
| `context-summariser` agent | workflow-toolkit (custom-compact skill) |
| `efficient-explorer` agent | General use (all plugins benefit) |

If another researcher installs just `code-toolkit`, the codex agent won't exist — it's a loose file in `~/.claude/agents/`, not in any plugin. `core-toolkit` packages these foundational tools as an installable plugin.

### What goes in

**Agents** (from `claude/agents/`):
| Agent | External deps | Notes |
|---|---|---|
| `efficient-explorer` | None (built-in tools) | Context-efficient codebase exploration |
| `context-summariser` | None (built-in tools) | Conversation compression |
| `codex` | Codex CLI + OpenAI key | Implementation delegation — **optional dep** |
| `gemini-cli` | Gemini CLI + Google key | Large context delegation — **optional dep** |

**Skills** (from `claude/skills/`):
| Skill | External deps | Notes |
|---|---|---|
| `docs-search` | `fd`, `rg` | Fast grep-based docs search |
| `fast-cli` | eza, fd, rg, bat, dust, etc. | Modern CLI tool mappings — **optional deps** |
| `spec-interview` | None | Interview-based spec development |
| `task-management` | None (built-in Task tools) | Timestamped task tracking |

**Hooks** (from `claude/hooks/` — safety guards):
| Hook | Type | Notes |
|---|---|---|
| `check_destructive_commands.sh` | PreToolUse:Bash | Blocks `sudo rm`, `xargs kill`, etc. |
| `check_secrets.sh` | PreToolUse:Bash | Blocks committing API keys/tokens |
| `check_read_size.sh` | PreToolUse:Read | Warns on reading large files without offset/limit |
| `task_force_background.sh` | PreToolUse:Task | Forces subagent calls to background, avoids JSONL dumps (#16789). Disable: `CLAUDE_TASK_FORCE_BG=0` |
| `truncate_output.sh` | PostToolUse:Bash | Truncates verbose output to prevent context waste |
| `pre_plan_create.sh` | PreToolUse:Write | Enforces per-project plans (not global) |
| `pre_task_create.sh` | PreToolUse:TaskCreate | Enforces per-project tasks |

All deps: `jq` (required), `git` (for pre_plan/task), `gitleaks` (optional for check_secrets).

**Convenience hooks → `workflow-toolkit`** (all opt-out via env var):
| Hook | Type | Notes |
|---|---|---|
| `auto_background.sh` | PreToolUse:Bash | Auto-backgrounds long commands. Disable: `CLAUDE_AUTOBACKGROUND=0` |
| `check_pipe_buffering.sh` | PreToolUse:Bash | Warns about piping anti-patterns. Warn only, non-blocking |
| `auto_log.sh` | Pre/PostToolUse:Bash | Audit trail of commands. Async, non-blocking |

**What stays in dotfiles (personal, not shared):**
- `llm-billing` — personal billing script
- `commit` / `commit-push-sync` — personal git workflow
- `anthropic-style` — Anthropic-specific branding
- `agent_spawned.sh` — personal agent tracking hook
- `pre_session_start.sh` — personal docs-staleness checker

### Plugin structure

```
core-toolkit/
├── .claude-plugin/plugin.json    # Includes hooks config
├── agents/
│   ├── efficient-explorer.md
│   ├── context-summariser.md
│   ├── codex.md
│   └── gemini-cli.md
├── hooks/
│   ├── check_destructive_commands.sh
│   ├── check_secrets.sh
│   ├── check_read_size.sh
│   ├── task_force_background.sh
│   ├── truncate_output.sh
│   ├── pre_plan_create.sh
│   └── pre_task_create.sh
└── skills/
    ├── docs-search/SKILL.md
    ├── fast-cli/SKILL.md
    ├── spec-interview/SKILL.md
    └── task-management/SKILL.md
```

Hooks are declared in `plugin.json` using `${CLAUDE_PLUGIN_ROOT}/hooks/...` paths.

### Hook migration from settings.json

When hooks move into plugins, the corresponding entries in dotfiles `settings.json` must be **removed** to avoid double-execution. Only personal hooks (`agent_spawned`, `pre_session_start`) remain in `settings.json`.

### Always-on configuration

For dotfiles owner: add `core-toolkit` to the `base` list in `profiles.yaml`.

For other users: guide them to enable globally:
```json
{ "enabledPlugins": { "core-toolkit@ai-safety-plugins": true } }
```

---

## Step 3: Create the marketplace repository

Create `~/code/ai-safety-plugins/`:

```
ai-safety-plugins/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   ├── core-toolkit/           # NEW — foundational agents & skills
│   ├── research-toolkit/       # From local-marketplace
│   ├── writing-toolkit/        # From local-marketplace
│   ├── code-toolkit/           # From local-marketplace
│   ├── workflow-toolkit/       # From local-marketplace
│   └── viz-toolkit/            # From local-marketplace
├── .gitignore
├── LICENSE                     # MIT
└── README.md                   # Tiered onboarding guide
```

### marketplace.json

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "ai-safety-plugins",
  "description": "Claude Code plugins for AI safety research: experiment design, academic writing, code review, workflow management, and visualization",
  "owner": { "name": "Yulong Lin" },
  "metadata": { "version": "1.0.0", "pluginRoot": "./plugins" },
  "plugins": [
    {
      "name": "core-toolkit",
      "source": "core-toolkit",
      "description": "Foundational agents and skills: codebase exploration, conversation compression, CLI delegation (Codex/Gemini), spec interviews, and docs search",
      "version": "1.0.0",
      "category": "core",
      "keywords": ["core", "agents", "delegation", "exploration"],
      "license": "MIT"
    },
    {
      "name": "research-toolkit",
      "source": "research-toolkit",
      "description": "AI safety research workflows: experiment design, execution, analysis, and literature review",
      "version": "1.0.0",
      "category": "research",
      "keywords": ["ai-safety", "experiments", "research", "analysis"],
      "license": "MIT"
    },
    {
      "name": "writing-toolkit",
      "source": "writing-toolkit",
      "description": "Academic writing: papers, drafts, presentations, and multi-critic review",
      "version": "1.0.0",
      "category": "writing",
      "keywords": ["academic", "papers", "presentations", "writing"],
      "license": "MIT"
    },
    {
      "name": "code-toolkit",
      "source": "code-toolkit",
      "description": "Code review, debugging, performance optimization, bulk editing, and CLI delegation",
      "version": "1.0.0",
      "category": "development",
      "keywords": ["code-review", "debugging", "performance", "delegation"],
      "license": "MIT"
    },
    {
      "name": "workflow-toolkit",
      "source": "workflow-toolkit",
      "description": "Agent teams, handover, conversation management, and usage analytics",
      "version": "1.0.0",
      "category": "workflow",
      "keywords": ["agents", "teams", "handover", "analytics"],
      "license": "MIT"
    },
    {
      "name": "viz-toolkit",
      "source": "viz-toolkit",
      "description": "TikZ diagrams and Anthropic-style visualization",
      "version": "1.0.0",
      "category": "visualization",
      "keywords": ["tikz", "diagrams", "visualization", "plotting"],
      "license": "MIT"
    }
  ]
}
```

### plugin.json updates (all 6 plugins)

Each `.claude-plugin/plugin.json` gets: `repository`, `license: "MIT"`, `keywords`.

---

## Step 4: Dependency documentation & onboarding

### Dependency matrix (in README)

| Dependency | core | research | writing | code | workflow | viz |
|---|---|---|---|---|---|---|
| **Claude Code v2.1+** | REQ | REQ | REQ | REQ | REQ | REQ |
| **CLI tools** | | | | | | |
| Codex CLI | opt | — | — | REQ | — | — |
| Gemini CLI | opt | — | — | opt | REQ¹ | — |
| `fd` + `rg` | opt | — | — | — | — | — |
| `bun`/`bunx` | — | — | opt² | — | — | — |
| LaTeX (pdflatex/xelatex) | — | — | opt³ | — | — | REQ |
| Modern CLI⁴ | opt | — | — | — | — | — |
| **Auth / API keys** | | | | | | |
| OpenAI API key | opt⁵ | opt⁶ | — | opt⁵ | — | — |
| Google API key | opt⁷ | — | — | opt⁷ | opt⁷ | — |
| `gh auth login` | — | — | — | opt | opt | — |
| **Python** | | | | | | |
| Python 3.9+ | — | REQ | — | — | REQ¹ | — |

¹ For `/insights` skill only. ² Slidev presentations. ³ Research presentations. ⁴ eza, bat, dust, duf, fzf, zoxide, delta, jq. ⁵ For Codex delegation. ⁶ For API experiments. ⁷ For Gemini delegation.

### README structure (tiered onboarding)

**Quick Start (1 minute):**
```
/plugin marketplace add yulonglin/ai-safety-plugins
/plugin install core-toolkit@ai-safety-plugins
/plugin install research-toolkit@ai-safety-plugins
```

**Per-plugin sections** — each with:
- What's included (agents + skills list)
- Required vs optional dependencies
- Install commands for dependencies

**Full Setup (5 minutes):**
```bash
# macOS
brew install codex gemini-cli fd ripgrep
brew install --cask mactex          # Only for viz-toolkit / presentations

# Auth
codex auth                           # OpenAI key
gh auth login                        # GitHub token (optional)
```

**Enable always-on:**
```json
{ "enabledPlugins": { "core-toolkit@ai-safety-plugins": true } }
```

---

## Step 5: Initialize git repo and push

```bash
cd ~/code/ai-safety-plugins
git init && git add -A
git commit -m "feat: initial marketplace with 6 plugins for AI safety research"
gh repo create yulonglin/ai-safety-plugins --public --source=. --push \
  --description "Claude Code plugins for AI safety research"
```

---

## Step 6: Update dotfiles to use remote marketplace

### 6a. Replace `claude/local-marketplace/` with symlink to marketplace repo

Instead of removing entirely, replace with a symlink:
```bash
# Remove the embedded marketplace content
trash claude/local-marketplace
# Symlink to the separate marketplace repo
ln -s ~/code/ai-safety-plugins claude/local-marketplace
```

This preserves the local development workflow:
- Claude Code still registers `~/.claude/local-marketplace` (local path) for zero-friction dev
- Edits in `~/code/ai-safety-plugins/` are immediately visible via the symlink
- `claude plugin marketplace update` or CC restart refreshes the cache
- `deploy.sh` on YOUR machine registers local path; for others, registers GitHub URL
- Publishing: `cd ~/code/ai-safety-plugins && git push`

**On other machines** (where the marketplace repo isn't cloned):
`deploy.sh` detects no local clone → registers GitHub URL instead.

### 6b. Remove migrated agents/skills/hooks from dotfiles

Agents moved to core-toolkit — remove from `claude/agents/`:
- `efficient-explorer.md`, `context-summariser.md`, `codex.md`, `gemini-cli.md`

Skills moved to core-toolkit — remove from `claude/skills/`:
- `docs-search/`, `fast-cli/`, `spec-interview/`, `task-management/`

Hooks moved to core-toolkit — remove from `claude/hooks/`:
- `check_destructive_commands.sh`, `check_secrets.sh`, `check_read_size.sh`
- `task_force_background.sh`, `truncate_output.sh`, `pre_plan_create.sh`, `pre_task_create.sh`

Hooks moved to workflow-toolkit — remove from `claude/hooks/`:
- `auto_background.sh`, `check_pipe_buffering.sh`, `auto_log.sh`

Keep in dotfiles (personal):
- Agents/skills: `llm-billing`, `commit`, `commit-push-sync`, `anthropic-style`
- Hooks: `agent_spawned.sh`, `pre_session_start.sh`

### 6b-extra. Clean up `settings.json` hooks section

Remove hook entries that now come from plugins (core-toolkit and workflow-toolkit). Only keep personal hooks (`agent_spawned`, `pre_session_start`) in `settings.json`.

### 6c. Update `deploy.sh` (lines 431-468)

Smart detection: use local path if marketplace repo is cloned, GitHub URL otherwise.

```bash
MARKETPLACE_REPO="$CODE_DIR/ai-safety-plugins"
if [[ -d "$MARKETPLACE_REPO/.claude-plugin" ]]; then
    # Local development — register local path (zero-friction edits)
    claude plugin marketplace add "$MARKETPLACE_REPO"
else
    # Other machines — register GitHub URL
    claude plugin marketplace add yulonglin/ai-safety-plugins
fi

# Install/update all plugins from the marketplace (no hardcoded list)
claude plugin marketplace update ai-safety-plugins 2>/dev/null || true
```

No hardcoded plugin list — `marketplace update` handles all plugins defined in `marketplace.json`.

### 6d. Update `profiles.yaml`

```yaml
# Registry — update all 5 + add core-toolkit
core-toolkit: core-toolkit@ai-safety-plugins
code-toolkit: code-toolkit@ai-safety-plugins
research-toolkit: research-toolkit@ai-safety-plugins
writing-toolkit: writing-toolkit@ai-safety-plugins
workflow-toolkit: workflow-toolkit@ai-safety-plugins
viz-toolkit: viz-toolkit@ai-safety-plugins

# Base — add core-toolkit as always-on
base:
  - superpowers
  - hookify
  - plugin-dev
  - commit-commands
  - claude-md-management
  - context7
  - core-toolkit          # NEW
```

### 6e. Update `settings.json` enabledPlugins

- Replace all `@local-marketplace` → `@ai-safety-plugins`
- Add `"core-toolkit@ai-safety-plugins": true`

### 6f. Verify `claude-context` CLI — no hardcoded `local-marketplace` strings

### 6g. Update documentation

| File | Change |
|------|--------|
| `claude/CLAUDE.md` | "Plugin Organization" — `local-marketplace` → `ai-safety-plugins`, add core-toolkit |
| `CLAUDE.md` | Architecture section — update directory tree |
| Global `CLAUDE.md` agents/delegation | Update agent refs if needed |

---

## Step 7: Plugin migration

1. `claude plugin marketplace remove local-marketplace`
2. `claude plugin marketplace add yulonglin/ai-safety-plugins`
3. Install all 6 plugins
4. Verify: `claude plugin list` shows `@ai-safety-plugins` entries

---

## Step 8: Verify end-to-end

1. `claude plugin marketplace list` — shows `ai-safety-plugins` from GitHub
2. `claude plugin list` — shows all 6 plugins
3. `claude-context code` — resolves with new marketplace name
4. `claude-context --check` — no drift
5. Test skills: `/docs-search` (core), `/review-draft` (writing)
6. Test agents: spawn efficient-explorer, codex delegation

### Clean-machine test
```bash
claude plugin marketplace add yulonglin/ai-safety-plugins
claude plugin install core-toolkit@ai-safety-plugins
claude plugin install research-toolkit@ai-safety-plugins
# Verify /spec-interview-research works
```

---

## Step 9: Commit dotfiles changes and push

---

## Summary of all files

### Dotfiles repo — modify

| File | Change |
|------|--------|
| `claude/local-marketplace/` | Replace with symlink → `~/code/ai-safety-plugins/` |
| `claude/agents/` | Remove 4 agents moved to core-toolkit |
| `claude/skills/` | Remove 4 skills moved to core-toolkit |
| `claude/hooks/` | Remove 9 hooks moved to plugins; keep 2 personal |
| `deploy.sh:431-468` | GitHub marketplace registration |
| `claude/templates/contexts/profiles.yaml` | `@local-marketplace` → `@ai-safety-plugins`, core-toolkit in base |
| `claude/settings.json` | enabledPlugins keys + remove migrated hook entries |
| `claude/CLAUDE.md` | Plugin Organization section |
| `CLAUDE.md` | Architecture section |
| `custom_bins/claude-context` | Verify no hardcoded refs |

### New repo (`ai-safety-plugins`) — create

| File | Content |
|------|---------|
| `.claude-plugin/marketplace.json` | Marketplace catalog (6 plugins) |
| `plugins/core-toolkit/` | Agents + skills + 6 safety hooks from dotfiles |
| `plugins/core-toolkit/.claude-plugin/plugin.json` | With hooks config using `${CLAUDE_PLUGIN_ROOT}` |
| `plugins/research-toolkit/` | From `claude/local-marketplace/plugins/` |
| `plugins/writing-toolkit/` | From `claude/local-marketplace/plugins/` |
| `plugins/code-toolkit/` | From `claude/local-marketplace/plugins/` |
| `plugins/workflow-toolkit/` | From local-marketplace + 3 convenience hooks |
| `plugins/workflow-toolkit/.claude-plugin/plugin.json` | Updated with hooks config |
| `plugins/viz-toolkit/` | From `claude/local-marketplace/plugins/` |
| `README.md` | Tiered onboarding with dependency matrix |
| `LICENSE` | MIT |
| `.gitignore` | Standard |
