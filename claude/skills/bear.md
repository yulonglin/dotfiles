---
name: bear
description: Read and edit Bear notes from a coding agent. macOS only. Mirrors Claude Code's Read/Edit/Write semantics onto bearcli (and the official Bear MCP). Use when reading, searching, creating, editing, tagging, archiving, or attaching files on Bear notes. Covers the surgical-edit playbook, hash-guarded overwrite, search syntax, and known failure modes.
---

# Bear Notes — Read/Edit playbook for coding agents

Bear is Yulong's note app. Treat its notes the way you'd treat source files:

| Claude Code tool | Bear equivalent | Notes |
|---|---|---|
| `Read` | `bearcli show <id> --format json --fields content,hash` | Always capture `hash` — it's your concurrency token |
| `Edit` (anchored find/replace) | `bearcli edit <id> --find … --replace …` | Exact-string match, must be unique unless `--all` |
| `Edit` (insert) | `bearcli edit <id> --find … --insert-after …` / `--insert-before …` | Anchored insert; no byte offsets |
| `Write` (full rewrite) | `bearcli overwrite <id> --base <hash> --content …` | **Always pass `--base`** — without it you can silently clobber concurrent edits |
| (new file) | `bearcli create "<title>" --content … --format json` | Returns `id` and `hash` — capture both |

**One rule, agent-facing:** if you didn't capture a `hash` in this session, you didn't read the note — re-read before writing.

Bear and bearcli ship in the same binary (Bear 2.8+). Both surfaces run **locally** against the Bear SQLite DB — no network, no telemetry. Encrypted notes show metadata but content is unreadable.

## CLI vs MCP — which one?

