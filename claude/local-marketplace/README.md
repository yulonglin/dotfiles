# Local Plugin Marketplace

Local Claude Code plugins, served as a filesystem marketplace.

## Structure

```
local-marketplace/
├── .claude-plugin/
│   └── marketplace.json    # Marketplace manifest (name, plugin registry)
├── README.md
└── plugins/
    ├── research-toolkit/   # Experiment design, execution, analysis, literature
    ├── writing-toolkit/    # Papers, drafts, presentations, multi-critic review
    └── code-quality/       # Code review, debugging, performance, bulk editing
```

Each plugin follows the standard structure:
```
plugin-name/
├── .claude-plugin/plugin.json   # Manifest (name, version, author)
├── agents/                       # Agent definitions (.md)
└── skills/                       # Skill definitions (name/SKILL.md)
```

## Setup

Plugins are automatically registered by `deploy.sh --claude`. Manual setup:

```bash
# 1. Register the marketplace
claude plugin marketplace add ~/.claude/local-marketplace

# 2. Install plugins
claude plugin install research-toolkit@local-marketplace
claude plugin install writing-toolkit@local-marketplace
claude plugin install code-quality@local-marketplace
```

## Updating Plugins

Edit files in `plugins/` directly — they're served from this directory.
After structural changes (new agents/skills), restart Claude Code.

## Adding a New Plugin

1. Create `plugins/<name>/.claude-plugin/plugin.json`:
   ```json
   {
     "name": "my-plugin",
     "description": "What it does",
     "version": "1.0.0",
     "author": { "name": "yulong" }
   }
   ```
2. Add `agents/` and/or `skills/` directories
3. Install: `claude plugin install my-plugin@local-marketplace`
4. Enable in settings or: `claude plugin enable my-plugin@local-marketplace`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Plugin not found | `claude plugin marketplace add ~/.claude/local-marketplace` |
| Plugin not loading | Check `claude plugin list` and `claude plugin validate plugins/<name>` |
| Changes not visible | Restart Claude Code (plugins loaded at startup) |
| Name collision | Rename in both `plugin.json` and agent/skill frontmatter `name:` field |

## Runtime Files

The following files in `claude/plugins/` are runtime state managed by Claude Code:
- `installed_plugins.json` - Plugin installation registry
- `known_marketplaces.json` - Registered marketplace paths
- `install-counts-cache.json` - Usage statistics

These files are git-ignored and regenerated on each machine. If you see them with hardcoded paths in git, they were committed by mistake and should be removed with `git rm --cached`.
