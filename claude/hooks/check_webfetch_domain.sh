#!/usr/bin/env bash
# PreToolUse:WebFetch hook — gates fetches by domain allowlist
# Exit 0 = allow, Exit 2 = block (with stderr feedback to LLM)
#
# Environment:
#   CLAUDE_TOOL_INPUT  - JSON with .url field (set by Claude Code)
#   WEBFETCH_ALLOW_ALL - set to 1 to bypass all checks

set -uo pipefail

# Escape hatch for unrestricted sessions
if [[ "${WEBFETCH_ALLOW_ALL:-}" == "1" ]]; then
  exit 0
fi

# Fail-open: if env var missing or empty, allow
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" ]]; then
  exit 0
fi

# Extract URL from JSON — fail-open if jq unavailable or parse fails
URL=$(printf '%s' "$INPUT" | jq -r '.url // empty' 2>/dev/null) || exit 0
if [[ -z "$URL" ]]; then
  exit 0
fi

# Extract domain from URL — fail-open on parse failure
DOMAIN=$(printf '%s' "$URL" | sed -n 's|^https\{0,1\}://\([^/:]*\).*|\1|p') || exit 0
if [[ -z "$DOMAIN" ]]; then
  exit 0
fi

# Lowercase for comparison
DOMAIN=$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')

# Allowed domains (exact match or subdomain match via suffix check)
ALLOWED_DOMAINS=(
  # GitHub
  "github.com"
  "api.github.com"
  "raw.githubusercontent.com"
  "objects.githubusercontent.com"
  "gist.githubusercontent.com"
  # Anthropic
  "api.anthropic.com"
  "docs.anthropic.com"
  "mcp-proxy.anthropic.com"
  # Package registries
  "registry.npmjs.org"
  "pypi.org"
  "index.crates.io"
  "static.crates.io"
  # Documentation
  "docs.python.org"
  "developer.mozilla.org"
  "arxiv.org"
  "en.wikipedia.org"
  # MCP
  "mcp.context7.com"
  "mcp.linear.app"
  "mcp.notion.com"
)

for allowed in "${ALLOWED_DOMAINS[@]}"; do
  # Exact match
  if [[ "$DOMAIN" == "$allowed" ]]; then
    exit 0
  fi
  # Subdomain match: domain ends with .allowed
  if [[ "$DOMAIN" == *".${allowed}" ]]; then
    exit 0
  fi
done

# Domain not in allowlist — block and tell the LLM to ask the user
echo "BLOCKED: WebFetch to '$DOMAIN' is not in the allowed domain list. Ask the user for permission before fetching from this domain, or use WebSearch instead." >&2
exit 2
