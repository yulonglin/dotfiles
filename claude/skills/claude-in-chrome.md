---
name: claude-in-chrome
description: "Claude-in-Chrome MCP tools for interacting with your actual browser tabs. Use for quick browser tasks: read page content, navigate, fill forms, find text, create GIFs, execute JS. Available when the Claude-in-Chrome extension is running. Triggers: 'check this page', 'read the page', 'what's on this tab', browser interaction with existing tabs. For screenshots, use chrome-devtools instead."
---

# claude-in-chrome MCP Tools

High-level browser interaction via the Claude-in-Chrome extension. Works with your actual Chrome tabs — already logged in, no setup needed.

**Not a plugin** — tools appear dynamically when the Chrome extension connects. Cannot be toggled via profiles.

## Available Tools

### Tab Management
```
mcp__claude-in-chrome__tabs_context_mcp   # Get info about open tabs (CALL FIRST)
mcp__claude-in-chrome__tabs_create_mcp    # Open new tab
mcp__claude-in-chrome__switch_browser     # Switch browser window
```

### Page Reading
```
mcp__claude-in-chrome__read_page              # Read page structure (DOM)
mcp__claude-in-chrome__get_page_text          # Get page text content
mcp__claude-in-chrome__find                   # Find text on page
mcp__claude-in-chrome__read_console_messages  # Read console output
mcp__claude-in-chrome__read_network_requests  # Read network activity
```

### Interaction
```
mcp__claude-in-chrome__navigate       # Navigate to URL
mcp__claude-in-chrome__computer       # Click, scroll, keyboard actions
mcp__claude-in-chrome__form_input     # Fill form fields
mcp__claude-in-chrome__javascript_tool # Execute JavaScript
```

### Visual
```
mcp__claude-in-chrome__gif_creator    # Record browser interaction as GIF
mcp__claude-in-chrome__upload_image   # Upload image to page
mcp__claude-in-chrome__resize_window  # Resize browser window
```

### Shortcuts
```
mcp__claude-in-chrome__shortcuts_list    # List available shortcuts
mcp__claude-in-chrome__shortcuts_execute # Execute a shortcut
mcp__claude-in-chrome__update_plan       # Update automation plan
```

## Workflow

1. **Always call `tabs_context_mcp` first** to see open tabs
2. Use existing tabs when possible, create new ones otherwise
3. Never reuse tab IDs from previous sessions

## When to Use

```
Quick browser task?
├─ Read content from open tab  → get_page_text / read_page
├─ Fill a form                 → form_input
├─ Navigate somewhere          → navigate (new tab) or tabs_create_mcp
├─ Run JS on page              → javascript_tool
├─ Record a workflow           → gif_creator
└─ Debug console/network       → read_console_messages / read_network_requests
```

## Tips

- Load tools first: `ToolSearch("select:mcp__claude-in-chrome__<tool_name>")`
- **Avoid triggering JS alerts/confirms** — they block the extension
- For SPAs, clicking can be unreliable — use `javascript_tool` as fallback
- Screenshots consume context — use `get_page_text` when text is sufficient
- For DevTools-level inspection (performance, memory), use chrome-devtools instead
- `read_console_messages` supports `pattern` param for filtering (regex)
