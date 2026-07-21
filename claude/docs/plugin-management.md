# Plugin Organization & Context Profiles

**12 always-on plugins** (`base:` in `profiles.yaml`) load in every session: `bear-mcp`, `claude-md-management`, `codex`, `commit-commands`, `context7`, `core`, `hookify`, `llms-fetch-mcp`, `plugin-dev`, `remember`, `superpowers`, `workflow`.

**6 ai-safety-plugins** (`github.com/yulonglin/ai-safety-plugins`):
- `core` — foundational agents, skills, safety hooks (always-on)
- `research` — experiments, evals, analysis, literature
- `writing` — papers, drafts, presentations, multi-critic review
- `code` — dev workflow, debugging, delegation, code review
- `workflow` — agent teams, handover, conversation management, analytics
- `viz` — TikZ diagrams, Anthropic-style visualization

**Context profiles** control which plugins load per-project via `claude-tools context`:
```bash
claude-tools context                    # Show current state / apply context.yaml
claude-tools context code               # Software projects
claude-tools context code typescript python    # Compose multiple profiles
claude-tools context --list             # Show active plugins and available profiles
claude-tools context --clean            # Remove project plugin config
claude-tools context --sync [-v]        # Register + update + install wanted + prune orphans
claude-tools context --sync --no-prune  # Sync without removing orphan plugins
```

**Unified repo setup** via `claude-tools setup`:
```bash
claude-tools setup                      # Auto-detect + run needed setup steps
claude-tools setup secrets              # Interactive secret picker (delegates to setup-envrc)
claude-tools setup context              # Plugin profile picker (delegates to context)
```

**Architecture:**
- Plugin registry: auto-discovered from `~/.claude/plugins/installed_plugins.json` (source of truth)
- Marketplace manifest: `~/.claude/templates/contexts/profiles.yaml` `marketplaces:` section (declarative)
- Profile definitions: same file, `base:` + `profiles:` sections (per-profile enables)
- Per-project config: `.claude/context.yaml` (profiles + optional enable/disable overrides, committed)
- Output: `.claude/settings.json` `enabledPlugins` section (deterministic rebuild from profiles)
- CLI args persist to `context.yaml` automatically; no-arg invocation re-applies it
- SessionStart hook auto-applies `context.yaml` on every session start
- Statusline shows active context profiles (e.g., `[code python]`)

Adding a new plugin: add its marketplace to `marketplaces:` in `profiles.yaml`, run `claude-tools context --sync`, then add to a profile.
