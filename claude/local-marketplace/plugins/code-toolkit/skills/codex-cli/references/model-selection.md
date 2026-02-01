# Model Selection Reference

## Listing Available Models

Codex CLI doesn't have a built-in model list command. Query the OpenAI API directly:

```bash
# List OpenAI models (codex-compatible ones)
curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" | \
  jq -r '.data[].id' | sort | grep -iE 'gpt|o[0-9]|codex'

# Check current default
grep '^model' ~/.codex/config.toml
```

## Changing the Default Model

Edit `~/.codex/config.toml`:

```toml
model = "gpt-5.2-pro"
model_reasoning_effort = "high"
```

## Per-Call Override

```bash
codex -m "gpt-5.2-pro" "your prompt"
codex exec -m "gpt-5.2-pro" --full-auto "your prompt"
```

## Reasoning Effort Levels

| Task complexity | Flag |
|---|---|
| Simple implementation, boilerplate | Default (high) |
| Complex logic, tricky edge cases | `-c model_reasoning_effort="xhigh"` |
| Plan review / second opinion | `-c model_reasoning_effort="xhigh"` |
| Different model entirely | `-m <model>` |
