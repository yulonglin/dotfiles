---
name: bear
description: "Read and edit Bear notes via the Bear MCP (macOS only): search, create, edit, tag, archive, attach. Load before the first Bear MCP call in a session — it carries the size-then-outline read playbook and the search caps. Covers surgical edits and known failure modes."
---

# Bear Notes — Read/Edit playbook for coding agents

Bear is Yulong's note app. Treat its notes the way you'd treat source files. **Default to the Bear MCP** (`mcp__plugin_bear-mcp_bear__*`) — it has built-in destructive-action gating, mandatory `baseHash` on overwrite, and avoids the sandbox SIGABRT issue the CLI hits inside Claude Code.

**The server is `bearcli mcp-server`, from the `bear-mcp` plugin** (`productivity-tools` marketplace, enabled in `settings.json` since 2026-08-30 — before that it was configured but never actually enabled, so the tools were missing). It needs `bearcli` on PATH and Bear 2.8+, so it is macOS-only: on Linux the server will not start and `mcp__plugin_bear-mcp_bear__*` simply will not appear.

| Claude Code tool | Bear MCP equivalent | Notes |
|---|---|---|
| `Read` | `mcp__plugin_bear-mcp_bear__get_note` (metadata first), then `read_note_content` | `get_note` returns `length` in bytes; over ~15 KB, `read_note_outline` then `read_note_content(address=…)` — see **Read playbook** below. Content reads return the `hash` you pass as `baseHash` |
| `Edit` (find/replace, insert) | `mcp__plugin_bear-mcp_bear__edit_note` (with `edits: [...]`) | Each edit object: `find` + one of `replace`/`insertAfter`/`insertBefore`. Per-edit flags: `all`, `ignoreCase`, `word`. Atomic — any unmatched `find` aborts the whole call |
| `Write` (full rewrite) | `mcp__plugin_bear-mcp_bear__overwrite_note` (with `baseHash`) | MCP **mandates** `baseHash` — you cannot silently clobber |
| (new file) | `mcp__plugin_bear-mcp_bear__create_note` | Returns `id` and `contentHash` — capture both |

**One rule, agent-facing:** if you didn't capture a `contentHash` in this session, you didn't read the note — re-read before writing.

## Before the first call: load the schemas

The Bear tools are deferred, so their parameter names are unknown until ToolSearch loads them — and **the Bear server ignores an argument it does not know instead of rejecting it.** A guessed `section=` on `read_note_content` returns the whole note; the same guess on `edit_note` runs the find/replace across the whole note instead of one section. On 2026-10-08 three parallel `section=` reads each returned the full 43 KB reflection note.

So, before the first Bear call in a session, load every tool you expect to use in one call — `ToolSearch("select:mcp__plugin_bear-mcp_bear__get_note,mcp__plugin_bear-mcp_bear__read_note_outline,mcp__plugin_bear-mcp_bear__read_note_content,mcp__plugin_bear-mcp_bear__search_notes")`, adding the write tools when you will edit. The section argument is `address`, never `section` or `heading`.

`claude/hooks/guard_bear_mcp_args.sh` enforces this: it refuses an argument outside the tool's schema, and a `search_notes` or `list_notes` call without `limit` <= 10 (<= 3 with `includeContent`). If Bear adds a parameter, add it to that hook's `ALLOWED` table.

Bear and bearcli ship in the same binary (Bear 2.8+). The MCP server is `bearcli mcp-server` under the hood. Both surfaces run **locally** against the Bear SQLite DB — no network, no telemetry. Encrypted notes show metadata but content is unreadable.

## When to use the CLI instead

Reach for `bearcli` only when:

- You're writing a shell script or cron job (MCP not available outside Claude Code)
- You need flags MCP doesn't expose (`--no-update-modified`, `--if-not-exists`, batch `--find/--replace` pairs in one transaction, `--all --word`)
- You're composing with `jq` / pipes
- The user explicitly asks for CLI

When that happens, load [`references/cli.md`](references/cli.md) — full playbooks (surgical edit, full rewrite, create, tags/pins, search, attachments) + CLI-only gotchas (sandbox SIGABRT, PATH in cron, stdin/escape). The MCP tool surface maps 1:1 to CLI subcommands, so the playbooks transfer directly.

## Read playbook: check size, then outline, then sections

**Never open with `get_note(includeContent=true)` on a note you haven't sized.** A tool result over roughly 25k tokens is not returned — it is dumped to a file you then have to `jq`, and the content hash with it (a 57 KB daily-log note hit this on 2026-09-03). Journals, running logs and inventories are routinely that big.

