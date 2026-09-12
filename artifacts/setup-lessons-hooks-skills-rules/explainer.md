# Six of the seven bugs were already fixed; the remaining diff is one section and one bullet

**Bottom line.** PR #132 (`18a0262`, already in `origin/main`) landed a `review-pr-queue` skill that documents items 1, 2, 3, 5, 7 and half of 4 verbatim. So the honest answer to "which ones should we learn from" is: the learning already happened for most of the list — it just happened in a file you have not read. What was genuinely missing is the sequence you described in your own words (comment with subagents, edit with subagents, then merge), the names of the model families that survive a security review, and three words in the background-jobs rule. That is the whole pull request.

The classifier ask is the one item with no clean fix. It is a procedure, not a hook, and this document says plainly what it cannot do.

## The moving parts, defined against files in this repo

### A hook is a script the harness runs, so it binds even when the model would rather not

A hook is a shell or Python script that Claude Code itself executes at a fixed moment in the loop — before a tool call, after one, when a session starts, when the model tries to stop. **The harness runs it, not the model.** That is the entire reason hooks exist: a written instruction is advice the model can forget, misread or reason its way past, while a hook is code that runs whether or not the model agrees with it.

Registration lives in `claude/settings.json`, keyed by event. The live events in this repo are `PermissionRequest`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart` and `SessionEnd`. A registration is a matcher plus a command:

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "$HOME/.claude/hooks/block_destructive_git.sh", "timeout": 5 }
  ]
}
```

That one refuses `git reset --hard`, `git checkout -- <path>`, `git clean -f`, bare `git stash` and `git stash pop`. `~/.claude` is a symlink to `claude/` in this repo, so the file on disk and the file under version control are the same file — editing a hook here changes your running environment immediately.

Three concrete ones worth knowing by name, all in `claude/hooks/`:

- `block_secret_expansion.sh` — `PreToolUse` on `Bash`. Stops a command that would expand a secret into a visible argument.
- `pr_after_push.sh` — `PostToolUse` on `Bash`, wrapped in a feature gate (`hook_feature.sh run git.pr-after-push`). It opens a draft PR when a branch is pushed. It did **not** fire for this task's branch, and `gh pr list` came back empty six seconds after the push, so I created PR #148 by hand. Whether that is the feature gate being off or the hook not running for a subagent, I did not establish.
- `approval_classifier.py` — `PermissionRequest`. Described in its own section below, because it is the reason item 3 is confusing.

The rule of thumb the repo already follows: a hook is worth writing when the failure is silent, mechanical and repeats. It is the wrong tool when the correct action depends on judgement, because a hook can only say yes or no to a string.

### A skill is a procedure loaded on demand, and costs nothing until it matches

A skill is a folder under `claude/skills/<name>/` holding a `SKILL.md` with YAML frontmatter — a `name` and a `description`. The description is the only part always in context; the body loads when a task matches. That makes a skill the cheap place for anything activity-specific.

`claude/skills/review-pr-queue/SKILL.md` is the worked example and the one this task extends. Its frontmatter description lists the triggers ("address the comments on these PRs", "clear the PR backlog"), and its body is 114 lines of procedure — how to read inline comments, how to scope against the remote, how to fan out one worktree per branch, and a "Known failure modes of the tooling" table that is literally the bug list you were handed, written down before you asked. That table is why six of seven items need no new work.

### A rule is always-loaded judgement, and the always-on tier is already over budget

Files in `claude/rules/*.md` load into **every session, forever**. So the bar is "relevant in every session", not "true and useful". Activity-specific procedure belongs in a skill; the repo's own standard adds that a new standard belongs in the checklist it governs (`claude/checklists/`), not in a rule.

This is measured, not a general warning. `tests/test_memory_tier_budget.py` sets a per-file ceiling on each rule and an aggregate ceiling on the whole always-on tier, and it is **red on `origin/main` today**, before any change of mine:

```
FAILED test_per_file_ceiling[claude/rules/background-jobs.md-1150] - 1342 > 1150
FAILED test_per_file_ceiling[claude/rules/communication.md-3100]   - 6011 > 3100
FAILED test_per_file_ceiling[claude/rules/delegation.md-2600]      - 3647 > 2600
FAILED test_aggregate_ceiling                                      - 30384 > 29900
7 failed, 12 passed
```

