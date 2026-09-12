---
name: review-pr-queue
description: Work a backlog of open pull requests down to merged — read the review comments that are actually there, fan out one fixer per PR in its own worktree, verify each with an adversarial reader from another model family, and merge in an order that avoids conflicts. Use on "address the comments on these PRs", "review and merge the queue", "clear the PR backlog", when a repo has accumulated more open PRs than anyone wants to read, or when review feedback exists but nobody has acted on it.
---

# /review-pr-queue

A PR queue is not reviewed by reading pull requests one at a time. It is reviewed by establishing the real scope, fanning out one agent per PR, and spending the saved effort on adversarial verification — which is where the defects actually surface.

## Read the comments that exist, not the ones the API shows first

`gh pr view <n> --json comments,reviews` returns review objects with **empty bodies** when the substance is in inline comments. Those live on a different endpoint:

```bash
gh api "repos/{owner}/{repo}/pulls/<n>/comments" \
  --jq '.[] | "\(.path):\(.line // .original_line)\n\(.body)"'
```

Sweep both across every PR before planning anything. Half the real feedback is inline, and a fixer briefed from the PR description alone will address the wrong thing.

## Establish scope against the remote, never local main

Fetch first, then diff against `origin/main`. A local `main` even a few commits stale inflates every branch's diffstat with commits that are already upstream, and the queue looks far more entangled than it is.

```bash
git fetch origin main --quiet
git diff --stat origin/main...origin/<branch>
```

In one run this turned an apparent nine-way tangle into five disjoint single-file PRs plus three genuine overlaps. Plan the merge order from the corrected picture: disjoint singles first, then branches sharing a file, then any repo-wide sweep last so it also covers what just landed.

## One worktree per branch, made before dispatch

`isolation: "worktree"` creates a **fresh** worktree, not one on the PR's branch, so it is the wrong tool here. Create them yourself and hand each agent an absolute path:

```bash
git worktree add .claude/worktrees/rq-<branch> <branch>
```

Brief every agent to start each Bash command with `cd <absolute worktree path> && ...`. An absolute path in a prompt does not follow a worktree switch, so a vague brief silently writes into the main checkout. A branch already checked out elsewhere cannot get a second worktree — reuse the existing path rather than renaming anything.

## Fan out fixers, then verify with a different family

The shape that works is a two-stage pipeline: one fixer per PR, then an adversarial reader on any branch carrying executable code. Documentation-only branches can skip the second stage.

Verification is not optional theatre. Across one queue, adversarial readers returned blocking findings on **four of four** code-carrying branches, including two silent data-corruption bugs that every passing test suite had missed. A same-family agent reviewing the same session's work echoes it; the second opinion has to come from elsewhere.

## A subagent's review only counts once it is on the PR

Findings that live in a returned agent message are not a review: nothing on the pull request records that the branch was read, so the next person starts from zero and the merge has no stated reason. Run the loop so every stage leaves a trace on the PR itself — the reader posts its findings, the fixer lands the edit against them, and the merge happens only after both exist.

```bash
gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews -f event=COMMENT -F body=@findings.md
```

`event=COMMENT` is the only event available here — the self-approval row below says why. Post before merging rather than after, because the review thread of a merged PR is where the reasoning has to be found later.

A refused action belongs in that trace too. When the classifier denies a merge or an edit, quote its verdict text verbatim, name the exact diff it refused, and put both in the PR comment and in the closing summary — then stop and let the user look. Re-running the same intent in a different shape converts a decision the user should see into one they never hear about.

## Expect the first fix to be too narrow

This is the single most valuable lesson from running the loop. A fix is written against the reported input and is usually wrong for its near cousin:

- A builder was fixed to reject malformed URL *strings*, and still silently dropped a row when the value was `false`, `0`, or an empty list, because normalisation collapsed those to the "unpublished" placeholder before validation ran.
- An unwrapper was fixed to protect `<pre>` blocks across blank lines, and still corrupted them when the opening tag contained a pipe, because the table guard ran first and returned before protection was installed.

So brief the verifier to spend **most** of its effort hunting the neighbouring spelling, not re-running the suite. Budget for a third round; two rounds is normal, not a sign anything went wrong.

## Three rounds of losing to a new case means the design is wrong

The previous section says to expect the first fix to be too narrow. There is a threshold past which that advice inverts: once a defect has survived three genuine fixes, each defeated by a different input of the same shape, stop patching and change the design. Continuing is not diligence, it is building a worse version of something that already exists.

The signal is specific: each round's fix is *correct*, the tests pass, and the next adversarial reader finds a fresh case within minutes. That pattern means the code is re-deriving something it should be delegating, or the data model makes the bug expressible. Three worked examples from one queue:

- A Markdown tool hand-rolled block detection and lost four times — blank lines in raw HTML, a pipe on an opening tag, a block on a list-marker line, a literal fence delimiter inside a quoted example. The fix was to parse with a real CommonMark library and unwrap only inside paragraph token line-ranges, so every other construct is excluded by construction. It deletes code rather than adding it.
- An index builder kept dropping rows for metadata it could not read, and the detector meant to catch misfiled rows kept being defeated by a new filename. The question "is this file meant to be a row?" is undecidable from a name. Inverting it to "does every published artifact have a row?" is decidable, and a misfiled row then surfaces as a true, actionable message.
- Two persistence layers lost updates through six rounds of increasingly sophisticated reconciliation, including one that enumerated sixteen states and proved ten unreachable by invariant. Both stored every item in one shared document, making each write a read-modify-write with no compare-and-set available. Storing one item per key removes the conflict rather than resolving it.

