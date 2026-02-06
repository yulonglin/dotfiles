# Gemini CLI Extensibility Research

**Research Date:** 2026-02-05
**Status:** Complete

## Executive Summary

Google's Gemini CLI is an open-source (Apache 2.0) terminal-based AI agent with extensive extensibility. It supports **7 primary extensibility mechanisms**: Extensions (bundled packages), Agent Skills, MCP Servers, Hooks, Custom Slash Commands, Custom Tools, and GEMINI.md context files.

**Key Finding:** Gemini CLI and Claude Code have surprisingly similar extensibility models, with some unique differences:
- **Gemini advantages**: Open-source, hooks system, discoverable custom tools via commands
- **Claude advantages**: Subagents with memory, plugin marketplace, more mature skill ecosystem

---

## 1. Extensions (Bundled Packages)

**What:** Self-contained, versionable packages that bundle MCP servers, context files, slash commands, Agent Skills, and hooks.

**Storage:**
- User-level: `~/.gemini/extensions/`
- Project-level: `.gemini/extensions/`

**Configuration:**
- `gemini-extension.json` - Main extension manifest
- Fields:
  - `mcpServers` - Map of MCP server configurations
  - `excludeTools` - Array of tool names to exclude
  - Command-specific restrictions (e.g., `run_shell_command`)

**Installation:**
```bash
gemini extensions install <github-url>
gemini extensions install <local-path>
gemini extensions list
```

**Precedence:** Workspace config > User config > Extension config

**Components an Extension Can Include:**
- MCP Server configurations
- GEMINI.md context files
- Custom slash commands (`.toml` files)
- Agent Skills (in `skills/` subdirectory)
- Hooks (in `hooks/hooks.json`)