Run at commit `7e2df60` in a clean detached worktree. This is the strongest argument against "just add a rule for it": the tier is 30.5 KB against a 29.9 KB ceiling and nothing is enforcing the limit, so every new rule is paid for by every future session.

### An agent is a separate model instance with its own context and no memory of yours

A subagent is another model run given a brief, working in its own context window, returning a result. It does not see your conversation — `claude/rules/delegation.md` requires every dispatch to state TASK, CONTEXT with explicit paths, CONSTRAINTS and an OUTPUT cap for exactly that reason.

Two properties matter for the PR queue. First, an agent can be routed to a different model family, which is the only way to get a real second opinion; a same-family agent reviewing the same session's work echoes it. Second, an agent's working directory is set by its brief, and an absolute path written in a brief does not follow a worktree switch — which is why the skill insists every dispatched command starts with `cd <absolute worktree path> && ...`.

### `settings.json` permissions are static string rules; the classifier is a model that judges what they do not cover

`claude/settings.json` carries a `permissions` block with four relevant keys, currently 75 `allow` entries, 43 `deny`, 3 `ask`, and `"defaultMode": "auto"`. Entries are patterns over tool calls — `Bash(git reset --hard *)` in deny, `Bash(sudo *)` in ask, bare `Grep` in allow.

These are static. They cannot express "allow this if the user asked for it". That gap is what the classifier fills, and there are **two** classifiers, which is the source of the confusion in item 3:

- **The repo's own hook**, `claude/hooks/approval_classifier.py`, registered on `PermissionRequest`. It sends the pending call plus session context to a model, reads `claude/hooks/approval_classifier_rules.md` as its policy, and logs a verdict to `~/.cache/claude/approval-classifier.log` in the form `DENY: Bash — <prose reason>`.
- **Claude Code's native auto-mode classifier**, active because `defaultMode` is `auto`. It emits bracketed category labels. The `auto-mode-probe` skill exists to test it and names one of its categories, `Credential Materialization`.

Evidence they are different, from the live log: `grep -c "Merge Without Review"` returns **0** and `Self-Approval` returns **0**, while `Self-Modification` returns **1** — and that single hit is prose inside a reason string, not a bracketed label. So the `[Merge Without Review]` and `[Self-Approval]` flags in your bug list came from the **native** classifier, which no file in this repo governs.

Order of operations, plainly: a static `deny` or `ask` entry settles the call outright. Anything not settled reaches the classifiers. A verdict of `unsure` does not block — it prints a warning and falls through to a normal permission prompt.

## The seven bugs, one verdict each

### 1. `gh pr edit --body-file` writes nothing — already in the skill, one clause added

**What happened.** Every agent that tried to set a PR body hit a Projects-classic GraphQL deprecation error, and the body was not written. The workaround is `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -F body=@<file>`.

**Why.** `gh pr edit` resolves the PR through a GraphQL query that touches Projects-classic fields GitHub has retired. The REST endpoint does not.

**Where the fix belongs: the skill, and it was already there** — `review-pr-queue` table row 1, verbatim including the `gh api` replacement. I added one clause: the command can report success while writing nothing, so confirm with `gh pr view <n> --json body`. That is the part that turns a known bug into a check you actually perform. Nowhere near a hook: this is a fact about one CLI subcommand in one situation, and a hook that intercepted `gh pr edit` would fire in repos where it works fine.

### 2. GitHub refuses self-approval — a fact to know, not a bug to fix

**What happened.** `gh pr review --approve` errors because the PR author and the authenticated `gh` account are the same person. Attempting it also trips a `[Self-Approval]` flag.

**Why.** GitHub's own API rule. Nothing local is involved.

**Where the fix belongs: nowhere.** It is already table row 2 of the skill, including the operationally important half — reviews can only land as `COMMENTED`, and if a merge gate wants an approval state you say so rather than retrying. Retrying is what trips the flag, so the guidance is "know this", and it is written down.

### 3. The classifier denied merges inconsistently — a procedure, and it gets its own section below

**What happened.** Four `gh pr merge` calls were allowed, then one was denied as `[Merge Without Review]`. A settings edit was denied as `[Self-Modification]`.

**Why, in part.** The `[Merge Without Review]` label is the native classifier's, which nothing here configures. The `[Self-Modification]` half has a documented cause in this repo — see the compound-command finding below.

