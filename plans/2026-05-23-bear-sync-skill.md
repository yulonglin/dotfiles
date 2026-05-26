# Bear ↔ Markdown Sync Skill (v11)

> **Plan-review iteration:**
> - v2 addressed Codex v1 feedback (P0 hash-safety, P1 CLI inconsistency, P1 `bearcli` PATH, P1 tags/attachments handling, P2 hash definition, P2 ID stability).
> - v3 addressed Codex v2 feedback: narrowed MCP claim (still launches `bearcli` by absolute path; FDA still required) + added Flow 0 Preflight; added tool-namespace verification as Task 1.0 (observed `mcp__Bear__*` with capital B); resolved manifest/frontmatter contradiction via new Flow F (`relink`).
> - v4 addressed Codex v3 feedback: aligned Decision 1 with Flow 0; split Flow C into directional batches; defined the `uninitialized` bucket explicitly.
> - v5 addressed Codex v4 feedback: Flow C pre-scan now classifies a `v1-refused` bucket; Flow B `push` on uninitialized entries refuses.
> - v6 addressed Codex v5 feedback: Flow B update path applies the repo-side V1 gate; Flow C pre-scan adds `frontmatter-missing`, `mapping-mismatch`, and `v1-refused-repo` hard-skip buckets.
> - v7 addressed Codex v6 feedback: made the initialization lifecycle internally consistent (only `import`/`relink` initialize); restructured Flow C's `v1-refused-repo` as direction-dependent classification.
> - v8 addressed Codex v7 feedback: Flow E `status` hint aligned with rest of plan.
> - v9 addressed Codex v8 feedback: Flow C now acts on all three drift buckets in both directions, with optional auto-resolve sub-prompt.
> - v10 addressed Codex v9 feedback: Flow C revalidates per-note before each write (closes batch TOCTOU).
> - v11 addresses Codex v10 feedback: `to bear` revalidation full 2x2 table — when repo SHA reverts to `content_sha256_at_sync` mid-batch, branch on the Bear-side state instead of always aborting as `in-sync`. If Bear drifted at scan, reclassify as `bear-only-changed` and surface Bear-side-changed Conflict UX. Prevents silent skip of a note that still has unsynced Bear edits.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Selective, per-invocation unidirectional sync between Bear notes and markdown files in a code repo. Enables Claude (and cross-machine via git) to read/edit Bear-drafted notes.

**Architecture:** Skill-only — no Python CLI. Bear I/O via the Bear MCP server (`mcp__Bear__*` tool family, already wired in `~/.claude/settings.json`). Manifest is plain JSON read/written by Claude. A small Python canonicalization helper (`claude/skills/bear-sync/lib/canonicalize.py`) runs inline via `uv` for deterministic hashing.

**Tech Stack:** Markdown skill, Bear MCP, git, Python (one helper script, `uv run --script`).

---

## Changes from v1

