# LLM Billing Process

## How to Run

```bash
cd /Users/yulong/code/dotfiles && uv run claude/agents/llm-billing.py
```

- Always use `uv run` (project convention)
- Working directory must be `/Users/yulong/code/dotfiles`
- Do not modify the script — just run it and show results
- If user asks about a specific provider, still run the full report (it skips unconfigured providers automatically)

## Output

The script produces rich-formatted tables with color coding. Present the output directly — do not reformat or summarize.

## Environment Variables

API keys live in `/Users/yulong/code/dotfiles/.env`:

| Provider | Variable |
|----------|----------|
| OpenRouter | `OPENROUTER_API_KEY` |
| OpenAI | `OPENAI_API_KEY` |
| Anthropic | `ANTHROPIC_API_KEY` |

## Troubleshooting

If all providers show errors or missing keys, inform the user which environment variables need to be set in the `.env` file.