**Where the fix belongs: the skill, as behaviour after a denial.** Already partly there (table row 3: post a real review first, and if it still refuses, ask rather than route around it). I extended it with what you asked for — surfacing. Details in the dedicated section.

### 4. OpenAI-routed reviewers died on a content flag — the skill needed the family names

**What happened.** Adversarial reviewers routed to OpenAI models died twice with an HTTP 400 cybersecurity content flag while reviewing a sanitiser. Kimi completed the same work; GLM answered but stalled through six retries on one task.

**Why.** A provider-side classifier reads security prose out of its frame. `claude/rules/sensitive-content.md` documents the same failure from the Anthropic side and its conclusion applies here: the vocabulary *is* the research, so rewriting to dodge the classifier degrades the work. Rerouting is the fix.

**Where the fix belongs: the skill's failure-mode table.** Row 4 already said "route that one review to a different family", which is unactionable without knowing which family. I added the measurement — OpenAI 400s twice, Kimi completes, GLM stalls — and made Kimi the named first re-route.

**What I deliberately did not do:** put this in `claude/rules/delegation.md` or the `council` skill. Delegation is always-on and already 3647 bytes over a 2600 ceiling. `council` is about panel composition, not about which seat survives a security review. And the finding is provider-drift-prone — it is one observation about today's endpoints, which is exactly the kind of thing that belongs in a table row that gets corrected, not in a rule loaded into every session for a year.

### 5. Stale local `main` made five disjoint PRs look like a nine-way tangle — already in the skill

**What happened.** Local `main` was three commits behind at session start, so every `git diff main...branch` included commits already upstream, inflating each diffstat.

**Why.** `main...branch` is computed from the merge base with your *local* `main` ref, which a `git fetch` updates and nothing else does.

**Where the fix belongs: the skill, and it is already there** — the section "Establish scope against the remote, never local main", complete with the commands and the exact outcome from that session ("this turned an apparent nine-way tangle into five disjoint single-file PRs plus three genuine overlaps"). I changed nothing.

A hook was worth considering here and I rejected it. A `PreToolUse` hook could refuse `git diff` against a stale local `main`, but "stale" needs a network round trip on every diff, the correct base is not always `origin/main`, and the failure is loud once you know to look for it. A skill line costs nothing and covers it.

### 6. A variable revision inside a loop returned empty — three words added to the rule

**What happened.** `git show` with a variable revision inside a loop silently returned empty output under the background-job git guard.

**Why.** In a worktree-isolated background job, the CLI's git guard requires the command *text* to prove every touched path stays inside the worktree. A revision it cannot read statically cannot be proven safe.

**I could not reproduce this.** I ran the literal and variable forms back to back in my worktree and both printed identical output with exit 0. The reason is that this job is not worktree-isolated, so the guard was not active. The guard is in the Claude Code CLI, not in this repo, so there is nothing here to test it against. I am recording your report as the source.

**Where the fix belongs: `claude/rules/background-jobs.md`, extended by one clause.** PR #119 (`65822c3`) already added a four-bullet list of what the guard refuses, and one bullet covers "variable or `$(...)` **command names**". A variable *revision* is an argument, not a command name — genuinely not covered. I widened that bullet to name revisions and added the symptom, because the discrepancy is the dangerous part: the rule describes a guard that *refuses*, and what you saw was empty output. A refusal you can see costs a retry; an empty result you cannot see produces a confidently wrong answer.

The cost is honest: this file was 1342 bytes against a 1150 ceiling before my change and is 1477 after. I judged 135 bytes worth it for a silent-wrong-answer failure mode, but the tier being over budget is a real finding for you, not a footnote.

### 7. Inline review comments are on a different endpoint — already in the skill

**What happened.** `gh pr view --json reviews` returned review objects with empty bodies. The substance was in inline comments.

**Why.** GitHub models a review and its inline comments as separate resources. The review object carries only the summary body, which is empty when the reviewer wrote only line comments.

**Where the fix belongs: the skill, and it is the very first section** — "Read the comments that exist, not the ones the API shows first", with the `gh api repos/{owner}/{repo}/pulls/<n>/comments` call and its `--jq`. I changed nothing.

## Surfacing a classifier rejection: what it can and cannot be

You wrote: *"When there's a rejection, show me the exact diff and rationale. Or surface in PR for me to review. I feel like this should maybe be a skill or rule."*

