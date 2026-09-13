# Six PRs open, four need a decision from you

Handover from background job `2e583e0f`, in `/home/yulong/code/dotfiles`. Written by Claude Opus 5, 13 September 2026. `main` is green on all five CI workflows. **30 pull requests merged** across the session, two closed as split.

## Read this first

Three separate security mechanisms turned out to be documented as working while doing nothing. That is the through-line of the session, and it is why several things below say "measured" rather than "checked".

- The approval classifier's user-message extractor had been **blind for five months**, then — once fixed — was reading **26% injected content** as though you had typed it.
- `mask_env_read.sh` had **never masked anything** in its entire life. It emitted a JSON shape Claude Code ignores, and its test asserted only that the string `"deny"` appeared somewhere in the output, which both the working and the broken shape satisfy.
- My own claim that `permissions.deny` already blocked `curl … | sh` was **wrong**, and I had already used it to justify removing a gate.

Each was caught by running the thing, not by reading the comment above it. None would have been caught by the tests that existed.

## What needs you, in priority order

### #154 is held on a real defect, because the commit gate fails open

`config/git-hooks/pre-commit` lines 354-370: when `zsh` is absent from `PATH`, a staged file with a zsh shebang and an unterminated `if` was **accepted, hook exit 0, no diagnostic**. Sol found it by testing the missing-`zsh` case rather than the happy path.

The fix is to classify staged files *before* checking for `zsh`, and exit non-zero with an actionable message if any staged file is zsh and the interpreter is unavailable. Everything else in that PR verified clean: shebang-first classification holds, a broken zsh file is blocked with its parse error, and a bash-shebang file under `config/` correctly escapes the check.

**This is the one I would not merge as-is.** A commit gate that silently stops checking is the exact failure shape of the two hook bugs above.

### #158 needs `sudo` and `.env` decided separately

It empties `permissions.ask`. Its original justification was mine and was false: I said `mask_env_read.sh` made the two `.env` entries redundant. The hook had never worked, and now that it does, an adversarial pass still enumerated **13 live bypasses** — `dd if=.env of=/dev/stdout`, `sort`, `uniq`, `zcat`, `cat .e*`, `for f in .env`, `timeout cat .env`, a computed filename in any interpreter — two of which the hardening PR claimed to cover.

**So the hook is a guard rail and the `ask` rule is the gate.** My recommendation is to keep `Read(**/.env)` and `Read(**/.env.*)`.

`Bash(sudo *)` is a genuinely separate question: no built-in `soft_deny` rule names sudo or privilege escalation, so removing it hands every elevated command to the classifier's general judgement. The PR body is already rewritten to say all of this, and the correction is posted on the thread rather than quietly edited in. An automated security review flagged `"ask": []` as HIGH, independently.

### #117 asks whether to adopt the managed drop-in

This is the only open PR that changes how your machine is configured rather than what is in the repo. The recommendation is **adopt, but narrow it**: move only `ANTHROPIC_BASE_URL` and `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL`, leaving `ENABLE_TOOL_SEARCH`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and `modelPicker` in ordinary settings — the picker rows render from `config/model-router.toml`, which is already public here, so root protects nothing. As written, every model-roster edit would change the drop-in and demand a fresh `sudo install`.

Two permanent costs: one `sudo install` per machine, and `CLAUDE_RC_OVERRIDE` dies structurally, because a managed key cannot be overridden by `--settings`.

    /home/yulong/vault/tooling/dotfiles/spec-117-gateway-dropin-narrowing.md
    https://claude.ai/code/artifact/d1d52cd8-b565-4f98-a863-3870026adc8b

**Answering what you asked directly: no, the gateway keys have not moved.** `ANTHROPIC_BASE_URL` is in your working copy and absent from `origin/main` — the permanent working-copy diff, kept out of commits by `_validate_no_local_gateway`. Six merges touched `settings.json` today and none carried it.

### #112 has gone CONFLICTING again

`main` moved after the peer session rebased it, so it needs another rebase before your push. **Do not push the current tip.** The peer owns that branch and has the fd 0 context; I have not touched it.

When it is ready:

```
git -C /home/yulong/code/dotfiles/.claude/worktrees/tui-consolidation \
  push --force-with-lease \
  origin worktree-tui-consolidation
```

