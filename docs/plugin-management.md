# Plugin Management

**Every plugin that is on is on everywhere.** There are no profiles, no `context.yaml`, and no per-project plugin state — a repo works with no plugin setup step. The former enable-first system (`claude-tools context`, `profiles.yaml`, per-project `context.yaml`) was removed: it re-derived a default the platform already provided, cost a setup step in every new repo, and its project-scope writes generated ten "project settings override your user setting" warnings in `/plugin`. The `claude-tools context` subcommand is retired — the compiled binary still carries it, but nothing invokes it, and `claude-tools setup context` should not be used.

## An Explicit `false` Is The Only Off Switch

**A marketplace declaration is not the enable gate.** A plugin with an installation record in `~/.claude/plugins/installed_plugins.json` keeps loading unless `enabledPlugins` carries an explicit `false` for it. Removing its marketplace from `extraKnownMarketplaces` does *not* turn it off — it silently leaves the plugin running from its cached install. This is why the seven retired plugins carry `false` tombstones in the manifest rather than simply being deleted from it.

Verified 2026-08-30, not inferred: dropping the tombstones made the command below report **34 retired-but-enabled installation records** — seven at user scope plus seven, seven, seven and six bound to four different project paths — and restoring the tombstones returned that count to **0**. The same run also settles an older open question in this document: the platform does enable an installed plugin that has no `enabledPlugins` entry anywhere, so absence means on, not off.

```bash
claude --setting-sources '' --settings claude/settings.json plugin list --json
```

Read the `enabled` field per record. `--setting-sources ''` suppresses ambient user and project settings so the answer reflects this file alone.

**The tombstones must stay until every install record for those plugins is gone** — including the project-scope records pinned to other repos and worktrees, which no uninstall run from here touches. Delete a tombstone before its install records and the plugin comes back on, on every machine that syncs this file.

## The Manifest Is `enabledPlugins` In `claude/settings.json`

The user-scope manifest holds 20 entries: 13 `true` and 7 `false`. An explicit value wins at every scope, so the file is the single source of truth for what loads.

Enabled (13): `bear-mcp` and `things-mcp` from `productivity-tools`; `codex` from `codex-plugin-cc`; `llms-fetch-mcp` from `alignment-hive`; and `hookify`, `playground`, `playwright`, `pyright-lsp`, `remember`, `rust-analyzer-lsp`, `security-guidance`, `superpowers`, `typescript-lsp` from `claude-plugins-official`.

Tombstoned (7): `code`, `core`, `research`, `viz`, `workflow` and `writing` from `ai-safety-plugins`, plus `dev-browser` from `dev-browser-marketplace`. Their agents and skills were migrated into `claude/{agents,skills}/` before the disable, so nothing dangles; both of those marketplaces are gone from `extraKnownMarketplaces`.

**Architecture:**
- Marketplaces: `extraKnownMarketplaces` in `claude/settings.json` — declarative, symlinked to `~/.claude/settings.json`, so a fresh machine registers them with no sync step. Four remain: `claude-plugins-official`, `codex-plugin-cc`, `alignment-hive` and `productivity-tools`
- Which plugins a machine should have: `enabledPlugins` in the same file. It doubles as an **install manifest** — a `true` entry declares what a machine should have and guarantees it is on; a `false` entry guarantees it is off wherever it is still installed
- Installed state: `~/.claude/plugins/installed_plugins.json`, runtime-only, never in the repo (`deploy.sh` preserves it across redeploys rather than writing it)
- Per-project: nothing, in the normal case

Open caveat: it is not established that a `true` entry in a user-scope `enabledPlugins` *installs* a missing plugin, as opposed to merely enabling an already-installed one. `deploy.sh` runs no installs, so on a fresh machine assume the manifest declares intent only, install explicitly, then confirm with `claude plugin list`.

## Install At `user` Scope, Never `project`

`claude plugin install` defaults to `--scope user`; the old profile system instead wrote project-scope `enabledPlugins` maps, and the result was that *every* plugin on this machine ended up recorded in `installed_plugins.json` as `"scope": "project"` bound to one transient worktree's `projectPath`. Those records outlive the profile system that created them: the seven retired plugins still hold 34 of them, spread across user scope, this repo and three `sandbagging-detection` paths, which is exactly why the tombstones are load-bearing. Check with `claude plugin list`: if the Scope column says `project` for anything outside a deliberate per-repo case, reinstall it at user scope.

## Removal Ends With A Tombstone, Not A Deletion

```bash
claude plugin install <plugin>@<marketplace>    # then add the same key to enabledPlugins as true
claude plugin uninstall <plugin>@<marketplace>  # then set its key to false, or remove it once no install records remain
```

Adding: register its marketplace in `extraKnownMarketplaces`, install it, and add a `true` entry to `enabledPlugins` so other machines pick it up.

Removing: uninstalling on this machine is not enough, because other machines syncing this file still hold their own install records. Set the key to `false` and leave the tombstone in place; only drop the key once `plugin list --json` shows no record for it anywhere. If one repo must not load an otherwise-enabled plugin, hand-write a single `false` in that repo's `.claude/settings.json` — `enabledPlugins` is honoured at project scope too.

## macOS-Only Plugins Stay In The Manifest And Simply Fail To Spawn On Linux

The old `macos:` profile section gated macOS-only plugins out of the manifest and left them to be installed by hand on the Mac. Nothing replaces it, and nothing should: `bear-mcp` and `things-mcp` are both in `enabledPlugins` as `true`, so they deploy to every machine unconditionally. `bear-mcp` declares `"command": "bearcli"` in its `plugin.json`, and `bearcli` does not exist on Linux, so the MCP server just fails to spawn there. That is accepted noise, not a reason to leave the plugin out. `things-mcp` needs no exception at all — the `things3` skill is platform-aware and reaches Things Cloud on Linux.

Hand-installation is what caused the earlier bug: both plugins sat in `extraKnownMarketplaces` but never in `enabledPlugins`, so they never loaded anywhere, and the `bear` and `things3` skills spent months documenting tools that did not exist. A manifest entry that is inert on one platform is cheaper than a manifest that is silently incomplete on all of them.

## Renaming A Plugin In A Local Marketplace

Update these four locations, then restart Claude Code. No local-checkout marketplace is registered right now, so treat this as the procedure for the next one:

1. **Source**: rename dir `<marketplace-checkout>/plugins/<old>/` → `<new>/`, update `"name"` in `.claude-plugin/plugin.json`
2. **Marketplace manifest**: update the entry in `<marketplace-checkout>/.claude-plugin/marketplace.json`
3. **settings.json**: change `"<old>@<marketplace>"` → `"<new>@<marketplace>"` in `enabledPlugins`
4. **Clear cache**: remove `~/.claude/plugins/cache/<marketplace>/<old>` (re-created on next `/plugin` install)

## Stopping Serena's Dashboard From Auto-Opening

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
