# Skill and Rule Clarity Audit

**Contradictions and buried authority are the problem, not length.** Two other-family audits, compared against Lauren Tan's pstack, found places where a cold-reading agent would plausibly take the wrong path in 12 skills, 13 agents (four of them the review critics, listed as one item) and 6 rule files. The worst are contradictory instructions (two paragraphs that disagree on what to do) and permission gates that come after the action they gate. Shortening prose comes second. Six skills, three agent types and three rule passages are clear and should be left alone.

Audited 3 Nov 2026 at commit `e2510cda`. Skills audited by GPT-6.1 Sol; agents and rules by GPT-6 Astra; spot-checks and this page by Claude Opus 5.5. Mark each item below as fix, skip or discuss; comment on any row.

## How to read this page

- **Source.** Every finding cites `file:line` at commit `e2510cda`. Paths are relative to `/home/yulong/code/dotfiles/`.
- **Verified** means Claude Opus 5.5 read the cited lines and confirmed the finding. **Reported** means one auditor found it and nobody has re-checked it.
- **Predicted mistake** is what an agent could plausibly do wrong. It is a judgement, not a measured failure rate.
- **Confidence.** About 90% that the cited contradictions are real. The ranking order is judgement.

## Seven patterns make pstack easier to follow

pstack is not uniformly concise; its router and `arena` have dense paragraphs too. What it does consistently is expose the next action. These patterns are worth borrowing; its permissions and router are not.

| Pattern | pstack does | Ours does instead |
|---|---|---|
| Route neighbouring tasks by name | `how`: "Use why for motivation" | `council` description lists six panel types and "before publishing a result" with no default route (`claude/skills/council/SKILL.md:3`) |
| Procedure before reference | `figure-it-out` opens with Phase A, B, C and a handback (`figure-it-out.md:14-51`) | `server-storage-tiering`'s procedure starts after four sections of mechanics (`SKILL.md:45-74,121`) |
| A test, not pressure | `tdd`: "Confirm it fails for the intended reason" | `diagnosing-bugs`: "Be aggressive. Be creative. Refuse to give up." (`SKILL.md:16`); its later red-capable gate is good |
| Bounded retries with a named exit | `babysit`: three rounds, then stop and hand back | `review-pr-queue`: "Budget for a third round", then a redesign rather than an exit (`SKILL.md:67-81`) |
| Literal handback | `figure-it-out` names each item the reply must contain | `tufte-data-viz` never says whether it returns defects, an edited chart or a verdict (`SKILL.md:19-40`) |
| One rule per decision | `arena`: "proceed with N-1 and note the dropout" | `council` both allows and forbids retrying the surviving seats (`SKILL.md:81` vs `:94`) |
| One gate per sentence | `unslop`: "One idea per sentence" | `server-storage-tiering:59` packs eight independent checks into one list item |

## Decisions for Yulong

### One policy choice blocks the rest

- [ ] **Document authority: editable source or immutable snapshot?** `claude/rules/safety.md:11` says a published copy "is never edited or synced back"; `claude/CLAUDE.md:48` and `CLAUDE.md:13` prescribe editable Artifacts with a suggested-edits round trip. Lean: one named editable source, published pages rebuilt only from it, reviewed suggestions merged into that source. Rewrite proposal: *"Name one editable source. Published views update only from it. Merge reviewed Artifact suggestions into that source; never overwrite unreviewed user edits."* Reported by Astra; the two quoted lines verified.

### Contradictions an agent cannot resolve alone

- [ ] **`review-draft` and its four critics: told to write files and ask questions with tools they lack.** `claude/agents/clarity-critic.md:5` declares `tools: Read`, while lines 47-59 tell it to use AskUserQuestion and write `feedback/{draft}_clarity.md`; `narrative-critic`, `fact-checker` and `red-team` match. `review-draft/SKILL.md:36-57` then reads those files. Predicted mistake: a critic claims it wrote feedback, or the parent waits for files that cannot exist. Fix: critics return structured findings; the parent supplies the audience and writes the files. **Verified.** Both auditors found it independently.
- [ ] **`council`: retry the survivors, or never retry them.** Line 81: "Retry, or seat the survivors explicitly". Line 94: "do not retry with `--panel` trimmed to whoever answered". Its routing table also gives `advisor` first while another paragraph makes `advise` the default (`:23,33-37`). Fix: one routing table and one missing-seat policy; move roster upkeep and incident notes (`:120-157`) to a reference. **Verified.**
- [ ] **`merge-worktree`: leave an unclear conflict, or take the worktree's side?** Line 120: "If you cannot confidently resolve a conflict, leave it". Line 139: "Prefer the worktree's version when … intent is unclear". Fix: keep only the stop branch, and replace the settings-file exception at `:44-46` (which treats real value changes as disposable) with an ownership check. **Verified.**
- [ ] **`artifact-writing`: two capability declarations disagree.** Line 63 promises Download and Copy HTML on annotated pages; the capability object at `:104-108` is the one `md2artifact --capabilities` prints. The generated page calls `claude.use("downloads")`, but the object omits `downloads`, so Download HTML shows disabled (pointing at Copy HTML) on every page published with it. Fixed in PR #298: `md2artifact --capabilities` now prints `downloads`. Still to do: keep one declaration in the skill, and put a short new-page / update / refused-update procedure before the parser internals. **Verified**: publishing this page with the printed object raised the Artifact tool's undeclared-`downloads` warning.
- [ ] **`artifacts-sync`: a page in the listing is mapped back to live.** The reconcile table (`:120-125`) sets live for any same-org listed page, overwriting the done, archived and superseded states defined at `:63-71`. Fix: keep availability and editorial status as separate fields. Reported by Sol.
- [ ] **`code-reviewer`: a stale rule rated CRITICAL.** Lines 20, 35 and 44 flag "agent mentions in commits" as a critical CLAUDE.md violation; no current rule bans it, and every commit this session carries a `Co-Authored-By: Claude` line. Fix: cite the governing rule for any policy finding, and keep severity aligned with the real-output or security gate in `coding-conventions.md:13`. **Verified.**

