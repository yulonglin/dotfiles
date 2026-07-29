---
name: wrap-up
description: Drives a stalled session to a terminating end state - land the work, state the blocker, or take one step (dotfiles trial, manual-only)
disable-model-invocation: true
---

# Wrap Up

## Overview

You have been woken by the hourly `tmux-resume` nudge, not by a human. Something in this session hit a rate limit and the scheduler is prompting you to resume.

**Your job is to reach an end state, not to keep working.** Every branch below terminates. If you finish this skill still working, you have used it wrong.

**Announce at start:** "Using the wrap-up skill to bring this session to a close."

## Why this exists

The hourly nudge in `config/tmux-resume-patterns.conf` used to send a bare `continue`. `continue` has no exit branch, so sessions resume hourly forever and accumulate: 101 of 157 jobs on this machine were hourly `continue` nudges, and 56 sessions sat blocked on a human decision that was never surfaced. Fixing the inflow means the nudge must be able to *end* a session — so the nudge now types `/wrap-up` instead.

**Status: the nudge is wired, gated on opt-in, and its keystrokes are unconfirmed.** `tmux-resume` types `/wrap-up` only into panes whose tmux window name starts with `auto-` (`config/tmux-resume-patterns.conf`; toggle with `tauto` / `tnoauto`). So you are reading this because a human named this window that way — reaching this skill is itself evidence someone wanted this session wrapped up. Detection anchors on rate-limit wordings captured from real prompts, but the *action* — `1 Enter`, then `/wrap-up`, then two `Enter`s — has never been fired at a live prompt, because a sandboxed session cannot open a tmux socket. Both guesses are marked as such in the pattern file and are settled by one `tmux-resume --dry-run` against a real rate-limited pane.

**`disable-model-invocation: true` stays on regardless.** It makes this skill reachable only by someone typing `/wrap-up` — and the nudge sending those keystrokes *is* that invocation, so wiring the nudge is not a reason to drop the flag. Omitting it would instead make the skill model-invoked (see `claude/skills/writing-great-skills/SKILL.md` § Invocation), letting any matching dotfiles prompt fire an autonomous commit-and-push path with no nudge involved at all. That is a different and much wider trigger surface than the one being trialled here. Discovery during the trial is via `claude/skills/catalog/SKILL.md`.

## Step 0: Scope guard (required first)

Writing to git unattended — staging, committing, pushing, opening a PR — is trialled on `dotfiles` only. Before anything else:

```bash
basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)")"
```

**If that basename is not `dotfiles`**, Step 2 is closed: stage nothing, commit nothing, push nothing. Still classify (Step 1), then take the **blocked** branch (Step 3) — say where the work stands, name what is left uncommitted and in which checkout, and rename the session (Step 5). Then end your turn.

**Out of scope terminates; it does not resume.** An earlier version of this guard announced out-of-scope and then carried on with the prior task, exactly as a bare `continue` would. That was right while the nudge fired at every pane the scheduler could see: stopping dead would have stranded unrelated panes with no PR and no blocker stated, and since a resumed pane stops displaying a rate-limit banner, nothing would have matched on the next scan to retry. Opt-in removed that premise. The nudge now reaches only windows a human named `auto-…`, so there are no bystander panes to strand, and resuming would rebuild the endless-`continue` pump this entire change exists to remove. The trial scope governs *who may write to git*, not *whether the session may stop*.

Use `--git-common-dir`, not `--show-toplevel`. In a linked worktree (`cw`, `claude --worktree`) `--show-toplevel` returns the *worktree* path, whose basename is the worktree's name — `agent-sprawl-spec`, not `dotfiles` — so a `show-toplevel` test excludes every branch worktree, which is where most sessions actually live. `--git-common-dir` resolves to the owning repo's `.git` in both a worktree and the root checkout, so its parent's basename is the repo name either way. Worktrees are in scope: they are the intended home for a wrap-up commit, since Step 2 forbids committing on `main`.

The opt-in prefix in `config/tmux-resume-patterns.conf` is the primary scope, and it lives in the sender, where it belongs — by the time this guard runs the keystrokes have already landed, so a check here can never prevent an unwanted interruption. This guard is defence-in-depth for the git-writing branch only.

## Step 1: Classify honestly

Pick exactly one. The classification decides everything downstream, so get it right before acting.

| State | Test | Go to |
|---|---|---|
| **Done** | The work the session was asked to do is complete, or complete enough to land behind review | Step 2 |
| **Blocked** | Progress requires a decision, credential, or approval only the owner can give | Step 3 |
| **Mid-flight** | There is a concrete next step you can take alone, right now, without a decision | Step 4 |

**The honest classification is usually "blocked."** If you find yourself reasoning toward "mid-flight" because it feels more productive, re-read the blocked test. A session that invents a next step to avoid stating a blocker is the exact failure this skill was written to stop.

## Step 2: Done — land it and exit

**Precondition, before anything is staged: check the branch *and* the checkout.**

