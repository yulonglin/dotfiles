# OpenAI Codex CLI Extensibility Research

## Overview

Comprehensive research into OpenAI Codex CLI extensibility mechanisms, comparing with Claude Code's capabilities.

## Research Findings

### 1. Skills System ✅

**Status**: Fully supported, core extensibility mechanism

**Details**:
- Format: Markdown files with YAML frontmatter (`SKILL.md`)
- Location:
  - Global: `~/.codex/skills/` or `~/.agents/skills/` (as of Feb 2026)
  - Local: Can be stored in project directories
- Structure:
  ```markdown
  ---
  name: skill-name
  description: Description that helps Codex select the skill (max 500 chars)
  ---

  Skill instructions for the Codex agent to follow when using this skill.
  ```

**What Skills Can Do**:
- Bundle instructions, scripts, and resources together
- Reusable across projects (can be checked into repos)
- Lazy loading: metadata loaded at startup, body only loaded when invoked
- Can include: Python scripts, templates, schemas, reference data, documentation
- Installed with `$skill-installer` command
- Curated catalog: https://github.com/openai/skills

**Key Updates (Feb 2026)**:
- Live skill update detection (no restart needed)
- Personal skill loading from `~/.agents/skills`
- App-server APIs for listing/downloading remote skills

**Sources**:
- [Agent Skills](https://developers.openai.com/codex/skills/)
- [Create skills](https://developers.openai.com/codex/skills/create-skill/)
- [Skills Catalog](https://github.com/openai/skills)
- [Codex changelog](https://developers.openai.com/codex/changelog/)

---

### 2. Agents/Subagents ⚠️

**Status**: NOT natively supported, community workarounds exist

**Details**:
- Codex does NOT have native subagent support like Claude Code
- Open feature request: https://github.com/openai/codex/issues/2604
- Community has built workarounds:
  1. **MCP Server Approach**: `codex-subagents-mcp` by leonardsellem
     - Spins up clean Codex instances in temp workdirs
     - Injects personas via `AGENTS.md`
     - Uses `codex exec --profile <agent>` for isolated state
  2. **Wrapper Script Approach**: Parent Codex spawns child Codex instances
  3. **OpenAI Agents SDK Integration**: Use Codex as MCP server within multi-agent orchestration

**Custom Agent Definitions**:
- Community implementations use Markdown files in `~/.codex-subagents/agents/`
- Format: YAML frontmatter (name, description, model, tools) + agent instructions
- Agent name derived from file basename (e.g., `agents/review.md` → agent `review`)
- Execution profiles defined in `~/.codex/config.toml` under `[profiles.<n>]`

**What Codex LACKS vs Claude Code**:
- No native automatic subagent invocation
- No built-in specialized agents (review, debug, security)
- No agent-specific context windows or permission isolation
- Requires third-party MCP servers or wrappers for delegation

**Sources**:
- [Subagent Support Issue](https://github.com/openai/codex/issues/2604)
- [codex-subagents-mcp](https://github.com/leonardsellem/codex-subagents-mcp)
- [Hacking Subagents Into Codex CLI](https://app.daily.dev/posts/hacking-subagents-into-codex-cli-brian-john-betterup-qhtmwui7u)
- [How can I create custom agents](https://github.com/openai/codex/discussions/6109)

---

### 3. Plugins ❌

**Status**: No formal plugin system

**Details**:
- Codex does NOT have a plugin architecture like Claude Code's local marketplace
- Extensibility is achieved through:
  - Skills (primary mechanism)
  - MCP servers
  - Custom slash commands/prompts
- No plugin installation/management system

**What Codex LACKS**:
- No plugin manifest format
- No plugin installation tool
- No plugin versioning or dependencies
- No plugin marketplace (local or remote)

---

### 4. Hooks ⚠️

**Status**: Limited, single notification hook only

**Details**:
- Only supported hook: `notify`
- Triggered by events (currently only `agent-turn-complete`)
- Configuration in `~/.codex/config.toml`:
  ```toml
  notify = ["/bin/bash", "/path/to/script.sh", "args..."]
  ```

**What Hooks Can Do**:
- Run external programs when agent completes a turn
- Pass event data to scripts
- Use cases: webhooks, desktop notifiers, CI hooks, logging

**Community Tools**:
- `codex-notify`: macOS desktop notifications
- `code-notify`: Cross-platform notifications
- `agent-notifications`: Rust-based notification system

**What Codex LACKS vs Claude Code**:
- No pre-commit hooks
- No post-task hooks
- No file-change hooks
- Limited to single event type (agent-turn-complete)
- Feature request for expanded hooks: https://github.com/openai/codex/issues/2109

**Sources**:
- [Advanced Configuration](https://developers.openai.com/codex/config-advanced/)
- [Event Hooks Issue](https://github.com/openai/codex/issues/2109)
- [codex-notify](https://github.com/heydong1/codex-notify)
- [code-notify](https://github.com/mylee04/code-notify)

---

### 5. MCP Servers ✅

**Status**: Fully supported (stdio only, HTTP in progress)

**Details**:
- Configuration: `~/.codex/config.toml`
- Format:
  ```toml
  [mcp_servers.<server-name>]
  command = ["executable", "args..."]
  bearer_token_env_var = "OPTIONAL_TOKEN_ENV_VAR"
  http_headers = { "Header-Name" = "static-value" }
  env_http_headers = { "Header-Name" = "ENV_VAR_NAME" }
  ```

**What MCP Can Do**:
- Connect to external tools and context sources
- Standard protocol for third-party integrations
- Session-scoped "Allow and remember" for tool approvals (Feb 2026)
- `/debug-config` command to inspect MCP configuration

**Current Limitations**:
- Stdio-based only (no direct HTTP endpoint support yet)
- Less mature than Claude Code's MCP implementation

**Unique Feature**:
- Codex can run AS an MCP server for multi-agent systems

**Sources**:
- [Model Context Protocol](https://developers.openai.com/codex/mcp/)
- [Configuration Reference](https://developers.openai.com/codex/config-reference/)
- [Codex changelog](https://developers.openai.com/codex/changelog/)

---

### 6. Custom Slash Commands/Prompts ✅

**Status**: Fully supported

**Details**:
- Format: Markdown files in `~/.codex/` (or custom location)
- Filename becomes command: `review.md` → `/review`
- Requires explicit invocation (not auto-invoked like skills)

**Structure**:
```markdown
---
# Optional metadata
---

Prompt content with templating support:
- Positional: $1 through $9
- All args: $ARGUMENTS
- Named: $FILE, $TICKET_ID (supplied as KEY=value)
```

**What Custom Prompts Can Do**:
- Create team-specific workflows
- Personal shortcuts for common tasks
- Template-based prompts with arguments
- Local only (not shared via repo like skills)

**Key Difference from Skills**:
- Prompts: Explicit invocation, local-only
- Skills: Can be auto-invoked, shareable, include resources

**Sources**:
- [Slash commands](https://developers.openai.com/codex/cli/slash-commands/)
- [Custom Prompts](https://developers.openai.com/codex/custom-prompts/)
- [Supercharge Your Codex Workflow](https://jpcaparas.medium.com/supercharge-your-codex-workflow-with-slash-commands-a53c59edde38)

---

### 7. Configuration System ✅

**Status**: Comprehensive TOML-based configuration

**Details**:
- Primary: `~/.codex/config.toml`
- Project-specific: `.codex/config.toml` (trusted projects only)
- Shared between CLI and IDE extension

**Configuration Hierarchy** (highest to lowest priority):
1. Command-line flags
2. Profile settings (`[profiles.<name>]`)
3. Top-level config settings
4. Built-in defaults

**What's Configurable**:
- Default models and providers
- Approval policies (when to ask for permission)
- Sandbox settings (system access level)
- MCP server connections
- Notification hooks
- Profiles (named configuration sets)

**Profiles**:
```toml
[profiles.deep-review]
model = "o1-preview"
# ... other settings

# Make default
profile = "deep-review"
```

**CLI Override**:
```bash
codex --profile deep-review
codex -c key=value
```

**Sources**:
- [Config basics](https://developers.openai.com/codex/config-basic/)
- [Configuration Reference](https://developers.openai.com/codex/config-reference/)
- [Advanced Configuration](https://developers.openai.com/codex/config-advanced/)
- [Master Codex Config.toml](https://www.ipfly.net/blog/codex-config-toml-guide/)

---

## What Codex CLI Does NOT Support (vs Claude Code)

### Native Subagents ❌
- **Claude Code**: Built-in subagents with automatic invocation, custom system prompts, isolated contexts
- **Codex**: Requires third-party MCP servers or wrapper scripts
- **Impact**: Less intelligent task delegation, manual orchestration needed

### Plugin System ❌
- **Claude Code**: Local plugin marketplace, plugin installation/management
- **Codex**: No plugin architecture
- **Impact**: Less modular extensibility, harder to share complex extensions

### Task Management ❌
- **Claude Code**: Native TodoWrite, TaskCreate, TaskUpdate with dependencies, multi-session coordination
- **Codex**: No built-in task tracking
- **Impact**: Manual task tracking required for complex projects

### Advanced Hooks ❌
- **Claude Code**: Pre-commit, post-task, file-change hooks
- **Codex**: Single notification hook (agent-turn-complete only)
- **Impact**: Limited automation and workflow integration

### HTTP MCP Support ⚠️
- **Claude Code**: Full stdio and HTTP MCP support
- **Codex**: Stdio only (HTTP in progress)
- **Impact**: Can't use HTTP-based MCP servers directly

### Agent Definitions Directory ❌
- **Claude Code**: `~/.claude/agents/` with Markdown-based agent definitions
- **Codex**: No official agent definition system
- **Impact**: Harder to create/share custom agents

---

## Strengths of Codex CLI

1. **Open Source**: Full transparency, community contributions
2. **Skills System**: Mature, well-designed extensibility via SKILL.md
3. **Rust Performance**: Fast, efficient
4. **Codex as MCP Server**: Unique ability to embed Codex in multi-agent systems
5. **Shared Config**: CLI and IDE extension use same TOML config
6. **Profiles**: Powerful named configuration sets

---

## Summary Comparison Table

| Feature | Codex CLI | Claude Code | Notes |
|---------|-----------|-------------|-------|
| Skills | ✅ Native (SKILL.md) | ✅ Native (SKILL.md) | Similar format |
| Agents/Subagents | ⚠️ Community only | ✅ Native | Major difference |
| Plugins | ❌ None | ✅ Local marketplace | Codex uses Skills instead |
| Hooks | ⚠️ Single (notify) | ✅ Multiple types | Limited in Codex |
| MCP Servers | ✅ Stdio only | ✅ Stdio + HTTP | Codex catching up |
| Custom Commands | ✅ Slash commands | ✅ Slash commands | Similar |
| Configuration | ✅ TOML-based | ✅ JSON-based | Different formats |
| Task Management | ❌ None | ✅ Native | Major gap |
| Open Source | ✅ Yes | ❌ No | Transparency vs polish |

---

## Sources Summary

**Primary Documentation**:
- [Codex CLI](https://developers.openai.com/codex/cli/)
- [Agent Skills](https://developers.openai.com/codex/skills/)
- [Model Context Protocol](https://developers.openai.com/codex/mcp/)
- [Configuration Reference](https://developers.openai.com/codex/config-reference/)

**GitHub**:
- [openai/codex](https://github.com/openai/codex) - Main repository
- [openai/skills](https://github.com/openai/skills) - Skills catalog

**Community Tools**:
- [codex-subagents-mcp](https://github.com/leonardsellem/codex-subagents-mcp)
- [codex-notify](https://github.com/heydong1/codex-notify)
- [code-notify](https://github.com/mylee04/code-notify)

**Comparisons**:
- [Codex vs Claude Code 2026](https://smartscope.blog/en/generative-ai/chatgpt/codex-vs-claude-code-2026-benchmark/)
- [Builder.io Comparison](https://www.builder.io/blog/codex-vs-claude-code)
- [Northflank Comparison](https://northflank.com/blog/claude-code-vs-openai-codex)

---

## Key Takeaways

1. **Skills are Codex's primary extensibility mechanism** - well-designed, shareable, powerful
2. **No native subagent support** - major gap vs Claude Code, requires workarounds
3. **MCP support exists but less mature** - stdio only, HTTP coming
4. **Configuration is comprehensive** - TOML-based, profiles, hierarchical
5. **Open source nature** - allows community innovation but means some features lag behind Claude Code
6. **Task management gap** - no built-in task tracking like Claude Code
7. **Limited hooks** - only notification hook, no file/commit hooks

The overall architecture favors **explicit, shareable components (Skills)** over **built-in intelligence (Subagents)**, reflecting OpenAI's open-source philosophy vs Anthropic's integrated approach.
