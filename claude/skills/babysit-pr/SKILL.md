---
name: babysit-pr
description: Shepherd one open pull request to a mergeable state without re-prompting — fix failing CI one root cause at a time, act on the review comments that have a single mechanical answer, resolve conflicts on a branch that is ours, and re-check on a sensible cadence until it is green or a real decision is needed. Use on "babysit this PR", "get it green", "fix CI", "the checks are failing", "keep an eye on PR N", or after opening a PR the user wants driven to green. For a backlog of several PRs use `review-pr-queue`; to merge and push a finished change use `ship`.
---

# Babysit a PR

Adapted from pstack's `babysit` and `fix-ci` skills in [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT), the Claude Code port of Lauren Tan's pstack, folded into one skill and fitted to this setup's background-job and merge rules.

One PR, driven to mergeable. This skill does not merge: merging follows the rule in `coding-conventions.md` (merge it yourself only when simple, otherwise ask) or `ship` when the user already authorised merge and push. A subagent that opens a PR does not babysit it; it returns to its caller.

## Loop

1. **Fetch state.**

   ```bash
   gh pr view <number> \
     --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName
   gh pr checks <number>
   ```

   Read check state from `statusCheckRollup` (each entry's `conclusion`, `detailsUrl`, `workflowName`); `gh pr checks --json` is missing from older gh, including the 2.45 that Ubuntu 24.04 ships.

2. **Triage in priority order.**
   - **Conflicts** (`mergeStateStatus == DIRTY`): rebase or merge the base in. A rewrite of history on a branch anyone else may have pulled needs the user's approval first; never force-push `main`.
   - **Failing checks** (`conclusion` is `FAILURE`, `TIMED_OUT` or `CANCELLED`): take the first failing job and read its log (`gh run view <run-id> --log-failed`, with the run ID from `detailsUrl`; for an external service, open `detailsUrl`). Extract the first actionable error, find its root cause, apply the smallest safe fix, commit, push. Fix one failure per iteration; a later failure is often a symptom of the first.
   - **Review comments** (`gh api repos/{owner}/{repo}/pulls/<number>/comments` and `gh pr view <number> --comments`): act only on feedback you agree with. A comment with a single mechanical answer (a rename, a guard, a formatting nit) gets the edit, with the comment quoted in the commit message. A comment that hinges on judgement, or whose ask is unclear, is not guessed at: reply on the PR with what you would do, and add it to the decisions list.
   - **Bot comments** (Bugbot, Codex review, Copilot): classify each as fix, dismiss with a reason, or ask. Security, data-loss and high-severity findings default to ask.

3. **Wait without polling.** An active CI run: `gh pr checks <number> --watch` with `run_in_background: true`, which re-invokes you when it exits. Waiting on a reviewer: a 20–30 minute `ScheduleWakeup` or `loop` heartbeat. Idle but watching for new comments: hourly.

4. **Stop** when any of these holds:
   - Checks green, every comment handled, branch merges cleanly: report it ready.
   - Three rounds of fix → push → recheck and still not green: stop, say what is still broken and what was tried.
   - The next fix needs a design choice, a new dependency, a public-interface change, or a change outside the PR's file set: ask with `AskUserQuestion` (bundling every open decision, per `communication.md`), and in a background job follow it with `needs input:` on its own line.

5. **Report**: fixes applied (each by commit SHA), comments addressed, comments deferred with the reason, current PR status and URL.

## Hard rules

- Never change a test's expected value just to get a pass. Change an assertion only when the behaviour genuinely changed and the assertion was pinned to the old one, and say so in the commit message.
- Never `--no-verify`, never mark a failing check as not required, never disable a test to go green.
- `gh pr ready` only when checks are green and no review comment is unhandled.
- A flaky check is re-run at most once (`gh run rerun <run-id> --failed`); a second failure is a real failure.
