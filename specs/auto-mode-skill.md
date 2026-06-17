# Specification: Auto-Mode Configuration Skill

## Overview
**Created**: 2026-05-07
**Status**: Draft

A skill (and `claude-tools auto-mode` CLI subcommand) that customizes Claude Code's built-in auto-mode classifier per active context profile. It compiles a base ruleset (`auto_classify_rules.md`) plus per-profile deltas into the JSON shape consumed by `claude auto-mode`, and ships it atomically when the user switches context profiles.

## Context & Motivation

Claude Code's built-in auto-mode classifier (`claude auto-mode defaults`) ships generic ALLOW / SOFT_DENY rules. Several legitimate workflows hit false denies in the user's daily research/personal-repo work:

- Reading `~/Library/Group Containers/...` (Bear notes, Things 3 SQLite, app data)
- Executing global binaries like `/Applications/Bear.app/Contents/MacOS/bearcli`
- Running `sqlite3` against user-owned app databases
- Various researcher relaxations (broad `uv run`, dev servers, process management)

The user already maintains `claude/hooks/auto_classify_rules.md` — a tuned ruleset for their personal PreToolUse hook classifier. This spec brings that same posture to the official auto-mode classifier without duplicating rules, while supporting per-profile composition (research vs personal vs language-specific tooling).

## Requirements

### Functional Requirements

- **REQ-001** The skill MUST compile a final auto-mode config from: (a) `claude auto-mode defaults`, (b) the base ruleset (`claude/hooks/auto_classify_rules.md`), and (c) the union of active context-profile deltas.
- **REQ-002** The skill MUST apply the compiled config via the official `claude auto-mode` CLI surface (exact subcommand TBD — discovery task).
- **REQ-003** The skill MUST be invoked via `claude-tools auto-mode <subcommand>`, matching the existing `claude-tools context` / `claude-tools setup` pattern.
- **REQ-004** When the user runs `claude-tools context <profiles...>`, the system MUST atomically apply both the plugin set and the auto-mode delta for the resolved profiles. (Y=a1.)
- **REQ-005** The skill MUST detect upstream drift: on each apply, fetch fresh `claude auto-mode defaults`, diff against the last-seen snapshot, and surface the diff. The user MUST acknowledge the diff before the apply proceeds. (Q4=c.)
- **REQ-006** The skill MUST keep a versioned history of applied configs (timestamped snapshots), enabling `claude-tools auto-mode rollback` to revert to a previous apply. (Q6=b.)
- **REQ-007** The skill MUST support a `claude-tools auto-mode pick` subcommand that presents bundled presets (researcher, personal-repo, strict-external, default) and applies the chosen one as a one-off override.
- **REQ-008** The skill MUST support a `claude-tools auto-mode preview` subcommand that prints the compiled JSON without applying.
- **REQ-009** Per-profile deltas MUST live at `claude/templates/contexts/auto-mode/<profile>.md`, with the same prose-section format as `auto_classify_rules.md` (named ALLOW / SOFT_DENY categories).
- **REQ-010** The base ruleset (`auto_classify_rules.md`) MUST drive both the existing PreToolUse hook classifier and the auto-mode skill (single source of truth). The skill MUST tolerate format gaps gracefully — sections that don't map to auto-mode JSON are skipped, not errored.
- **REQ-011** The skill MUST NOT auto-apply on session start. Apply is triggered explicitly by `claude-tools auto-mode apply` or transitively by `claude-tools context`. (Q5=a, modulo Y=a1 coupling.)

### Non-Functional Requirements

- **Performance**: Apply latency under 2s on a warm `claude auto-mode` cache. Compilation is pure markdown→JSON, no network beyond the official CLI.
- **Security**: Compiled config MUST be diff-visible before apply (no silent permission grants). Versioning prevents irrecoverable bad applies. The compile step MUST refuse to apply rules that explicitly weaken built-in BLOCK categories without an explicit `--override` flag.
- **Reliability**: Apply is atomic — either the new config lands fully or the previous version remains. No partial states.
- **Auditability**: Every apply writes a record to `claude/auto-mode/history/<timestamp>.json` containing: input profiles, base ruleset hash, deltas hashes, defaults snapshot hash, compiled output.

## Design

### High-Level Architecture