### Gates that stall unattended work

- [ ] **`research-engineer` stops on warnings.** `claude/agents/research-engineer.md:146-166`: on a blocking gap it says "STOP"; on warnings alone it asks "Proceed anyway? [Y/n]". A background worker has nobody to answer. Fix: *"Resolve reversible implementation details and record assumptions. Return missing scientific decisions to the caller. Do not launch until the pilot and spend gates pass."* Also drop its argparse and click advice (`:79,93,188`, the stack is cyclopts) and its API-keys-in-`.env` advice (`:83`, keys come from `secrets`). **Verified** for lines 146-166.
- [ ] **`autonomous-researcher`: "never ask, never stop early".** Absolutes at `:16-20` conflict with its own error-table stops. Fix: *"Work autonomously within the approved spec and budget. Stop and return AMBIGUOUS for new scope, safety or approval decisions."* Reported by Astra.
- [ ] **`review-pr-queue`: authority comes after action.** Collecting, dispatching fixers and posting reviews (`:10-58`) come before the reviewed-versus-unreviewed split and the merge-hold rules (`:97-126`). Fix: reorder to scope and permissions, collect, partition, fix, verify, merge or hold, report. Reported by Sol.
- [ ] **`jobs` still recommends the retired headless worker.** `claude/skills/jobs/SKILL.md:10,18,51,59,83-85` against `claude/rules/delegation.md:17` (retired 2026-09-02). Fix: open with one current runner-by-shape table. Reported by Sol.

### Examples that would be copied as facts

- [ ] **`transcript-reviewer` turns a selected sample into a run-wide rate.** The worked example at `:139-142` reads 8 of 100 samples, finds 4 of 5 failures mis-scored, and reports "Estimated 15-20% of failures"; another example trusts a whole run after seven samples (`:155-157`). Fix: *"Report problems among reviewed samples. Do not estimate run-wide prevalence without a sampling design."* **Verified.**
- [ ] **`data-analyst` states its statistics policy five times, differently.** `:29-36,97-120,197-207,264,272-280` alternate between "CI or SE" and "always CI", and set the question as the unit without the qualifications in `checklists/results-analysis.md`. Fix: make the checklist the single owner; keep a short contract (name the estimand, the independent unit, pairing and uncertainty sources before computing intervals). Reported by Astra.
- [ ] **`application-writer` and `paper-writer` embed claims as examples.** Biographical results, novelty claims and wrong word counts (Astra counts 108 words where the example says 148, and 157 where it says 176) sit in reusable instructions (`application-writer.md:121-160`, `paper-writer.md:144-168`). `paper-writer` also forbids any AI-assistance disclosure, which some venues require. Fix: placeholders instead of claims; measure word counts; follow venue disclosure rules. Reported by Astra.
- [ ] **`experiment-designer` prescribes a canned schedule.** Fixed stage durations and sample counts (`:29-33,122-125,159-162`) with no measured rates, against `communication.md`'s no-uncalculated-estimates rule. Fix: decision gates, and estimates only from measured rates. Reported by Astra.
- [ ] **`efficient-explorer` claims Haiku.** Frontmatter says `model: inherit`; line 18 says "Uses haiku model for speed". Fix: delete the claim. **Verified.**

### Skills whose order hides the path

