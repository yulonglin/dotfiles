---
name: session-sweep
description: Clean up and finish every open Claude Code session on this machine — background jobs in agent view and interactive tmux sessions — by checking that each "done" session really is complete, landing work stranded in worktrees (a private remote for a repo that has none, then merging), relaying every blocked session's pending question as one bundle, and removing only the sessions with nothing left open. Use on "clean up the sessions", "finish up open sessions", "clear agent view", "close out the background jobs", "sessions are piling up", or when agent view lists stopped sessions that may be incomplete. For one stalled session from the inside, use `wrap-up`; for a recap of this session alone, `catch-me-up`.
---

# Session Sweep

## "Done" in agent view is not done

A background session shows `done` once it writes a `result:` line. That line often still hands work back ("still needs", "await your merge", "pull", "drafted, unsent"), and its worktree can hold commits that exist on no remote. On 2026-11-07, three attention-analyser sessions were `done` while 3.6k lines of their work sat in worktrees of a repo with no remote, and `claude rm` would have been the only thing between that work and deletion. **Finish a session before closing it**: closing is the last step, never the sweep.

## Step 1: Inventory every session, read-only

```bash
claude-sessions-audit            # digest (Needs you / New / In progress / Done earlier): age, verdict, result line, marker, worktree state
claude agents --json --all       # what agent view shows, including stopped and completed sessions
```

Both need the sandbox off (`gh` fails TLS verification and `claude agents` cannot reach the daemon inside it). `ListAgents` adds the interactive sessions with their tmux targets; read each with `tmux capture-pane -p -t <session> -S -30` (sandbox off for the socket). An interactive pane can hold an **unsent prompt** in its input box or an open `AskUserQuestion` — both are Yulong's half-finished intent, so report them, and never kill the pane.

Three more places hold open loops that neither listing shows:

- **Worktrees no job owns.** The SessionStart notice names stale worktrees with unmerged commits; `git worktree list` gives the full set. Delegate one classification sweep (`git cherry`, merged-PR lookup, dirty state, on-origin) that returns a table, and treat each `+` row like a `stranded` or `unmerged` session.
- **Job directories with no session.** A `~/.claude/jobs/<id>` that holds only an empty `tmp/` is residue; report it, do not chase it.
- **Sessions that died mid-work.** A row stuck in `working` or `waiting` whose `timeline.jsonl` stopped updating days ago is a crashed turn, not a busy one; the audit's age column shows it and tags it `stalled?` past a day. It is a Step 4 nudge, not a question for Yulong.

`claude-sessions-audit` verdicts are a starting point, ranked worst first:

| Verdict | Meaning | Action |
|---|---|---|
| `open` | blocked or working | Step 4 |
| `stranded` | worktree work on no remote, or uncommitted | Step 3, before anything else |
| `unmerged` | pushed but not in the base branch | look up the PR; Step 3 or Step 4 |
| `check` | the result line hands something back | Step 2 |
| `complete` | nothing in the result or worktree left open | Step 5 |

A session's own closing marker (`background-jobs.md`) outranks the follow-up words the audit guesses from its result line, but never the worktree checks, which run first. `✅ **Safe to close this session**` with the worktree checks passed is `complete`: skip Step 2 for it. `⚠️ **Keep open:** <what>` is `check`, and what it names goes through Step 2.

## Step 2: Verify each follow-up against live state

A follow-up named in a result line may already be done; check the source before listing it. Typical checks: `git status -sb` for "pull" (main level with origin means done); `gh pr view <n>` for a PR; the Gmail connector's `list_drafts` for "drafted, unsent" (`gws` auth expires; the connector does not); `git cherry main <branch>` before calling a branch squash-merged — and since a squash merge rewrites the patch, a `+` from `git cherry` is not proof it is unmerged: check `gh pr list --state merged --head <branch>` and grep a distinctive changed line on main. A local branch name is often not the PR's head name, so look a PR up by number (`gh pr view <n>`) when a result line names one. A branch whose change main has since reversed is superseded, not unmerged. Check `git stash list` too: the stack is shared across worktrees, so stashed work hides from every per-worktree check. A follow-up made moot by later events (a timezone override after moving back) counts as closed — say why. Only verified-open items go in the final list.

## Step 3: Land stranded work — private remote, then merge

Yulong's standing instruction (2026-11-07): a personal repo whose work sits only on this machine gets a **private** GitHub remote, and its finished branches get **merged**, not just preserved.

