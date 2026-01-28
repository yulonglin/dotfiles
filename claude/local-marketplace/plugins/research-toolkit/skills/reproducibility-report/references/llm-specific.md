# LLM-Specific Reproducibility Concerns

## Stochasticity
- Even with temperature=0 and seed, LLMs can be non-deterministic
- Document system_fingerprint (OpenAI) to detect backend changes
- Note API access dates - models may be updated or deprecated

## Prompt Sensitivity
- Minor prompt changes can dramatically affect results
- Document exact prompts including whitespace, newlines, special chars
- Note any prompt engineering iterations

## Model Version Drift
- APIs update models without changing IDs (especially "latest" aliases)
- Prefer versioned model IDs (e.g., `gpt-4-0613` not `gpt-4`)
- Document the exact date range of API calls

## Provider-Specific Metadata to Capture

| Provider | Metadata Field | Purpose |
|----------|---------------|---------|
| OpenAI | `system_fingerprint` | Detect backend model changes |
| OpenAI | `seed` parameter | Request-level reproducibility |
| Anthropic | Response headers | API version, rate limit info |
| All | `usage.prompt_tokens` | Verify tokenization, cost |
| All | `usage.completion_tokens` | Detect truncation |
| All | Response timestamps | Batch vs streaming, latency |

## Context and Token Handling
- How are long inputs truncated?
- Are outputs cut off at max_tokens?
- What tokenizer assumptions exist?

## Caching Considerations
- Cached responses may mask model updates
- Document cache key strategy (what fields are included?)
- Note whether caching affects reported metrics

## Multi-Provider and Fallback
- If using fallback providers (e.g., OpenAI → Anthropic on rate limit), document which provider served each request
- For ensembles, document: which models, combination method, voting/averaging strategy
- Note per-request provider logging for cost attribution and reproducibility
- Different providers have different tokenizers - document any tokenization assumptions
