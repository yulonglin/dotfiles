# Background Jobs

In a background job (`~/.claude/jobs/`) a prose question reaches nobody: it renders into a job list that fires no notification, so the session looks stalled. Every decision point goes through `AskUserQuestion`, preceded by `needs input:` on its own line (the call blocks). Confirmations, option menus and "OK to proceed?" are decision points too.

**Ping the user with `PushNotification` when a job finishes or fails** — right before the `result:` or `failed:` line, which fires no notification on its own. Skip it for `needs input:`: a waiting `AskUserQuestion` already pushes (`inputNeededNotifEnabled`). The tool is deferred, so load it first with `ToolSearch` `select:PushNotification`. One line under 200 characters that leads with what to act on ("PR #412 ready: 2 tests still red"), never routine progress. A "not sent" result means the user is at the terminal already; do not retry.

**The closing message says where the work landed, what was not checked, and whether the session can close.** Name each place the work now lives — commit SHA, PR number or URL, file path, artifact link — then an `Unverified:` line listing what was not checked (`Unverified: nothing` when all of it was). End with one marker line directly above the `result:` line, which stays the final line because agent view takes its row from it:

- `✅ **Safe to close this session**` when nothing is left open: the work has landed, no question is pending and nothing waits on the user.
- `⚠️ **Keep open:** <what remains>` otherwise.

`claude-sessions-audit` and `session-sweep` read the marker, so write it exactly as shown.

The escape hatch is not asking in prose — it is not asking: when the decision is scoped, low-risk and reversible, take the default, state the assumption, and keep working.

Unscoped, irreversible or security-sensitive calls stay the user's however obvious one option looks; on conflict, ask. A subagent without `AskUserQuestion` returns the options plus a recommendation flagged `AMBIGUOUS:` for its caller to raise.

In worktree-isolated jobs, the CLI's git guard requires command text to prove all touched paths stay inside the worktree. It refuses:

- `git -C` outside the worktree, even reads — inspect parent refs with `git log main`, `git diff main...HEAD`, or `gh pr view`.
- Variable or `$(...)` command names, and variable revisions (`git show "$rev"` in a loop) — resolve first, invoke the literal text in a separate call. A blocked revision comes back empty rather than refused, so an unexplained empty `git show` is this.
- Git combined with heredocs or output redirection — separate git calls from file writes.
- Shell text that merely quotes git commands — write that content with Write or Edit.
