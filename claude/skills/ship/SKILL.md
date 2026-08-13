---
name: ship
description: Use when the user says "ship this" or explicitly asks to review, finish, merge, and push implementation that is ready to deliver.
---

# Ship

Complete an authorized delivery path. This supersedes `finishing-a-development-branch` only when the user already selected merge and push.

## Authorization Boundary

Review fixes are in scope only when they stay within the original task files and preserve the approved design. Stop for a new dependency, public-interface change, new subsystem, or edit outside that file set. Run at most two review-fix rounds; then report any remaining material finding and ask.

## Shared Workflow

1. Record the original task file list. Run relevant tests and inspect the diff.
2. **REQUIRED SUB-SKILL:** Use `superpowers:requesting-code-review` with a code-review agent and a different model family when available.
3. Apply in-scope material fixes. Re-run tests and re-review with a review agent from a different model family when available. Repeat within the two review-fix rounds limit.
4. Commit only the task files; preserve unrelated user changes. Choose one delivery path below.

## Local-Merge Path

Use this path for a small, non-structural change.

1. In a worktree, use the repo worktree workflow. If its branch-name convention does not match, merge the branch manually from the parent checkout. Let that workflow resolve or escalate worktree-merge conflicts under its own rules.
2. Run the relevant tests again in the merged parent checkout.
3. Apply the fetch, state-check, sync, and push stages of `commit-push-sync` to the parent checkout and named parent branch. Do not stage unrelated parent-checkout changes. Stop on a remote-sync conflict, authentication failure, or non-fast-forward state that needs a user choice.
4. Verify the remote named parent branch contains the shipped commit.

## Pull-Request Path

Use this path for a large or structural change.

1. Push the reviewed feature or worktree branch. Do not merge or push the parent branch.
2. Open a tracked pull request against the named parent branch.
3. Verify the remote feature branch contains the shipped commit and report the PR URL.

## Report

Report the final shipped file list, test evidence, review rounds, commit, chosen delivery path, and push result.

## Quick Reference

| State | Action |
|---|---|
| In-scope finding | Fix, test, cross-family re-review |
| Out-of-scope finding | Stop and ask |
| Small, non-structural change | Local-merge path |
| Large or structural change | Pull-request path |
| Remote sync conflict | Stop under `commit-push-sync` policy |

## Common Mistakes

- Turning fixable findings into a new decision.
- Expanding review fixes outside the authorized file set.
- On the local-merge path, pushing the worktree branch after merging into the parent branch.
- On the pull-request path, merging or pushing the parent branch.
- Staging unrelated parent-checkout changes or force-pushing.