```bash
git rev-parse --abbrev-ref HEAD
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] && echo "root checkout" || echo "linked worktree"
```

If the branch is `main` or `master`, you may not commit. "Never push to `main`" suppresses only the *push* — committing first still lands a direct local commit on `main` with no review path, and the nudge runs unattended in whatever checkout the pane happened to be in.

What you may do about it depends on which checkout you are in, because a branch switch is not a private act:

| Checkout | On `main`/`master` | On a feature branch |
|---|---|---|
| **Linked worktree** (`cw`, `claude --worktree`) | `git switch -c wrap-up/<topic>` — the worktree owns its own HEAD, so nobody else is affected | Commit here |
| **Root checkout** (`/home/yulong/code/dotfiles`) | **Classify blocked (Step 3).** Do not switch | Commit here, but still do not switch branches |

**Never `git switch` in the root checkout.** A checkout has one HEAD shared by every pane, editor, and cron job pointed at it. Switching it to `wrap-up/<topic>` silently moves everyone else's working branch, so their next commit, pull, or `deploy.sh` runs against a branch they never chose — from their side it looks like the repo changed under them for no reason. Owning the *edits* does not mean owning the *checkout*. If the work genuinely needs to land, that is a decision for the owner: state it in Step 3 and say the tree holds work that needs a worktree to land safely.

0. **Run the tests first, if any exist and you have not run them.** This has to happen before staging, not after: a test run can generate fixes or artifacts that belong in the commit, and the PR body created in item 6 is supposed to carry the result. A failing suite does not block landing a draft PR — it blocks *claiming the work is finished*. Report the outcome plainly in the PR body and say which of the two it is.
1. **List the paths this session touched**, from your own transcript — not from `git status`. A shared checkout can hold edits from the user, a runtime process, or another job running concurrently, and none of those are yours to commit.
2. **Stage by name**: `git add <path> <path> …`, including new files this session created. Never `git add -u` (it sweeps up every tracked edit in the tree, including someone else's) and never `git add -A` (it also stages the sandbox's char-device masks). A blanket untracked ban is equally wrong in the other direction — it silently drops the session's own new files and the run ends having landed nothing.
3. **Verify before committing — read the content, not just the names.** `git diff --cached --name-only` must match your list exactly, nothing extra. That is necessary but *not sufficient*: a path is not an ownership boundary. In a shared checkout, another actor can have edited a different hunk of a file you also touched, and `git add <path>` stages their hunk alongside yours while the name-only check still passes cleanly. So also read `git diff --cached` and confirm every hunk is one you recognise. If a hunk is not yours, `git restore --staged <path>` and leave that file out. Anything modified that you cannot attribute to this session stays unstaged; name it in the PR body so the owner knows it is there. If you cannot attribute the changes at all, stop and go to Step 3 — an unattributable diff is a decision for the owner, not a commit.
4. Commit with a real message that says *why*, not just what. No heredocs — write to `/tmp/claude/<job>-msg.txt` and `git commit -F`.
5. **If the branch is ahead of `main`, push and open a draft PR — a dirty tree does not excuse skipping this.** the staging rule above deliberately leaves unattributable edits unstaged, so a dirty tree is the *expected* end state, not an error; gating the push on cleanliness would mean the common case commits locally, exits "done", and leaves the work invisible on a machine nobody looks at. Push the commit; mention the leftover unstaged paths in the PR body. Never push to `main`, never force-push, never merge.
6. **The PR command must be non-interactive.** `gh pr create --draft` alone prompts for title and body, and an unattended job has no way to answer — it hangs or dies before it can terminate, which is the exact failure this skill exists to prevent. Always supply both: `gh pr create --draft --title "<subject>" --body-file /tmp/claude/<job>-pr.md`. Do **not** use `--fill`: it derives the body from commit messages, which cannot carry the three sections below.

   **Run it as its own command**, never chained onto the push. `quality_pr_gate.sh` runs *before* the command does, so a `git push && gh pr create` would have it inspect the pre-push state; it refuses the whole line rather than answer the wrong question. Push in item 5, create here.

   **If `gh pr create` is denied, that is the code-review gate, not a bug.** `quality_pr_gate.sh` blocks the command when the branch changes code files and `superpowers:requesting-code-review` has not run on it. Run that skill over the branch diff and re-run the command — the review is the point, so do it rather than reaching for the bypass. The deny message prints a ready-to-run `mkdir -p … && touch …` escape for branches a review genuinely does not apply to; using it is a judgement call you should state in the PR body. It also refuses `--head` outright (check out the branch instead) and `--base` on an unreviewed branch.

   **The body is the state of the work, in three headed sections, under ~250 words total.** Write it to that file before calling `gh`:

   | Section | Contents |
   |---|---|
   | **What's done** | What now works that did not before. Not a file list — `gh pr diff` already shows files. |
   | **What's left** | Known gaps, deferred decisions, and any paths left unstaged because you could not attribute them to this session. "Nothing" is a valid answer — say it explicitly rather than dropping the section. |
   | **How it was tested** | The command you ran and what it returned. If the suite failed, or you did not run one, say that here; per item 0 a failing suite does not block a draft PR, it blocks claiming the work is finished. Never write "tested" without naming what was run. |

   The word ceiling is load-bearing, not politeness. This PR is read cold by someone deciding whether to look further, and the session that produced it cannot answer follow-up questions. A wall of narration gets skipped exactly the way a 157-entry job list does — the sections exist so a reviewer can reconstruct the state in one screen.
