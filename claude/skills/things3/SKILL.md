---
name: things3
description: Access Things 3 task manager via MCP, and apply Yulong's task system (what lives in Things vs Bear, no orphans, name-plus-link, weekly review, cleanup playbook). Platform-aware — Python things-mcp on macOS (local SQLite), Go things-cloud-mcp on Linux (cloud API). Use when reading/managing tasks, projects, areas, or tags in Things 3, running or helping with a weekly review, triaging the Inbox, or cleaning up Things.
---

# Things 3 Access

Things 3 is Yulong's task manager. Access it through platform-specific MCP backends.

## Platform Detection

| Platform | Backend | Transport | Tool prefix |
|----------|---------|-----------|-------------|
| **macOS** | `things-mcp` plugin (Python, local SQLite) | stdio | `mcp__plugin_things-mcp_things__` |
| **Linux** | `things-cloud-mcp` (Go, cloud API) | HTTP `localhost:8080/mcp` | `mcp__things-cloud__things_` |

Check platform: `uname -s` — `Darwin` = macOS, `Linux` = Linux.

## Tool Mapping

| Action | macOS (Python) | Linux (Go) |
|--------|---------------|------------|
| Today | `get_today` | `things_list_today` |
| Inbox | `get_inbox` | `things_list_inbox` |
| Anytime | `get_anytime` | `things_list_anytime` |
| Someday | `get_someday` | `things_list_someday` |
| Upcoming | `get_upcoming` | `things_list_upcoming` |
| All tasks | `get_todos` | `things_list_all_tasks` |
| Projects | `get_projects` | `things_list_projects` |
| Areas | `get_areas` | `things_list_areas` |
| Tags | `get_tags` | `things_list_tags` |
| Single task | `show_item(uuid)` | `things_get_task(uuid)` |
| Search | `search_todos(query)` | `things_search_tasks(query)` |
| Project tasks | — | `things_list_project_tasks(project_uuid)` |
| Area tasks | — | `things_list_area_tasks(area_uuid)` |
| Completed | `get_logbook` | `things_list_completed` |
| Checklist items | — | `things_list_checklist_items(task_uuid)` |
| Tagged items | `get_tagged_items(tag)` | — |
| Create task | `add_todo(title, ...)` | `things_create_task(title, ...)` |
| Edit task | `update_todo(uuid, ...)` | `things_edit_task(uuid, ...)` |
| Complete | `update_todo(uuid, completed=true)` | `things_complete_task(uuid)` |

## Read-Only Default (Linux)

The Go server is **read-only by default**. Write tools require `ENABLE_WRITES=true` in the systemd service. This protects against accidental corruption of Things data via the cloud sync protocol.

## Setup

### macOS (already configured)

The `things-mcp` plugin reads the local Things 3 SQLite database directly and needs no other setup — it runs `uvx --from git+https://github.com/yulonglin/things-mcp things-mcp`. It was enabled in `settings.json` on 2026-08-30; before that the marketplace was configured but the plugin was never actually enabled, so the tools were silently absent.

### Linux (requires setup)

1. **Build the server** (if not already built):
   ```bash
   cd ~/code/mcps/things-cloud-mcp && go build -v -o things-server ./server/
   ```

2. **Configure credentials** — create `~/.config/things-cloud-mcp/env`:
   ```bash
   mkdir -p ~/.config/things-cloud-mcp
   # Option A: BWS (recommended)
   bws secret get <SECRET_ID> | jq -r '.value | fromjson | "THINGS_USERNAME=\(.username)\nTHINGS_PASSWORD=\(.password)"' > ~/.config/things-cloud-mcp/env
   # Option B: Manual
   printf 'THINGS_USERNAME=%s\nTHINGS_PASSWORD=%s\n' 'email@example.com' 'password' > ~/.config/things-cloud-mcp/env
   chmod 600 ~/.config/things-cloud-mcp/env
   ```

3. **Install systemd service**:
   ```bash
   cp ~/code/dotfiles/config/systemd/things-cloud-mcp.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now things-cloud-mcp
   ```

4. **Add MCP to Claude Code** — add to `~/.claude/settings.json` under `mcpServers`:
   ```json
   "things-cloud": {
     "type": "http",
     "url": "http://127.0.0.1:8080/mcp"
   }
   ```

5. **Verify**: `curl -s http://127.0.0.1:8080/ | jq .`

## Checking Service Health (Linux)

