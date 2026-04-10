# SendMessage API

When using `SendMessage` to communicate with another agent:
- **Always include `summary`** — it's a required parameter when `message` is a string
- Format: `SendMessage({ to: "agent-name", message: "...", summary: "Brief description of what you're telling them" })`
- Without `summary`, the call will error with "summary is required when message is a string"