7. If push or PR creation fails — no remote, auth expired, a protected branch — do **not** exit as done. The commit exists but nobody can see it, which is indistinguishable from the pile-up this skill was written to stop. Classify as **blocked** (Step 3), name the failure, and say where the commit is.
8. Rename the session (Step 5), then **end your turn.**

## Step 3: Blocked — state the decision and exit

This is the branch that matters most. Produce, in this order:

1. **The decision**, in one sentence, phrased as a question.
2. **The options**, each with its real tradeoff — not a strawman and a favourite.
3. **Your recommendation**, with one sentence of reasoning.
4. **What it gates** — what stays stuck until this is answered.

**Order matters: rename first, ask second.** Do the Step 5 rename (`blocked: <one-line decision>`) and write the four items above into your narration *before* calling `AskUserQuestion`. `AskUserQuestion` is synchronous — if the owner does not answer, it does not return, and every instruction after it is unreachable. Put the rename after the call and an unanswered question leaves the session sitting under its old name with the blocker recorded nowhere: exactly the invisible-stall state this skill exists to eliminate, now produced by the skill itself. Renaming first means the disposition survives regardless of whether an answer ever arrives.

Then surface the decision via **`AskUserQuestion`**, not prose. This session is a background job; prose questions do not notify the owner, and an unnotified question is indistinguishable from no question at all. See `rules/background-job-questions.md`.

Write `needs input:` on its own line. If the call returns with an answer, act on it. If it never returns, the session is already named and the blocker already stated — that is the correct terminal state, not a failure.

> **Never choose on the owner's behalf in order to look finished.** A stalled session is visibly stalled and costs an hour. A silently-wrong autonomous choice is invisible and lands in `main`. This constraint is not negotiable for the sake of a tidier job list — if you are unsure whether a call is yours, it is not yours.

## Step 4: Mid-flight — one step, then land or state

Take **one** concrete step. Not a work session — one step, the one you already knew you needed.

Then re-classify against Step 1 and follow Step 2 or Step 3. You may not return to Step 4 twice in a row: if the next nudge finds you mid-flight again, treat that as evidence you are actually blocked and go to Step 3.

## Step 5: Rename so the list is readable

The jobs list shows `nameSource: "auto"` names that say nothing about outcome, which is why 157 entries are unreadable at a glance. Set the tmux window name to encode disposition:

```bash
tmux rename-window "done-<topic>"      # landed, PR open or committed
tmux rename-window "blocked-<topic>"   # question surfaced, awaiting the owner
```

Keep `<topic>` to two or three words. If `tmux rename-window` fails (no tmux, detached), skip it — it is a legibility nicety, not a correctness step, and it must never abort a wrap-up.

**Known limitation, stated rather than papered over:** this renames the *tmux window*, which is what you see in a terminal. The `name` field in `~/.claude/jobs/<id>/state.json` — what the agents list reads — is not writable from inside a session, and the sandbox denies writes under `~/.claude/jobs` regardless. So this improves tmux legibility only. Closing the gap for the agents list needs a change outside this skill.

## Anti-patterns

| Thought | Reality |
|---|---|
| "I'll just keep going, I'm close" | That is what `continue` did 101 times. Classify and terminate. |
| "I'll pick the sensible option and note it" | Step 3 exists precisely to stop this. Surface it. |
| "This repo isn't dotfiles but the work is obviously fine" | Step 0 closes Step 2 only. Say where the work stands, name the uncommitted paths and their checkout, rename the session, and end the turn. Do **not** resume — out of scope means "do not write to git", never "keep going". |
| "The PR body should explain everything I did" | Under ~250 words, three sections, no narration. `gh pr diff` shows the files; the body says what works, what does not, and what was run. |
| "I'll commit everything to be safe" | Stage the paths you touched, by name. `git add -u` commits other people's work; `git add -A` also stages sandbox char-device masks. |
| "I'm on `main` but the change is small" | Step 2's precondition is a hard stop. Unattended commits onto `main` are exactly what the draft-PR flow exists to prevent. |
| "I'll just switch the checkout to a branch first" | Only in a linked worktree. In the root checkout that moves HEAD for every other pane and cron job pointed at it. |
| "The file is on my list, so the staged diff is mine" | A path is not an ownership boundary. Read `git diff --cached`, not just `--name-only`. |
| "No blocker, so I'll invent a next step" | Re-read Step 1. Inventing work to avoid stating a blocker is the failure mode. |
| "I'll ask in prose, the owner will see it" | Background jobs do not notify on prose. `AskUserQuestion` or it did not happen. |
