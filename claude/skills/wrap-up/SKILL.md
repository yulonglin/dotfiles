---
name: wrap-up
description: Drives a stalled session to a terminating end state - land the work, state the blocker, or take one step (dotfiles trial, manual-only)
disable-model-invocation: true
---

# Wrap Up

## Your job is to reach an end state, not to keep working

You were woken by the hourly `tmux-resume` nudge, not by a human: this session hit a rate limit and the scheduler is prompting you to resume. Every branch below terminates — if you finish this skill still working, you have used it wrong. **Announce at start:** "Using the wrap-up skill to bring this session to a close."

**`disable-model-invocation: true` stays on.** It makes this skill reachable only by someone typing `/wrap-up` (the nudge's keystrokes are that invocation); omitting it would make the skill model-invoked (see the `superpowers:writing-skills` skill § Invocation), letting any matching dotfiles prompt fire the commit-and-push path with no nudge at all. Discovery is via `claude/skills/catalog/SKILL.md`.

## Step 0: Only `dotfiles` may be written to unattended

Writing to git unattended — staging, committing, pushing, opening a PR — is scoped to `dotfiles`, so run this before anything else:

```bash
basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")"
```

**If that basename is not `dotfiles`**, Step 2 is closed: stage nothing, commit nothing, push nothing. Still classify (Step 1), then take the **blocked** branch (Step 3) — say where the work stands, name what is left uncommitted and in which checkout, and rename the session (Step 5). Then end your turn. **Out of scope terminates; it does not resume** — the scope governs *who may write to git*, never *whether the session may stop*.

Use `--git-common-dir`, not `--show-toplevel`, which in a linked worktree (`cw`, `claude --worktree`) returns the worktree path and so would exclude every branch worktree — and worktrees are in scope, being the intended home for a wrap-up commit since Step 2 forbids committing on `main`.

## Step 1: The classification decides everything downstream

Pick exactly one, and get it right before acting.

| State | Test | Go to |
|---|---|---|
| **Done** | The work the session was asked to do is complete, or complete enough to land behind review | Step 2 |
| **Blocked** | Progress requires a decision, credential, or approval only the owner can give | Step 3 |
| **Mid-flight** | There is a concrete next step you can take alone, right now, without a decision | Step 4 |

**The honest classification is usually "blocked."** If you find yourself reasoning toward "mid-flight" because it feels more productive, re-read the blocked test — a session that invents a next step to avoid stating a blocker is the exact failure this skill exists to stop.

## Step 2: Done — land it and exit

**Precondition, before anything is staged: check the branch *and* the checkout.** If the branch is `main` or `master` you may not commit — "never push to `main`" suppresses only the *push*, while a local commit still lands on `main` with no review path.

```bash
git rev-parse --abbrev-ref HEAD
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] && echo "root checkout" || echo "linked worktree"
```

| Checkout | On `main`/`master` | On a feature branch |
|---|---|---|
| **Linked worktree** (`cw`, `claude --worktree`) | `git switch -c wrap-up/<topic>` — the worktree owns its own HEAD, so nobody else is affected | Commit here |
| **Root checkout** (`/home/yulong/code/dotfiles`) | **Classify blocked (Step 3).** Do not switch | Commit here, but still do not switch branches |

**Never `git switch` in the root checkout**: its single HEAD is shared by every pane, editor, and cron job pointed at it, so switching silently moves everyone else's working branch. If the work genuinely needs to land, say so in Step 3.

0. **Run the tests first, if any exist and you have not run them** — before staging, because a run can generate fixes or artifacts that belong in the commit. A failing suite does not block landing a draft PR; it blocks *claiming the work is finished*. Report which of the two it is.
1. **List the paths this session touched, from your own transcript** — not from `git status`. A shared checkout can hold edits from the user, a runtime process, or a concurrent job, and none of those are yours to commit.
2. **Stage by name**: `git add <path> <path> …`, including new files this session created. Never `git add -u` (sweeps up every tracked edit, including someone else's) and never `git add -A` (also stages the sandbox's char-device masks); do not blanket-ban untracked files either, which silently drops the session's own new files.
3. **Verify before committing — read the content, not just the names.** `git diff --cached --name-only` must match your list exactly, but a path is not an ownership boundary: another actor can have edited a different hunk of a file you also touched. Read `git diff --cached`, confirm every hunk is yours, and `git restore --staged <path>` any that is not. Anything you cannot attribute stays unstaged and gets named in the PR body; if you cannot attribute the changes at all, stop and go to Step 3.
4. **Commit with a real message that says *why*, not just what.** No heredocs — write to `/tmp/claude/<job>-msg.txt` and `git commit -F`.
5. **If the branch is ahead of `main`, push and open a draft PR — a dirty tree does not excuse skipping this**, since item 3 deliberately leaves unattributable edits unstaged; mention those leftover paths in the PR body. Never push to `main`, never force-push, never merge.
6. **The PR command must be non-interactive**: `gh pr create --draft` alone prompts for title and body and will hang an unattended job, and `--fill` derives the body from commit messages, which cannot carry the sections below. Always `gh pr create --draft --title "<subject>" --body-file /tmp/claude/<job>-pr.md`, writing that file first. **The body is the state of the work, in three headed sections, under ~250 words total** — it is read cold by someone deciding whether to look further, and this session cannot answer follow-ups:
   - **What's done** — what now works that did not before. Not a file list; `gh pr diff` already shows files.
   - **What's left** — known gaps, deferred decisions, and any paths left unstaged because you could not attribute them. "Nothing" is a valid answer, said explicitly rather than dropping the section.
   - **How it was tested** — the command you ran and what it returned. If the suite failed, or you ran none, say so here. Never write "tested" without naming what was run.
7. **If push or PR creation fails** — no remote, auth expired, a protected branch — do **not** exit as done: the commit exists but nobody can see it. Classify as **blocked** (Step 3), name the failure, and say where the commit is.
8. Rename the session (Step 5), then **end your turn.**

## Step 3: Blocked — state the decision and exit

This is the branch that matters most. Produce, in this order: **the decision** in one sentence phrased as a question; **the options**, each with its real tradeoff, not a strawman and a favourite; **your recommendation**, with one sentence of reasoning; **what it gates**, i.e. what stays stuck until this is answered.

**Order matters: rename first, ask second.** Do the Step 5 rename (`blocked: <one-line decision>`) and write those four items into your narration *before* calling `AskUserQuestion`, which is synchronous and never returns if the owner does not answer — everything after it would be unreachable, leaving the blocker recorded nowhere.

Then surface the decision via **`AskUserQuestion`**, not prose: this session is a background job, and prose questions do not notify the owner (see `rules/background-job-questions.md`). Write `needs input:` on its own line. If the call returns, act on the answer; if it never returns, the session is already named and the blocker already stated — that is the correct terminal state, not a failure.

> **Never choose on the owner's behalf in order to look finished.** A stalled session is visibly stalled and costs an hour; a silently-wrong autonomous choice is invisible and lands in `main`. If you are unsure whether a call is yours, it is not yours.

## Step 4: Mid-flight — one step, then land or state

Take **one** concrete step — not a work session, just the one you already knew you needed. Then re-classify against Step 1 and follow Step 2 or Step 3. You may not return to Step 4 twice in a row: if the next nudge finds you mid-flight again, treat that as evidence you are actually blocked and go to Step 3.

## Step 5: Rename so the list is readable

Set the tmux window name to encode disposition, keeping `<topic>` to two or three words:

```bash
tmux rename-window "done-<topic>"      # landed, PR open or committed
tmux rename-window "blocked-<topic>"   # question surfaced, awaiting the owner
```

If `tmux rename-window` fails (no tmux, detached), skip it — legibility nicety, never a reason to abort a wrap-up. **It renames the tmux window only**: the `name` field in `~/.claude/jobs/<id>/state.json`, which the agents list reads, is not writable from inside a session, and the sandbox denies writes under `~/.claude/jobs` anyway.

## These thoughts are the failure mode, not a shortcut

| Thought | Reality |
|---|---|
| "I'll just keep going, I'm close" | That is what a bare `continue` does, forever. Classify and terminate. |
| "I'll pick the sensible option and note it" | Step 3 exists precisely to stop this. Surface it. |
| "This repo isn't dotfiles but the work is obviously fine" | Step 0 closes Step 2 only. State where the work stands, name the uncommitted paths and their checkout, rename, end the turn — do **not** resume. |
| "I'll commit everything to be safe" | Stage the paths you touched, by name. `git add -u` commits other people's work; `git add -A` also stages sandbox char-device masks. |
| "The file is on my list, so the staged diff is mine" | A path is not an ownership boundary. Read `git diff --cached`, not just `--name-only`. |
| "I'll just switch the checkout to a branch first" | Only in a linked worktree. In the root checkout that moves HEAD for every other pane and cron job pointed at it. |
| "No blocker, so I'll invent a next step" | Re-read Step 1. Inventing work to avoid stating a blocker is the failure mode. |
| "I'll ask in prose, the owner will see it" | Background jobs do not notify on prose. `AskUserQuestion` or it did not happen. |
