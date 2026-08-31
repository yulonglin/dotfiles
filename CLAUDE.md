# CLAUDE.md

Dotfiles for ZSH, Tmux, Vim, SSH and dev tools across macOS, Linux and RunPod, deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — **edits here change your running environment immediately.**

## Top Rules

- **Direct pushes to main are allowed** — personal repo, no PR overhead. Single branch: `main`; branch worktrees off it. Route only large or structural merges through a tracked PR.
- **Flags are ADDITIVE to defaults unless `--minimal` is used.** `install.sh` and `deploy.sh` enable every component by default; `--no-<component>` disables one; `--minimal` disables all; modifiers (`--append`, `--ascii`, `--force`) don't affect defaults. Detail in README.md.
- **Sandbox blocks `git pull`/`merge`/`stash`** here, and `codex exec` crashes on macOS inside it — both need `dangerouslyDisableSandbox: true`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks` and `permissions` keys — [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **Secrets are NOT globally exported** (supply-chain defense). Use `setup-envrc` per project via direnv; `secrets-edit` to add or update.
- **Plot with the house style by default** — `import style as house; house.set_defaults()` from `lib/plotting/` (pastel + soft grid). Charts on an artifact page are drawn as native SVG from `lib/plotting/tokens.json` instead; matplotlib is for papers and decks. Full API in the `house-plots` skill.
- **Specs, plans and reports are Artifacts**, not files in `specs/` or `plans/`. Publish them and record the URL with its finding in this file; write Markdown source only when it must be version-controlled with the code. See the `artifacts-sync` skill.
- **The standards live in `claude/checklists/`, and skills route to them** — writing, presentation, results-analysis (plus domain subskills), research, experiments. A new rule belongs in the checklist it governs; adding it to a skill or a rule instead is how the duplication came back last time. `catalog` maps which skill routes where.
- **Plugins are a last resort; the marketplace is the unit** — four remain (`claude-plugins-official`, `codex-plugin-cc`, `alignment-hive`, `productivity-tools` for the Bear and Things MCPs). Prefer a local skill in `claude/skills/`, which is version-controlled here, over a plugin loading from a gitignored cache that drifts silently. **A marketplace entry is not an enabled plugin** — check `enabledPlugins` too, or a skill will document tools that never load.
- **Verification is a design problem** — plan *how* you'll verify before starting. Catching yourself thinking "let me figure out how to verify this" is EnterPlanMode. Checklist: [`.claude/skills/verification-planning/SKILL.md`](.claude/skills/verification-planning/SKILL.md).

## Common Tasks

| Want to... | Command / file |
|---|---|
| Convey standards | `claude/checklists/*.md` (five + subskills) |
| Add a new alias | `config/aliases/<topic>.sh` (themed split; or `aliases_<name>.sh` for env-specific) |
| Add a deploy component | Create `deploy_X()` in `deploy.sh` — [`docs/deploy-components.md`](docs/deploy-components.md) § Extending |
| Add a custom binary | Drop it in `custom_bins/` (already on PATH); `chmod +x` |
| Install/manage Mac apps | Add a line to `config/apps.conf` → run `app-picker` (gum TUI) → `brew bundle --file=config/Brewfile`. Official casks + `mas` only, **no third-party taps**. Then `scripts/setup/auth-setup` |
| Add an encrypted secret | `secrets-edit` (interactive dotenv editor) |
| Run an experiment with resource caps | `jexp uv run python -m ...` (Linux: needs pueue + systemd user session) |
| Commit / commit + push + PR | `/commit` skill or `/commit-push-sync` |
| Merge worktree → parent branch | `cwmerge` (or `git merge <branch>` from the parent if the branch isn't `worktree-` prefixed) |

## Where To Look

- Deploy components, per-component behaviors, cloud provisioning, how to extend → [`docs/deploy-components.md`](docs/deploy-components.md)
- Package strategy, symlink-vs-copy, directory env vars, operational gotchas → [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md)
- File layout → `eza --tree -L2 config claude custom_bins tools lib` (filenames are self-describing)
- Global behavioral rules → `~/.claude/rules/*.md`; this repo's → `.claude/rules/*.md`

## Worktrees

`yolo` skips permissions with no worktree. `cw [name]` gives worktree + tmux; `cwy` adds skip-permissions.

| Command | What it does |
|---------|-------------|
| `cwl` | List all worktrees |
| `cwmerge [name]` | Merge worktree branch into parent (auto-detects from inside a worktree) |
| `/merge-worktree` | Claude skill: merge + AI conflict resolution |
| `cwport <name> [dirs...]` | Copy artifacts (out/, logs/) from worktree to main tree |
| `cwrm [--no-merge] <name>` | Merge branch → remove worktree → delete branch |
| `cwclean [--dry-run]` | Remove clean worktrees (no changes, no artifacts) |

`cwrm` **merges by default**; `--no-merge` skips it, `--force` skips artifact warnings. `cwmerge` only recognises `worktree-`-prefixed branches — merge others with `git -C <main-tree> merge --ff-only <branch>`. Gitignored files (`.env`, `out/`, `logs/`) do **not** exist in a new worktree. Lifecycle: `cw auth-fix` → work → `cwport auth-fix` → `cwrm auth-fix`.

## Personal Content

This repo is **public** — and a branch in a public repo is public too, so personal working artifacts must not live on any branch here. They go in the separate **private** `dotfiles-personal` repo: `plans/`, `specs/`, `.remember/`, `tmp/`, personal `docs/`, `config/machines.conf`. Those paths are in `.gitignore` here so they can't reach public `main` by accident. A superset "personal branch" was rejected because it would have exposed everything it was meant to hide. `main` is not kept "clean for others" — it is just the personal working branch.

## Rules That Prevent Data Loss

**Obsidian sync — promote a vault to bidirectional only by hand**: `ob sync-config --path <vault-path> --mode bidirectional`. Never automate it, and never let `deploy.sh` or `obsidian-sync-check` do it. Any vault whose `sync.log` has no `"Fully synced"` entry is force-set to pull-only on deploy; a vault with sync history is never touched, so a manual promotion sticks. `obsidian-sync-check [--path <vault-path>]` is **advisory only**. The incident this guards against: in 2026-06/07 a bidirectional sync against an incomplete local copy misread "never downloaded" as "deleted" and propagated the deletions upstream — 135 files lost, recovered via pull-only reconciliation.

**Secrets are per-project, not global.** API keys live in Bitwarden Secrets Manager and are **not** exported into every shell. Reach them with `setup-envrc` in the repo that needs them (direnv), or `with-secrets KEY... -- <cmd>` for one shot — the latter is a zsh function, so scripts use `dotfiles-secrets shell KEY`. Managed: `OPENAI`/`OPENROUTER`/`ANTHROPIC_API_KEY`, `HF_TOKEN`, `MODAL_TOKEN_ID`/`SECRET`. BWS token at `~/.config/bws/token`; `secrets-init bws` on a new machine. A project without `.envrc` genuinely cannot see the keys — that is the defense working, not a bug.

## Learnings

Project-specific bugs, quirks, decisions and current state. Timestamp `- description (YYYY-MM-DD)`, keep under 20, prune past two weeks — retired entries move to [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md) § Past Learnings, and git history is the archive for the rest.

- **`excludedCommands` takes `"cmd:*"`, and the form is measured, not read off a doc** — I asserted the colon form was wrong and the space-star form right, committed that to a rules file, and had it backwards. `permissions.md` line 189 states `:*` is an equivalent way to write a trailing wildcard, so `Bash(ls:*)` and `Bash(ls *)` match the same commands; `:*` is only recognised at the *end* of a pattern, so `git:* push` treats the colon literally and matches nothing. The test that settles it needs an operation the sandbox *cannot* fake: `git ls-remote origin HEAD` and `ssh -T git@github.com` both succeed sandboxed while a raw socket to `github.com:22` fails DNS, and the only entries they can match are `git:*`/`ssh:*` — two independent tools, so not git special-casing. The 2026-08-20 bare-word finding is untouched and still true: a bare word is an exact matcher, inert for any invocation carrying arguments. **The real cost of an entry is not the binary, it is the line** — "when any part of a compound command matches an entry, Claude Code runs the whole command unsandboxed", so `ps:*` also unsandboxes `ps aux | tee ~/f`, and converting the remaining bare words wholesale would hand `python:*`/`uv:*` arbitrary unsandboxed execution. `ps`/`top`/`pgrep` were added because Seatbelt refuses to *exec* them — `/bin/ps` is `.rwsr-xr-x root`, setuid — not because of any process-info policy; `lsof` is unaffected (2026-08-31)

- **The app-lifecycle suites read `tests/fixtures/app-lifecycle.yaml`, never your real app policy** — both used to `cp` the shipped config in as their baseline, which made changing your mind about an app a test failure. Measured, not guessed: stripping the app list broke 18 assertions, and 12 were the AX close-button sequence, which needs only *some* app on the close rung and had adopted Bear because the config happened to put it there. `Would QUIT (4)` was a hardcoded count that any added or removed app would break. The fixture now owns one app per rung and is deliberately not kept in step with `config/app-lifecycle.yaml`. **The one retained coupling is test 2b**, which asserts only that the shipped file *parses* — `app-lifecycle-config` exits 78 on an action outside its `ACTIONS` tuple, so this is what catches `manaul: close`, a typo that otherwise resolves silently to the `quit` default on the app you meant to spare. Verified both ways: flipping every shipped app to a different rung leaves 165/0 green, and a typo'd action fails 2b (2026-08-30)

- **md2review's comment box flickered, and the persistence added alongside it was cut** — opening the box focuses its textarea, which collapses the selection, which the debounced `selectionchange` handler read as a deselect; selection events now only ever open. The three rejected recovery layers each lost or leaked data: an IndexedDB mirror let a save race its own recovery, a backup key resurrected deliberately-cleared comments, and a neighbouring-key scan copied one document's confidential note onto an unrelated page. What remains is a bare JSON array under a filename-derived key, prefix-namespaced aux keys, and a keystroke draft. `tests/test_md2review_browser.py` drives Chromium (2026-08-28)

- **The standards are five checklists Yulong edits, and everything else routes to them** — `claude/checklists/{writing,presentation,results-analysis,research,experiments}.md` plus `results-analysis/{monitoring,jlens,sandbagging}.md`, carved by activity rather than artifact type. The old `taste/sources/` layer is gone: his meta-prompts fold into the docs they seeded, so the file he edits *is* the source. Always-on tier is ~22.8 KB and `tests/test_memory_tier_budget.py` passes for the first time in months. Duplication was measured, not guessed — TF-IDF put `rules/experiments.md` at 0.78 against the experiments checklist while it loaded every session. **When a checklist rule changes, check whether an always-on rule states it too**, or the two ship contradicting each other (2026-08-30)

- **Plugins retired, keepers migrated first** — `writing`, `research`, `core`, `code`, `workflow`, `viz` and `dev-browser` are gone, their agents and skills moved into `claude/{agents,skills}/` before the disable so nothing dangled. `ai-safety-plugins` and `dev-browser-marketplace` left `extraKnownMarketplaces` (`jq '.extraKnownMarketplaces|keys' claude/settings.json` for what remains). **A `false` tombstone in `enabledPlugins` is the only off switch** — marketplace presence is not the gate, so a plugin with an installation record stays live without one; `claude --setting-sources '' --settings claude/settings.json plugin list --json` is how you check, and dropping the tombstones once showed 34 retired-but-enabled records. **The trap: a plugin can ship an MCP server in its `plugin.json`**, which disappears silently when the plugin goes — `research` carried Zotero (`uvx --from zotero-mcp-server zotero-mcp`, `ZOTERO_LOCAL=true`), dropped for good since this box has no Zotero installed at all. The reverse trap bit too: `bear-mcp` and `things-mcp` sat in `extraKnownMarketplaces` but were **never in `enabledPlugins`**, so the `bear` and `things3` skills had been documenting tools that did not exist; both are now actually enabled. Slack needs nothing here — it comes from the claude.ai connector, not this repo. Those plugins ship hook *scripts* but no `hooks.json`, so no enforcement was lost (2026-08-30)