| # | v1 issue (Codex) | v2 resolution |
|---|------------------|---------------|
| P0 | mtime as concurrency token can clobber Bear edits | **Bear `hash` is the concurrency token.** MCP `overwrite_note` mandates `baseHash`. mtime is demoted to UX hint only. |
| P1 | Tags / inline `#tag` lines silently dropped; attachments break overwrite | **V1 refuses notes with tags or attachments.** Skill checks `get_note` response; if non-empty `tags` or `has_attachments`, return clear error + how to proceed. Round-tripping deferred to Phase 2. |
| P1 | `--path` referenced but undeclared; `to-bear --file` ambiguous | **No CLI.** Skill flows define bootstrap semantics in prose (with explicit example invocations). |
| P1 | `bearcli` PATH absent; sandbox SIGABRT | **Avoids PATH lookup and shell sandbox.** MCP server is launched by absolute path from `~/.claude/settings.json` (`/Applications/Bear.app/Contents/MacOS/bearcli mcp-server`). FDA still required (the launched process reads Bear's SQLite), and the MCP server itself can be unavailable. **Skill enforces explicit preflight** — see Flow 0 below. |
| P2 | `content_sha256` bytes undefined | **Canonical content form defined** — frontmatter stripped, line endings normalized, trailing whitespace stripped, SHA-256. Implemented once in `canonicalize.py`. |
| P2 | "Bear IDs stable across iCloud" unverified | **Phase 0 (blocking)**: validate ID stability across two devices before Phase 1 ships. Documented finding in skill README. |

---

## Key Design Decisions

| # | Decision | Why |
|---|----------|-----|
| 1 | **Skill-only, no CLI** | MCP's mandatory `baseHash` is the safety primitive. Avoids PATH lookup and shell sandboxing — but **still depends on Bear MCP visibility and Bear DB access (Full Disk Access)** at runtime; both are first-class preflight checks (Flow 0). CLI doesn't add enough to justify V1 complexity. Extract later if cron need appears. |
| 2 | **Bear `hash` is the concurrency token** | Authoritative per `claude/skills/bear.md`; verified in Bear 2.8 docs. mtime drops to UX hint. |
| 3 | **Manifest-as-scope** (no Bear tags) | Cleaner mental model; explicit registration. |
| 4 | **Per-repo manifest, committed** | Enables cross-machine via git (validated in Phase 0). |
| 5 | **V1 refuses notes with tags or attachments** | Round-trip semantics are non-trivial. Refuse-with-message is cheap and honest. |
| 6 | **Canonical content form for drift detection** | Single defined algorithm; same bytes on both sides → same hash. Implementation lives in one helper. |
| 7 | **Python helper, not a CLI** | One `canonicalize.py` script invoked inline. Not a packaged tool; just deterministic hashing. |

---

## Manifest Schema (`.bear-sync.json`)

```json
{
  "version": 1,
  "notes": {
    "ABC-123-XYZ": {
      "repo_path": "notes/foo.md",
      "title": "Foo",
      "last_sync_at": "2026-05-24T10:00:00Z",
      "last_sync_direction": "bear-to-repo",
      "bear_hash_at_sync": "<hash returned by MCP get_note>",
      "content_sha256_at_sync": "def123...",
      "repo_mtime_at_sync": "2026-05-24T10:00:00Z"
    }
  }
}
```

**Field semantics:**
- `bear_hash_at_sync` — `hash` field returned by `mcp__Bear__get_note` at last sync. Passed as `baseHash` on the next `overwrite_note` call. **Authoritative safety primitive.**
- `content_sha256_at_sync` — SHA-256 of canonical content. Used to detect "repo side changed since last sync" (mirror of `bear_hash` on the Bear side).
- `repo_mtime_at_sync` — UX hint only. Helps distinguish "edited" from "git pull touched it" in the drift summary. Not a safety check.
- No `bear_mtime_at_sync` — Bear's `hash` already does that job.

**Canonical content form** (algorithm in `canonicalize.py`):

1. If input has YAML frontmatter (between two `---` lines at start), strip it.
2. Normalize line endings: `\r\n` → `\n`, `\r` → `\n`.
3. Strip trailing whitespace from each line (spaces, tabs).
4. Strip trailing blank lines from end of content.
5. Ensure single trailing newline.
6. SHA-256 hex digest of the resulting UTF-8 bytes.

Same algorithm runs on Bear's body (from `get_note` content) and the markdown file's body. Both sides → same hash.

---

## Skill Flows

### Trigger phrases

The skill activates on phrases like:
- "import bear note <id> [into <path>]"
- "push <file> to bear" / "sync <file> to bear"
- "sync bear notes" / "sync all"
- "bear sync status" / "what's the drift?"
- "register bear note <id> as <path>"
- "unregister bear note <id>"
- "relink <repo-path>" (recover from orphaned frontmatter — see Flow F)

---

### Flow 0 — Preflight (runs before any other flow)

Every other flow must pass these checks first; failure halts with the named error.

1. **macOS check:** `uname -s` is `Darwin`. Otherwise: `Bear is macOS-only. This skill cannot run here.`
2. **Bear app present:** `/Applications/Bear.app` exists. Otherwise: `Bear app not installed. Install from https://bear.app and rerun.`
3. **Bear MCP tools visible:** attempt a no-op read (e.g., `mcp__Bear__list_tags` with empty args, or `mcp__Bear__list_notes` with a tight limit). Catch tool-missing error.
   - If missing: `Bear MCP tools not visible to Claude. Boot manually: open a terminal and run \`/Applications/Bear.app/Contents/MacOS/bearcli mcp-server\`, then restart Claude Code.`
4. **Bear DB readable (Full Disk Access):** if the read returns a permission/SQLite-access error, surface FDA setup: `Bear's database is not readable — typically a Full Disk Access issue. Open System Settings → Privacy & Security → Full Disk Access, add the Claude Code app (or Terminal if launched from there), restart Claude Code, and retry.`
5. **In a git repo:** `git rev-parse --show-toplevel`. Otherwise: `bear-sync requires a git repo (manifest lives at repo root).`

Preflight is cheap (one read call) and runs every invocation. No caching — if Bear was running and gets quit between invocations, we want to catch that fresh.

---

### Flow A — `import bear note <bear-id> [into <repo-path>]`

1. **Preflight** (Flow 0).
2. **Fetch from Bear:** `mcp__Bear__get_note(id=<bear-id>)` → capture `content`, `hash`, `title`, `tags`, `has_attachments` (or whatever MCP returns — verify in Task 1.1).
3. **V1 gate:** if `tags` non-empty OR `has_attachments`, refuse:
   > `Note <id> has tags or attachments. V1 doesn't round-trip these — see Phase 2. To proceed: remove tags/attachments in Bear, or wait for V2.`
4. **Resolve `repo_path`:**
   - Argument provided → use it (relative to repo root).
   - Else manifest already has entry for this `bear_id` → use stored `repo_path`.
   - Else default: `notes/<slugified-title>.md`.
5. **Destination check:**
   - If file doesn't exist → safe to write.
   - If file exists AND in manifest with matching `bear_id`:
     - Compute `content_sha256` of current file body (via `canonicalize.py`).
     - If matches `content_sha256_at_sync` → repo unchanged → safe to overwrite.
     - Else → repo changed; trigger **Conflict UX: repo-side changed** (see below).
   - If file exists with `bear_id` in frontmatter but **no manifest entry**: refuse with `Orphaned frontmatter at <repo-path> — manifest entry missing. Run \`relink <repo-path>\` first.` (See Flow F.)
   - If file exists with **no `bear_id` frontmatter** and not in manifest: this is an unrelated file at the destination. Refuse with `<repo-path> exists and is not a synced Bear note. Pick a different path or remove the file.`
6. **Write file:** YAML frontmatter + Bear body.
   ```yaml
   ---
   bear_id: ABC-123-XYZ
   title: Foo
   synced_at: 2026-05-24T10:00:00Z
   ---
   <Bear content>
   ```
7. **Update manifest:** `bear_hash_at_sync`, `content_sha256_at_sync`, `repo_mtime_at_sync`, `last_sync_at`, `last_sync_direction: "bear-to-repo"`.
8. **Report:** `Imported "<title>" → <repo-path> (bear_id=<id>)`.

---

### Flow B — `push <repo-path> to bear`

1. **Preflight** (Flow 0).
2. **Read repo file**, separate frontmatter from body.
3. **Determine bear_id and route:**
   - Frontmatter has `bear_id` AND manifest has **initialized** entry with matching `bear_id` → **update path** (steps 4b–10b).
   - Frontmatter has `bear_id` AND manifest has **uninitialized** entry (from `register`) with matching `bear_id` → refuse: `Entry is uninitialized — Bear's current state has never been compared to this file. Run \`import bear note <bear_id>\` (Bear → repo) or \`relink <repo-path>\` (reconcile first) before pushing.` We do **not** push blindly into a Bear note we've never read.
   - Frontmatter has `bear_id` AND manifest entry has a **different** `bear_id` → refuse: `Mismatch: manifest says <id-A>, file frontmatter says <id-B>. Resolve by editing one to match.`
   - Frontmatter has `bear_id` BUT manifest has **no** entry → refuse with `Orphaned frontmatter at <repo-path> — manifest entry missing. Run \`relink <repo-path>\` first.`
   - **No `bear_id` in frontmatter AND manifest has entry for this `repo_path`** → refuse with `Frontmatter missing \`bear_id\` (manifest says <id>). This is ambiguous — was the file freshly created, or was the frontmatter stripped by accident? Run \`import bear note <id>\` to restore frontmatter from Bear, or edit the file to add \`bear_id: <id>\` if you're certain it should map to that note.` (Previously this path auto-bound via the manifest; that's removed because it can silently mis-attach a freshly-written file to an unrelated note.)
   - No frontmatter `bear_id` AND no manifest entry → **bootstrap** (steps 4a–7a).

**Bootstrap (new Bear note):**

4a. V1 gate on body: scan for inline `#tag` lines or attachment markers (`[image:...]`, `![alt](file://...)`). If found, refuse with same message as Flow A step 3.
5a. `mcp__Bear__create_note(title=<from frontmatter or first H1>, content=<body>)` → capture new `id` and `hash`.
6a. Write `bear_id` (and other frontmatter fields) into the markdown file.
7a. Add manifest entry. Report: `Created Bear note <id> from <repo-path>`.

**Update (existing Bear note):**

4b. `mcp__Bear__get_note(id=<bear_id>)` → capture current `hash`, `content`, `tags`, `has_attachments`.
5b. **V1 gate (Bear-side):** if Bear has `tags` non-empty OR `has_attachments`, refuse with the V1 message.
5b-2. **V1 gate (repo-side, applies to update path too):** scan the outgoing markdown body (post-frontmatter strip) for inline `#tag` lines or attachment markers (`[image:...]`, `![alt](file://...)`, Bear's attachment placeholder syntax — see SKILL.md scan rules). If found, refuse: `<repo-path> would introduce tags or attachments into Bear note <bear_id>. V1 doesn't round-trip these — see Phase 2. To proceed: remove them from the repo file, or wait for V2.` This blocks a sync-then-edit-to-add-tags exploit of the update path.
6b. **Bear-side drift check:**
   - Compute `content_sha256` of Bear's body.
   - If matches `content_sha256_at_sync` → Bear unchanged → safe path.
   - Else → Bear changed; trigger **Conflict UX: bear-side changed**.
7b. **Repo-side staleness check (combo case):**
   - Compute `content_sha256` of repo file body.
   - If repo also differs from `content_sha256_at_sync` AND Bear differs → **both-changed** conflict.
8b. **Write to Bear:** `mcp__Bear__overwrite_note(id=<bear_id>, content=<new>, baseHash=<bear_hash_at_sync>)`.
   - On stale-hash error from MCP (Bear was edited between our `get_note` and `overwrite_note` — a third-party race): treat as bear-side-changed, re-prompt. If it happens twice in a row, ask user to wait and retry.
9b. Update manifest with new `bear_hash_at_sync`, `content_sha256_at_sync`, etc.
10b. Report: `Pushed <repo-path> → Bear note <bear_id>`.

---

### Flow C — `sync all from bear` / `sync all to bear` (directional batch)

**A single `sync all` invocation is directional, matching V1's per-invocation unidirectional safety model.** There is no mixed-direction batch — running both directions requires two explicit invocations.

Trigger forms (both must be supported):
- `sync all from bear` — Bear is the source of truth for this batch. Equivalent to running Flow A on every drifted entry.
- `sync all to bear` — repo is the source of truth for this batch. Equivalent to running Flow B on every drifted entry.

Steps:

1. Preflight (Flow 0).
2. Iterate manifest entries. For each, **fetch Bear via `get_note` once** and capture `content`, `hash`, `tags`, `has_attachments` (the V1-gate fields). Also read the repo file (if present) and parse its frontmatter (extract `bear_id` if any) + compute `content_sha256` of canonical body + scan body for repo-side V1 markers (inline `#tag` lines, attachment markers). Classify into **hard-skip buckets first**, then drift buckets:

   Bucket classification is **direction-aware**: the requested direction (`from bear` or `to bear`) is known at scan time and determines which markers are hard-skips vs warnings.

   **Direction-independent hard-skips (never written by batch, either direction):**
   - `uninitialized` — entry has no `bear_hash_at_sync` / `content_sha256_at_sync` (from `register`, never imported/pushed). Hint: "run `import` or `relink` to initialize. `push` does not initialize."
   - `bear-missing` — `get_note` returns not-found. Per-entry prompt regardless of direction.
   - `repo-missing` — `repo_path` doesn't exist on disk. Per-entry prompt regardless of direction.
   - `v1-refused-bear` — Bear note has non-empty `tags` or `has_attachments`. Hint: "remove tags/attachments in Bear, or wait for V2".
   - `frontmatter-missing` — repo file exists, manifest entry exists, but file has **no** `bear_id` in frontmatter. Hint: "run `import bear note <id>` to restore frontmatter, or add `bear_id: <id>` manually".
   - `mapping-mismatch` — repo file frontmatter has a `bear_id` that **differs** from the manifest entry's `bear_id`. Hint: "manifest says <id-A>, file frontmatter says <id-B>. Resolve manually before sync".

   **Direction-dependent classification:**
   - Repo body has inline `#tag` lines or attachment markers:
     - Under `to bear` → bucket `v1-refused-repo` (hard-skip). Hint: "remove tags/attachments from repo file, or wait for V2."
     - Under `from bear` → not a write blocker (Bear is the source; the write replaces the repo body), but emit a **warning row** in the summary: "repo body has V1-unsupported markers — `to bear` will refuse this note until you remove them. Proceeding `from bear` will overwrite them." Classification proceeds to a drift bucket below.

   **Drift buckets (eligible for the requested direction):**
   - `in-sync` — both sides match `*_at_sync`. Skipped silently.
   - `bear-only-changed` — Bear hash differs from `bear_hash_at_sync`, repo SHA matches.
   - `repo-only-changed` — repo SHA differs, Bear hash matches.
   - `both-changed` — both differ.
3. Print summary table grouped by bucket, with the hint string per bucket. Hard-skip buckets are visible to the user but never acted on.
4. **Actionable buckets per direction** (hard-skip buckets and direction-dependent skips from step 2 are already removed). Both directions act on **all three drift buckets** — the difference is which side wins by default and which UX prompt fires when the destination has drifted:

   | Bucket | `from bear` action | `to bear` action |
   |--------|-------------------|------------------|
   | `bear-only-changed` | **Write without prompt** (repo matches sync state) — write Bear → repo | Bear-side-changed Conflict UX (Bear advanced; user picks: overwrite Bear / skip / merge) |
   | `repo-only-changed` | Repo-side-changed Conflict UX (repo advanced; user picks: overwrite repo / skip / merge) | **Write without prompt** (Bear matches sync state) — write repo → Bear |
   | `both-changed` | Both-changed Conflict UX | Both-changed Conflict UX |
   | `bear-missing` | Per-entry prompt regardless of direction | Per-entry prompt regardless of direction |
   | `repo-missing` | Per-entry prompt regardless of direction | Per-entry prompt regardless of direction |

   No bucket is "opposite-direction skipped" — every drift bucket has defined behavior in both directions. The single-note flows (A/B) already prompt on destination drift; batch mode preserves that.

5. **Batch prompt:** show summary (with bucket counts and per-conflict count). Prompt: `Process N notes in direction <from-bear|to-bear>? [y/N]`. Default no.
   - Optional sub-prompt: `Auto-resolve K conflicts in favor of source side? [y/N]` — if yes, force-overwrite destination on all conflicts in this batch without per-entry prompting. Default no (per-entry prompting).
6. **Per acted-on note**, hand off to the matching flow's write step. Bucket-membership gates (`v1-refused-bear`, `v1-refused-repo`, `frontmatter-missing`, `mapping-mismatch`, `uninitialized`) were enforced in step 2 and the entries removed; they don't reach this step. **But state can drift between step 2 and the actual write** (the batch prompt, optional auto-resolve prompt, and per-conflict prompts all widen the check→write window). Each per-note write **revalidates first** with cheap local rechecks, and aborts the note if state diverged:

   **Repo-side revalidation (before any write that touches repo OR before any Bear write that uses the repo body):**
   - Re-read the file; re-parse frontmatter; re-extract `bear_id`.
   - If frontmatter `bear_id` no longer matches manifest's entry → abort note, surface: `<repo-path> frontmatter changed during batch (now bear_id=<id-X>, expected <id-Y>). Skipped — rerun \`sync all\` to reclassify.`
   - If frontmatter `bear_id` disappeared → abort note, surface: `<repo-path> frontmatter stripped during batch. Skipped — rerun \`sync all\` to reclassify.`
   - Re-scan body for repo-side V1 markers (inline `#tag`, attachment markers).
     - Under `to bear` → if markers now present → abort note, surface as `v1-refused-repo` (no Bear write).
     - Under `from bear` → record but don't abort (Bear's content will overwrite the markers anyway, matching step 2's classification).
   - Recompute repo `content_sha256` (canonical form).
     - Under `from bear` writing to a repo: if new SHA differs from the SHA captured in step 2, the file changed since the scan — abort note, surface: `<repo-path> changed during batch. Skipped — rerun \`sync all\` to reclassify, or use single-note import.` (We don't silently apply step 2's decision to a now-different file.)
     - Under `to bear`: if new SHA differs from step 2's, the body we're about to push has changed. Reclassify locally based on the **current** SHA pair (Bear's pre-scan hash vs `bear_hash_at_sync`, AND new repo SHA vs `content_sha256_at_sync`):
       - new repo SHA still ≠ `content_sha256_at_sync` AND Bear matched at scan → still `repo-only-changed`; proceed with new body.
       - new repo SHA still ≠ `content_sha256_at_sync` AND Bear drifted at scan → still `both-changed`; surface both-changed Conflict UX with new body.
       - new repo SHA = `content_sha256_at_sync` AND Bear matched at scan → reclassify as `in-sync`; abort silently (no push needed).
       - new repo SHA = `content_sha256_at_sync` AND Bear drifted at scan → reclassify as `bear-only-changed`; surface Bear-side-changed Conflict UX (do NOT abort as `in-sync` — Bear still has unsynced edits). User can pick: pull Bear → repo (effectively a `from bear` on this note), keep Bear, or skip.
   - Bear-side revalidation: `baseHash` enforced by MCP on `overwrite_note`. If stale, treat as bear-side-changed (re-fetch, re-prompt per Conflict UX) — this remains the per-note safety primitive on the Bear side.

   **Then run the direction-specific flow step:**
   - `from bear`: Flow A's write step on `bear-only-changed`; Flow A's destination check (repo-side-changed Conflict UX) on `repo-only-changed`; both-changed Conflict UX on `both-changed`.
   - `to bear`: Flow B's update step on `repo-only-changed`; Flow B's Bear-side drift handling (bear-side-changed Conflict UX) on `bear-only-changed`; both-changed Conflict UX on `both-changed`. Use captured Bear `hash` as `baseHash`; on stale-hash error re-prompt per Conflict UX.

   The revalidation cost is cheap (one file read + one SHA per note, no extra MCP calls). The Bear side still relies on `baseHash` (no extra `get_note` per write), which is the existing per-note safety primitive.

7. Skip hard-skip buckets and `in-sync` silently after the summary.

**Why prompts inside a batch:** the destination already has uncommitted edits relative to sync state. Forcing the user to choose (or to explicitly opt into auto-resolve in step 5) preserves the per-invocation-unidirectional safety model — the *direction* is fixed, but conflict resolution is consensual.

**Why per-note revalidation:** the batch widens the check→write window. Without revalidation, `from bear` could silently overwrite repo edits the user made during the batch, and `to bear` could push a now-stale body. Bear-side has `baseHash` protection (free); repo-side gets equivalent protection via cheap SHA + frontmatter recheck.

**Cost note:** the pre-scan does one `get_note` per manifest entry. For N entries this is N MCP calls upfront — acceptable for V1 where N is expected to be small (tens, not thousands).

---

### Flow D — `register <bear-id> [as <repo-path>]` / `unregister <bear-id | repo-path>`

Manifest-only. No file or Bear writes.
- `register`: adds an entry with `repo_path` + `title` (if known) but **no** `bear_hash_at_sync` / `content_sha256_at_sync` / `repo_mtime_at_sync` / `last_sync_at` / `last_sync_direction`. The entry is in the **`uninitialized`** state — see below. **Only `import <bear-id>` or `relink <repo-path>` can transition it to initialized; `push` never initializes** (safety rationale below).
- `unregister`: removes entry. Does not delete files or Bear notes.

**The `uninitialized` state — explicit semantics:**

| Operation | Behavior on an uninitialized entry |
|-----------|----------------------------------|
| `status` (Flow E) | Lists the entry with bucket `uninitialized` and a hint: "run `import bear note <id>` (Bear → repo) or `relink <repo-path>` (reconcile) to initialize. `push` is not a valid initializer." |
| `sync all from bear` / `to bear` (Flow C) | Skipped silently (counted in summary) — no fake hash, no forced initialization |
| `import <bear-id>` (Flow A) | Initializes the entry by writing the file fresh (file must not exist, or must be empty / safe to overwrite per Flow A's destination check) |
| `relink <repo-path>` (Flow F) | Initializes the entry by reconciling repo body vs Bear body (three sub-cases per Flow F) |
| `push <repo-path>` (Flow B) | **Refuses** — Bear's current state has never been read into this entry, so we can't compute `baseHash` safely. User must run `import` or `relink` first |
| Any other read | Treats `*_at_sync` fields as missing; never reads them as "matches nothing" |

**Safety rationale for "push never initializes":** to push safely we need `baseHash` (Bear's current `hash`). We've never read Bear for this entry, so we'd have to either (a) call `get_note` inside `push` and blindly trust the returned hash, which silently couples push to Bear's current state without any user review, or (b) fail. We pick (b) and route through `import` (canonicalize from Bear) or `relink` (reconcile both sides with user choice). This keeps Bear-side reads explicit.

Implementation note: detect `uninitialized` by absence of `bear_hash_at_sync`. Don't use empty-string sentinels — missing means missing.

---

### Flow E — `status`

Read-only. Prints all manifest entries with drift bucket — `in-sync`, `uninitialized`, `bear-only-changed`, `repo-only-changed`, `both-changed`, `bear-missing`, `repo-missing`. Per-entry, the `uninitialized` row shows hint "run `import bear note <id>` or `relink <repo-path>` to initialize; `push` is not a valid initializer" and does not call `get_note` (no Bear traffic needed for that bucket).

---

### Flow F — `relink <repo-path>` (recover orphaned frontmatter)

For when a markdown file has `bear_id` in frontmatter but no manifest entry (e.g., manifest was deleted, file was copied from another repo, merge conflict mangled the manifest). This is the **only** safe path to re-attach an orphan; Flows A and B refuse to proceed on orphan state.

1. Preflight (Flow 0).
2. Read `repo_path`'s frontmatter; extract `bear_id`. If missing: `<repo-path> has no bear_id frontmatter — relink needs the Bear ID. Use \`register <bear-id> as <repo-path>\` and run \`import bear note <bear-id>\` instead.`
3. If manifest already has an entry for this `bear_id` or `repo_path`: `Not orphaned — manifest entry already exists. Use \`sync\` instead.`
4. `mcp__Bear__get_note(id=<bear_id>)` → capture `content`, `hash`, `tags`, `has_attachments`.
5. V1 gate: refuse if tags/attachments present.
6. Compute `content_sha256` of repo file body AND of Bear body.
7. **Three sub-cases:**
   - **Hashes match** → file and Bear are in sync. Initialize manifest entry with current `hash` and `content_sha256`. Report: `Relinked <repo-path> ↔ <bear_id> (in sync).`
   - **Hashes differ** → present diff summary, prompt user:
     ```
     ⚠️  Bear and repo content differ. Pick the canonical version:
       [b] bear is canonical → overwrite repo from Bear (manifest initialized from Bear state)
       [r] repo is canonical → overwrite Bear from repo (uses get_note's hash as baseHash, then re-fetches for manifest)
       [d] show diff
       [m] merge manually in $EDITOR
       [s] skip — leave orphaned, don't relink yet
     ```
   - **Bear note not found** (deleted in Bear since file was created elsewhere) → prompt: `Bear note <bear_id> not found. [r]ecreate from repo file as new Bear note (new id assigned) / [u]nregister frontmatter / [s]kip?`
8. Apply user's choice; write manifest entry with the resulting `bear_hash_at_sync`, `content_sha256_at_sync`, `repo_mtime_at_sync`, `last_sync_at`, `last_sync_direction`.

**Why explicit relink (not auto-register):** the orphan case has hidden risk — the file's content may have drifted from Bear since it was originally synced (possibly months ago), and we can't tell from frontmatter alone. Forcing the user through `relink` makes the reconciliation visible.

---

## Conflict UX

Same shape as v1; uses `content_sha256` for detection (not mtime).

**Repo-side changed (during import):**
```
⚠️  notes/foo.md changed since last sync
   +2 / -1 lines

  [o] overwrite repo (Bear → repo)
  [k] keep repo (skip)
  [d] show full diff
  [m] open both versions in $EDITOR
  [q] quit
```

**Bear-side changed (during push):**
```
⚠️  Bear note "Foo" changed since last sync
   +5 / -2 lines

  [o] overwrite Bear (force push, loses Bear-side edits)
  [k] keep Bear (skip)
  [d] show diff
  [m] merge manually
  [q] quit
```

**Both changed (true conflict):**
```
⚠️  Both sides changed since last sync
   Bear: +5 / -2
   Repo: +1 / -3

  [b] bear wins (overwrite repo)
  [r] repo wins (overwrite bear, force push)
  [d] diff side-by-side
  [m] merge manually
  [s] skip
```

**Manual merge:**
- Write Bear's content to `$TMPDIR/bear-sync/<bear_id>.bear.md`.
- Write repo's body to `$TMPDIR/bear-sync/<bear_id>.repo.md`.
- Open both in `$EDITOR`.
- User edits one to be the canonical version, saves, closes.
- Skill writes canonical content to both sides (Bear via `overwrite_note` with current `baseHash`, repo file directly).

**Hash race on `overwrite_note`:** If MCP returns stale-hash error (Bear edited between our last `get_note` and `overwrite_note`), re-fetch and re-prompt user as bear-side-changed. If this happens twice consecutively, surface to user: `Bear note keeps changing — close other Bear clients and retry.`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `claude/skills/bear-sync/SKILL.md` | Frontmatter (name/desc/triggers) + skill prose (flows, conflict UX) |
| Create | `claude/skills/bear-sync/README.md` | User-facing docs: setup, manifest format, V1 limitations, ID stability finding |
| Create | `claude/skills/bear-sync/lib/canonicalize.py` | Deterministic canonical content hashing (uv-shebang, stdlib only) |
| Modify | `CLAUDE.md` (project) | Add gotcha: manifest committed, V1 tag/attachment limitation, ID stability assumption |

No `custom_bins/bear-sync`. No Python package. Just a skill + one helper script.

---

## Implementation Phases

### Phase 0 — Validation (blocks Phase 1)

- [ ] **Task 0.1:** Verify Bear note IDs are stable across iCloud sync.
  - Create test note on primary Mac. Capture ID via `mcp__Bear__create_note` response or `list_notes`.
  - Wait for iCloud sync (or force via Bear app).
  - On secondary Mac (or via Bear's iCloud DB inspection), confirm same ID present.
  - Document finding in `claude/skills/bear-sync/README.md`.
  - **If unstable:** stop. Redesign with title-based identity + relink-on-fetch.

### Phase 1 — MVP

- [ ] **Task 1.0:** **Probe Bear MCP surface (prerequisite to all other tasks).** Verify exact callable tool names by triggering tool-use in a fresh session and listing what's exposed. Confirm namespace (currently observed: `mcp__Bear__*` with capital B; settings key is `bear` lowercase). Probe `get_note` response shape — exact field names for: `content`, `hash`, `title`, `tags`, `has_attachments` (or attachment metadata, possibly nested). Probe `overwrite_note` parameter name for the hash guard (`baseHash` per skill docs — verify exactly). Probe `create_note` return shape (does it return `id` + `hash` directly?). **Document findings in `SKILL.md` before writing any flow logic** — if any tool name or field name differs from what's used in this plan, update the plan first.
- [ ] **Task 1.1:** **Implement Flow 0 (Preflight) helper.** Write the exact check sequence as prose in SKILL.md (the skill executes it inline; no separate script). Verify the FDA failure surface — what error does `get_note` return when Bear's SQLite is unreadable? Document the exact error shape so the skill can match on it.
- [ ] **Task 1.2:** Scaffold `SKILL.md` with frontmatter (name, description, triggers) and trigger phrases.
- [ ] **Task 1.3:** Implement `canonicalize.py` (uv-shebang, stdlib only, accepts stdin, prints SHA-256 hex). Unit test the algorithm with edge cases (no frontmatter, CRLF, trailing whitespace, empty body, frontmatter without trailing `---`).
- [ ] **Task 1.4:** Write Flow A (`import bear note`) with V1 gate and orphan refusal.
- [ ] **Task 1.5:** Write Flow B (`push to bear`) — bootstrap, update, and orphan-refusal paths.
- [ ] **Task 1.6:** Write Flow C (`sync all`) with summary table.
- [ ] **Task 1.7:** Write Flows D and E (`register`/`unregister`/`status`).
- [ ] **Task 1.8:** Write Flow F (`relink`) — three sub-cases (hashes match / hashes differ / Bear note not found).
- [ ] **Task 1.9:** Implement Conflict UX (all three variants) including manual merge via `$EDITOR`.
- [ ] **Task 1.10:** Implement hash-race handling on `overwrite_note`.
- [ ] **Task 1.11:** Write README with setup (FDA grant, MCP server boot), manifest format, V1 limitations, ID stability finding, troubleshooting (`Bear MCP unavailable`, `FDA denied`).
- [ ] **Task 1.12:** Add CLAUDE.md gotcha entry (project, not global).
- [ ] **Task 1.13:** End-to-end manual test (see Testing Plan).

### Phase 2 (deferred)

- Tag round-tripping (Bear inline `#tag` ↔ YAML `tags: [...]`).
- Attachment handling (Bear attachments → `notes/attachments/<bear_id>/...` + path rewriting).
- `--dry-run` flag (well, "dry-run" mode in the skill — list changes without writing).
- Standalone CLI (only if cron/automation justifies it).

---

## Edge Cases (V1)

| Case | Handling |
|------|----------|
| Bear note has tags | Refuse with clear message; user removes tags or waits for V2 |
| Bear note has attachments | Same refusal |
| Bear note deleted, still in manifest | On import attempt: MCP `get_note` returns error → skill detects, prompts: skip / unregister / manually recreate |
| Repo file deleted, still in manifest | On push: error early; prompt: import from Bear to recreate / unregister |
| Bear title changed | Manifest title diverges; skill updates manifest title silently as part of sync |
| Markdown file moved within repo | Frontmatter `bear_id` survives. `status` flow detects mismatch between manifest `repo_path` and actual file location; prompts to update manifest |
| Manifest missing | First-time: skill creates empty `.bear-sync.json` on first `register`/`import`. No "no manifest" error path needed |
| Outside git repo | Error: `bear-sync requires a git repo (manifest lives at repo root)` |
| Hash race on `overwrite_note` | Catch stale-hash error → re-prompt as bear-side-changed; twice consecutively → surface to user |
| Concurrent sync from two machines | Manifest is committed JSON; conflicting writes surface as a regular git merge conflict |
| Bear MCP server not running | Error: `Bear MCP unavailable — restart Claude Code, or run 'bearcli mcp-server' in a separate terminal` |
| `bear_id` in frontmatter but not in manifest | **Refuse import/push.** Direct user to `relink <repo-path>` (Flow F), which reconciles content before initializing sync state. Manifest is authoritative for sync state; we can't safely fabricate `bear_hash_at_sync` or `content_sha256_at_sync` from frontmatter alone |
| Manifest entry exists but file's frontmatter `bear_id` differs | Refuse with `Mismatch: manifest says <id-A>, file frontmatter says <id-B>. Resolve by editing one to match` — never silently pick a side |

---

## Open Questions Resolved from v1

1. ~~Exact `bearcli` API surface~~ — Now uses MCP per `claude/skills/bear.md`.
2. ~~Bear modification timestamp precision~~ — Irrelevant; hash is the safety primitive.
3. ~~Tag round-tripping~~ — Deferred to Phase 2; V1 refuses notes with tags.
4. ~~Bear ID stability~~ — Phase 0 Task 0.1 validates before V1 ships.
5. ~~`delta` availability~~ — V1 conflict UX uses Claude's built-in diff rendering, falls back to `git diff --no-index` if needed. `delta` is nice-to-have, not required.

---

## Testing Plan

### Phase 0
- ID stability: as part of Task 0.1.

### Phase 1 — happy paths
- **Import (new):** Create Bear note → `import bear note <id>` → verify frontmatter + manifest entry.
- **Push (bootstrap):** Create `notes/test.md` → `push to bear` → verify new Bear note + frontmatter updated.
- **Push (update):** Edit `notes/test.md` body → `push` → verify Bear updated + manifest `bear_hash_at_sync` advanced.
- **Import (existing):** Edit Bear note → `import` (same id) → verify repo file overwritten.
- **Cross-machine:** Register on Mac A → commit + push → pull on Mac B → `import` same id → verify identical content.

### Phase 1 — conflict paths
- **Repo-side conflict:** Edit repo file → `import` → verify repo-side-changed prompt.
- **Bear-side conflict:** Edit Bear → `push` → verify bear-side-changed prompt.
- **Both changed:** Edit both → either flow → verify both-changed prompt.
- **Hash race:** Stage `overwrite_note` to fail (manually edit Bear during the flow) → verify retry/re-prompt.

### Phase 1 — refusal paths
- **Tags:** Add `#tag` to Bear note → `import` → verify refusal with clear message.
- **Attachments:** Add image to Bear note → `import` → verify refusal.

---

## Out of Scope (Explicit Non-Goals)

- Automatic/scheduled sync (no cron, no fswatch)
- Multi-account Bear
- 3-way merge with common ancestor (`[m]erge` is manual via `$EDITOR`)
- Tag round-tripping (Phase 2)
- Attachment handling (Phase 2)
- Standalone CLI (defer)
- Non-Bear markdown editors (Obsidian etc.)
- Mobile-side editing of the manifest (read-only on iOS — that's by Bear's design)
