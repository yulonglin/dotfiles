# Background Jobs

In a background job (`~/.claude/jobs/`) a prose question reaches nobody — it renders into a job list that fires no notification, so the session just looks stalled. Every decision point goes through `AskUserQuestion`, followed by `needs input:` on its own line. Confirmations, option menus and "OK to proceed?" are decision points too.

The escape hatch is not asking in prose — it is not asking: when the decision is scoped, low-risk and reversible, take the default, state the assumption, and keep working.

Unscoped, irreversible or security-sensitive calls stay the user's however obvious one option looks; on conflict, ask. A subagent without `AskUserQuestion` returns the options plus a recommendation flagged `AMBIGUOUS:` for its caller to raise.