Each rewrite was justified by an assumption nobody had re-examined. The persistence one was explicit in a comment: "a merge cannot express an untick, because deleting the key is the only way to say not-ticked." Storing an explicit false was always available. **When a design keeps failing, find the sentence that justified it and check whether it is true.**

Brief the rewrite to DELETE machinery, and ask for the net line change. If the diff grows, the new model was layered on the old one and every old bug is still there.

## Run the suite around a merge, and notice if there is no suite

A merged one-file change broke a test in one of these queues, and nothing caught it, because the repo had no way to run its own suites. Before merging, run whatever suite covers the change; after merging, run it again. If you cannot find a runner, that absence is itself the most valuable finding available — a repo whose CI has been failing for ten days on an unrelated job looks exactly like a repo whose CI passes, and a queue reviewed against invisible tests is reviewed against nothing.

When you do build or find a runner, make it distinguish a real failure from a skip for an absent optional dependency. A runner that reports every environment gap as a failure gets ignored within a week, which leaves the repo exactly where it started.

## Writing a defect brief an agent can act on

State the defect as established fact with its reproduction, name the file and line, then give the fix and the required regression tests. Demand the test **fail first** and require real command output at each step — a fixer that never watched a test fail has not shown the defect existed. Add the principle the fix serves ("this builder must never drop a row for metadata it cannot read"), because it generalises where a patch does not.

## Cross-cutting asks belong on their own branch

Review comments cluster. Several separate remarks usually turn out to be one request — "I want a single place to edit this" — and a comment saying "we should fix this globally" is a second piece of work, not an expansion of the PR it was left on. Give those their own branch and PR. It keeps each existing PR reviewable and stops one comment from doubling a diff.

## An uncommented PR is unreviewed, not approved

Split the queue by whether the user has actually looked at each PR, and never let the two halves share a fate. A PR carrying review comments has been read and is waiting on work. A PR carrying none has usually not been read at all — silence is the absence of an opinion, not consent to merge and not permission to close.

Acting on the commented half and saying nothing about the rest reports the queue as handled when most of it was never seen. So every run ends with an explicit list of what the user has not reviewed, with enough detail to triage each one without opening it: what it does, how old it is, whether it still merges, and a recommended disposition — merge, needs-a-decision, rebase-or-close, or stale. Say how many there are up front, because that number is the real state of the queue.

Where a queue has drifted for weeks, most of the unreviewed half is usually closeable rather than mergeable, and a stale-or-close recommendation is worth more than a review. Recommend; do not close anything unasked.

## Verify the facts a page or doc asserts

Any claim a merged page will carry gets checked against the system it describes. In one queue a published page stated a directory was empty; it held ~880K of backups, invisible to a plain `ls` because they were dotfiles. Re-run every scan a doc quotes, and drop any number whose source a reader cannot reach.

## A sweep tool's own corpus proves almost nothing

When a tool rewrites files in bulk, the repo's own files are a weak test — they may exercise none of the failure modes. Assert preservation on **constructed** inputs covering each protected construct, and assert idempotence directly: running the fixer twice must equal running it once. Keep the tool and the sweep in **separate commits** so either can be reverted alone.

## Known failure modes of the tooling

| Symptom | Cause and what to do |
|---|---|
| `gh pr edit --body-file` fails with a Projects-classic GraphQL deprecation error | Repo-wide, hits every agent, and it can report success while writing nothing. Use `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -F body=@<file>`, then confirm with `gh pr view <n> --json body` |
| `gh pr review --approve` fails: "Can not approve your own pull request" | The PR author and the authenticated `gh` account are the same person. Reviews can only land as `COMMENTED`, never `APPROVED`. Attempting it also trips a `[Self-Approval]` security flag — do not retry it, and say so if a merge gate wants an approval state |
| `gh pr merge` denied by the auto-mode classifier as `[Merge Without Review]` | Inconsistent: it may allow several then refuse. Post a real review first, and if it still refuses, ask rather than route around it |
| An adversarial reviewer dies with a cybersecurity content flag | Security prose trips a provider-side classifier. Measured on one sanitiser review: the OpenAI-routed seats died twice with an HTTP 400 content flag, Kimi completed the same brief, and GLM answered but stalled through six retries on one task. Re-route to Kimi first, and describe the mechanism in words — file and line, never payload text. See `claude/rules/sensitive-content.md` |

## Merge, and what to hold back

Merge what is disjoint and verified. Hold anything touching settings, hooks, CI or secrets for an explicit decision, and say plainly which PRs those are and why. Anything outward-facing — filing an upstream issue, publishing a page — is the user's call, so draft it into the repo and hand over the path rather than posting it.

Bundle every decision into **one** question set once the verdicts are in, rather than interrupting per PR.