```
# 1. Size — metadata only, cheap; `length` is UTF-8 bytes
mcp__plugin_bear-mcp_bear__get_note(id=ID)
  → { id, title, length: 57184, tags: [...], attachments: [...], ... }

# 2a. Small note (under ~15 KB): read it whole; the hash is your baseHash
mcp__plugin_bear-mcp_bear__read_note_content(id=ID)
  → { content: "...", hash: "abc123" }

# 2b. Large note: outline first — every section's address, offset and length
mcp__plugin_bear-mcp_bear__read_note_outline(id=ID)
  → { outline: [{ address: "## Thu, 3 Sep 2026", offset: 25, length: 6228 }, ...] }

# 3. Read only the section you need; its hash covers that section
mcp__plugin_bear-mcp_bear__read_note_content(id=ID, address="## Thu, 3 Sep 2026")

# 4. Edit inside that section — `address` confines every `find` to it
mcp__plugin_bear-mcp_bear__edit_note(id=ID, address="### Schedule", edits=[...])
```

"First section", "today's entry", "the top of the note" are all outline questions: answer them from step 2b, not by reading the whole note. An `address` on `edit_note` also makes short `find` strings safe in a note where the same text recurs across dated entries.

**Live notes move under you.** If the user is editing in Bear while you work, a `find` that matched a minute ago can fail with `string_not_found` — that is the atomic guard working. Re-read the section (step 3), not the whole note, and retry with the current text; keep each `find` to the smallest span that is still unique, so an edit elsewhere in the section does not invalidate it.

## Surgical-edit playbook (the default workflow)

This mirrors how `Edit` works on source files. Use this for almost every modification.

```
# 1. Read — size, outline if large, then the section; capture the hash
mcp__plugin_bear-mcp_bear__get_note(id=ID)                       # length, tags, attachments
mcp__plugin_bear-mcp_bear__read_note_content(id=ID, address=…)   # or whole note when small
  → { content: "...", hash: "abc123" }

# 2. Edit — anchored find/replace, must match a unique location
mcp__plugin_bear-mcp_bear__edit_note(
  id=ID,
  edits=[{
    find: "## Notes\n\n- old bullet",
    replace: "## Notes\n\n- new bullet",
  }],
)

# 3. Insert without replacing — anchor on an existing string
mcp__plugin_bear-mcp_bear__edit_note(id=ID, edits=[{ find: "## Tasks\n", insertAfter: "\n- [ ] new task\n" }])
mcp__plugin_bear-mcp_bear__edit_note(id=ID, edits=[{ find: "## Tasks",   insertBefore: "Intro paragraph.\n\n" }])

# 4. Batch atomic edits in one call — all-or-nothing
mcp__plugin_bear-mcp_bear__edit_note(id=ID, edits=[
  { find: "TODO", replace: "DONE" },
  { find: "v1",   replace: "v2"   },
])

# 5. Whole-word, all occurrences (the analogue of replace_all + \b)
mcp__plugin_bear-mcp_bear__edit_note(id=ID, edits=[{ find: "task", replace: "TASK", all: true, word: true }])
```

**Properties — same as Claude Code's `Edit`:**
- Default rejects ambiguous matches: error names N locations → add context to `find` or pass `all: true`.
- Default rejects missing matches: edit fails atomically, note untouched.
- `\n \t \r \\` are interpreted in `find` / `replace` / `insertAfter` / `insertBefore`.
- `edit_note` returns only the metadata fields that changed — inspect the response to catch unintended drops (e.g. a tag).

**Locate before editing** when you're unsure: `mcp__plugin_bear-mcp_bear__search_in_note(id=ID, string="task")` returns offset + snippet for each hit.

## Full-rewrite playbook (when `edit_note` won't do)

Reach for `overwrite_note` only when the change is structural (reordering sections, generating from a template). It replaces the entire note, so:

```
# 1. Read — metadata response always includes contentHash
{ contentHash } = mcp__plugin_bear-mcp_bear__get_note(id=ID)

# 2. Write with baseHash — fails if note changed since
mcp__plugin_bear-mcp_bear__overwrite_note(
  id=ID,
  baseHash=contentHash,
  content=f"# {title}\n\n{body}\n\n{inline_tags}",
)
```

**Mandatory invariants when rebuilding content:**
- Keep the first `# Heading` line — Bear derives the title from it.
- Preserve inline `#hashtag` lines — they ARE the note's tags.
- Preserve any inline attachment links — dropping them removes attachments. If the change deliberately drops one, declare it via `expectedRemovedAttachments: ["photo.jpg"]`. Otherwise prefer the dedicated `delete_attachment` call.

MCP **requires** `baseHash` — you can't silently clobber. (The CLI lets you omit `--base`; never do.)

## Create a new note