| Situation | Use | Why |
|---|---|---|
| Default: agent edits a note | **CLI** | Faster, scriptable, JSON output for parsing |
| Conversational, single-note edit inside Claude | **MCP** (`mcp__bear__*`) | Better destructive-action gating via `destructiveHint` |
| Write where the new note ID matters | CLI `create --format json` **or** MCP | Mutating CLI commands are otherwise silent |
| Safe overwrite | Either — both support hash guard | MCP **mandates** `baseHash`; CLI lets you omit `--base` (don't) |

MCP server is already wired in `~/.claude/settings.json`:

```json
"bear": { "command": "/Applications/Bear.app/Contents/MacOS/bearcli", "args": ["mcp-server"] }
```

The rest of this doc uses the CLI surface — MCP tool names map 1:1 to CLI subcommands.

## Surgical-edit playbook (the default workflow)

This mirrors how `Edit` works on source files. Use this for almost every modification.

```bash
# 1. Read — capture hash for later concurrency check
bearcli show "$ID" --format json --fields content,hash > /tmp/note.json
HASH=$(jq -r .hash /tmp/note.json)

# 2. Edit — anchored find/replace, must match a unique location
bearcli edit "$ID" --find "## Notes\n\n- old bullet" \
                   --replace "## Notes\n\n- new bullet"

# 3. Insert without replacing — anchor on an existing string
bearcli edit "$ID" --find "## Tasks\n" --insert-after "\n- [ ] new task\n"
bearcli edit "$ID" --find "## Tasks"   --insert-before "Intro paragraph.\n\n"

# 4. Batch edits in one transaction — pair flags positionally
bearcli edit "$ID" \
  --find "TODO" --replace "DONE" \
  --find "v1"   --replace "v2"

# 5. Whole-word, all occurrences (the analogue of replace_all + \b)
bearcli edit "$ID" --find "task" --replace "TASK" --all --word
```

**Properties — same as Claude Code's `Edit`:**
- Default rejects ambiguous matches: `Error: String matches N locations … provide more surrounding context` → add context or pass `--all`.
- Default rejects missing matches: edit fails, note untouched.
- Escape sequences `\n \t \r \\` are interpreted in `--find` / `--replace` / `--insert-*` (text flags) but **not** in stdin.
- `edit` is **silent on success** — exit code is the signal. Re-read with `show --fields content` if you need to verify.

**Locate before editing** when you're unsure:

```bash
bearcli search-in "$ID" --string "task" --format json   # offset + snippet for each hit
```

## Full-rewrite playbook (when `edit` won't do)

Reach for `overwrite` only when the change is structural (reordering sections, generating from a template). It replaces the entire note, so:

```bash
# 1. Read hash
HASH=$(bearcli show "$ID" --format json --fields hash | jq -r .hash)

# 2. Write with --base — fails (exit 1) if note changed since
printf '# %s\n\n%s\n\n%s' "$TITLE" "$BODY" "$INLINE_TAGS" \
  | bearcli overwrite "$ID" --base "$HASH"
```

**Mandatory invariants when rebuilding content:**
- Keep the first `# Heading` line — Bear derives the title from it.
- Preserve inline `#hashtag` lines — they ARE the note's tags.
- Preserve any inline attachment links — dropping them removes attachments. If the gate fires (`Error: removes N attachments — use --force to confirm`), re-run with `--force` only if intentional.

Without `--base`, `overwrite` is an unconditional clobber — verified empirically, it'll silently overwrite a note someone else just edited. **Never omit it in agent code.**

## Create a new note

```bash
# Returns {id,title,tags}; add --fields id,hash for follow-up edits
ID=$(bearcli create "Note title" --content "Body" --tags "work,draft" \
       --format json --fields id | jq -r .id)

# Idempotent create
bearcli create "Daily Log" --if-not-exists --format json
```

`--tags` inserts tags at Bear's configured top-or-bottom position; inline `#hashtag` lines in `--content` also work but won't be deduped against `--tags`.

## Organize: tag, pin, archive, trash

```bash
bearcli tags add    "$ID" work "work/meetings"
bearcli tags remove "$ID" draft
bearcli tags list   "$ID" --format json
bearcli tags rename --from old --to new          # refuses if 'new' already exists
bearcli tags rename --from old --to new --force  # MERGES (irreversible)

bearcli pin add    "$ID" global                   # or a tag name
bearcli pin remove "$ID" global
bearcli pin list   --format json                  # every pin context in use

bearcli archive "$ID"        # hide from active list
bearcli trash   "$ID"        # soft-delete (restorable)
bearcli restore "$ID"        # move back to active
bearcli open    "$ID" --edit # bring Bear forward — avoid in scripts
```

## Search

`bearcli search` accepts Bear's full app-search syntax. Combine freely.

```bash
bearcli search "@today @todo meeting -cancelled" --format json --fields id,title,matches
bearcli search "@title Mars" --format json | jq -r '.[].id'
bearcli list --tag work --sort modified:desc -n 20 --format json
```

| Category | Operators |
|---|---|
| Text | `keyword`, `"exact phrase"`, `word1 or word2`, `-negation` |
| Tags | `#tag` (incl. children), `!#tag` (exact, no children), `#*/tag` (children only) |
| Modified | `@today`, `@yesterday`, `@lastNdays`, `@date(YYYY-MM-DD)`, `@date(<2026-01-01)` |
| Created | `@ctoday`, `@createdNdays`, `@cdate(YYYY-MM-DD)` |
| Tasks | `@todo` (has open), `@done` (all closed), `@task` (any) |
| Tag presence | `@tagged`, `@untagged` |
| Title-only | `@title <term>` |
| Pins | `@pinned` |
| Content kinds | `@images`, `@files`, `@attachments`, `@code` |
| State | `@locked`, `@readonly`, `@empty`, `@untitled` |
| Links | `@wikilinks`, `@backlinks` |
| Bear Pro | `@ocr` |

## Attachments

```bash
bearcli attachments list "$ID" --format json
cat photo.jpg | bearcli attachments add "$ID" --filename photo.jpg
bearcli attachments save "$ID" --filename photo.jpg > photo.jpg
bearcli attachments delete "$ID" --filename photo.jpg
```

`edit`/`overwrite` that drops inline attachment links is rejected by default; pass `--force` to confirm.

## Conventions

- Identify a note by **ID** or `--title "..."` (case-insensitive). Prefer ID in scripts.
- Output: `--format tsv` (default, no header), `csv` (RFC 4180, with header), `json` (always structured).
- Exit codes: `0` success, `1` business error, `64` usage error. Mutations are silent on success — check `$?`.
- Errors: stderr (plain text) by default, stdout (`{"error":{"code":…,"message":…}}`) with `--format json`. Exit code unchanged.
- Timestamps: ISO 8601 UTC.
- Tags: `#single`, `#multi word#`, `#nested/child`. Surrounding `#` and whitespace stripped from args.
- `--no-update-modified` on `edit`/`overwrite`/`append`/attachments keeps the `modified` timestamp stable (useful for tag-only cleanups).

## Failure modes (verified empirically)

| # | Failure | Symptom | Mitigation |
|---|---|---|---|
| 1 | **Concurrent clobber** | `overwrite` without `--base` silently replaces a note edited elsewhere | Always pass `--base $HASH`. Stale hash → exit 1 with `Note has changed since last read` |
| 2 | **Ambiguous `--find`** | `edit` exit 1: `String matches N locations` | Add surrounding context to `--find`, or use `--all` (+ `--word` for whole-word) |
| 3 | **Find string missing** | `edit` exit 1, note untouched | `search-in` first to confirm presence |
| 4 | **Attachment-removal gate** | `edit`/`overwrite` exit 1 naming dropped files | Preserve inline attachment links, or pass `--force` deliberately |
| 5 | **`overwrite` strips title/tags** | Title regenerates from first `# heading`; missing inline `#tag` lines drop tags | Re-include `# heading` and `#tag` lines in new content |
| 6 | **Note lookup miss** | `{"error":{"code":"note_not_found",…}}`, exit 1 | Trap exit; resolve via `search` if title fuzzy. Trash/archive lookups need ID, not title |
| 7 | **Encrypted note** | Reads return metadata; `cat`/edit/overwrite refuse | Filter `locked` from `show --fields all` before bulk ops |
| 8 | **Sandbox SIGABRT (exit 134)** | `bearcli` aborts inside Claude Code's bash sandbox (configd NULL) | Pass `dangerouslyDisableSandbox: true` on every `bearcli` Bash call |
| 9 | **PATH absence in non-login shells** | `bearcli: command not found` in cron | Use absolute path `/Applications/Bear.app/Contents/MacOS/bearcli`, or rely on `/usr/local/bin/bearcli` symlink (deployed by dotfiles `deploy.sh`) |
| 10 | **`bearcli open` steals focus** | Brings Bear to foreground | Use `cat`/`show` for read; reserve `open` for explicit user-facing flows |
| 11 | **Stdin vs flag escaping mismatch** | `--content $'foo\n'` and `printf 'foo\n' \| bearcli …` both emit a real newline; but `--content 'foo\n'` (single quotes) is interpreted by bearcli, while stdin is passed verbatim | Pick one channel and stick to it. For multi-line content prefer stdin via `printf`/heredoc |
| 12 | **`tags rename --force` merges silently** | New tag pre-exists; default refuses, `--force` merges (no undo) | Check both populations with `list --tag` first |
| 13 | **MCP tools missing** | `mcp__bear__*` not visible in tool list | Boot manually: `bearcli mcp-server`; restart Claude Code if it errors. Verify `settings.json` entry intact |
| 14 | **Full Disk Access** | Reads from a fresh terminal app fail opaquely | Grant Full Disk Access to the terminal (System Settings → Privacy & Security) |

## References

- Official CLI docs: <https://bear.app/faq/command-line-interface/>
- Bear 2.8 release: <https://blog.bear.app/2026/04/bear-2-8-bearcli-claude-connector-and-mcp-server/>
- Search syntax: <https://bear.app/faq/how-to-search-notes-in-bear/>
- Full reference: `bearcli help all` (~1000 lines — pipe to a file)