**Sources:**
- [Gemini CLI Extensions Documentation](https://geminicli.com/docs/extensions/)
- [Getting Started with Extensions](https://geminicli.com/docs/extensions/getting-started-extensions/)
- [Browse Extensions](https://geminicli.com/extensions/)

---

## 2. Agent Skills

**What:** On-demand expertise and specialized workflows. Unlike GEMINI.md (persistent context), skills are activated only when needed, saving context tokens.

**Storage:**
- User-level: `~/.gemini/skills/`
- Project-level: `.gemini/skills/`
- Extension-bundled: `<extension>/skills/`

**File Format:** SKILL.md with YAML frontmatter

**Structure:**
```markdown
---
name: unique-skill-name
description: What the skill does and when to use it
---

# Instructions

Your detailed instructions for how the agent should behave...
```

**Optional Resources:**
- `scripts/` - Helper scripts
- `references/` - Reference materials
- `assets/` - Additional resources

**Behavior:**
- Gemini CLI discovers skills by name/description at startup
- Full SKILL.md body and folder structure loaded on-demand when activated
- Skill directory added to agent's allowed file paths (can read bundled assets)

**Discovery:** Only metadata (name, description) loaded initially; full content loaded when skill is invoked.

**Sources:**
- [Agent Skills Documentation](https://geminicli.com/docs/cli/skills/)
- [Creating Agent Skills](https://geminicli.com/docs/cli/creating-skills/)
- [Getting Started with Agent Skills](https://geminicli.com/docs/cli/tutorials/skills-getting-started/)

---

## 3. MCP Servers (Model Context Protocol)

**What:** Applications that expose tools and resources to Gemini CLI through the Model Context Protocol. Acts as a bridge between the Gemini model and local environment or external APIs.

**Configuration Location:** `~/.gemini/settings.json` or `.gemini/settings.json`

**Configuration Format:**
```json
{
  "mcpServers": {
    "server-name": {
      "command": "python",
      "args": ["-m", "your_mcp_server"],
      "env": {
        "API_KEY": "$MY_API_KEY"
      }
    }
  }
}
```

**FastMCP Integration:**
- As of FastMCP v2.12.3, can install local STDIO transport MCP servers
- Command: `fastmcp install gemini-cli`
- Python-based MCP server framework

**Language Support:**
- Python (via FastMCP)
- Go (via custom MCP servers)
- TypeScript (MCP SDK)
- Any language supporting stdio/SSE/HTTP

**Authentication:**
- OAuth 2.0 support for remote MCP servers (SSE/HTTP transports)
- Environment variable substitution in config (`$VAR_NAME` or `${VAR_NAME}`)

**Tool Availability:** Once configured, MCP tools are available to the model like built-in tools.

**Sources:**
- [MCP Servers with Gemini CLI](https://geminicli.com/docs/tools/mcp-server/)
- [Gemini CLI + FastMCP Blog](https://developers.googleblog.com/gemini-cli-fastmcp-simplifying-mcp-server-development/)
- [Official MCP Support for Google Services](https://cloud.google.com/blog/products/ai-machine-learning/announcing-official-mcp-support-for-google-services)

---

## 4. Hooks (Lifecycle Events)

**What:** Scripts/programs executed at specific points in the agentic loop. Runs synchronously - Gemini CLI waits for all hooks to complete before continuing.

**Configuration Location:** `settings.json` (user/project/extension)

**Configuration Format:**
```json
{
  "hooks": {
    "beforeTool": [
      {
        "command": "node",
        "args": ["validate-tool.js"],
        "matcher": "run_shell_command"
      }
    ],
    "afterTool": [...],
    "startup": [...],
    "shutdown": [...]
  }
}
```

**Lifecycle Events:**
- `startup` - Before first user message
- `shutdown` - After session ends
- `beforeTool` - Before any tool execution
- `afterTool` - After any tool execution
- More events (matchers use exact strings or wildcards like `*`)

**Matchers:**
- Lifecycle events: Exact strings (e.g., `"startup"`)
- Tool events: Regular expressions (e.g., `"run_shell_.*"`)
- Wildcards: `"*"` or `""` (empty string) matches all

**Communication Protocol:**
- Input: stdin (JSON)
- Output: stdout (JSON only - no plain text)
- Debug: stderr (for logging, not parsed)

**Environment Variables:**
- `GEMINI_PROJECT_DIR` - Absolute path to project root
- `GEMINI_SESSION_ID` - Unique session ID
- `GEMINI_CWD` - Current working directory
- `CLAUDE_PROJECT_DIR` - Compatibility alias

**Use Cases:**
- Add context (inject git history before request)
- Validate actions (review tool args, block dangerous ops)
- Enforce policies (security scanners, compliance checks)
- Log interactions (track tool usage for auditing)

**Sources:**
- [Hooks Documentation](https://geminicli.com/docs/hooks/)
- [Writing Hooks](https://geminicli.com/docs/hooks/writing-hooks/)
- [Hooks Best Practices](https://geminicli.com/docs/hooks/best-practices/)
- [Tailor Gemini CLI with Hooks Blog](https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/)

---

## 5. Custom Slash Commands

**What:** Reusable, parameterizable prompts that can be called directly within Gemini CLI.

**Storage:**
- User-level: `~/.gemini/commands/`
- Project-level: `.gemini/commands/`

**File Format:** TOML (`.toml` extension)

**Naming Convention:**
- Filename determines command name
- `test.toml` → `/test`
- `git/commit.toml` → `/git:commit` (namespaced via subdirectories)

**TOML Structure:**
```toml
description = "Brief one-line description (shown in /help)"
prompt = """
Your multi-line prompt here.
Use {{args}} for user input.
Use @{file.txt} to embed file content.
Use @{dir/} for directory listing.
"""
```

**Features:**
- `{{args}}` - Replaced with text after command name
- `@{...}` - Embed file content or directory listing
- Single-line or multi-line prompts
- Supports both user and project scope

**Sources:**
- [Custom Commands Documentation](https://geminicli.com/docs/cli/custom-commands/)
- [Gemini CLI Custom Slash Commands Blog](https://cloud.google.com/blog/topics/developers-practitioners/gemini-cli-custom-slash-commands)
- [Custom Commands Tutorial](https://medium.com/google-cloud/gemini-cli-tutorial-series-part-7-custom-slash-commands-64c06195294b)

---

## 6. Custom Tools

**What:** Extend Gemini CLI with custom tool definitions via two methods.

### Method 1: Command-Based Discovery

**Configuration:**
```json
{
  "tools": {
    "discoveryCommand": "node discover-tools.js",
    "callCommand": "node call-tool.js"
  }
}
```

**Behavior:**
- `discoveryCommand` outputs JSON array of `FunctionDeclaration` objects
- Tools registered as `DiscoveredTool` instances
- `callCommand` executes the tools

### Method 2: MCP Server Integration

For complex scenarios, create MCP server exposing tools.

**Tool Definition Requirements:**
- Unique internal name
- `parameterSchema` - JSON schema defining parameters
- Methods to:
  - Validate incoming parameters
  - Provide human-readable description of planned action
  - Determine if user confirmation required

**Sources:**
- [Gemini CLI Tools Documentation](https://geminicli.com/docs/tools/)
- [Tools API Core Documentation](https://geminicli.com/docs/core/tools-api/)
- [How to Extend with Custom Tools](https://milvus.io/ai-quick-reference/how-do-i-extend-gemini-cli-with-custom-tools)

---

## 7. GEMINI.md (Context Files)

**What:** Project-specific instructional context files providing persistent context to the model.

**Default Filename:** `GEMINI.md` (configurable via `context.fileName` in settings)

**Hierarchical Loading Order:**
1. `~/.gemini/GEMINI.md` (global, all projects)
2. Searched upward from CWD to project root (`.git` folder)
3. Scanned downward in subdirectories (respects `.gitignore` and `.geminiignore`)

**Workspace Context Configuration:**
```json
{
  "includeDirectories": ["src/", "docs/"],
  "context": {
    "fileName": "GEMINI.md",
    "includeDirectories": true
  }
}
```

**Features:**
- Import content from other files: `@file.md` (relative or absolute paths)
- Break large files into components
- Hierarchical context merging

**Commands:**
- `/memory show` - Display full concatenated context
- `/memory refresh` - Re-scan and reload all GEMINI.md files
- `/memory add <text>` - Append to global `~/.gemini/GEMINI.md`

**Use Cases:**
- Project-specific instructions
- Define persona
- Coding style guides
- Component/module-specific context (via subdirectories)

**Sources:**
- [GEMINI.md Documentation](https://geminicli.com/docs/cli/gemini-md/)
- [Configuration Documentation](https://geminicli.com/docs/get-started/configuration/)
- [Provide Context with GEMINI.md](https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html)

---

## Configuration Locations

**Directory Structure:**
```
~/.gemini/                    # User-level config
├── settings.json             # Main configuration
├── GEMINI.md                 # Global context
├── commands/                 # User slash commands
├── skills/                   # User Agent Skills
└── extensions/               # Installed extensions

.gemini/                      # Project-level config
├── settings.json             # Project settings (override user)
├── GEMINI.md                 # Project context
├── commands/                 # Project slash commands
└── skills/                   # Project Agent Skills
```

**Configuration Precedence:**
1. Project settings (`.gemini/settings.json`)
2. User settings (`~/.gemini/settings.json`)
3. Extensions
4. System defaults

**Environment Variables:**
- Settings support env var substitution: `$VAR_NAME` or `${VAR_NAME}`
- Example: `"apiKey": "$MY_API_TOKEN"`

**Sources:**
- [Configuration Documentation](https://geminicli.com/docs/get-started/configuration/)
- [Settings Command Reference](https://geminicli.com/docs/cli/settings/)

---

## Gemini CLI vs Claude Code: Extensibility Comparison

### What Gemini CLI Has That Claude Code Does NOT

1. **Open Source (Apache 2.0)**
   - Community can audit, contribute, and fork
   - Claude Code is closed-source, proprietary

2. **Hooks System**
   - Lifecycle event interception (`beforeTool`, `afterTool`, `startup`, `shutdown`)
   - Synchronous hook execution with stdin/stdout protocol
   - Claude Code has hooks but more limited scope

3. **Command-Based Custom Tool Discovery**
   - `tools.discoveryCommand` / `tools.callCommand` pattern
   - Dynamic tool registration without MCP server overhead

4. **GEMINI.md Hierarchical Context**
   - Automatic scanning upward/downward from CWD
   - Project-wide persistent context with subdirectory specificity
   - `/memory` commands for runtime context management
   - Claude Code has `CLAUDE.md` but less sophisticated hierarchy

5. **Extensions as First-Class Bundles**
   - Single package containing MCP servers, skills, commands, hooks
   - Version-controlled, easily distributable
   - Extension marketplace at [geminicli.com/extensions](https://geminicli.com/extensions/)

6. **Built-in Google Services Integration**
   - Official MCP servers for Google Cloud, Workspace, etc.
   - Tight integration with Google ecosystem

7. **FastMCP Integration**
   - One-command install for Python MCP servers: `fastmcp install gemini-cli`
   - Streamlined Python-based tool creation

### What Claude Code Has That Gemini CLI Does NOT

1. **Subagents with Persistent Memory**
   - Independent context windows
   - `memory` field for persistent knowledge across conversations
   - Subagents can build up codebase patterns, debugging insights over time
   - Gemini has Agent Skills but they're stateless (loaded on-demand)

2. **Tool Permission Granularity in Subagents**
   - Explicit `tools` (allowlist) and `disallowedTools` (denylist) per subagent
   - Fine-grained security model
   - Gemini has `excludeTools` at extension level, less granular

3. **Plugin Marketplace**
   - Local filesystem-based marketplace (`.claude/local-marketplace/`)
   - Organized plugin discovery (research-toolkit, writing-toolkit, code-quality)
   - Gemini has extensions but no local marketplace structure

4. **Skills with Runtime Injection**
   - Skills can be injected into subagent context at startup
   - Subagent controls system prompt + skill loading
   - More flexible skill composition

5. **More Mature Skill Ecosystem**
   - Extensive community skills (100+ subagents, numerous skills)
   - Organized by domain (research, writing, code quality)
   - Gemini CLI skills are newer (Agent Skills launched Jan 2026)

6. **Project-Specific Settings Overrides**
   - Claude Code has `~/.claude/projects/` for per-project settings
   - Gemini CLI uses `.gemini/settings.json` (similar but different structure)

7. **Integrated Task Management**
   - TodoWrite, TaskCreate, TaskList, TaskUpdate tools
   - Built-in task tracking and coordination
   - Gemini CLI doesn't have native task management

### Similarities

Both support:
- **MCP (Model Context Protocol)** - Industry standard for tool integration
- **Custom slash commands** - Reusable prompts (TOML in Gemini, format unclear in Claude)
- **Agent Skills** - On-demand expertise bundles
- **Context files** - GEMINI.md vs CLAUDE.md
- **User/project configuration** - `~/.gemini/` vs `~/.claude/`
- **Environment variable substitution** - In config files

### Architecture Philosophy Differences

**Gemini CLI:**
- **Extension-centric** - Bundle everything into extensions
- **Open, community-driven** - Apache 2.0, public contributions
- **Google ecosystem** - First-class Google Cloud/Workspace integration
- **Command-based flexibility** - Discovery/call commands for custom tools

**Claude Code:**
- **Agent-centric** - Subagents with memory and tool permissions
- **Curated, controlled** - Closed-source, Anthropic-managed
- **Platform-agnostic** - MCP for cross-platform integration
- **Task management** - Built-in coordination tools

---

## Sources

### Official Documentation
- [Gemini CLI Official Documentation](https://geminicli.com/docs/)
- [Gemini CLI GitHub Repository](https://github.com/google-gemini/gemini-cli)
- [Google Developers: Gemini CLI](https://developers.google.com/gemini-code-assist/docs/gemini-cli)
- [Google Cloud Gemini CLI Documentation](https://docs.cloud.google.com/gemini/docs/codeassist/gemini-cli)

### Extensions
- [Extensions Documentation](https://geminicli.com/docs/extensions/)
- [Getting Started with Extensions](https://geminicli.com/docs/extensions/getting-started-extensions/)
- [Getting Started with Gemini CLI Extensions (Codelabs)](https://codelabs.developers.google.com/getting-started-gemini-cli-extensions)
- [Browse Extensions Marketplace](https://geminicli.com/extensions/)
- [Extensions Tutorial (Medium)](https://medium.com/google-cloud/gemini-cli-tutorial-series-part-11-gemini-cli-extensions-69a6f2abb659)

### Agent Skills
- [Agent Skills Documentation](https://geminicli.com/docs/cli/skills/)
- [Creating Agent Skills](https://geminicli.com/docs/cli/creating-skills/)
- [Getting Started with Agent Skills](https://geminicli.com/docs/cli/tutorials/skills-getting-started/)
- [Beyond Prompt Engineering: Agent Skills (Medium)](https://medium.com/google-cloud/beyond-prompt-engineering-using-agent-skills-in-gemini-cli-04d9af3cda21)
- [Mastering Agent Skills](https://danicat.dev/posts/agent-skills-gemini-cli/)

### MCP Servers
- [MCP Servers with Gemini CLI](https://geminicli.com/docs/tools/mcp-server/)
- [Gemini CLI + FastMCP Blog](https://developers.googleblog.com/gemini-cli-fastmcp-simplifying-mcp-server-development/)
- [Official MCP Support for Google Services](https://cloud.google.com/blog/products/ai-machine-learning/announcing-official-mcp-support-for-google-services)
- [How to Build MCP Server with Go (Codelabs)](https://codelabs.developers.google.com/cloud-gemini-cli-mcp-go)

### Hooks
- [Hooks Documentation](https://geminicli.com/docs/hooks/)
- [Writing Hooks](https://geminicli.com/docs/hooks/writing-hooks/)
- [Hooks Best Practices](https://geminicli.com/docs/hooks/best-practices/)
- [Hooks Reference](https://geminicli.com/docs/hooks/reference/)
- [Tailor Gemini CLI with Hooks (Blog)](https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/)

### Custom Commands
- [Custom Commands Documentation](https://geminicli.com/docs/cli/custom-commands/)
- [Custom Slash Commands (Google Cloud Blog)](https://cloud.google.com/blog/topics/developers-practitioners/gemini-cli-custom-slash-commands)
- [Custom Commands Tutorial (Medium)](https://medium.com/google-cloud/gemini-cli-tutorial-series-part-7-custom-slash-commands-64c06195294b)

### Configuration
- [Configuration Documentation](https://geminicli.com/docs/get-started/configuration/)
- [Settings Command Reference](https://geminicli.com/docs/cli/settings/)
- [Configuration Tutorial (Medium)](https://medium.com/google-cloud/gemini-cli-tutorial-series-part-3-configuration-settings-via-settings-json-and-env-files-669c6ab6fd44)

### GEMINI.md
- [GEMINI.md Documentation](https://geminicli.com/docs/cli/gemini-md/)
- [Provide Context with GEMINI.md](https://google-gemini.github.io/gemini-cli/docs/cli/gemini-md.html)

### Tools
- [Tools Documentation](https://geminicli.com/docs/tools/)
- [Tools API Core](https://geminicli.com/docs/core/tools-api/)
- [How to Extend with Custom Tools](https://milvus.io/ai-quick-reference/how-do-i-extend-gemini-cli-with-custom-tools)

### Comparisons
- [Gemini CLI vs Claude Code (Composio)](https://composio.dev/blog/gemini-cli-vs-claude-code-the-better-coding-agent)
- [Gemini CLI vs Claude Code (DeployHQ)](https://www.deployhq.com/blog/comparing-claude-code-openai-codex-and-google-gemini-cli-which-ai-coding-assistant-is-right-for-your-deployment-workflow)
- [Claude Code vs Gemini CLI (Shipyard)](https://shipyard.build/blog/claude-code-vs-gemini-cli/)
- [Claude Code vs Gemini CLI (Milvus)](https://milvus.io/blog/claude-code-vs-gemini-cli-which-ones-the-real-dev-co-pilot.md)
- [Claude Code vs Gemini CLI (DEV Community)](https://dev.to/tech_croc_f32fbb6ea8ed4/claude-code-vs-gemini-cli-which-ai-coding-agent-rules-the-terminal-4e6b)

### Claude Code
- [Create Custom Subagents (Claude Code Docs)](https://code.claude.com/docs/en/sub-agents)
- [Skills Explained (Claude Blog)](https://claude.com/blog/skills-explained)
- [Claude Code Customization Guide](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)
- [Understanding Claude Code Features](https://www.youngleaders.tech/p/claude-skills-commands-subagents-plugins)

---

## Recommendations for Integration

If integrating Gemini CLI extensibility patterns into the dotfiles:

1. **Create `config/gemini/GEMINI.md`**
   - Global context file for all Gemini CLI projects
   - Symlink to `~/.gemini/GEMINI.md`

2. **Create `config/gemini/settings.json`**
   - Global settings template
   - MCP server configurations
   - Tool exclusions
   - Symlink to `~/.gemini/settings.json`

3. **Create `gemini/` directory structure** (parallel to `claude/`)
   ```
   gemini/
   ├── GEMINI.md           # Global context
   ├── settings.json       # Global settings
   ├── commands/           # User slash commands
   ├── skills/             # User Agent Skills
   ├── extensions/         # Extension manifests/configs
   └── hooks/              # Global hooks
   ```

4. **Add deployment function to `deploy.sh`**
   - `deploy_gemini_cli()` function
   - Symlink approach (like Claude Code deployment)
   - Smart merge for existing installations

5. **Document in README.md**
   - Add Gemini CLI section
   - Note compatibility with Claude Code approach
   - Explain extension vs plugin model differences

6. **Consider cross-pollination**
   - Skills that work in both Gemini CLI and Claude Code
   - Shared MCP server configurations
   - Unified slash commands where possible

---

## Key Insights

1. **Gemini CLI is remarkably similar to Claude Code** in architecture, despite being from different companies. Both use:
   - Agent Skills
   - MCP for tool integration
   - Context files (GEMINI.md vs CLAUDE.md)
   - User/project configuration hierarchy

2. **Gemini CLI's open-source nature** enables community contributions and transparency, while Claude Code's closed-source approach allows tighter optimization.

3. **Hooks are Gemini CLI's unique strength** - no other CLI tool has this level of lifecycle interception. Extremely powerful for validation, logging, policy enforcement.

4. **Claude Code's subagent memory** is a unique differentiator - persistent knowledge across conversations enables long-term learning about codebases.

5. **Extensions vs Plugins** - Gemini bundles everything into extensions (one package = MCP + skills + commands + hooks), while Claude Code has a more granular plugin marketplace.

6. **Both tools are converging** - Gemini CLI added Agent Skills in Jan 2026, showing adoption of Claude Code patterns. Both now support similar core extensibility mechanisms.

---

**Research completed:** 2026-02-05
**All extensibility mechanisms documented:** ✓
**Comparison with Claude Code:** ✓
**Configuration locations identified:** ✓
