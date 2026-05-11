---
name: bear
description: Access Bear notes via bearcli (CLI) or the official Bear MCP server. macOS only. Use when reading, searching, creating, editing, tagging, archiving, or attaching files on Bear notes. Covers Bear's search syntax, safe-edit patterns (hash guard, attachment gate), and CLI-vs-MCP selection.
---

# Bear Notes Access

Bear is Yulong's note app. Two surfaces, both official, both shipped inside Bear 2.8+:

| Surface | Tool prefix / command | Best for |
|---------|----------------------|----------|
| **CLI** | `bearcli <subcommand>` (Bash) | One-shot reads, scripted bulk edits, piping into Unix tools, `cron` |
| **MCP** | `mcp__bear__*` (already configured in `~/.claude/settings.json`) | Conversational reads/writes inside Claude, structured write responses, optimistic concurrency |

Both run **locally** against the Bear SQLite DB — no network, no telemetry. Encrypted notes show metadata but content is unreadable.

## When to use which

| Situation | Use | Why |
|-----------|-----|-----|
| "What's in my Mars note?" | CLI `bearcli cat` or MCP `read_note` | Either works; CLI is faster for single shots |
| Search + iterate over results | CLI with `--format json` | Pipe to `jq`, no MCP roundtrip per note |
| Bulk tag rename / scripted edits | CLI | One process, clean shell semantics |
| Write where the new note ID matters | MCP **or** CLI `create --format json --fields id` | Mutating CLI commands are silent by default |
| Safe overwrite with concurrency check | MCP (mandatory `baseHash`) or CLI `overwrite --base <hash>` | Prevents clobbering edits from Bear app |
| Working interactively from Claude | MCP | Better destructive-action gating via `destructiveHint` |

Default: reach for **CLI** unless you need structured write responses or `baseHash` enforcement.

## CLI: core surface

Full reference: `bearcli help all` (≈1000 lines — pipe to file if you need it). Highlights below.

**Conventions**
- Exit codes: `0` success, `1` business error, `64` usage error
- Identify a note by ID **or** `--title "..."` (case-insensitive), never both
- `--format json` produces structured output for every read; **mutations are silent on success** (use MCP if you need a structured write response)
- Text flags interpret `\n \t \r \\`; **stdin does not** (pass raw bytes)
- Tags: `#single`, `#multi word#`, `#nested/child` — strip surrounding `#` and whitespace in args
- Timestamps: ISO 8601 UTC

**Reads**

```bash
bearcli list --tag work --sort modified:desc -n 20 --format json
bearcli search "@today @todo" --format json --fields id,title,matches
bearcli search "@title meeting -draft" --count
bearcli cat <id>                                  # raw content
bearcli cat <id> --offset 0 --limit 500           # byte-range slice
bearcli show <id> --format json --fields all      # metadata (no content)
bearcli show <id> --format json --fields all,content
bearcli search-in <id> --string "TODO" --format json
```

**Writes**

```bash
# Create — capture id for follow-ups
ID=$(bearcli create "Daily Log" --tags "journal,daily" --format json --fields id | jq -r .id)
printf "# Daily Log\n\n- thing 1\n" | bearcli create "Daily Log"

# Append / prepend
bearcli append <id> --content "Update at 14:00"
bearcli append <id> --position beginning --content "TL;DR: ..."

# Exact-string edit (preferred over overwrite — preserves attachments)
bearcli edit <id> --find "TODO" --replace "DONE" --all
bearcli edit <id> --find "## Notes" --insert-after "\nNew bullet\n"

# Full overwrite WITH concurrency check (recommended)
HASH=$(bearcli show <id> --format json --fields hash | jq -r .hash)
bearcli overwrite <id> --base "$HASH" --content "# New title\nNew body"
```

**Organize**

```bash
bearcli tags add <id> work "work/meetings"
bearcli tags remove <id> draft
bearcli tags rename --from draft --to published
bearcli pin add <id> global
bearcli archive <id>          # hide from active list
bearcli trash <id>            # soft delete (restore with `bearcli restore`)
bearcli open <id> --edit      # bring Bear forward, cursor in editor
```

**Attachments**

```bash
bearcli attachments list <id> --format json
cat photo.jpg | bearcli attachments add <id> --filename photo.jpg
bearcli attachments save <id> --filename photo.jpg > photo.jpg
```

