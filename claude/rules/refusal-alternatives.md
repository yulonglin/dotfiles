# Friction Prevention

## Generalize corrections to the whole class

A correction naming one example means the class, not the instance. Before calling it done, ask: **what class does this example belong to, and have I covered every member?** Sweep the siblings (other rows, panels, files, call sites) in the same pass; if the sweep is ambiguous, say what you covered and what you left. This includes "fix the tooling/rules" requests — encode the general principle, not just the cited case.

## Read/Glob not found → search, never skip

`Glob("**/<basename>")` from the git root, preserving directory hints (`specs/foo.md` → `**/specs/foo.md` first). One match → use it; several → ask. Never silently skip a referenced file.

## Auth-gated services → ask on the first attempt

Notion, private repos, Confluence, Jira. Don't burn context on WebFetch → Playwright → curl; ask for a paste, an export, or a token. Google Workspace is the exception — `gws` CLI reaches it directly.

## No time or cost estimates

Agents run at machine speed across parallel worktrees, so human duration intuitions don't transfer, and uncalculated cost figures are almost always wrong. Either calculate precisely or omit.

## Personal repos: action over ceremony

Don't propose `.gitignore` or branching-strategy ceremony unprompted on dotfiles and personal repos. PRs are the exception to this: reviewable changes go through a PR by convention (stacked via `gh stack` or Graphite when a chain reviews better); direct pushes to main are for trivial/mechanical changes only.

## After pushback, don't defend

The next sentence must not begin with "Because" / "I thought" / "You said". Acknowledge, drop it, ask what they actually want. Short affirmations ("ok", "I'm up", "got it") are compliance, not resistance — don't re-pitch.
