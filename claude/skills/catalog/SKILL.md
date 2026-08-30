---
name: catalog
description: |
  A human-facing index of every skill and agent in this repo, grouped by category, with a one-line trigger for each. Use only when the user explicitly asks "what skills do I have", "what can you do", "is there a skill for X", or invokes `/catalog` directly — never fires on its own.
disable-model-invocation: true
---

# Catalog

One place to look up what already exists instead of re-discovering it mid-task. This file is the `catalog` skill itself; it only fires when asked for by name, so it does not compete for context on other requests.

Most skills below are **model-invoked**: Claude fires them automatically when your request matches the trigger phrase, so you don't need to remember exact names. A few are **user-invoked only** (marked below) — Claude never reaches for these on its own, so the name is the only way in.

Everything here lives in this repo under `claude/skills/` and `claude/agents/`, except the rows prefixed `superpowers:`, which come from the one enabled plugin that still carries skills worth reaching for and have their own section near the end. The `writing:`, `research:`, `core:`, `code:`, `workflow:`, `viz:` and `dev-browser:` plugins are disabled — what was worth keeping from them now lives here under a bare name.

## The standards live in checklists, not skills

The five files at `claude/checklists/` say what good looks like. They are **not** skills and are never invoked; skills route to them, so the standard is written once and loaded on demand. **These are the files Yulong edits** — a rule belongs in the checklist it governs, not in a new skill.

| Checklist | The question it answers | Routed to by |
|---|---|---|
| `writing.md` | Will the reader finish holding the idea I meant? | `clear-writing`, `review-draft`, `review-paper`, `deslop` |
| `presentation.md` | Can a busy reviewer get the findings in minutes? | `research-presentation`, `slidev`, `artifact-writing`, `tufte-data-viz`, `tikz-diagrams` |
| `results-analysis.md` | Is the claim supported, and can a reader check it? | `results-artifact`, `check-prose-claims`, `read-paper` |
| `research.md` | Is this worth running, and could it come out the other way? | `spec-interview-research`, `research-loop` |
| `experiments.md` | Will this run finish, and will I trust it when it does? | `jobs`, `mats-slurm`, `research-loop` |

`checklists/results-analysis/` holds domain subskills — what the generic standard cannot say about one research area: `monitoring.md` (usable verbatim as an analysis prompt), `jlens.md` and `sandbagging.md`. Reach for the subskill by path when the work is in that area; nothing routes to `jlens.md` or `sandbagging.md` automatically.

`claude/rules/research-core.md` is the always-loaded companion and owns the red lines rather than the craft. A standard you cannot find there is delegated to a checklist, not missing.

## Writing and reviewing prose

| Skill | Use when |
|---|---|
| `clear-writing` | Drafting or revising anything a reader must follow — paragraph structure, sentence mechanics, claim calibration, the LLM tics to cut |
| `review-draft` | "review my draft", "run the critics", "tear this apart" — dispatches the critic panel in parallel, or one lens on its own |
| `review-paper` | "review this paper", "critique this manuscript" — ML/AI research writing against Neel Nanda's criteria |
| `reduce-ambiguity` | "is this clear", "will this be misread" — red-teaming a draft before it is sent or acted on |
| `check-prose-claims` | Fact-checking stats, comparatives and quotes in slides, reports and PDFs |
| `check-bib-references` | Verifying BibTeX citations aren't LLM-fabricated |
| `strategic-communication` | Messages needing negotiation or persuasion — rentals, salary, declining an offer |
| `externalise-handover` | Handing this conversation to another person or agent — next tasks, what ran, bugs, open uncertainties |

## Artifacts, specs and slides

| Skill | Use when |
|---|---|
| `artifact-writing` | Publishing or updating any report, plan, findings page or transcript view as an Artifact — md2review, the annotation layer, republishing, viewer sandbox quirks |
| `artifacts-sync` | Recording a published artifact in `ARTIFACTS.md`, or reconciling the index after a link 404s or an org switch |
| `spec-artifact` | Writing a spec or plan — the three mandatory sections, per-requirement variables |
| `results-artifact` | The statistics for a results page — which interval or test a number gets, the four nulls, chance correction, when to slice |
| `research-presentation` | Structuring a research update, deck, findings page or figure for a reviewer |
| `slidev` | Building, previewing or exporting a Slidev deck, and fixing a slide that overflows or renders blank |

