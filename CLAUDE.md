# CLAUDE.md

Dotfiles for ZSH, Tmux, Vim, SSH and dev tools across macOS, Linux and RunPod, deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — **edits here change your running environment immediately.**

## Top Rules

- **Direct pushes to main are allowed** — personal repo, no PR overhead. Single branch: `main`; branch worktrees off it. Route only large or structural merges through a tracked PR.
- **Flags are ADDITIVE to defaults unless `--minimal` is used.** `install.sh` and `deploy.sh` enable every component by default; `--no-<component>` disables one; `--minimal` disables all defaults; modifiers (`--append`, `--ascii`, `--force`) don't affect defaults. Detail in README.md.
- **Sandbox blocks `git pull`/`merge`/`stash`** here, and `codex exec` crashes on macOS inside it — both need `dangerouslyDisableSandbox: true`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks` and `permissions` keys — [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **Secrets are NOT globally exported** (supply-chain defense). Use `setup-envrc` per project via direnv; `secrets-edit` to add or update.
- **Plot with the house style by default** — `import style as house; house.set_defaults()` from `lib/plotting/` (pastel + soft grid). Charts on an artifact page are drawn as native SVG from `lib/plotting/tokens.json` instead; matplotlib is for papers and decks. Full API in the `house-plots` skill.
- **Specs, plans and reports are Artifacts**, not files in `specs/` or `plans/`. Publish them and record the URL with its finding in this file; write Markdown source only when it must be version-controlled with the code. See `~/.claude/rules/pointers.md`.
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

Project-specific bugs, quirks, decisions and current state. Timestamp `- description (YYYY-MM-DD)`, keep under 20, prune past two weeks — retired entries move to [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md) § Past Learnings, and git history is the archive for the rest.

- **`install.sh`/`deploy.sh` could stall or silently abort unattended; CI now runs both end-to-end and fails on either** — two stall sites guarded on `[[ -t 0 ]]` alone, so on a real terminal `--non-interactive` still stopped at a password prompt (`front_load_sudo`, and the mas prewarm in install.sh); `chsh` authenticated through PAM on stdin, blocking even where sudo was cached. Separately, `set -euo pipefail` made a probe for an absent tool fatal *above* the fallback written for it — `bws --version` (127 through a pipefail substitution) ended deploy.sh before SSH and secrets, `loginctl enable-linger` before scheduled tasks, the Node LTS and `gh` release downloads ended install.sh with no network, `${SUDO_USER:-$USER}` ended it in any container, and cancelling the component TUI with Esc killed the whole run. `$SUDO -E` ran as the command `-E` under root (zsh never word-splits scalars). `tests/test_install_deploy_no_stall.py` runs both scripts against a throwaway HOME with **an stdin that stays open but never delivers a byte** — `</dev/null` is useless here because every `read` returns EOF, so a prompting script still passes — in pipe and pty flavours, the pty being the only one that tests `--non-interactive` rather than the TTY guards. Two traps worth remembering: a stub asserts "this tool never prompts", so stubbing `sudo` to `exit 0` made it look passwordless and hid the flagship stall; and in `tests/test_stall_guards.sh` a `grep` that matches nothing makes a `while` loop assert nothing, so every search is routed through `require_hits` — which must return non-zero for the *caller* to report, since `$(...)` is a subshell and a counter incremented there is discarded (2026-08-28)

- **md2review's comment box flickered because a selection event could close it** — opening the box focuses its textarea, focusing collapses the selection, and the debounced `selectionchange` handler read that back as a deselect, closing the box ~350 ms after `mouseup` opened it. Opening and closing are now asymmetric: selection events only ever open. Enter saves, Esc discards, Save leads the buttons. **The persistence added alongside it was reviewed and cut** — an IndexedDB mirror let a save racing its own async recovery destroy what it was recovering; a backup key resurrected deliberately-cleared comments; a neighbouring-key scan copied one document's confidential note onto an unrelated page. What remains: a bare JSON array under a filename-derived key (older layers `.reduce()` it and die on anything else), prefix-namespaced aux keys, a keystroke draft. `tests/test_md2review_browser.py` drives Chromium — 19 of 27 checks fail against the pre-fix layer, 13 against the version review rejected (2026-08-28)

- **Rules were cut from 24 files to 9 and activity-scoped procedure moved into skills** — the always-loaded tier (`claude/rules/*.md` + `claude/CLAUDE.md` + the output style) went from ~76 KB to ~28 KB. Rules now carry only always-relevant judgment; `rules/pointers.md` indexes which skill owns each activity (`artifact-writing`, `results-artifact`, `spec-artifact`, `llm-judge`, `jobs`, …). Anything procedural belongs in a skill, not in a rule (2026-08-28)

- **OpenRouter families are reached via `custom_bins/openrouter-cli`, never via subagents** — agent-frontmatter `model:` names resolve against api.anthropic.com only, so a non-Anthropic name either hard-fails with "There's an issue with the selected model" or answers from Claude wearing another family's label; the `kimi-k3`/`glm-5.3`/`qwen3.8-max`/`muse-spark-1.2` agent files were deleted for exactly this. `openrouter-cli ask <alias>` and `openrouter-cli fusion` verified live against all four families; config in `config/openrouter-models.toml`, key via per-project secrets. `fusion` fails closed on panel degradation, since OpenRouter keeps `status: "ok"` on partial panel failures (2026-08-25)

- **The Codex desktop app self-heals disabled Sky launch paths** — after `codex plugin remove computer-history@openai-bundled` it rewrote the `turn-ended` hook and relaunched `SkyComputerUseService` two minutes later, despite both Sky-backed plugins showing `not installed`. The durable mitigation is an empty `~/.codex/computer-use` marked `uchg` (preserved runtime: `~/.codex/computer-use.disabled-2026-08-24`). Keep `codex/config.toml` free of Sky `notify` hooks — a disabled plugin section does not neutralize a top-level notifier. Do not add a periodic killer; it only creates respawn churn (2026-08-24)

- **`claude/settings.json` is permanently dirty on purpose** — the machine-local model-router gateway token cannot be relocated out of a public file, so the working tree always carries a diff here. The full reasoning, the `_validate_no_local_gateway` pre-commit guard and the stage-a-stripped-blob recipe are in [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md) (2026-08-18)

- **The statusline has two implementations that must stay in sync** — `tools/claude-tools/src/statusline.rs` (what runs) and `claude/statusline.sh` (fallback). Nothing nudges you on edit any more — the parity hook was deleted on 2026-08-28 — so the drift is caught only after the fact by `tests/test_statusline_classifier.sh`, which asserts both render identically, and `scripts/check-claude-tools-fresh.sh`, which flags committed binaries older than the source. Edit one, edit the other in the same pass. The silent failure is `darwin-arm64`, which nobody on Linux can cross-compile (2026-08-03, hook removed 2026-08-28)

- **The PermissionRequest hook is `claude/hooks/approval_classifier.py`**, not Anthropic's harness auto-mode classifier — a separate path sessions keep confusing it with. Its two backends, the model-era swap trap they hide from each other, and the `NO KEY:` diagnostic are in [`docs/tooling-and-packages.md`](docs/tooling-and-packages.md) § Past Learnings (2026-08-03)
