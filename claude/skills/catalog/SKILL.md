---
name: catalog
description: |
  A human-facing index of every skill and agent in this repo, grouped by category, with a one-line trigger for each. Use only when the user explicitly asks "what skills do I have", "what can you do", "is there a skill for X", or invokes `/catalog` directly — never fires on its own.
disable-model-invocation: true
---

# Catalog

One place to look up what already exists instead of re-discovering it mid-task. This skill only fires when asked for by name — it does not compete for context on other requests.

Most skills below are **model-invoked**: Claude fires them automatically when your request matches the trigger phrase, so you don't need to remember exact names. A few are **user-invoked only** (marked below) — Claude never reaches for these on its own, so the name is the only way in.

## Git / worktree workflow

| Skill | Use when |
|---|---|
| `commit` | "commit this", "commit these changes", "save my work" |
| `commit-push-sync` | "commit and push", "sync changes", "update remote" |
| `ship` | "ship this" or review, finish, merge, and push an authorized completed change |
| `merge-worktree` | "merge this worktree", "merge my branch back", "finish this worktree" |
| `superpowers:finishing-a-development-branch` | Implementation is done, tests pass, deciding merge/PR/cleanup |
| `wrap-up` | A session needs to reach a terminal state — land it as a draft PR, state the blocker, or say it's done (dotfiles trial) |
| `diagnosing-bugs` | "diagnose"/"debug this", something broken/throwing/failing/slow |
| `mv-repo` | Moving a repo to a new directory (venv, project state, tmux sessions) |

## Browser automation

| Skill | Use when |
|---|---|
| `agent-browser` | CLI-driven browser automation — navigate, fill forms, screenshot, scrape; opens with the Chrome-profile preflight |
| `chrome-devtools` | DevTools-level access — evaluate JS, profiling, network inspection |
| `claude-in-chrome` | Quick tasks in your actual live Chrome tabs |

## Writing / content

| Skill | Use when |
|---|---|
| `artifact-writing` | Publishing any report, plan or findings page as an Artifact — titles, collapsible units, transcripts, annotation layer, republishing |
| `results-artifact` | A research results page — the review checklist, intervals, nulls, chance correction, slicing |
| `spec-artifact` | Writing a spec or plan — the three mandatory sections, per-requirement variables |
| `house-plots` | Any chart or figure — pastel matplotlib defaults, the palette, overlap checking. Code lives in `lib/plotting/` |
| `check-bib-references` | Verifying BibTeX citations aren't LLM-fabricated |
| `check-prose-claims` | Fact-checking stats/comparatives/quotes in slides, reports, papers |
| `reduce-ambiguity` | Reducing ambiguity in a draft before sending — artifacts, results, specs, handoff briefs |

## Research / infra ops

| Skill | Use when |
|---|---|
| `modal` | Cloud GPU/serverless compute — training, batch jobs, serving |
| `jobs` | Submitting experiments/agent jobs with resource caps, queue status, sandbox failure modes |
| `llm-judge` | Building an LLM judge that scores text by meaning — prompt design, blinding, fan-out, JSONL persistence |
| `server-storage-tiering` | Root disk near full on a server/cloud box with an attached volume |
| `sweep-ai-safety` | Sweeping recent AI safety research from curated sources |
| `spawn-session` (user-invoked only) | Starting a detached Claude session in another directory with a seed prompt, optionally reachable by Remote Control |

## Productivity / personal

| Skill | Use when |
|---|---|
| `bear` | Reading/editing Bear notes (macOS) |
| `things3` | Reading/managing Things 3 tasks, projects, areas, tags |
| `setup-channel` | Setting up Telegram/iMessage/Things Cloud for a project |

## Self-reflection / meta

| Skill | Use when |
|---|---|
| `interview-me` | Stress-testing a plan or decision — "interview me", "grill me", "poke holes in this" |
| `superpowers:writing-skills` (user-invoked only) | Reference for writing/editing skills well — read before authoring a new one |

## Agents (Task tool, not slash-invoked)

| Agent | Use when |
|---|---|
| `context-fetcher` | Gathers cross-source Gmail/Slack/Granola/Calendar context for a named person |
| `llm-billing` | "how much have I spent on OpenRouter/OpenAI/Anthropic", checking API credits |

## Maintaining this file

When adding a new skill or agent, add one row under the closest-fitting category (or a new one). When removing a skill, remove its row. Keep each entry to a single trigger-focused line — the full behavior lives in the skill's own `SKILL.md`.