## Bear search syntax cheatsheet

Same syntax as the Bear app search bar. Use with `bearcli search "<query>"` or the MCP search tool.

| Category | Operators |
|----------|-----------|
| Text | `keyword`, `"exact phrase"`, `word1 or word2`, `-negation` |
| Tags | `#tag` (incl. children), `!#tag` (exact, no children), `#*/tag` (children only) |
| Dates (modified) | `@today`, `@yesterday`, `@last7days`, `@date(YYYY-MM-DD)`, `@date(<2026-01-01)` |
| Dates (created) | `@ctoday`, `@created7days`, `@cdate(YYYY-MM-DD)` |
| Tasks | `@todo` (has open), `@done` (all closed), `@task` (any) |
| Tag presence | `@tagged`, `@untagged` |
| Title-only | `@title meeting` (restricts text terms to titles) |
| Pins | `@pinned` (globally pinned) |
| Content kinds | `@images`, `@files`, `@attachments`, `@code` |
| State | `@locked`, `@readonly`, `@empty`, `@untitled` |
| Links | `@wikilinks`, `@backlinks` |
| Bear Pro | `@ocr` (search attachment text) |

Combine freely: `bearcli search "@today @todo meeting -cancelled"`.

## Safety gates (read before writing)

**Hash guard (`--base`)** — for `overwrite`. Pass the hash from a prior `show --fields hash`; the write fails if the note changed since. **Required** when calling via MCP; optional but recommended for CLI. Without it, you may clobber edits from the Bear app or sync.

**Attachment-removal gate (`--force`)** — `edit` and `overwrite` reject writes that drop attachments. Read the rejection message naming the dropped files, then re-run with `--force` only if intentional.

**`overwrite` semantics** — replaces the **entire** note. Bear derives title from the first `# heading` and tags from inline `#hashtags`; **preserve both in the new content** or they're removed. Inline attachment links must be preserved too. Prefer `edit` or `append` when possible.

**Modification date** — pass `--no-update-modified` on `edit`/`overwrite`/`append`/attachments if you want to keep the note's `modified` timestamp stable (useful for scripted tag cleanups).

## MCP surface

Already wired in `~/.claude/settings.json`:

```json
"bear": { "command": "/Applications/Bear.app/Contents/MacOS/bearcli", "args": ["mcp-server"] }
```

Tools cover the same operation set as the CLI subcommands. Notable divergences:
- `overwrite_note` **requires** `baseHash` (CLI may omit `--base`)
- MCP exposes `expectedRemovedAttachments` for declarative gating instead of `--force`
- CLI exposes `--force` / `--no-update-modified` for human ergonomics
- Each tool carries `readOnlyHint` / `destructiveHint` so Claude can gate destructive ops

If MCP tools aren't visible, the server may not have started — run `bearcli mcp-server` manually to check it boots, then restart Claude Code.

## Gotchas

- **Sandbox SIGABRT (exit 134)** — `bearcli` crashes inside Claude Code's bash sandbox with the same `SCDynamicStoreCreate NULL` pattern as `codex exec`. Workaround: `dangerouslyDisableSandbox: true` on `bearcli` Bash calls. Reads via MCP are unaffected.
- **`bearcli` not on PATH on a fresh machine** — the dotfiles `deploy.sh` symlinks it to `/usr/local/bin/bearcli` so `cron`/scripts find it. Without the symlink, only the shell alias works (won't apply in non-interactive shells).
- **Title matching is case-insensitive but not fuzzy** — if `--title "Mars"` errors, run `bearcli search "@title Mars" --format json` and use the returned ID.
- **`open` brings Bear to the foreground** — fine for interactive use, disruptive in scripts. Prefer `cat`/`show` for read-only access.
- **Encrypted notes** — `show`/`list`/`search` return metadata; `cat`, content-bearing `show --fields ...,content`, and `edit`/`overwrite` refuse.

## References

- Official CLI docs: <https://bear.app/faq/command-line-interface/>
- Bear 2.8 release notes: <https://blog.bear.app/2026/04/bear-2-8-bearcli-claude-connector-and-mcp-server/>
- Search syntax: <https://bear.app/faq/how-to-search-notes-in-bear/>
- Full command reference: `bearcli help all`