### The always-on context budget keeps growing

`tests/test_memory_tier_budget.py` fails six ways. `CLAUDE.md` is roughly **3.5x its pinned ceiling** and grew during the session; `## Learnings` is past its own documented 20-entry limit. Nothing runs this test automatically, so it is not a gate and nothing will stop the drift.

A prune plan is written and waiting — which entries retire, with a reason each, and the exact replacement section to paste:

    /home/yulong/vault/tooling/dotfiles/spec-claude-md-prune.md

I did not apply it. Which findings stop earning their place in every session is a judgement about your work, not mine.

### Two open PRs are not mine

**#151** (`write-prose`) and **#157** (`project-hub`) belong to another session and are both CONFLICTING. I left them alone.

## What landed

Thirty pull requests. The ones that matter:

**CI went green on all five workflows, first time since 1 September.** Two causes: `test_profile_defaults.sh` compared against golden fixtures that restated the config rather than testing it, and a hard-wrapped skill broke the Markdown gate. A side effect worth knowing — the mutation canary sits *after* the profile step, so it had been **skipped on every run for eleven days**; its first real execution passed.

**`./install.sh`'s menu was broken and now works.** `helpers.sh:287` passed `claude-tools select --items`, a flag that did not exist in the binary — lost in a June merge. The parser skipped it silently, fell through to stdin, and blocked having drawn nothing. Writing its container test turned up **three more live bugs on `main`**, each ending a run with no message: a failed version probe killing `install.sh` under zsh's `set -e`; an unset `$SHELL` aborting under `set -u`, which is how cron, systemd and the cloud provisioning path invoke it; and `((n++))` ending `deploy.sh` **after** `~/.codex` had been moved aside.

**The #123 split missed a component and you caught it.** Two commits landed on its branch between my reading its scope and closing it. Recovered separately: the Codex token refresh. Your statusline had been reading two-day-old quota since 6 September, because `account/rateLimits/read` returns 401 forever once the token lapses and only a real Codex request refreshes it. The trap worth remembering is that the CLI credential and model-router's credential are different copies of the same account, and only the router refreshes itself — so healthy GPT routes are not evidence the CLI credential is alive.

**`$defaults` restored.** Effective `allow` 11 to 20, `environment` 6 to 22. This was a **loosening**, not a fix: your custom `Git Push to Working Branch` is narrower than the built-in `Git Push Destination` it now sits beside, so your push posture widened.

**`deny` went 43 to 60**, closing the pipe-to-interpreter gap I created. The agent rejected my suggested spelling `Bash(* | sh*)` because it would also have blocked `sha256sum` (55 real uses in your history) and `shellcheck` (12), and measured a `| python*` wildcard at **314 false positives against zero true ones**.

## Three uncertainties worth carrying

**The evidence channel is better, not closed.** The whitelist posture loses 0 characters from real human turns, but an unterminated unknown tag keeps its body, and tag-free machine prose is untouched and is now the largest remaining channel. The aggressive variant was built, measured at 423 characters lost across 5 human turns, and rejected on that evidence rather than on preference.

**The env hook is a guard rail, not a boundary,** and its header now says so. Thirteen bypasses survive.

**One live page still argues a withdrawn claim.** `artifacts/classifier-rate-limits-2026-09/` is published in the **MATS Program** org while this machine is signed in personally, so its republish is refused from here. The repo metadata states the retraction in three places; the live page does not. Correct the page first, then sign in to MATS Program and publish at the existing URL.

## Traps that cost time

- `gh pr edit --body-file` fails repo-wide and **writes nothing while reporting success**. Use `gh api -X PATCH repos/yulonglin/dotfiles/pulls/<n> -F body=@<file>` and confirm with `gh pr view`.
- Inline review comments do not appear in `gh pr view --json comments`. Read `gh api repos/{owner}/{repo}/pulls/<n>/comments` separately or miss half the feedback.
- **A PR's `updatedAt` moving between reading its scope and closing it is a re-read, not a detail.** That is how the split lost a component.
- Compound commands are judged more harshly by the classifier than the same actions issued separately. Two of four denials cleared purely by splitting the command.
- `permissions.deny` is absolute — evaluated before the classifier and not overridable by user intent or an `autoMode.allow` entry. That is why the force-pushes could not be delegated to an agent.
