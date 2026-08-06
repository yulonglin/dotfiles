# CLAUDE.md

Dotfiles for ZSH, Tmux, Vim, SSH and dev tools across macOS, Linux and RunPod, deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — **edits here change your running environment immediately.**

## Top Rules

- **Direct pushes to main are allowed** — personal repo, no PR overhead. Single branch: `main`; branch worktrees off it. Route only large or structural merges through a tracked PR.
- **Flags are ADDITIVE to defaults unless `--minimal` is used.** `install.sh` and `deploy.sh` enable every component by default; `--no-<component>` disables one; `--minimal` disables all defaults; modifiers (`--append`, `--ascii`, `--force`) don't affect defaults. Detail in README.md.
- **Sandbox blocks `git pull`/`merge`/`stash`** here, and `codex exec` crashes on macOS inside it — both need `dangerouslyDisableSandbox: true`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks` and `permissions` keys — [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **Secrets are NOT globally exported** (supply-chain defense). Use `setup-envrc` per project via direnv; `secrets-edit` to add or update.
- **Plot with Anthropic style by default** — `from anthro_colors import use_anthropic_defaults`. Colours, the `petri`/`deepmind` alternatives and the full API are in the `anthropic-style` skill.
- **Specs go in `specs/`** (overriding the brainstorming skill's default), plans in `plans/` via `plansDirectory`.
- **Verification is a design problem** — plan *how* you'll verify before starting. If you catch yourself thinking "let me figure out how to verify this", that's EnterPlanMode. Triggers and checklist: [`.claude/skills/verification-planning/SKILL.md`](.claude/skills/verification-planning/SKILL.md).

## Common Tasks

| Want to... | Command / file |
|---|---|
| Add a new alias | `config/aliases/<topic>.sh` (themed split; or `aliases_<name>.sh` for env-specific) |
| Add a deploy component | Create `deploy_X()` in `deploy.sh` — [`docs/deploy-components.md`](docs/deploy-components.md) § Extending |
| Add a custom binary | Drop it in `custom_bins/` (already on PATH); `chmod +x` |
| Install/manage Mac apps | Add a line to `config/apps.conf` → run `app-picker` (gum TUI) → `brew bundle --file=config/Brewfile`. Official casks + `mas` only, **no third-party taps**. Then `scripts/setup/auth-setup` |
| Add an encrypted secret | `secrets-edit` (interactive dotenv editor) |
| Run an experiment with resource caps | `jexp uv run python -m ...` (Linux: needs pueue + systemd user session) |
| Commit / commit + push + PR | `/commit` skill or `/commit-push-sync` |
| Switch active plugin context | `claude-tools context <profile>` (composable: `code python rust`; `--list` for the current set) |
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

`cwrm` **merges by default**; `--no-merge` skips it, `--force` skips artifact warnings. `cwmerge` only recognises `worktree-`-prefixed branches — merge others manually with `git -C <main-tree> merge --ff-only <branch>`. Gitignored files (`.env`, `out/`, `logs/`) do **not** exist in a new worktree. Lifecycle: `cw auth-fix` → work → `cwport auth-fix` → `cwrm auth-fix`.

## Personal Content

This repo is **public** — and a branch in a public repo is public too, so personal working artifacts must not live on any branch here. They go in the separate **private** `dotfiles-personal` repo: `plans/`, `specs/`, `.remember/`, `tmp/`, personal `docs/`, `config/machines.conf`. Those paths are listed in `.gitignore` here so they can't reach public `main` by accident. A superset "personal branch" was rejected because it would have exposed everything it was meant to hide.

`main` is no longer kept "clean for others" — it's just the personal working branch.

## Rules That Prevent Data Loss

**Obsidian sync — promote a vault to bidirectional only by hand**: `ob sync-config --path <vault-path> --mode bidirectional`. Never automate it, and never let `deploy.sh` or `obsidian-sync-check` do it. Any vault whose `sync.log` has no `"Fully synced"` entry yet is force-set to pull-only on deploy; a vault with sync history is never touched, so a manual promotion sticks across redeploys. `obsidian-sync-check [--path <vault-path>]` is **advisory only** and never changes mode. The incident this guards against: in 2026-06/07 a bidirectional sync against an incomplete local copy misread "never downloaded" as "deleted" and propagated the deletions upstream — 135 files lost, recovered via pull-only reconciliation.

**Secrets are per-project, not global.** API keys live in Bitwarden Secrets Manager and are **not** exported into every shell. Reach them with `setup-envrc` in the repo that needs them (direnv), or `with-secrets KEY... -- <cmd>` for one shot. Managed: `OPENAI`/`OPENROUTER`/`ANTHROPIC_API_KEY`, `HF_TOKEN`, `MODAL_TOKEN_ID`/`SECRET`. BWS token at `~/.config/bws/token`; run `secrets-init bws` on a new machine. A project without `.envrc` genuinely cannot see the keys — that is the supply-chain defense working, not a bug.

## Learnings

Project-specific bugs, quirks, decisions and current state. Timestamp `- description (YYYY-MM-DD)`, keep under 20, prune past two weeks — retired entries move to [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md) § Past Learnings.

- The simplify nudge now has a second signal: `simplify_track_reuse.py` counts *runs* of scratch scripts (not writes — writes are iteration) and the Stop hook suggests promoting any that ran 3× with at least one run unchanged. Rules for where a promoted script lands: `claude/rules/reusable-component-promotion.md` (2026-08-01)
- Background-session job dirs (`~/.claude/jobs/<id>/`) have no built-in retention — `cleanupPeriodDays` only covers `~/.claude/projects` transcripts. `custom_bins/claude-jobs-reap` deletes terminal-state job dirs inactive >7d (active-looking states get 30d grace); `claude/hooks/reap_jobs.sh` runs it daily via SessionStart. Deleting a job dir removes the `claude agents` entry only — the transcript and `--resume` survive (2026-08-02)
- **The PermissionRequest hook is `claude/hooks/approval_classifier.py`** (was `auto_classify.py`) — renamed because sessions kept confusing it with Anthropic's harness "auto mode classifier", which is a completely separate path. It now has two backends: the API key first (~1s), then the Claude subscription via `claude -p --model haiku` (~9s) when the API path fails for any reason. `claude -p --bare` cannot be used for the fallback — its help states OAuth and keychain are never read — so recursion is stopped by the `APPROVAL_CLASSIFIER_NESTED` env marker instead. State is written to `~/.cache/claude/approval-classifier-health.json` on every attempt and rendered by the statusline as `auto-ant:<key>` / `auto-sub (api down)` / `🔴auto` — the suffix after `auto-` names the *backend*, not the key, so a key labelled `sub` can't be mistaken for the degraded state (2026-08-03)
- **The classifier health file records the last *backend attempt*, not the current state** — `write_health()` runs only on the `classify()` path, so fast-path allows/denies and `AskUserQuestion` surfaces leave it frozen. A single transient API read timeout on 2026-08-05 therefore pinned `🔴auto` for 2.5h while nothing was actually wrong: the API key resolved fine (HTTP 200 in 1.2s) and only fast-pathed tools had run since. The statusline now ages the entry out — past **15m** it renders a dim `auto?` (unknown, not down) for *every* backend, past 6h nothing at all; the backend string is validated before the age tiers so a corrupt file renders nothing rather than a confident `auto?`. When diagnosing a red `auto`, check `~/.cache/claude/approval-classifier.log` for a `NO KEY:` line before suspecting credentials — a socket read timeout and a missing key look identical in the statusline but not in the log (2026-08-05)
- **`custom_bins/claude-tools` is a bash dispatch wrapper, never a binary** — it execs `claude-tools-<os>-<arch>`. Rebuilds go to the arch-suffixed asset; copying one to the generic path makes one platform's build the runtime for all of them, and it exits 0 so the `|| bash statusline.sh` fallback cannot fire. Clobbered twice (`e7c2de0` fixed, `eabeba2` re-broke, undetected 13 days). No script writes that path — it is always a hand-copied rebuild, so the guards are `check-claude-tools-fresh.sh` (asserts `#!` + validates SHA256SUMS) and `tests/test_statusline_classifier.sh`, which now drives the *deployed* dispatcher rather than `target/release/` (2026-08-03)
- **`deploy.sh` marks ANTHROPIC_API_KEY with `secrets-use --global-once`, never `--global`** — deploy runs on every deployment, so an unconditional mark would undo a deliberate `--no-global` at the next `deploy.sh`, silently reopening bare non-TTY resolution for a name the user had just closed. `--global-once` stands down once the conf carries a `# global-scope-decided: NAME` comment. That sentinel records that a **decision exists**, not that the marker was written: on a conf predating the migration the name is already unmarked, so `--no-global` changes no bytes — recording only on the write path would leave exactly that revocation unrecorded. Conf mutations take a `mkdir`-based lock (not `flock`, which is util-linux and absent on stock macOS), acquired before the first conf *read* — locking only the write let two writers land an outcome equal to neither serial ordering. **Forking two writers and hoping they collide detects nothing** (0/40 with the lock neutered); the suite forces the interleaving via the test-only `SECRETS_USE_TEST_PRE_MV_DELAY` seam plus a barrier on the staged `$CONF.tmp.<pid>` file, which catches it 8/8. Treat any concurrency test here as broken until you've watched it fail against a neutered lock (2026-08-06)
- The statusline has **two implementations that must stay in sync**: `tools/claude-tools/src/statusline.rs` (what actually runs) and `claude/statusline.sh` (fallback). Guards added because comments alone can't catch drift: `tests/test_statusline_classifier.sh` asserts both render identically, `claude/hooks/nudge_statusline_parity.sh` fires on edits to either, and `scripts/check-claude-tools-fresh.sh` flags committed binaries older than the source — the silent failure is `darwin-arm64`, which nobody on Linux can cross-compile (2026-08-03)
