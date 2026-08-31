# LLM Billing Process

## How to Run

```bash
cd "${DOT_DIR:-$HOME/code/dotfiles}" && uv run claude/agents/llm-billing.py
```

- Always use `uv run` (project convention)
- Working directory must be the dotfiles repo (`$DOT_DIR` or `~/code/dotfiles`)
- Do not modify the script — just run it and show results
- If user asks about a specific provider, still run the full report (it skips unconfigured providers automatically)

## Output

The script produces rich-formatted tables with color coding. Present the output directly — do not reformat or summarize.

## Environment Variables

API keys live in `${DOT_DIR:-$HOME/code/dotfiles}/.env`:

| Provider | Variable | Scope needed for billing |
|----------|----------|---------------------------|
| OpenRouter | `OPENROUTER_API_KEY` | any key (balance endpoint is key-scoped) |
| OpenAI | `OPENAI_API_KEY` | **org-level** key — a project-scoped `sk-proj-...` key works for inference but 403s on `/v1/organization/costs` |
| Anthropic | `ANTHROPIC_ADMIN_API_KEY`, falls back to `ANTHROPIC_API_KEY` | **admin** key (`sk-ant-admin-...`) needed for cost/usage reports — the script tries `ANTHROPIC_ADMIN_API_KEY` first, then falls back to the regular `ANTHROPIC_API_KEY` most users have set (which will 403 and trigger the manual-check fallback message rather than being skipped as "missing") |

## Troubleshooting

If all providers show errors or missing keys, inform the user which environment variables need to be set in the `.env` file.

### No org-admin access (common — not a bug)

If you (the user) only have a project-scoped OpenAI key or a non-admin Anthropic key, the script will print
`No data — needs an org/admin key` for that provider plus a manual dashboard URL. This is an API-level
restriction, not something the script or agent can work around — there is no read-only "check my balance"
endpoint for non-admin keys on either provider. The agent should relay this immediately and stop; it should
not spend extra tool calls (e.g. probing `/v1/models`) trying to re-derive what's already a known limitation.

Manual balance/usage checks:
- OpenAI: https://platform.openai.com/settings/organization/billing/overview (requires org owner/admin role)
- Anthropic: https://console.anthropic.com/settings/billing (requires admin role)