- [ ] **`docs-search` advertises an interface it does not implement.** Usage examples show filters and a 20-result limit; the shown script forwards options and caps 100 lines (`:12-17,41-60,94-110`). Fix: one real interface, stated truncation. Reported by Sol.
- [ ] **`gmail-connector` blurs evidence and reconstruction.** It supplies an API-body reconstruction workflow (`:57-72`) that `evidence-packs` (`:8-12`) rejects as evidence. Fix: label reconstructions as working material that never clears the evidence gate. Reported by Sol.
- [ ] **`tufte-data-viz` competes with `house-plots` and `dataviz`.** Fix: narrow it to a post-render review that returns ranked defects. Proposed description: *"Review a rendered chart for readability and misleading presentation. Apply house style and evidence rules first; return ranked defects, not a redraw."* Reported by Sol.
- [ ] **`server-storage-tiering`, `commit-push-sync`: the numbered procedure starts late or skips.** `commit-push-sync:15` can say push before the commit step, and refers to a Step 4 that does not exist. Fix: one numbered sequence each, gates before every move. Reported by Sol.

### Always-loaded bytes that could move

The byte ceiling was removed on 3 Nov in PR #296 (tier now 34,932 bytes), so these no longer fix a failing test. They still cut what every session pays for. Astra's estimates; nothing moved yet.

- [ ] **Move four always-on passages into the skills that own them, saving about 2,577 bytes.** `sensitive-content.md:7-9` (model-switch history, about 1,005 bytes) to a router troubleshooting doc; `background-jobs.md:9-14` (worktree git-guard recipe, about 520) and `delegation.md:17` (launch-tool history, about 458) to `jobs`; `communication.md:13` (generated-page mechanics, about 594) to `presentation.md`. Each keeps a one-line trigger in the rule.
- [ ] **Move `.claude/rules/dotfiles-settings.md:14-26` into a doc, saving about 6,547 bytes in this repo.** Keep the required-key check (`:7-12`) and the global-versus-project scope (`:28-31`); move gateway history, version measurements and repair steps to `docs/claude-settings-operations.md`.
- [ ] **Split `delegation.md:13-17`** into self-check, independent review, factual verification and process ownership, one sentence each.

## Overlapping pairs: what each side does better

| Ours | Theirs | Verdict |
|---|---|---|
| `deslop` | `deslop` + `unslop` | Ours is already well bounded (uncommitted changes only, 1-3 sentence report). Borrow pstack's one sentence on preserving behaviour. `unslop` is a separate prose task. |
| `diagnosing-bugs` | `figure-it-out` | Different jobs. Ours has the stronger gate (no fix without a red-capable loop). Cut its motivational preamble; borrow `figure-it-out`'s phase outline and handback. |
| `council` | `interrogate` + `arena` | pstack splits defect-finding from build-and-graft; ours bundles routing, sizing, briefing, upkeep and recovery. Ours is the only one that crosses model families. Fix the contradiction first. |
| `debrief` | `ketchup` | Different handbacks (a commentable page versus a chat catch-up). `catch-me-up` now covers the chat case. `debrief` needs a short end-to-end entry sequence. |
| `review-pr-queue` | `babysit` | Ours needs multi-PR scope and merge order, but it should expose its loop the way `babysit` does. |
| `clear-writing` | `unslop` | Ours is correctly thin (routes to `writing.md`). `unslop` pairs each pattern with an edit; replace our framework synopsis with one first-action sentence. |

## These are clear and should stay as they are

"Leave alone" means no structural rewrite for clarity, not that every command inside was tested.

- **Skills:** `ship` (authority boundary, two-round limit, two delivery paths); `read-paper` (grounding rules, then four ordered tasks); `llm-judge` (per-sample actions and an auditable schema); `externalise-handover` (reader's needs, enumerated handback); `evidence-packs` (what qualifies and how to record a gap); `wrap-up` (long, but every state and exit is explicit, which shows length is a poor proxy for unclarity).
- **Agents:** the generated foreign-model wrappers (thin by design); `context-fetcher` (one job, a two-thread cap, explicit non-goals); `llm-billing` (a clear stop rule).
- **Rules:** `experiments.md` (two pilot gates and a spend gate); `background-jobs.md:3-7` (how decisions reach a person); the hard limits in `safety.md` (quarantine, binary checks, draft-only email, desktop consent).

## Method

- **Inputs.** 61 skills (the six just ported from pstack excluded), 33 agents (the generated wrappers assessed once through `custom_bins/model-router-wire:209-222`), all of `claude/rules/` and `.claude/rules/`, both CLAUDE.md files, and `claude/checklists/writing.md` as the standard. The yardstick was 28 pstack skills and its router from [pstack-claude](https://github.com/michael-denyer/pstack-claude).
- **Readers.** Skills: GPT-6.1 Sol (high effort). Agents and rules: GPT-6 Astra (high effort). Both were briefed fresh, without this session's conclusions. Claude Opus 5.5 re-read the cited lines for every item marked verified.
- **Not done.** No workflow was executed, and trigger accuracy was not measured. A finding is a static reading of the text.
- **Related pages.** [Rigour Checks Review](https://claude.ai/artifact/BsHW8Yo2cmJLGyLEfL4XaX) (12 Oct) rated 75 research-integrity checks and found five contradicting pairs; [Context Ledger](https://claude.ai/code/artifact/439482e4-0d10-4715-a7d1-add2805e614a) (30 Aug) measured per-session context cost and usage.
