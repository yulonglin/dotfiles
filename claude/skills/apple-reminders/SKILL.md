---
name: apple-reminders
description: Read, add, edit, reschedule, rename, tick off or delete Apple Reminders from the shell with `rem` (EventKit, macOS only), including repeating reminders. Use when checking or setting up habits and routines in Reminders, auditing a list, cleaning duplicates or overdue items, or when the user asks to add or change a reminder.
---

# Apple Reminders via `rem`

`rem` (`custom_bins/rem`) wraps a small EventKit program, `tools/rem/rem.swift`, which it compiles into `~/.cache/rem/` on first use and again whenever the source changes. No third-party code. `rem --help` lists every command.

## Every call runs outside the sandbox

Run `rem` with `dangerouslyDisableSandbox: true`. Inside the sandbox the XPC call to `calaccessd` is blocked and access fails with "Mach error 4099"; `--help` and the build itself work sandboxed. Each call therefore goes through the permission gate, so batch related commands into one Bash call.

Access is a one-time macOS grant to the terminal app: the first call raises a Reminders permission dialog, or the user turns the app on under System Settings → Privacy & Security → Reminders. A call that hangs about 60 s and exits "no Reminders access" means the dialog is waiting on screen.

## Commands take a reminder's ID from `rem list`

```
rem lists
rem list --list "routine 😴"            # ID | list | title | due | repeat | state | notes
rem add --list "routine 😴" --title "☀️ go outside" --due "2026-11-04 12:30" --repeat daily --notes "within an hour of waking"
rem add --list "routine 😴" --title "🚶 easy cardio" --due "2026-11-04 17:00" --repeat weekly:Mon,Wed,Fri
rem due --id <ID> --due "2026-11-04 00:40"     # moves due time and alert, keeps the repeat
rem title --id <ID> --set "💊 take meds"
rem notes --id <ID> --append "Start SnoreLab"
rem complete --id <ID>
rem delete --id <ID>                           # prints the reminder, then deletes it
```

`--due` is local time, `YYYY-MM-DD HH:MM`, and also sets an alert at that time. A daily reminder left unticked stays at its old date and shows as overdue; `rem due` rolls it forward.

## Look before changing anything

List first and quote the IDs and titles in the reply. Confirm a delete with the user unless they named the reminder; the user may be editing in the app at the same time, so an ID can vanish between list and write ("no reminder with id" just means it is already gone). Prefer `complete` over `delete` when unsure, since a completed reminder is still visible under "Show Completed".

## Sections and manual order need the Reminders app

EventKit has no API for list sections or manual ordering; the SDK headers contain no "section" symbol (checked 3 Nov 2026). Group items with lists, title emoji or due times, or ask the user to make sections in the app (or use computer use, with permission). Reminders' AppleScript cannot set repeats either, which is why this tool exists.

## Read-only fallback without EventKit

To inspect without the permission grant, copy the store and query the copy, never the live file:

```
cp ~/Library/Group\ Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite* "$TMPDIR"/rem-db/
sqlite3 "$TMPDIR"/rem-db/Data-<UUID>.sqlite "select ZTITLE from ZREMCDREMINDER where ZCOMPLETED=0 and ZMARKEDFORDELETION=0"
```

Dates are seconds since 2001-01-01 (add 978307200 for Unix time). Never write to the database.
