---
name: chrome-devtools
description: "Chrome DevTools MCP tools for page inspection, performance profiling, network monitoring, and low-level browser control. Use when needing DevTools-level access: evaluate JS, take screenshots, inspect network requests, run Lighthouse audits, trace performance, or take memory snapshots. Available when Chrome DevTools MCP extension is running."
---

# chrome-devtools MCP Tools

Low-level Chrome DevTools Protocol access via MCP. Available when the chrome-devtools extension is running in Chrome.

**Not a plugin** — these tools appear dynamically when the MCP extension connects. Cannot be toggled via profiles.

## Available Tools

### Page Management
```
mcp__chrome-devtools__list_pages        # List open pages
mcp__chrome-devtools__select_page       # Switch to a page
mcp__chrome-devtools__new_page          # Open new page
mcp__chrome-devtools__close_page        # Close page
mcp__chrome-devtools__navigate_page     # Navigate to URL
mcp__chrome-devtools__resize_page       # Resize viewport
mcp__chrome-devtools__emulate           # Emulate device
```

### Interaction
```
mcp__chrome-devtools__click             # Click element
mcp__chrome-devtools__hover             # Hover element
mcp__chrome-devtools__drag              # Drag element
mcp__chrome-devtools__fill              # Fill input
mcp__chrome-devtools__fill_form         # Fill entire form
mcp__chrome-devtools__press_key         # Press keyboard key
mcp__chrome-devtools__type_text         # Type text
mcp__chrome-devtools__upload_file       # Upload file
mcp__chrome-devtools__wait_for          # Wait for condition
```

### Inspection
```
mcp__chrome-devtools__evaluate_script   # Run JavaScript in page context
mcp__chrome-devtools__take_screenshot   # Screenshot current page
mcp__chrome-devtools__take_snapshot     # DOM snapshot
```

### Performance & Debugging
```
mcp__chrome-devtools__lighthouse_audit              # Run Lighthouse audit
mcp__chrome-devtools__performance_start_trace       # Start performance trace
mcp__chrome-devtools__performance_stop_trace        # Stop trace
mcp__chrome-devtools__performance_analyze_insight    # Analyze trace results
mcp__chrome-devtools__take_memory_snapshot           # Heap snapshot
```

### Network & Console
```
mcp__chrome-devtools__list_network_requests   # View network activity
mcp__chrome-devtools__get_network_request     # Get specific request details
mcp__chrome-devtools__list_console_messages   # View console output
mcp__chrome-devtools__get_console_message     # Get specific message
mcp__chrome-devtools__handle_dialog           # Handle JS dialogs
```

## When to Use

```
Need DevTools-level inspection?
├─ Performance profiling     → performance_start_trace + stop + analyze
├─ Memory leaks              → take_memory_snapshot
├─ Network debugging         → list_network_requests
├─ Lighthouse audit          → lighthouse_audit
├─ Run JS in page context    → evaluate_script
└─ Quick screenshot          → take_screenshot
```

## Tips

- Load tools first: `ToolSearch("select:mcp__chrome-devtools__<tool_name>")`
- Use `list_pages` to find the right page before interacting
- `evaluate_script` runs in the page's JS context — access DOM directly
- For simple browser interaction, prefer claude-in-chrome (higher-level)