```
{ id, contentHash } = mcp__plugin_bear-mcp_bear__create_note(
  title="Note title",
  content="Body",
  tags=["work", "draft"],
)

# Idempotent create — returns existing note if title already exists
mcp__plugin_bear-mcp_bear__create_note(title="Daily Log", ifNotExists=true)
```

Tags are inserted at Bear's configured top-or-bottom position; inline `#hashtag` lines in `content` also work but won't be deduped against `tags`.

## Organize: tag, pin, archive, trash

| Action | Tool |
|---|---|
| Add / remove / list / rename tags | `mcp__plugin_bear-mcp_bear__add_tags`, `remove_tags`, `list_tags`, `rename_tag` |
| Delete a tag globally | `mcp__plugin_bear-mcp_bear__delete_tag` |
| Pin / unpin / list pins | `mcp__plugin_bear-mcp_bear__add_pins`, `remove_pins`, `list_pins` |
| Archive (hide from active) | `mcp__plugin_bear-mcp_bear__archive_note` |
| Trash (soft-delete, restorable) | `mcp__plugin_bear-mcp_bear__trash_note` |
| Restore from trash/archive | `mcp__plugin_bear-mcp_bear__restore_note` |
| Open in Bear UI (steals focus — avoid unless user asked) | `mcp__plugin_bear-mcp_bear__app_open_note` |
| Append text to end of note | `mcp__plugin_bear-mcp_bear__append_to_note` |
| Attachments: list / delete / add from an HTTPS URL | `mcp__plugin_bear-mcp_bear__list_attachments`, `delete_attachment`, `add_attachment_from_url` — reading attachment bytes has no MCP tool; use `bearcli attachments save` ([`references/cli.md`](references/cli.md)) |

`rename_tag` with `force: true` MERGES tags irreversibly — check both populations first via `list_notes(tag=..., limit=0)` (counts only).

## Search

`mcp__plugin_bear-mcp_bear__search_notes` accepts Bear's full app-search syntax. Returns notes with per-note match counts.

**Always pass `limit`** (at most 10; `limit: 0` returns only the count). Without it every match comes back: loose words like `working with me` matched 98 notes on 2026-10-08 when the lookup needed one title. **To find a note by name, search the title for an exact phrase** — `query="@title \"work-with-me\""` — not common words that recur in note bodies. A sweep across many notes belongs in a subagent (`rules/delegation.md`).

```
mcp__plugin_bear-mcp_bear__search_notes(query="@today @todo meeting -cancelled", limit=10)
mcp__plugin_bear-mcp_bear__search_notes(query="@title Mars", limit=5)
mcp__plugin_bear-mcp_bear__list_notes(tag="work", sort="modified:desc", limit=10)
```

Pass `includeContent: true` on either to also pull each note's raw Markdown body (excludes locked notes).

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

## Conventions

- **Todos and separate points are bullet lists, one item per line.** A task is its own `- [ ]` line so it can be ticked; sub-points nest two spaces under their parent. Never pack several items into one line with commas, semicolons or "then" — `- [ ] 19:30 session 2 — jobs 20m; then pings: A, B, C` becomes a `session 2` line with `jobs` and `pings` nested under it and A, B, C nested under `pings`. Match the marker the note already uses (`- [ ]` in a task list, `-` in a plain list).
- Identify a note by **ID** or title (case-insensitive). Prefer ID once you have one.
- Tags: `#single`, nested `#parent/child`. Surrounding `#` and whitespace are stripped from args. Spaces are allowed inside tag names.
- Timestamps: ISO 8601 UTC.
- Mutating tools (`edit_note`, `overwrite_note`, `append_to_note`, `add_tags`, …) return **only the metadata fields that changed** — inspect the response to catch unintended drops.
- For modification-date-preserving cleanups (e.g. tag-only bulk fixes), use the CLI's `--no-update-modified` flag — MCP doesn't expose this.
- Math (Bear 2.5+): `$...$` inline, `$$...$$` block — rendered live in the editor via MathJax. Escape literal dollar signs as `\$` so prices/amounts don't accidentally trigger math rendering.

## Failure modes (verified empirically)