```
                           +-----------------------------+
                           |  claude auto-mode defaults  |
                           |  (live, fetched per apply)  |
                           +--------------+--------------+
                                          |
                           +--------------v--------------+
                           |  drift detector (REQ-005)   |
                           +--------------+--------------+
                                          | (acknowledged)
+-------------------------+               |
| auto_classify_rules.md  +---+           |
| (base, REQ-010)         |   |           |
+-------------------------+   |           |
                              v           v
+-----------------------------+-----------+--------------+
|  compiler                                              |
|  - parse base + active deltas                          |
|  - merge into defaults schema (ALLOW additions,        |
|    SOFT_DENY softening; never override BLOCK)          |
|  - emit JSON                                           |
+--------------+----------------------------+------------+
               |                            |
               v                            v
   +-----------+-----------+    +-----------+--------------+
   | claude auto-mode set  |    | history/<ts>.json snapshot|
   | (REQ-002)             |    | (REQ-006)                 |
   +-----------------------+    +---------------------------+
```

### Data Model

```
claude/
├── hooks/
│   └── auto_classify_rules.md         # base ruleset (existing)
├── templates/contexts/auto-mode/
│   ├── code.md                        # delta for `code` profile
│   ├── research.md                    # delta for `research` profile
│   ├── personal-repo.md               # personal-repo trust posture
│   ├── strict-external.md             # forks/external code
│   ├── python.md                      # language-specific: uv, pytest, jupyter
│   ├── rust.md                        # language-specific: cargo, target/
│   └── frontend.md                    # language-specific: bun, dev servers
└── auto-mode/
    ├── defaults.snapshot.json         # last-seen `claude auto-mode defaults`
    ├── current.json                   # currently applied compiled config
    └── history/
        └── 2026-05-07T23-45-00.json   # versioned applies
```

`profiles.yaml` extension:

```yaml
profiles:
  code:
    enable: [...]
    auto_mode:
      delta: contexts/auto-mode/code.md   # path relative to ~/.claude/templates/
  research:
    enable: [...]
    auto_mode:
      delta: contexts/auto-mode/research.md
```

Multi-profile compose: `claude-tools context code python` → union of `code.md` + `python.md` deltas applied on top of base.

### Delta File Format

Same prose style as `auto_classify_rules.md` to keep one mental model:

