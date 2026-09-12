# Background Jobs

In a background job (`~/.claude/jobs/`) a prose question reaches nobody — it renders into a job list that fires no notification, so the session just looks stalled. Every decision point goes through `AskUserQuestion`, followed by `needs input:` on its own line. Confirmations, option menus and "OK to proceed?" are decision points too.

The escape hatch is not asking in prose — it is not asking: when the decision is scoped, low-risk and reversible, take the default, state the assumption, and keep working.

Unscoped, irreversible or security-sensitive calls stay the user's however obvious one option looks; on conflict, ask. A subagent without `AskUserQuestion` returns the options plus a recommendation flagged `AMBIGUOUS:` for its caller to raise.

In worktree-isolated jobs, the CLI's git guard requires command text to prove all touched paths stay inside the worktree. It refuses:

- `git -C` outside the worktree, even reads — inspect parent refs with `git log main`, `git diff main...HEAD`, or `gh pr view`.
- Variable or `$(...)` command names, and variable revisions (`git show "$rev"` in a loop) — resolve first, invoke the literal text in a separate call. For a revision the refusal surfaces as empty output, not an error, so an unexplained empty `git show` is this.
- Git combined with heredocs or output redirection — separate git calls from file writes.
- Shell text that merely quotes git commands — write that content with Write or Edit.