## Charts and diagrams

| Skill | Use when |
|---|---|
| `house-plots` | Any matplotlib figure — pastel defaults, the palette, overlap checking. Code lives in `lib/plotting/` |
| `tufte-data-viz` | The chart-quality pass — reviewing or styling any chart, in any library or medium |
| `tikz-diagrams` | A conceptual (non-data) diagram for a LaTeX paper — pipelines, architectures, eval flows |

## Designing research

| Skill | Use when |
|---|---|
| `spec-interview-research` | "spec this experiment" — hypotheses, variables, controls, baselines, sample size, before any code |
| `spec-interview` | The same interview for a large software feature — implementation, UX, tradeoffs |
| `read-paper` | Reading a PDF or arXiv link, a literature review, or explaining a concept that needs the source |
| `sweep-ai-safety` | "sweep AI safety", "what's new in alignment" — recent work from curated sources |

## Running experiments and infra ops

| Skill | Use when |
|---|---|
| `jobs` | Submitting experiments or agent jobs with resource caps, queue status, sandbox failure modes |
| `modal` | Cloud GPU or serverless compute — training, batch jobs, serving |
| `mats-slurm` | A GPU job on the MATS cluster — `grun`, `gbatch`, queue and log watching |
| `inspect-ai-evals` | Silent failure modes running `inspect_ai` against vLLM/Modal/RunPod endpoints |
| `research-loop` | "run experiments overnight", "automate this research" — interviews you into a `program.md`, then launches the `autonomous-researcher` agent |
| `llm-judge` | Building an LLM judge that scores text by meaning — prompt design, blinding, fan-out, JSONL persistence |
| `server-storage-tiering` | Root disk near full on a server or cloud box with an attached volume |
| `spawn-session` (user-invoked only) | Starting a detached Claude session in another directory with a seed prompt |

## Reaching another model family

| Skill | Use when |
|---|---|
| `second-opinion` | "sanity check this", "am I wrong", adversarial review — routes to Fable, codex-companion, OpenCode |
| `openrouter-fusion` | A multi-model panel with judge synthesis, one non-Anthropic model, or the raw OpenRouter API reference |

## Code, git and session workflow

| Skill | Use when |
|---|---|
| `commit` | "commit this", "commit these changes", "save my work" |
| `commit-push-sync` | "commit and push", "sync changes", "update remote" |
| `ship` | "ship this" or review, finish, merge, and push an authorized completed change |
| `merge-worktree` | "merge this worktree", "merge my branch back", "finish this worktree" |
| `superpowers:finishing-a-development-branch` | Implementation is done, tests pass, deciding merge/PR/cleanup |
| `diagnosing-bugs` | "diagnose"/"debug this", something broken/throwing/failing/slow |
| `deslop` | Before committing agent-written code — narrating comments, defensive guards, needless abstraction |
| `mv-repo` | Moving a repo to a new directory (venv, project state, symlinks, tmux sessions) |
| `wrap-up` (user-invoked only) | A stalled session needs a terminal state — land it, state the blocker, or take one step |
| `done` | "done", "finished", "ship it" — titles the finished session and hands back the `/rename` line |

## Searching and the shell

| Skill | Use when |
|---|---|
| `docs-search` | Grep-based search across docs, specs and CLAUDE.md files with `fd` + `rg` |
| `fast-cli` | Which modern CLI to reach for — `eza`, `fd`, `rg`, `bat`, `dust`, `duf`, `fzf`, `jq`, `delta` |

## Browser automation

| Skill | Use when |
|---|---|
| `agent-browser` | CLI-driven browser automation — navigate, fill forms, screenshot, scrape; opens with the Chrome-profile preflight |
| `chrome-devtools` | DevTools-level access — evaluate JS, profiling, network inspection, Lighthouse |
| `claude-in-chrome` | Quick tasks in your actual live Chrome tabs |

## Productivity and personal

| Skill | Use when |
|---|---|
| `bear` | Reading or editing Bear notes (macOS) |
| `things3` | Reading or managing Things 3 tasks, projects, areas, tags |
| `setup-channel` | Setting up Telegram, iMessage or Things Cloud for a project |

