---
name: things3
description: Access Things 3 task manager via MCP. Platform-aware — Python things-mcp on macOS (local SQLite), Go things-cloud-mcp on Linux (cloud API). Use when reading/managing tasks, projects, areas, or tags in Things 3.
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

The `things-mcp` plugin is installed globally. No additional setup needed — it reads the local Things 3 SQLite database directly.

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
