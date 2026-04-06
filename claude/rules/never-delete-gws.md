# Never Delete via Google Workspace CLI

**Deletions across Google Workspace are irreversible.** Never use `delete`, `batchDelete`, `emptyTrash`, or `clear` methods via `gws` CLI.

## What's Blocked

- **Gmail**: `users messages delete`, `users messages batchDelete`, `users threads delete`
- **Drive**: `files delete`, `files emptyTrash`, `comments/drives/permissions/replies/revisions/teamdrives delete`
- **Calendar**: `events/calendars/acl/calendarList delete`, `calendars clear`
- **Tasks**: `tasklists/tasks delete`
- **Any service**: any `delete` subcommand

## What's Allowed

- **Trash/archive**: `messages trash`, `threads trash`, Drive trash — reversible
- **Read/list/get**: All read operations
- **Create/update/modify**: All write operations that don't destroy data
- **`--dry-run`**: Safe to test any command

## Enforcement

Global PreToolUse hook `block_gws_delete.sh` enforces this at the tool level.
If you need to permanently delete something, tell the user to do it via the Google Workspace UI.
