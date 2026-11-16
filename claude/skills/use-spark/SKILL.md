---
name: use-spark
description: "Search and read email across every account and inbox at once through the Spark Desktop CLI, read-only. Use on \"search my email\", \"find the email from\", \"check all inboxes\", \"did anyone email me about\", \"what did X send\", or when a Gmail-only search misses mail in another account. Receipts, invoices and attachment recovery from Gmail stay with gmail-connector."
---

# Spark email search (read-only)

`spark` (`/usr/local/bin/spark`, a link into `/Applications/Spark Desktop.app`) is a thin client for the running Spark Desktop app. It reads every account, folder, team and shared inbox Spark has, so one query covers all inboxes. Checked against CLI 1.3.1 on 2026-10-04.

This is a curated read-only cut of the vendor skill. Never regenerate it with `spark skill` or `spark skill --install`: the vendor text is 800 lines and teaches drafting, sending and triage.

## Never run the write commands

These subcommands change mail, calendar or contacts. Do not run them, even when asked to "just archive it" — tell Yulong to do it in Spark.

| Subcommand | Why it is off-limits |
|---|---|
| `action` | Archive, move, trash, mark read, snooze, assign, unsubscribe, and `send` for drafts |
| `draft` | Creates, edits or deletes drafts |
| `comment` | Posts to a shared team thread |
| `event` (singular) | Creates, edits, deletes or RSVPs to calendar events |
| `contact-action` | Blocks, accepts or recategorises senders |
| `skill --install` | Overwrites a skill file with the vendor version |

Spark enforces this too: each account has an access level under Spark Desktop > Settings > AI Agents. `read-only` refuses every command above; `triage` allows them. `spark accounts` shows the level per account.

## When a call fails

The CLI talks to Spark over a Unix socket at `~/Library/Application Support/Spark Desktop/cli`.

| Error text | Meaning | Do this |
|---|---|---|
| `a sandbox blocked access to its socket at …/Spark Desktop/cli (operation not permitted)` | The Claude Code sandbox blocks the socket | Run the same read-only command with `dangerouslyDisableSandbox: true`, or ask Yulong to add `spark` to `sandbox.excludedCommands` |
| `Spark CLI can't access your Spark Desktop application. Please check that the app is running and CLI settings are enabled.` | Spark Desktop is not running, or its CLI access is off | Ask Yulong to open Spark. Never launch the app yourself — it takes the desktop |

## Find mail across all inboxes

**Use `search`, not `emails`, for anything account-wide.** `emails` sees only the Unified Inbox; `search` covers every folder of every account. Trash, Spam and Blocked are left out unless `--in` names them.

`search` has two modes:

- **List mode (no topic):** a compact paged table — ID, From, Date, Subject, Flags — of every email matching `--filter` and `--in`, newest first. Start here.
- **Topic mode (`spark search "<topic>"`):** keyword plus semantic match, top 20 results **with full bodies**. Output is large, so use it only when the question is about content and list mode cannot narrow it.

```bash
spark search --filter "from:alice@example.com" --limit 20          # every email from alice, all accounts
spark search --filter "subject:\"offer letter\" newer_than:1y" --limit 20
spark search --filter "has:attachment filename:invoice" --limit 20
spark search "visa appointment" --filter "newer_than:3m"            # topic mode, returns bodies
spark search --filter "is:unread" --in user@example.com             # one account, all its folders
spark search --filter "from:bank" --in user@example.com:Spam        # include Spam explicitly
spark search --filter "newer_than:7d" --page 2 --limit 20 --order ascending
```

`--page`, `--limit` (alias `--page-size`, default 50) and `--order ascending|descending` apply to list mode only.

### Filter operators

Gmail-style, combined with spaces inside one `--filter` string. Quote multi-word values: `subject:"quarterly report"`.

| Kind | Operators |
|---|---|
| People | `from:<addr>` `to:<addr>` `cc:<addr>` |
| Subject and file | `subject:<text>` `filename:<name>` |
| Absolute dates | `before:yyyy/MM/dd` `after:yyyy/MM/dd` |
| Relative dates | `newer_than:Xd` `older_than:Xd` (units `d` `w` `m` `y`) |
| Content | `has:attachment` `has:document` `has:spreadsheet` `has:presentation` `has:reminder` |
| State | `is:unread` `is:read` `is:starred` `is:pinned` `is:unreplied` |
| Category | `category:personal` `category:priority` `category:notification` `category:newsletter` `category:invitation` `category:invitation_response` |
| Team | `assigned_to:me` `assigned_by:me` |

### Scope identifiers

Run `spark folders` to list the exact identifiers, or `spark accounts` for accounts, aliases, teams and shared inboxes.

| Form | Meaning |
|---|---|
| `user@example.com` | All folders of one account (`--in`) or its inbox (`emails`) |
| `user@example.com:Archive` | One folder of one account |
| `"Team Name"` / `"Team Name:Sent"` | A team, or one team folder |
| `shared@example.com:Inbox` | A shared inbox folder |
| `Inbox` | The unified cross-account inbox |

## Read a thread and its attachments

```bash
spark thread 1114                     # every message in the thread: headers, plain-text bodies, attachments table
spark thread "<Spark deep link>"      # a Link: line from earlier output works too
spark attachment 42                   # metadata for one attachment (ID from the thread's Attachments table)
spark attachment 42 --stream > "$TMPDIR/report.pdf"   # raw bytes to stdout; the sandbox-safe way to save it
```

`thread --download-attachments` fetches missing attachments over IMAP; it changes no mail, but prefer `attachment <id>`, which downloads only the one file.

## Other read-only commands

| Command | Use |
|---|---|
| `spark emails [folder] --filter … --limit N` | Browse one folder, default the Unified Inbox; `--new-senders` shows mail held by GateKeeper |
| `spark contacts "<name or domain>"` | Resolve a person to an address before a `from:` search |
| `spark events --week` / `--start yyyy-MM-dd --end yyyy-MM-dd` | Calendar events, read-only |
| `spark meetings` / `spark meeting <id>` | Spark meeting transcripts |

## Workflow

1. Unsure of an address? `spark contacts "<name>"`.
2. `spark search --filter "<operators>" --limit 20` to get IDs across all inboxes.
3. `spark thread <ID>` to read the one that matters.
4. Report sender, date and subject with the gist. Quote only what the question needs — bodies and addresses are Yulong's private mail.