```bash
systemctl --user status things-cloud-mcp   # service status
journalctl --user -u things-cloud-mcp -n 20  # recent logs
curl -s http://127.0.0.1:8080/              # health check
curl -s http://127.0.0.1:8080/api/verify    # credential check
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Tools not available | Check `uname -s`, verify correct backend is running |
| Linux: connection refused | `systemctl --user start things-cloud-mcp` |
| Linux: credential error | Check `~/.config/things-cloud-mcp/env` has valid `THINGS_USERNAME`/`THINGS_PASSWORD` |
| macOS: "database not found" | Things 3 must be installed and synced at least once |
| Writes disabled | Set `ENABLE_WRITES=true` in systemd env file (Linux) or env (macOS) |

## Forks

- Python: [yulonglin/things-mcp](https://github.com/yulonglin/things-mcp) — macOS local SQLite
- Go: [yulonglin/things-cloud-mcp](https://github.com/yulonglin/things-cloud-mcp) — cloud API, read-only default, localhost binding

## Yulong's system (agreed 2026-11-21)

The canonical rules are the Bear note [🧭 Where things live](bear://x-callback-url/open-note?id=7340E86D-96AE-4404-9080-EF5C39EDAD27); this section is the working summary. Re-read that note before changing the structure.

- **Things holds only committed next actions.** Anything to read, think about or consult (lists, brainstorms, reading, ideas, recipes, research backlogs) lives in Bear. Research task lists Claude works from are Bear notes tagged `TODO/agent`.
- **Structure:** one `📝 Area: Admin` area with `📋 paperwork` (one-off and repeating admin, incl. health appointments, travel bookings, money), `💸 buy`, and the packing template; `🔭 Project: Research` for research with next actions this week. Add a project only while it has next actions.
- **No orphans.** Every Anytime or Someday to-do belongs to a project or area; the Inbox is the only place for unfiled items, until the next weekly review. `things-orphans` lists violations; a launchd job runs `things-orphans --notify` every Sunday at 09:00 and adds one Today to-do linking them.
- **Repeating admin lives in Paperwork**, not a separate project; Quick Find > "Repeating" (Things 3.11+) lists every repeating to-do.
- **Reusable checklists are Someday templates.** The packing list is a project never ticked; Duplicate (⌘D) per trip and tick the copy. Reminders was rejected for this because scripts cannot create Reminders sections.
- **Cross-references are name plus link:** `[title](things:///show?id=<uuid>)` for Things items, `[title](bear://x-callback-url/open-note?id=<id>)` for Bear notes, `[[Title]]` between Bear notes.
- **No hoarding.** Cancel rather than port when an item has no lasting value; completed history stays in the Things Logbook and is not copied to Bear. Linear was dropped (nothing assigned, idle since April 2026; archived in Bear).
- **Bear tags for ported material:** `list` for lists consulted over time, `to-try` for things to try, topic tags (`learn`, `claude-code`, `food/cooking`, `writing/blog`, `ideas`, `travel`, `health/workout`); `archive` only for dead material. There is no `keep` tag: no status tag means live.

## Weekly review with Claude

The repeating to-do "30m weekly review" (Sunday) carries the checklist and links to the rules note and Yulong's Weekly Review Google Form (reflection questions). When asked to help with the review:

1. Run `things-orphans`; propose a home (project, area, Bear, cancel) for each orphan.
2. Read the Inbox (`get_inbox`); for each item propose: do now, file into a named project, move to Bear (name the note), or cancel. Batch the proposals as one `AskUserQuestion` bundle, then apply.
3. Scan `📋 paperwork` and `💸 buy` for stale items (no change in 4+ weeks); propose cancel or reschedule.
4. Check Upcoming and Someday for anything past its date.
5. Leave the reflection form and the 3 weekly priorities to Yulong; offer to draft priorities from Paperwork and the Research project if asked.

## Cleanup playbook

For a large cleanup (the 2026-11-21 run took Things from 1,061 to 140 open to-dos):

- **Inventory from SQLite read-only**, not the MCP: the MCP hides repeating templates and has no creation dates. Path: `~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-*/Things Database.thingsdatabase/main.sqlite`, opened with `sqlite3 -readonly` (needs `dangerouslyDisableSandbox`). Tables: `TMTask` (type 0 to-do, 1 project, 2 heading; status 0 open, 2 cancelled, 3 completed; `start` 0 Inbox, 1 Anytime, 2 Someday; `rt1_recurrenceRule` set on repeating templates), `TMArea`, `TMChecklistItem`.
- **Port before cancel:** write the Bear note, re-read it, and only then cancel the Things source. Include project notes and checklists (they often hold the real content).
- **Let Yulong review loose items in a Bear checklist note** (ticked = keep, unticked = cancel), with notes and checklist items shown as plain sub-bullets so he sees what a cancel hides. Default-untick anything older than about two months. Read his `#COMMENT` lines before acting.
- **Salvage selectively:** distil research ideas from cancelled items into one Bear note, not raw copies.

## MCP, URL scheme and AppleScript gotchas (macOS)

- `get_todos` and `get_projects` omit repeating templates; read them from SQLite.
- `update_project(canceled=true)` cascades: every open to-do in the project is cancelled too.
- Repeating to-dos and projects cannot be cancelled or completed via the MCP or URL scheme (the call reports success and nothing changes); moving them with `list_id` and editing notes does work. Yulong deletes them in the app.
- The MCP and URL scheme cannot delete anything, create or delete areas, set a repeat, or empty the Trash. `update-project` accepts `area-id` per the URL-scheme docs, but the MCP's `update_project` does not expose it.
- AppleScript (`tell application "Things3"`) can `delete` areas and projects, `move`, set `area of` a project, and `empty trash`. It cannot set repeats. `osascript` is blocked in the sandbox, so write the script and give Yulong the command; make it dry-run by default. Deleting an area sends all its items, including Logbook items, to the Trash.
- `show_item` and `search_items` drive the Things UI (they open the item or a search in the app) rather than returning data; prefer `get_*` tools or SQLite.
- `update_todo(notes=...)` replaces the notes; read the existing notes first and keep them.
