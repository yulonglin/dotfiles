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
| `merge-worktree` | "merge this worktree", "merge my branch back", "finish this worktree" |
| `finishing-a-development-branch` | Implementation is done, tests pass, deciding merge/PR/cleanup |
| `diagnosing-bugs` | "diagnose"/"debug this", something broken/throwing/failing/slow |
| `mv-repo` | Moving a repo to a new directory (venv, project state, tmux sessions) |
| `migrate-to-codex` | Migrating instructions/skills/agents/MCP config into Codex |

## Browser automation

| Skill | Use when |
|---|---|
| `agent-browser` | CLI-driven browser automation — navigate, fill forms, screenshot, scrape |
| `browser-session` | **Before** any agent-browser task — sets up the right Chrome profile |
| `playwright` | Automating a real browser from the terminal for dev/testing |
| `chrome-devtools` | DevTools-level access — evaluate JS, profiling, network inspection |
| `claude-in-chrome` | Quick tasks in your actual live Chrome tabs |

## Writing / content

| Skill | Use when |
|---|---|
| `anthropic-style` | Any visual output that should match Anthropic's look (plots, TikZ, slides, web) |
| `check-bib-references` | Verifying BibTeX citations aren't LLM-fabricated |
| `check-prose-claims` | Fact-checking stats/comparatives/quotes in slides, reports, papers |
| `marp-deck` | Building slide decks from Markdown with Marp |
| `pdf` | Reading, creating, or reviewing PDFs where layout matters |

## Research / infra ops

| Skill | Use when |
|---|---|
| `modal` | Cloud GPU/serverless compute — training, batch jobs, serving |
| `jobs` | Submitting experiments/agent jobs with resource caps, queue status |
| `server-storage-tiering` | Root disk near full on a server/cloud box with an attached volume |
| `sweep-ai-safety` | Sweeping recent AI safety research from curated sources |

## Productivity / personal

| Skill | Use when |
|---|---|
| `bear` | Reading/editing Bear notes (macOS) |
| `things3` | Reading/managing Things 3 tasks, projects, areas, tags |
| `use-spark` | Searching/reading Spark email, calendar, contacts |
| `setup-channel` | Setting up Telegram/iMessage/Things Cloud for a project |
| `reply` | Stuck on replying to someone — scaffolds while you write |
| `context-fetcher` (skill) | Gathering Gmail/Slack/Granola/Calendar context before drafting a reply |
| `log-gap` | Recording a knowledge gap you just noticed ("wait, I didn't know that") |
| `recall-feedback` | Spaced-repetition review of past feedback memories |
| `decide` | Stuck overthinking/oscillating on a decision |

## Self-reflection / meta

| Skill | Use when |
|---|---|
| `grilling` | Stress-testing a plan or decision — "grill me", "poke holes in this" |
| `grill-me` (user-invoked only) | Same as `grilling`, invoked directly by name |
| `chronicle` | Resolving ambiguity via screen/recent-history context ("what was I just doing") |
| `writing-great-skills` (user-invoked only) | Reference for writing/editing skills well — read before authoring a new one |

## Agents (Task tool, not slash-invoked)

| Agent | Use when |
|---|---|
| `context-fetcher` | Same as the skill above — gathers cross-source context for a named person |
| `llm-billing` | "how much have I spent on OpenRouter/OpenAI/Anthropic", checking API credits |

## Maintaining this file

When adding a new skill or agent, add one row under the closest-fitting category (or a new one). When removing a skill, remove its row. Keep each entry to a single trigger-focused line — the full behavior lives in the skill's own `SKILL.md`.
