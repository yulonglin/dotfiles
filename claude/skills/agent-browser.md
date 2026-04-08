---
name: agent-browser
description: "Browser automation via agent-browser CLI. Use when navigating websites, filling forms, taking screenshots, scraping web data, or automating browser workflows from the command line. Triggers: 'go to [url]', 'click on', 'fill form', 'take screenshot', 'scrape', 'automate browser', 'log into', agent-browser."
---

# agent-browser CLI

Fast browser automation CLI for AI agents. Uses Playwright under the hood with `@ref`-based element targeting from accessibility snapshots.

**Sandbox note:** Needs `dangerouslyDisableSandbox: true` (writes to `~/.agent-browser`).

## Core Workflow

```bash
agent-browser open <url>        # Navigate
agent-browser snapshot -i       # Get interactive elements with @refs
agent-browser click @e1         # Click by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

Always `snapshot -i` first to get `@ref` IDs, then interact using those refs.

## Commands

### Navigation
```bash
agent-browser open <url>
agent-browser back | forward | reload
agent-browser close [--all]
```

### Snapshot (page analysis)
```bash
agent-browser snapshot          # Full accessibility tree
agent-browser snapshot -i       # Interactive elements only (recommended)
agent-browser snapshot -c       # Compact output
agent-browser snapshot -d 3     # Limit depth
```

### Interactions (use @refs from snapshot)
```bash
agent-browser click @e1
agent-browser dblclick @e1
agent-browser fill @e2 "text"         # Clear and type
agent-browser type @e2 "text"         # Type without clearing
agent-browser press Enter             # Key press
agent-browser press Control+a         # Key combo
agent-browser hover @e1
agent-browser check @e1 | uncheck @e1
agent-browser select @e1 "value"
agent-browser scroll down 500
agent-browser scrollintoview @e1
agent-browser drag @e1 @e2
agent-browser upload @e1 file.png
```

### Get Info
```bash
agent-browser get text @e1      # Element text
agent-browser get value @e1     # Input value
agent-browser get title         # Page title
agent-browser get url           # Current URL
agent-browser get html @e1      # Element HTML
agent-browser get count @e1     # Count matching elements
```

### Screenshots & PDF
```bash
agent-browser screenshot              # To stdout
agent-browser screenshot path.png     # Save to file
agent-browser screenshot --full       # Full page
agent-browser pdf output.pdf
```

### Wait
```bash
agent-browser wait @e1                     # Wait for element
agent-browser wait 2000                    # Wait ms
agent-browser wait --text "Success"        # Wait for text
agent-browser wait --load networkidle      # Wait for network idle
```

### JavaScript Evaluation
```bash
agent-browser eval "document.title"
agent-browser eval --stdin <<'EOF'
document.querySelectorAll('.item').forEach(el => console.log(el.textContent))
EOF
```

### Semantic Locators (alternative to @refs)
```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign In" click
agent-browser find label "Email" fill "user@test.com"
```

### Auth & Sessions
```bash
# Reuse Chrome profile (picks up existing logins)
agent-browser --profile Default open <url>
# ⚠️ --profile only applies if daemon not running. Use 'agent-browser close' first.

# Named session (auto-persists)
agent-browser --session-name myapp open <url>

# State save/load
agent-browser state save ./auth.json
agent-browser --state ./auth.json open <url>
```

### Network Control
```bash
agent-browser network route "**/*.png" --abort       # Block images
agent-browser network route "**/api/*" --body '{"mock":true}'
agent-browser network requests --filter "api"         # View requests
agent-browser network har start                       # Record HAR
```

### Browser Settings
```bash
agent-browser set viewport 1920 1080
agent-browser set device "iPhone 14"
agent-browser set media dark
agent-browser set offline on
agent-browser set credentials user pass
```

## Tips

- For SPAs: CSS selector clicks (`click 'a.nav-link'`) more reliable than `@ref` clicks
- `scrollintoview 'selector'` before clicking off-screen elements
- Re-snapshot after navigation or significant DOM changes
- `batch "cmd1" "cmd2"` for sequential commands