1. **Scan before the first push**: `gitleaks git --redact .`, and confirm `data/`, `out/` and anything personal never entered history (`git log --all --name-only --format= | grep -E '^(data|out)/'`).
2. `gh repo create yulonglin/<repo> --private --source . --remote origin`, push main, then `git push origin --all` so every branch has a backup before any merge.
3. Run the tests on main for a baseline. Merge each branch with `git merge --no-ff`, oldest first, stopping at the first conflict. **A `git merge-tree` preview goes stale after each merge**: a branch that previewed clean can conflict once an earlier branch has landed, so re-check against the current main.
4. Resolve additive conflicts by keeping both sides: two README sections, two index rows (convert to the existing table's schema), two parallel implementations under different names. Keeping both changes neither branch's behaviour; name any resulting duplication in the report rather than choosing between implementations unasked. Stop and ask when a conflict needs a semantic choice.
5. Tests and `ruff check` after the merges, then push. Every branch should show `0` for `git rev-list --count main..<branch>`.

Work that should not be published — a WIP commit marked superseded, or a repo where gitleaks fails — is backed up locally instead: `git format-patch` or `git bundle create` into `~/scratch/claude-jobs-archive/`, then ask before `claude rm --discard-unpushed`.

For a repo that already has a remote and PR review (dotfiles), an unmerged session branch goes through its PR instead: merge it if the repo's merge rule allows (`coding-conventions.md`), otherwise it is a decision for Step 4.

## Step 4: One bundle of decisions, relayed to the sessions

Collect every blocked session's pending question with its options verbatim. **Pending means unanswered**: an `AskUserQuestion` `tool_use` in `~/.claude/projects/*/<sessionId>.jsonl` with no matching `tool_result` — the last card asked is usually already answered. Most blocked sessions instead wait on a prose decision (a ⚠️ line or `>` quote in the last assistant message), so read that too. Include open cards and unsent prompts in interactive panes. Add every unmerged PR that needs Yulong's call, and every verified-open manual action. Ask them in one `AskUserQuestion` bundle (four per call, several calls in one message), each question naming its session and PR. Then act on the answers yourself, or `SendMessage` the answer to the session that asked so it finishes its own work. A session that died mid-work gets a `SendMessage` nudge with `notify_when_idle: true`, naming where it stopped and asking for a fresh `result:` line; it continues only work Yulong already authorised there.

## Step 5: Close only what is finished, reversibly

1. Archive job state first: `tar czf ~/scratch/claude-jobs-archive/jobs-<date>.tgz -C ~/.claude/jobs <ids…>`.
2. Never delete from agent view with Ctrl+X: that removes the worktree including uncommitted changes, which `claude rm` refuses to do ([agent view docs](https://code.claude.com/docs/en/agent-view)). A successful `claude rm` may print only the worktree path as its last line; confirm by checking that the directory is gone, not by reading that line as a refusal. `claude stop <id>` stops a session and keeps it resumable; `claude rm <id>` deletes its job state and worktree and refuses when the worktree has unpushed commits or uncommitted changes. The conversation transcript survives both (`claude --resume <sessionId>`).
3. On a refusal, read the leftover files: keep outputs (copy an ignored `out/` into the main checkout with no overwrite), `trash` disposable logs such as `.playwright-mcp/`, then `rm` again. **Never pass `--discard-unpushed` or `--force-remove-worktree` without Yulong's yes.**
4. Remove merged worktrees that no session owns with plain `git worktree remove` (it refuses dirty or locked trees); keep the branches, which are on the remote. First read `git worktree list --porcelain`: Claude Code locks a worktree while its session runs, so a lock naming a live PID means hands off, and a dead PID is a stale lock. Claude Code's own periodic sweep already removes clean background worktrees past `cleanupPeriodDays`, but never ones made by hand or holding work ([worktree docs](https://code.claude.com/docs/en/worktrees)), so those are the ones left for this step.
5. **Before removing any worktree** — by `claude rm`, `git worktree remove` or `trash` — check that nothing is using it and record its size. A lock is not the only sign of use: run `lsof +D <path>` with the sandbox off (inside it, `lsof` sees only the sandbox's own processes and prints nothing), and leave the tree alone if any process has a file or its working directory there, such as a shell, editor or dev server left open in it. Then note `du -sh <path>` for the report.
6. **Clear stray directories.** A directory under `<repo>/.claude/worktrees/` that `git worktree list` does not name is not a worktree, so `git worktree remove` does not apply. Read it, copy out anything worth keeping (an ignored `out/`, notes), then `trash` it after the same `lsof` and `du` checks.
7. Finish each repo with `git worktree prune`, which drops the bookkeeping for worktrees whose directory is already gone.

Leave in agent view any session whose follow-up is still open — it is the reminder — unless Yulong says to clear it, and leave interactive sessions running.

## Step 6: Report

A map of removed, kept and why; what landed where (repo URL, merge commit, test count before and after); disk freed, as the sum of the `du -sh` sizes recorded before each removal; the verified-open list grouped by who acts; and the archive path. Gates and sandbox refusals hit on the way (a denied `git branch -D`, expired `gws` auth) are reported, not retried.
