# Plugin Management

**Every installed plugin is on, everywhere.** There are no profiles, no `context.yaml`, and no per-project plugin state — a repo works with no plugin setup step.

What guarantees that is the user-scope manifest: `enabledPlugins` in `claude/settings.json` lists all 24 plugins with an explicit `true`, and an explicit `true` wins at every scope. The platform *also* appears to enable an installed plugin that has no entry anywhere, but that behaviour is undocumented and was not observable here (every installed plugin already carries an entry), so nothing in this setup relies on it.

The former enable-first system (`claude-tools context`, `profiles.yaml`, per-project `context.yaml`) was removed. It re-derived a default the platform already provided, cost a setup step in every new repo, and its project-scope writes generated ten "project settings override your user setting" warnings in `/plugin`. The `claude-tools context` subcommand is retired — the compiled binary still carries it, but nothing invokes it, and `claude-tools setup context` should not be used.

**ai-safety-plugins** (`github.com/yulonglin/ai-safety-plugins`):
- `core` — foundational agents, skills, safety hooks
- `research` — experiments, evals, analysis, literature
- `writing` — papers, drafts, presentations, multi-critic review
- `code` — dev workflow, debugging, delegation, code review
- `workflow` — agent teams, handover, conversation management, analytics
- `viz` — TikZ diagrams, Anthropic-style visualization

**Architecture:**
- Marketplaces: `extraKnownMarketplaces` in `claude/settings.json` — declarative, symlinked to `~/.claude/settings.json`, so a fresh machine registers them with no sync step
- Which plugins a machine should have: `enabledPlugins` in the same file. It doubles as an **install manifest** — every entry is `true`, both declaring what a machine should have and guaranteeing it is on
- Installed state: `~/.claude/plugins/installed_plugins.json`, runtime-only, never in the repo (`deploy.sh` preserves it across redeploys rather than writing it)
- Per-project: nothing, in the normal case

**Install scope — install at `user`, never `project`.** `claude plugin install` defaults to `--scope user`; the old profile system instead wrote project-scope `enabledPlugins` maps, and the result was that *every* plugin on this machine ended up recorded in `installed_plugins.json` as `"scope": "project"` bound to one transient worktree's `projectPath`. Install records pinned to a worktree die with it. Check with `claude plugin list` — if the Scope column says `project` for anything outside a deliberate per-repo case, reinstall it at user scope.

Open caveat: it is not established that a `true` entry in a user-scope `enabledPlugins` *installs* a missing plugin, as opposed to merely enabling an already-installed one. `deploy.sh` runs no installs, so on a fresh machine assume the manifest declares intent only and install explicitly, then confirm with `claude plugin list`.

**Turning a plugin off.** Prefer uninstalling — "off" now means "not installed". If one repo genuinely must not load a plugin, hand-write a single `false` in that repo's `.claude/settings.json`; `enabledPlugins` is still honoured at project scope. Never add `false` entries to the global manifest.

```bash
claude plugin install <plugin>@<marketplace>    # then add the same key to enabledPlugins, all true
claude plugin uninstall <plugin>@<marketplace>  # then remove its key
```

Adding a new plugin: register its marketplace in `extraKnownMarketplaces`, install it, and add a `true` entry to `enabledPlugins` so other machines pick it up.

**No OS-conditional loading.** The old `macos:` profile section gated macOS-only plugins (`bear-mcp`). Nothing replaces it: a plugin listed in the manifest is installed on every machine. macOS-only plugins are therefore left out of the manifest and installed by hand on the Mac. `productivity-tools` stays registered as a marketplace precisely so that remains possible.

## Renaming a local marketplace plugin

Update these four locations, then restart Claude Code:

1. **Source**: rename dir `claude/ai-safety-plugins/plugins/<old>/` → `<new>/`, update `"name"` in `.claude-plugin/plugin.json`
2. **Marketplace manifest**: update the entry in `claude/ai-safety-plugins/.claude-plugin/marketplace.json`
3. **settings.json**: change `"<old>@ai-safety-plugins"` → `"<new>@ai-safety-plugins"` in `enabledPlugins`
4. **Clear cache**: remove `~/.claude/plugins/cache/ai-safety-plugins/<old>` (re-created on next `/plugin` install)

## Stopping Serena's dashboard from auto-opening

Serena's web dashboard opens in the browser on every new session unless the MCP server is started with `--open-web-dashboard false`. Add the flag to the server args in `claude/plugins/marketplaces/claude-plugins-official/external_plugins/serena/.mcp.json`:

```json
{
  "serena": {
    "command": "uvx",
    "args": [
      "--from", "git+https://github.com/oraios/serena",
      "serena", "start-mcp-server",
      "--open-web-dashboard", "false"
    ]
  }
}
```

That file lives in the plugin marketplace cache (`plugins/marketplaces/`), which is gitignored — so the change must be reapplied after clearing the plugin cache or on a new machine, and needs a full Claude Code restart to take effect. The dashboard stays reachable at `http://127.0.0.1:24286/dashboard/index.html` when you actually want it; `~/.claude/logs/mcp-serena.log` is the place to check if it misbehaves.