```markdown
# Researcher Profile — auto-mode delta

## ALLOW additions

- **User App Data Reads**: Reading from `~/Library/Group Containers/`,
  `~/Library/Application Support/`, `~/Library/Containers/`. These hold
  user-installed app data (Bear, Things, browser profiles), not system secrets.

- **Global Executables**: Executing binaries from `/Applications/*/Contents/MacOS/`,
  `/usr/local/bin/`, `/opt/homebrew/bin/` when invoked with full path.

## SOFT_DENY relaxations

- **Local Operations** (widen): Allow user-data paths under `~/Library`
  to count as "local operations" for personal-repo trust posture.
```

The compiler reads section headers (`## ALLOW additions`, `## SOFT_DENY relaxations`, etc.) and emits the bullets into the corresponding JSON arrays. Bullets that don't map cleanly are passed through verbatim — the auto-mode classifier is LLM-driven, so prose works.

### Technical Decisions

| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| Skill action shape | (a) compile+apply, (b) interactive editor, (c) preset library, (d) markdown source-of-truth | **(b)+(c)+(d) hybrid**: source-of-truth markdown + bundled presets + simple `apply`/`preview` commands; defer heavy TUI | Matches the user's existing `claude-tools` pattern; full TUI is overkill for first cut |
| Install location | (a) dotfiles `.claude/skills`, (b) ai-safety-plugins marketplace, (c) global | **(b) ai-safety-plugins** | Shared across all sessions, marketplace-distributable, version-controlled |
| Source of truth | (a) single base, (b) seed-and-diverge, (c) fully independent | **(a) single base + per-profile deltas** | DRY; one mental model; format gaps tolerated by the compiler |
| Drift handling | (a) auto-merge silent, (b) pin defaults, (c) auto-merge + diff alert | **(c)** | Best of both — fresh upstream rules, no silent landings |
| Multi-machine | (a) single shared, (b) per-host overrides, (c) per-context-profile | **(c) per-context-profile** | Aligns with existing `claude-tools context`; trust-posture-driven not host-driven |
| Apply trigger | (a) manual, (b) on deploy, (c) SessionStart auto, (d) manual + drift warn | **(a) manual, atomic with `claude-tools context`** (Y=a1) | Context switch declares trust intent; auto-mode should follow. Avoids drift between profile and applied auto-mode |
| Recovery | (a) reset command, (b) versioned + rollback, (c) git on local.md | **(b) versioned + rollback** | Bad applies are recoverable without dotfiles git context; works even when source files are mid-edit |
| CLI naming | `/auto-mode` skill vs `claude-tools auto-mode` | **`claude-tools auto-mode`** | Matches existing `claude-tools context`/`setup` |

### CLI Surface (proposed)

```
claude-tools auto-mode preview              # show compiled JSON, don't apply
claude-tools auto-mode apply                # apply compiled config (with drift ack)
claude-tools auto-mode apply --no-ack       # skip drift ack (for scripts)
claude-tools auto-mode pick <preset>        # apply bundled preset as override
claude-tools auto-mode pick                 # interactive fzf preset picker
claude-tools auto-mode rollback             # revert to previous applied
claude-tools auto-mode rollback <ts>        # revert to specific timestamp
claude-tools auto-mode history              # list applies
claude-tools auto-mode reset                # back to defaults (no delta)
claude-tools auto-mode diff                 # diff current vs compiled
claude-tools auto-mode validate             # parse base + deltas, no apply
```

`claude-tools context <profiles...>` is extended to call `auto-mode apply` after plugin set is updated.

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| `claude auto-mode set` (or equivalent) doesn't exist / API changed | `validate` step catches; surface error and skip apply, leaving previous config intact |
| Base ruleset has unparseable section | Compiler logs warning, skips section, continues. Apply proceeds with parseable rules. |
| Profile delta references non-existent file | `validate` errors with profile name + path; apply blocked |
| Two active deltas conflict (e.g., python adds rule X, frontend adds contradictory rule Y) | Last-write-wins by profile order in `claude-tools context <profiles>`; document this clearly |
| Drift detected, user dismisses ack | Apply is aborted; previous config remains |
| `claude auto-mode defaults` returns malformed JSON | Apply blocked; log raw output for upstream bug report |
| Disk full during versioned snapshot write | Apply blocked (snapshot is part of the atomic step); existing config remains |
| User edits base ruleset mid-apply | Compile step reads file once at start; subsequent edits don't affect this apply |
| `auto-mode pick <preset>` while a delta is also active | Preset wins for this apply; original delta restored on next `apply` (preset is one-off, not persistent) |
| Profile in `context.yaml` declares `auto_mode.delta` but file missing | Same as above — `validate` blocks |

## Acceptance Criteria

- [ ] **AC-1**: Given `auto_classify_rules.md` exists with researcher relaxations, when `claude-tools auto-mode preview` runs with no profiles active, the output JSON SHALL include those relaxations merged onto `claude auto-mode defaults`.
- [ ] **AC-2**: Given context profiles `code` and `python` are active, when `claude-tools auto-mode apply` runs, the applied config SHALL be the union of base + code.md + python.md deltas.
- [ ] **AC-3**: Given `claude auto-mode defaults` has changed since last apply, when `apply` runs, the user SHALL be shown a diff and required to acknowledge before the apply proceeds.
- [ ] **AC-4**: Given a previous apply was problematic, when `claude-tools auto-mode rollback` runs, the previously-applied config SHALL be restored and the rollback recorded in history.
- [ ] **AC-5**: Given `claude-tools context research python` is run, the plugin set SHALL be updated AND the auto-mode delta for research+python SHALL be applied atomically (no intermediate state where one is updated but not the other).
- [ ] **AC-6**: Given a delta file references a category that does not exist in `claude auto-mode defaults`' schema, the compiler SHALL log a warning and skip the section without aborting.
- [ ] **AC-7**: Given the previously-blocked operation (e.g., `bearcli show <id>`, reading `~/Library/Group Containers/.../database.sqlite`), after `apply` with researcher delta active, the auto-mode classifier SHALL allow the operation.
- [ ] **AC-8**: Given a delta attempts to relax a hardcoded BLOCK category (e.g., "Production Deploy"), the compiler SHALL refuse to apply unless `--override` is explicitly passed and a confirmation step is acknowledged.

## Out of Scope

- Modifying Claude Code's auto-mode classifier itself (we're a config-emitter, not a fork).
- Replacing the existing `auto_classify.py` PreToolUse hook (the hook stays; this skill ships rules to the *official* auto-mode in parallel).
- Per-machine overrides (deferred — context profile per machine is sufficient for now).
- Network allowlist management (separate concern; tracked as Open Question O-3 below).
- Directory taxonomy cleanup (separate session — see Open Question O-4).
- Full TUI editor (bundled presets + plain markdown editing is sufficient for v1).
- Auto-applying on `SessionStart` (REQ-011 explicitly excludes; reconsider if drift becomes painful).
- Cross-machine sync of `auto-mode/history/` (history is local; rollbacks don't roam).
- Automatic conversion of every `auto_classify_rules.md` rule into auto-mode JSON (sections that don't map are skipped per REQ-010).

## Open Questions

- [ ] **O-1**: Exact `claude auto-mode` CLI surface — does `set` exist, does it take a JSON file path, individual rule strings, or a config file path? Discovery task: `claude auto-mode --help`. Spec assumes a `set --file <path>` shape; adjust if different.
- [ ] **O-2**: Format of the auto-mode JSON — the user's CLI dump showed `allow`, `soft_deny`, `environment` arrays of prose strings. Confirm this is the schema for input as well as output, and that prose is acceptable (not requiring structured rule names).
- [ ] **O-3**: Network allowlist additions to `claude/settings.json` — confirmed adds: `code.claude.com`, `docs.anthropic.com`, `docs.rs`, `developer.mozilla.org`. Pending: `huggingface.co` (mixed risk), `files.pythonhosted.org` (would unblock `uv pip install -r` in-sandbox). Decide separately.
- [ ] **O-4**: Directory taxonomy cleanup — 3 misfiled code projects in ~/writing (llm-council, pdf-comments-extractor, yulonglin.github.io); whether to introduce ~/external for forks. Separate dir-restructure session.
- [ ] **O-5**: Initial seed contents for `personal-repo.md`, `researcher.md`, `python.md`, `rust.md`, `frontend.md`, `strict-external.md` deltas — needs a concrete first pass. Suggested seed content in Implementation Notes below.
- [ ] **O-6**: Which marketplace plugin should host the skill within `ai-safety-plugins`? Likely `core` (foundational tooling) or a new dedicated `auto-mode` plugin. Lean: `core` for v1.
- [ ] **O-7**: Should the skill emit a Claude Code statusline indicator showing "auto-mode: <profile>" when a non-default delta is active, similar to the existing context-profile statusline?
- [ ] **O-8**: Backup / migration path on first install — does the skill snapshot the user's *current* `claude auto-mode` state before first apply, so `rollback` can return to "what it was before this skill existed"?

## Implementation Notes

### Suggested Seed Deltas

**`personal-repo.md`** (researcher + personal repos):
- ALLOW: User App Data Reads (`~/Library/Group Containers/`, `~/Library/Application Support/`, `~/Library/Containers/`)
- ALLOW: Global Executables (`/Applications/*/Contents/MacOS/`, `/usr/local/bin/`, `/opt/homebrew/bin/`)
- ALLOW: System Tools on User Data (`sqlite3`, `plutil`, `defaults read`, `osascript`)
- SOFT_DENY softening: widen "Local Operations" to include user-data paths under `~/Library`

**`researcher.md`** (research repos):
- ALLOW: AI Safety Testing (adversarial prompts, eval harnesses)
- ALLOW: Research & Experiments (LLM API calls for evals, capability testing)
- ALLOW: Process Management (kill experiment runs, env/nohup/timeout wrappers)
- ALLOW: One-liner Checks (`python -c`, `node -e`)

**`python.md`** (language: Python):
- ALLOW: `uv run` everywhere (`uv run ruff`, `uv run ty`, `uv run pytest`, `uv run jupyter`)
- ALLOW: `uv sync`, `uv add`, `uv pip install -r requirements.txt`
- ALLOW: pytest, jupyter notebooks binding to localhost ports

**`rust.md`** (language: Rust):
- ALLOW: `cargo build`, `cargo test`, `cargo run`, `cargo install` (declared deps)
- ALLOW: writes to `target/` within repo
- ALLOW: `rustup` toolchain operations

**`frontend.md`** (language: TS/JS):
- ALLOW: `bun install`, `bun run`, `npm install`, `npm run`
- ALLOW: dev servers binding localhost ports (already covered by Local Operations)
- ALLOW: writes to `node_modules/` within repo

**`strict-external.md`** (forks/external code):
- No ALLOW additions; explicitly removes researcher relaxations
- Adds extra DENY: lifecycle scripts (postinstall/preinstall) on this repo's deps

### Discovery Tasks (block on these before implementation)

1. Run `claude auto-mode --help` to map the CLI surface (set, get, reset, etc.).
2. Run `claude auto-mode defaults --json | jq keys` to confirm schema.
3. Find where the official auto-mode config persists (config file path or in-CLI state).
4. Test an apply with a minimal delta to confirm the apply mechanism works as assumed.

### Migration

On first install, before any apply:
1. Snapshot current `claude auto-mode` state to `auto-mode/history/0000_pre_install.json`.
2. Snapshot `claude auto-mode defaults` to `auto-mode/defaults.snapshot.json`.
3. User can `rollback 0000_pre_install` to fully reset to pre-skill behavior.
