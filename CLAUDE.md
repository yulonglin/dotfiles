# CLAUDE.md

Dotfiles for ZSH, Tmux, Vim, SSH and dev tools across macOS, Linux and RunPod, deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — **edits here change your running environment immediately.**

## Top Rules

- **Direct pushes to main are allowed** — personal repo, no PR overhead. Single branch: `main`; branch worktrees off it. Route only large or structural merges through a tracked PR.
- **Flags are ADDITIVE to defaults unless `--minimal` is used.** `install.sh` and `deploy.sh` enable every component by default; `--no-<component>` disables one; `--minimal` disables all; modifiers (`--append`, `--ascii`, `--force`) don't affect defaults. Detail in README.md.
- **Sandbox blocks `git pull`/`merge`/`stash`** here, and `codex exec` crashes on macOS inside it — both need `dangerouslyDisableSandbox: true`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks` and `permissions` keys — [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **One command: `secrets`** — `init`, `edit`, `ls`, `get`, `use`, `envrc`, `run`, `doctor`, and a bare `secrets` for status. Keys are NOT exported into every shell (supply-chain defense); `secrets envrc` binds a repo through direnv.
- **Plot with the house style by default** — `import style as house; house.set_defaults()` from `lib/plotting/` (pastel + soft grid). Charts on an artifact page are drawn as native SVG from `lib/plotting/tokens.json` instead; matplotlib is for papers and decks. Full API in the `house-plots` skill.
- **Specs, plans and reports are Artifacts — editable and commentable**, not files in `specs/` or `plans/`. Source and built HTML are committed under `artifacts/<slug>/` (`artifacts/README.md`), the page is published from the committed HTML, and review runs the suggested-edits round-trip in `spec-artifact`; record the URL with its finding in this file per `artifacts-sync`.
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
| Install/manage Mac apps | Add a line to `config/apps.conf` → run `app-picker` (`claude-tools select` TUI; `--installed` preselects what this Mac has) → `brew bundle --file=config/Brewfile`. `app-picker --audit` diffs the Mac against the Brewfile and prints uninstall commands. An app you considered and turned down goes in `config/apps-excluded.conf` (`method|id|name|since|why`), never `apps.conf` — `app-picker --excluded` lists those with their reasons and flags the ones still on disk. Official casks + `mas` only, **no third-party taps**. Then `scripts/setup/auth-setup` |
| Add an interactive menu or picker to a script | Short known list → `claude-tools select --items FILE` (`group\|name\|description\|checked`, `--single` for one pick); long list you type to narrow → `fzf`. Never pipe items on stdin: that makes fd 0 a pipe and forces crossterm onto its `/dev/tty` fallback. Conventions in [`docs/tui-tools.md`](docs/tui-tools.md) |
| Add an encrypted secret | `secrets edit` (interactive fzf editor) |
| Add, remove or switch off a foreign model (picker row, agent, route), or put an older Claude model in `/model` (`provider = "anthropic"`) | Edit `config/model-router.toml` → `model-router-wire apply` (renders router config, picker rows and `claude/agents/` files; `status` shows drift) → `tests/test_model_router_gateway.sh` |
| Run an experiment with resource caps | `jexp uv run python -m ...` (Linux: needs pueue + systemd user session) |
| Check or repair hard-wrapped Markdown | `md-unwrap --check claude/` (gated in pre-commit and CI); `md-unwrap --fix <path>` |
| Find a cloud resource left running | `cloud-spend-check --days 14` (daily timer + session nudge; flags flat daily spend) — [`docs/cloud-spend-check.md`](docs/cloud-spend-check.md) |
| Commit / commit + push + PR | `/commit` skill or `/commit-push-sync` |
| Merge worktree → parent branch | `cwmerge` (or `git merge <branch>` from the parent if the branch isn't `worktree-` prefixed) |

## Where To Look

- Deploy components, per-component behaviors, cloud provisioning, how to extend → [`docs/deploy-components.md`](docs/deploy-components.md)
- Package strategy, symlink-vs-copy, directory env vars, operational gotchas → [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md); why each Homebrew formula is installed (generated by `app-picker`) → [`docs/brew-formulae.md`](docs/brew-formulae.md)
- Terminal/shell/dev-tool usage detail (Ghostty themes, p10k machine ID, statusline, `claude-tools ignore`, pdb++, media recovery) → [`docs/terminal-and-dev-tools.md`](docs/terminal-and-dev-tools.md)
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

**Bitwarden Secrets Manager is the single source of truth, and `secrets` is the only command that reaches it.** Managed: `OPENAI`/`OPENROUTER`/`ANTHROPIC_API_KEY`, `HF_TOKEN`, `MODAL_TOKEN_ID`/`SECRET`. `secrets init` writes the per-machine BWS token to `~/.config/bws/token`; `secrets edit` rotates a key without touching any repo. `custom_bins/dotfiles-secrets` is the engine underneath, named in every generated `.envrc` and never typed by hand.

**`.envrc` is a convenience, not a boundary.** `secrets envrc` binds a repo so direnv exports its keys on `cd`, but `secrets get`/`secrets run` reach any key from **any** directory — a repo without `.envrc` is not locked out. The defense is that nothing is exported ambiently, so a postinstall script finds an empty environment; the gate is this machine's BWS token, and a leaked key is closed by rotating it.

## Learnings

Transient machine state only: what is broken right now, what is mid-migration, what the next session would otherwise trip over. Anything that outlives about a week moves to the file that owns its topic — a doc under `docs/`, the skill that runs the thing, or the rule that governs it. Anything a named test, the code, or the config already records is dropped outright rather than archived, because version history is the archive and `log -S` finds it. The binding constraint is a whole-file byte ceiling pinned by `tests/test_memory_tier_budget.py`, not an entry count, and the head above this line already spends most of it — so this section holds a handful of lines at most, and is empty whenever nothing is actually in flight.