**A skill, and I built it into `review-pr-queue`. Here is the honest limit first: nothing in this repo can veto a classifier decision.** The native auto-mode classifier runs inside the CLI. Even the repo's own `approval_classifier.py` runs as a hook and returns a verdict; a second hook cannot overrule the first. So "surface the rejection" cannot mean "and then proceed". The only thing a rule or skill can change is what the model does **next** — and the default next action, which is to quietly rephrase and retry, is the one that actually harms you. It converts a decision you should see into one you never hear about.

What surfacing means concretely, and what I wrote into the skill:

- Quote the verdict text **verbatim**. Not "the classifier objected" — the actual sentence. The repo hook's reasons are prose and often name the specific thing that tripped it; the log line for the one `Self-Modification` denial on record reads in part *"this is inspecting the agent's own permission/settings configuration ... rather than routine project work — no clear user instruction in recent messages directs this specific inspection"*, which tells you the fix is a sentence of intent, not a permission change.
- Name the exact diff or command that was refused.
- Put both in a real PR comment **and** in the closing summary, so it survives in the place the decision lives.
- Then stop. Do not re-run the same intent in a different shape.

**The data point that makes this concrete, and it is not what it looks like.** In this session's predecessor, a compound `git commit && git push` of a `claude/settings.json` change was denied as `[Self-Modification]`, while the same commit split into separate calls went through. That reads like an evasion recipe. It is not — it is documented behaviour. `claude/hooks/approval_classifier_rules.md` states:

> Chained commands joined with `&&` are one action — evaluate the whole chain.

So the compound call was judged as a single action containing a settings modification, and denied on its most sensitive component. The split calls were judged individually, and each one on its own did not match. That is the policy working as written, not a bug.

The right lesson is therefore **not** "split the command to get past it", and I deliberately did not write that anywhere. It is that one Bash call should do one thing, so each verdict is about one action — which the background-jobs rule already says for a different reason ("separate git calls from file writes"). If a split call is *itself* denied, that is a real answer: ask.

**The genuinely unexplained part stays unexplained.** A subagent pushed an equivalent settings change without being blocked at all, and four merges were allowed before one was refused. Both point at the classifier seeing different context in different runs, which the repo has already been bitten by once — the `## Learnings` entry dated 2026-09-08 records that the extractor had been feeding the classifier an empty string for five months. I did not investigate further; if it recurs, `~/.cache/claude/approval-classifier.log` and the `CONTEXT: users=N tools=M` line are where to start, and a subagent's own PermissionRequest verdicts landing in that same log would settle whether subagents are classified at all.

## Reviewing with subagents, then merging: the sequence, written down

You wrote: *"I mean, we should leave comments when reviewing with subagents, and edit with subagents? Then that's when we merge."*

That is a real gap and it is now a section in `review-pr-queue`. The skill already fanned out fixers and verifiers, but the verifier's findings only ever existed in a returned agent message. Nothing on the pull request recorded that the branch had been read, so the merge had no stated reason and the next reader started from zero.

The sequence the skill now states: the adversarial reader **posts** its findings to the PR as a `COMMENT` review, the fixer lands the edit against them, and the merge happens only after both exist. Posting comes before merging, because the review thread of a merged PR is where the reasoning has to be found later. And a refused action belongs in that same trace, which is where this joins the previous section.

## What I did not build, and why

- **No new rule file.** Nothing on this list is relevant in every session — six items are specific to working a GitHub PR queue and one is specific to worktree-isolated background jobs. The always-on tier is already 30.5 KB against a 29.9 KB ceiling with the test red.
- **No new hook.** Every candidate fails the same way: a hook can only pattern-match strings, and each of these needs either a network check (item 5), a judgement call (item 3), or knowledge of a remote API's shape (items 1 and 7). The one mechanical candidate — intercepting `gh pr edit` — would misfire in every other repo, since the bug is not universal.
- **No change to `approval_classifier_rules.md`.** Loosening the classifier is a security decision and yours to make. My reading is that it behaved correctly on the compound command; the inconsistency is worth investigating before anything is relaxed.
- **No change to `claude/rules/delegation.md` or the `council` skill** for the model-family finding, for the budget and drift reasons in item 4.

## Where this landed

The explainer is this file. The code change is **PR #148**, https://github.com/yulonglin/dotfiles/pull/148 — two files, 15 insertions, 3 deletions.