## Self-reflection and meta

| Skill | Use when |
|---|---|
| `interview-me` | Stress-testing a plan or decision — "interview me", "grill me", "poke holes in this" |
| `skill-invocation-modes` (user-invoked only) | Choosing model-invoked vs user-invoked when authoring a skill, and what each costs |
| `superpowers:writing-skills` (user-invoked only) | Reference for writing and editing skills well — read before authoring a new one |

## From the superpowers plugin, which is still enabled

These are not in this repo, but they fire automatically like any other skill — `brainstorming` and `systematic-debugging` are the two most-invoked skills in the whole environment, so a list that omits them misleads.

| Skill | Use when |
|---|---|
| `superpowers:brainstorming` | Before any creative work — a feature, a component, a behaviour change. Explores intent and design before implementation |
| `superpowers:systematic-debugging` | Any bug, test failure or unexpected behaviour, before proposing a fix |
| `superpowers:writing-plans` | A spec or requirements exist for multi-step work and the plan comes before the code |
| `superpowers:executing-plans` | Working through a written plan with review checkpoints |
| `superpowers:test-driven-development` | Implementing a feature or bugfix, before the implementation code |
| `superpowers:verification-before-completion` | About to claim something is done, fixed or passing — evidence before assertions |
| `superpowers:requesting-code-review` / `receiving-code-review` | Asking for review, and responding to it without performative agreement |
| `superpowers:subagent-driven-development` / `dispatching-parallel-agents` | Independent tasks that can run in parallel without shared state |
| `superpowers:using-git-worktrees` | Feature work needing isolation from the current workspace |

## Research agents (Task tool, not slash-invoked)

| Agent | Use when |
|---|---|
| `autonomous-researcher` | Running an experiment loop unattended overnight, with keep/discard logic. Launched by `research-loop` |
| `experiment-designer` | Turning a research question into a rigorous plan — de-risking, confounds, hypothesis tests |
| `research-advisor` | Research ideation and evaluating directions — expert perspectives on an ML/AI research idea |
| `research-engineer` | Implementing experiment runners and eval pipelines with reproducibility built in |
| `data-analyst` | Parsing experiment outputs and computing statistics with intervals after a run completes |
| `transcript-reviewer` | Reviewing sampled transcripts after an eval for scorer misconfiguration, eval awareness, refusals |
| `research-skeptic` | Red-teaming a finding — confounds, alternative explanations, suspiciously convenient results |
| `literature-scout` | A multi-pass read across papers to position work in its related work |

## Writing agents (the critic panel)

`review-draft` dispatches these; reach for one directly when only that lens is wanted.

| Agent | Use when |
|---|---|
| `clarity-critic` | Vague pronouns, hedging, run-ons, jargon, passive voice, buried ledes |
| `narrative-critic` | Argument structure, flow, hooks, conclusions |
| `fact-checker` | Verifying claims, flagging unsupported assertions, finding citations |
| `red-team` | Counterexamples, unstated assumptions, the strongest objection |
| `paper-writer` | Drafting a paper section with scientific conventions and honest limitations |
| `application-writer` | Job and fellowship applications — narrative, positioning, word limits |

## Code and utility agents

| Agent | Use when |
|---|---|
| `code-reviewer` | Reviewing code just written — CLAUDE.md violations, research validity, correctness, security |
| `debugger` | An error, exception, test failure or intermittent bug needing systematic root-cause work |
| `tooling-engineer` | A well-scoped support tool — API client, parser, data processor, automation script |
| `efficient-explorer` | Exploring an unfamiliar codebase without pulling whole files into context |
| `claude` | Delegating headless work to `claude -p` for fresh auth or separate billing (synchronous only) |
| `context-fetcher` | Gathering Gmail/Slack/Granola/Calendar context on a named person before drafting a reply |
| `llm-billing` | "how much have I spent on OpenRouter/OpenAI/Anthropic", checking API credits |

## Maintaining this file

When adding a skill or agent, add one row under the closest-fitting category (or a new one). When removing one, remove its row. Keep each entry to a single trigger-focused line — the full behavior lives in the skill's own `SKILL.md`. A standard, as opposed to a procedure, does not get a row here at all: it goes in a checklist.
