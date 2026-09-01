---
name: openrouter-fusion
description: Query OpenRouter — a parallel multi-model panel with judge synthesis for deep-research and compare-and-contrast questions, a single non-Anthropic model for a one-off, or the raw HTTP reference for auth, the /models catalogue and the /chat/completions body. Use when reaching a non-Anthropic family, when a question wants several models answering in parallel rather than one, on "fusion", "ask GLM/Kimi/Qwen/DeepSeek", "what does another model think", or when writing code against the OpenRouter API.
---

# OpenRouter

**Reach OpenRouter through `openrouter-cli`, never through a subagent.** Claude Code resolves an agent's `model:` frontmatter against api.anthropic.com only, so a non-Anthropic name there either hard-fails or answers from Claude wearing another family's label. The CLI is on PATH; `--help` on any subcommand is authoritative.

```bash
openrouter-cli models              # configured models; --check cross-checks the catalogue
openrouter-cli ask glm "question"  # one model
openrouter-cli fusion "question"   # panel in parallel, then judge synthesis
```

`fusion` takes `--panel <aliases>` to override the configured panel and `--dry-run` to print the request body instead of spending. Model config lives in `config/openrouter-models.toml`; the key comes from per-project secrets (`setup-envrc`, or `with-secrets OPENROUTER_API_KEY -- <cmd>`), never a global export.

## Fusion is for disagreement, not for lookup

The prompt goes to every panel model in parallel — each with `openrouter:web_search` and `openrouter:web_fetch` — and a judge synthesises them. The whole pipeline is server-side: one call from your side. The synthesis names **consensus**, **contradictions**, **partial_coverage**, **unique_insights** and **blind_spots**, which is the point: a collapsed panel is visible rather than silent.

It costs latency and money. Use it for research questions, multi-domain critique and compare-and-contrast. Skip it for a simple factual lookup or a generation task — one model is cheaper and no worse.

## The raw API, when you are writing code rather than asking

```
Base URL:  https://openrouter.ai/api/v1
Auth:      Authorization: Bearer $OPENROUTER_API_KEY
```

OpenAI-compatible, so any OpenAI SDK works with `base_url="https://openrouter.ai/api/v1"`. Optional `HTTP-Referer` and `X-OpenRouter-Title` headers feed the usage leaderboard.

The model catalogue is dynamic — query it rather than hardcoding slugs:

```bash
curl https://openrouter.ai/api/v1/models -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  | jq '.data[] | {id, context_length, pricing}'
```

Fusion as a raw tool call is `"tools": [{"type": "openrouter:fusion", "parameters": {...}}]` with `"tool_choice": "required"`. Its parameters: `analysis_models` (1-8 slugs, the panel), `model` (the judge slug), `max_tool_calls` (1-16, default 8 web calls per panel model), `max_completion_tokens`, `reasoning.effort` (low/medium/high), `temperature` (0-2).

## Reach for a neighbour instead when

- the point is an **adversarial check on your own work** rather than an OpenRouter query — that is the `council` skill, which picks the rung (one model, two advisors, agentic, or the full panel)
- the question is about **spend or queueing** a long fan-out: the `jobs` skill, and `~/.claude/checklists/experiments.md` for the spend gate
- you are **judging text by meaning** at scale rather than asking a question once: the `llm-judge` skill
