# Desktop Control — Ask Before Taking Over the Machine

The user is often **physically at the machine** while Claude Code is working. Anything that moves focus, launches apps, types, clicks, or steals the cursor interrupts them and can stomp on what they're doing.

**Rule: ask before any action that visibly changes the user's desktop, unless the user has already explicitly authorized it for the current task.**

## What requires asking first

| Action | Examples | Why |
|--------|----------|-----|
| Launching a GUI app | `open -a Bear`, `open -a "Google Chrome"`, `osascript -e 'tell application "X" to activate'` | App jumps to foreground, steals focus, may pop dock notifications |
| Computer-use MCP actions that move focus | `mcp__computer-use__open_application`, `left_click`, `type`, `key`, `scroll`, `mouse_move`, `left_click_drag` | Cursor moves, keystrokes go wherever focus is — can corrupt what user is typing |
| Claude-in-Chrome navigation / typing | `mcp__Claude_in_Chrome__navigate`, `click`, `form_input`, `tabs_create_mcp`, `switch_browser`, `resize_window` | Changes active tab, scrolls user's page, takes window focus |
| Anything that resizes, minimizes, or rearranges windows | `mcp__chrome-devtools__resize_page`, AppleScript window manipulation, `wmctrl` | Reflows whatever the user was looking at |
| Closing apps or tabs | `osascript "quit"`, `tabs_close_mcp` | Loses unsaved state |

## What does NOT require asking

- **Read-only screenshots** that don't change focus (`mcp__computer-use__screenshot` of an already-visible app) — fine
- **Listing**: `list_granted_applications`, `mcp__Claude_in_Chrome__list_connected_browsers`, `tabs_context_mcp` — read-only, no focus change
- **CLI/file alternatives** that bypass the GUI entirely: `bearcli show/edit`, `gws docs get`, `pbpaste`, reading files on disk
- **Background processes** the user explicitly launched (e.g. a dev server already running)

## How to ask

One sentence, with the alternative offered:

> "I need to launch Bear to update note X — OK to bring it to the foreground? (Or I can prepare the diff and you paste it in.)"

> "I'd click through the AIC portal to check enrolment status — OK to take over the browser tab, or do you want to check yourself?"

If the user has said "go ahead, take the machine" or similar for the current task, you're authorized for that task. **Authorization doesn't carry across tasks** — re-ask for the next thing.

## Sandbox is not the same as user-presence

The sandbox protects the filesystem and network. It does NOT know whether the user is sitting at the machine. `dangerouslyDisableSandbox: true` lets you write to a path; it does NOT give you permission to seize the cursor or pop apps to the foreground. Those are separate consent decisions.

## Prefer CLI alternatives when they exist

| Want to… | GUI-stealing way (ask first) | CLI-only alternative (no permission needed) |
|---|---|---|
| Read/edit a Bear note | `open -a Bear; bearcli ...` | `bearcli show <id>` — works while Bear is already running; if not running, ask first |
| Read a Google Doc | Open in Chrome via claude-in-chrome | `gws docs documents get --id <id>` |
| Check a Notion page | Open in Chrome | `notion-fetch <url>` via MCP |
| Send a Slack message draft | Open Slack desktop, navigate | `slack_send_message_draft` MCP |
| Browser screenshot for verification | claude-in-chrome navigation | Playwright MCP (separate browser, doesn't touch user's Chrome) |

When a CLI/MCP path exists, use it — it removes the question entirely.

## Red flags (catch yourself)

- About to run `open -a <app>` to "make sure it's running"? — Ask. Or check `pgrep -f <app>` / `list_granted_applications` first.
- About to `request_access` to a new app mid-task? — That's a checkpoint; tell the user what and why.
- Typing a long sequence via `mcp__computer-use__type`? — One typo lands in the wrong window. Use a file + clipboard handoff instead, or ask.
- "Just one click" to dismiss a dialog? — That click is in the user's session. Ask.