| # | Failure | Mitigation |
|---|---|---|
| 1 | **Concurrent clobber risk** | MCP `overwrite_note` requires `baseHash` — pass it from a recent `get_note`. Stale hash → call fails with "Note has changed since last read" |
| 2 | **Ambiguous `find`** | Add surrounding context, or pass `all: true` (+ `word: true` for whole-word) |
| 3 | **Find string missing** | `search_in_note` first to confirm presence |
| 4 | **Attachment-removal gate** | `edit_note`/`overwrite_note` refuses to drop inline attachment links. Preserve them, or declare the intended drops via `expectedRemovedAttachments: ["name.ext", ...]`. For pure deletes prefer `delete_attachment` |
| 5 | **`overwrite_note` strips title/tags** | Title regenerates from first `# heading`; missing inline `#tag` lines drop tags. Re-include both in new content |
| 6 | **Note lookup miss** | Resolve via `search_notes` if title fuzzy. Trash/archive lookups need ID, not title |
| 7 | **Encrypted note** | Reads return metadata only; edit/overwrite refuse. Filter `locked` from list results before bulk ops |
| 8 | **MCP tools missing from tool list** | They are deferred first: `ToolSearch("bear")` waits for a still-connecting server. If still absent, check `enabledPlugins` in `~/.claude/settings.json` has `"bear-mcp@productivity-tools": true`, then restart Claude Code. As a one-off, you can boot manually via `bearcli mcp-server` |
| 9 | **Full Disk Access** | Reads from a fresh terminal app fail opaquely. Grant Full Disk Access in System Settings → Privacy & Security |
| 11 | **Large note overflows the tool result** (`get_note(includeContent=true)` on a long journal comes back as "exceeds maximum allowed tokens" plus a dump file) | Size first with `get_note` (no content), then `read_note_outline` and `read_note_content(address=…)` — the **Read playbook** above. Don't `jq` the dump file; you'd still be holding a stale hash |
| 12 | **`find` matched a minute ago, now `string_not_found`** | The note changed under you (user editing live). Re-read only that section by `address`, retry with the current text, and shorten each `find` to the smallest unique span |
| 13 | **A guessed argument is silently ignored** (`section=` on `read_note_content` returned the whole 43 KB note, three times in parallel, 2026-10-08) | Load the schemas first — **Before the first call** above. The section argument is `address`. `guard_bear_mcp_args.sh` now refuses unknown keys |
| 14 | **Search returns every match** (`search_notes` with no `limit` returned 98 notes of metadata) | Pass `limit` <= 10, search `@title "exact phrase"`, and sweep in a subagent. The hook refuses a missing or larger `limit` |
| 10 | **Dollar amounts render as garbled math** (e.g. `$5 ... $10` becomes math in the editor) | An unescaped `$`-pair triggered MathJax (Bear 2.5+, editor/reading view). Escape literal dollar signs as `\$` |

For CLI-specific failure modes (sandbox SIGABRT, PATH issues in cron, stdin/flag escaping), see [`references/cli.md`](references/cli.md).

## References

- Official CLI/MCP docs: <https://bear.app/faq/command-line-interface/>
- Bear 2.8 release (CLI + Claude connector + MCP): <https://blog.bear.app/2026/04/bear-2-8-bearcli-claude-connector-and-mcp-server/>
- Search syntax: <https://bear.app/faq/how-to-search-notes-in-bear/>
- CLI reference (for scripting/cron): [`references/cli.md`](references/cli.md)

## Bear-flavoured Markdown

Bear's own FAQ omits the colour encoding, so Yulong's copied-from-Bear examples are the source of truth: highlight is `==text==`, a coloured highlight is a coloured-dot emoji at the START of the span (`==🔴text==`, where 🔴 means flag this / verify before shipping; `==🟢proofread by Claude Fable 5.1, 8 Sep==`, where 🟢 means checked and clear), strikethrough is `~~text~~`, and underline is `~text~`. Don't use `==` or `~text~` in files that render as plain GitHub Markdown.

**Nothing separates the colour emoji from the text it marks** — `==🔴not recorded==`, never `==🔴 not recorded==`. The dot is a marker glued to the front of the span, not a word inside it, and a stray space renders as a gap in the highlight. This holds for every colour, not only 🔴.

**Wikilinks are how the vault cross-references itself.** A link to another note is `[[Note Title]]`, and it resolves by **title**, not by ID — the same title lookup the rest of this skill uses, so it is case-insensitive and matches the note's first `# Heading` (Bear derives the title from that line). `search_notes(query="@wikilinks", limit=10)` finds notes that contain one and `@backlinks` finds notes that are linked to, so both are searchable state, not decoration.

Two consequences for editing:

- **`overwrite_note` that changes the first `# Heading` changes the note's title, and therefore what every inbound `[[...]]` was pointing at.** Before rewriting a heading, run `search_notes(query="@wikilinks \"Old Title\"", limit=10)` to see who links in. This skill does not document whether Bear repairs those links itself — check the affected notes rather than assuming either way.
- `[[Note Title]]` is a `find` anchor like any other string, so `edit_note` can retarget links in bulk (`{ find: "[[Old Title]]", replace: "[[New Title]]", all: true }`).

As with `==` and `~text~`, `[[...]]` does not link in files that render as plain GitHub Markdown.
