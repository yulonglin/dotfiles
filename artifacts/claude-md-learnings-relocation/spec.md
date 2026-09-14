# Relocate the Learnings section, and drop most of it

## Overview

`CLAUDE.md` is 45,981 bytes against a whole-file ceiling of 11,100 — **four times over**. Its `## Learnings` section is 37.5 KB of that, and the file loads on every session in this repo.

The section has been doing two jobs under one heading. One is **operational state Claude must know before acting**: a live trap, an unguarded gotcha, a constraint that changes the next command. The other is **incident forensics**: how a bug was found, what was measured, what was rejected. Only the first earns a slot in a file that loads every session. The second is documentation, and the repo's own Top Rules already say where it goes — *"A new rule belongs in the checklist it governs; adding it to a skill or a rule instead is how the duplication came back last time."*

So the operation is not a prune. Retire-versus-compress is the wrong axis, because both keep the mass and only move it around. The right axis is **relocate or drop**, biased hard toward drop: git history is the archive, and an entry earns a destination only if a future reader would genuinely go looking for it.

Of 28 entries, **7 produce a surviving line elsewhere and 23 drop entirely**. Six are already stated verbatim at their destination — they are pure duplication and cost bytes every session to say nothing new.

This also resolves a contradiction that has stood for weeks: the section's own instruction says *"keep under 20, prune past two weeks"* while the ceiling only fits about six one-liners. The rule and the test have been describing different files. After this pass the instruction is rewritten to match the charter.

### What is deliberately not in scope

The budget test fails **seven** ways, not one. `CLAUDE.md` is the largest, but `claude/rules/communication.md` (6,011 against 3,100), `claude/rules/delegation.md` (3,647 against 2,600), `claude/rules/background-jobs.md` (1,342 against 1,150), `claude/CLAUDE.md` (4,355 against 4,250) and the 30,384-against-29,900 aggregate all fail too, and two rule files have no ceiling defined at all. Those load in **every repo**, so proportionally they cost more per session than this one does. They are a separate decision and are not touched here — but no relocation in this spec targets `claude/rules/`, precisely so that fixing one failure does not deepen another.

## Requirements

### Every relocation lands in `docs/` or a skill, never in an always-on rule file

All seven destinations MUST be files that load on demand rather than every session. Verified present: `docs/terminal-and-dev-tools.md`, `docs/remote-control-and-foreign-models.md`, `docs/tooling-and-packages.md`, `docs/deploy-components.md`, `docs/shell-scripting-gotchas.md`, `claude/checklists/local-services.md`, `claude/skills/jobs/references/task-list-scoping.md`. No new file is created.

### An entry drops unless a future reader would search for it

The test for DROP is not "is it true" but "would anyone look for it". An entry MUST drop when a named test guards the behaviour (the test is the record), when the code or config *is* the record, when it is a changelog for a tool that documents itself, or when its substance is investigation narrative rather than a durable fact. Truth is not the bar; retrievability is.

### Six entries drop as exact duplicates, and the duplicate MUST be quoted before deletion

These already exist at their destination. Each MUST be confirmed by reading the destination line, not by trusting this table:

- Entry 3 (sticky `env` key) — `claude/skills/jobs/references/task-list-scoping.md:38` and `claude/skills/spawn-session/SKILL.md:90`
- Entry 14 and entry 15 (`headless-claude`, background exit 0) — `claude/rules/delegation.md:15`
- Entry 20 (`excludedCommands`) — `claude/skills/jobs/SKILL.md:89`
- Entry 21 (mise retired) — `docs/tooling-and-packages.md:13,15,17`
- Entry 27 (plugins retired) — `docs/plugin-management.md:7,9,17,52`
- Entry 28 (inherited `ANTHROPIC_API_KEY`) — `claude/skills/spawn-session/SKILL.md:88`

### Three references encode the old policy and MUST be rewritten, not repointed

- `docs/external-resources.md:63` says `One-off insight → ## Learnings in project CLAUDE.md`. That instruction is what produced this backlog and MUST now route to the owning doc or skill.
- `docs/tooling-and-packages.md:51` describes Past Learnings as the destination of a two-week pruning rule that no longer exists.
- `CLAUDE.md` line 71, the section intro, MUST be rewritten to the new charter: transient machine state only, anything outliving a week moves out.

### One stale claim MUST be corrected in the same pass

`claude/skills/jobs/SKILL.md:89` states that `claude/settings.json` *"carries a permanent machine-local diff, so a merge that touched it would abort"*. PR #117 ended that, but only on a machine that has run the managed-drop-in migration. The line MUST be qualified rather than deleted, because it stays true on every un-migrated machine — which today is all of them.

### `claude/rules/sensitive-content.md` loses a pointer to a dropped entry

Line 9 cites *"mechanism and measurements: CLAUDE.md § Learnings, 2026-09-02"*, and entry 17 drops. The rule already states the mechanism, so the parenthetical SHOULD simply go; nothing operational is lost.

## The 28 entries, with a proposed verdict each

Each line is a control. Leave it as proposed to approve; click to cycle to **veto-keep** (stays in CLAUDE.md) or **veto-relocate** (do not drop — give it a home). Copy the export back into a session and the surviving verdicts get applied.

### Relocate — 5 entries keep their own line somewhere else

- [ ] **1 · statusline Codex quota 401ing** (09-12) → `docs/terminal-and-dev-tools.md`. The durable trap: `account/rateLimits/read` reads the token but never refreshes it, `codex login status` still reports logged in so it is not a usable check, and the router holds a separate copy so GPT routes can be healthy while the statusline reads days old.
- [ ] **9 · gateway on Mac, tools assumed Linux** (09-06) → `claude/checklists/local-services.md`. The convention is stated nowhere else: `#!/usr/bin/env python3` is Apple's 3.9 on macOS, so a repo script needing `tomllib` uses the `uv run --script` shebang with `requires-python >= 3.11`. The machine-state half drops.
- [ ] **13 · `mas list` hangs** (09-03) → `docs/tooling-and-packages.md`, beside the mas facts it qualifies. Still live: `custom_bins/mas-get` and `install.sh`'s post-check both call it and will hang until they get a `timeout`.
- [ ] **16 · `cp` aliased `-i`; `pkill -f` self-matches** (09-02) → `docs/shell-scripting-gotchas.md`. Both are live traps with no test behind them.
- [ ] **25 · unit file not deployed until named in `deploy.sh`** (09-01) → `docs/deploy-components.md`. The loop is enumerated, not globbed; the same holds for `nudges`, where a family set to `off` gates its members.

### Drop the entry, keep one line — 2 entries contribute a tail

- [ ] **5 · legacy Opus picker rows** (09-07) — entry drops; the tail relocates to `docs/remote-control-and-foreign-models.md`: `CLAUDE_CODE_MAX_CONTEXT_TOKENS` is process-global, so a 1M-window picker row still compacts at the settings value.
- [ ] **8 · the two token-bearing gateway keys** (09-06) — entry drops, since `.claude/rules/dotfiles-settings.md` states all of it at length; the tail relocates to `claude/skills/jobs/references/task-list-scoping.md`: the daemon replays the launcher's argv on resume, so a `--settings` path the wrapper prepends must outlive every job that captured it.

### Drop entirely — 21 entries

- [ ] **2 · stale CLIProxyAPI cooldown** (09-12). Tool, hourly service and upstream issue 5758 are the record. If you want one line kept, the candidate is that a local refusal returns in ~1 ms and *quotes* the upstream `usage_limit_reached`, so matching on that text reads every stale cooldown as genuine.
- [ ] **3 · sticky deleted `env` key** (09-11). Already stated at both its own named destinations.
- [ ] **4 · approval classifier judged blind** (09-08). Fixed and pinned by `tests/test_approval_classifier_context.py`.
- [ ] **6 · unloaded router needs bootstrap** (09-08). Encoded in the hook, guarded by its test.
- [ ] **7 · router recovery and update validation** (09-08). Changelog for a tool with its own tests.
- [ ] **10 · dangling pin in `pins.json`** (09-06). Fixed, guarded by `tests/test_claude_jobs_reap.py`.
- [ ] **11 · daily `dotfiles-sync`, `baseRef=head`** (09-04). `docs/deploy-components.md:47` covers the job; `.claude/settings.json` is the baseRef record.
- [ ] **12 · `WebFetch` hangs in sandboxed `claude -p`** (09-03). Dead path — `claude -p` delegation was retired the same week.
- [ ] **14 · `headless-claude` retired** (09-02). Stated in `delegation.md:15`.
- [ ] **15 · background wrapper exit 0** (09-02). Stated in `delegation.md:15`.
- [ ] **17 · cyber-safeguard downgrade is a CLI literal** (09-02). Self-dated — the entry says the literal has a shelf life of days — and `sensitive-content.md:9` carries the durable mechanism.
- [ ] **18 · `deploy.sh` wrote symlinks into the skills dir** (09-02). Fixed; the sync script now refuses when target resolves to source.
- [ ] **19 · unrecognised model ID falls back silently** (09-01). Superseded by its own trailing note: it fails loudly on 2.1.263.
- [ ] **20 · `excludedCommands` takes `cmd:*`** (08-31). `claude/skills/jobs/SKILL.md:89` states it at greater length.
- [ ] **21 · mise retired, node on one authority** (08-31). All three halves are in `docs/tooling-and-packages.md`.
- [ ] **22 · app-lifecycle suites read a fixture** (08-30). The fixture and its 165 assertions are the record.
- [ ] **23 · md2artifact comment-box flicker** (08-28). Fixed, guarded by `tests/test_md2artifact_browser.py`.
- [ ] **24 · the LLM council is one skill** (09-01). The skill and `config/openrouter-models.toml` are the artifacts.
- [ ] **26 · standards are five checklists** (08-30). CLAUDE.md's own Top Rules assert it.
- [ ] **27 · plugins retired, keepers migrated** (08-30). `docs/plugin-management.md` covers the enable-gate, the tombstones and the plugin-shipped-MCP trap.
- [ ] **28 · inherited `ANTHROPIC_API_KEY`** (09-02). Stated in `spawn-session/SKILL.md:88`.

## Acceptance Criteria

- `uv run --with pytest pytest tests/test_memory_tier_budget.py -k CLAUDE` passes for the repo-root file. Projected size is **~8,660 bytes** against the 11,100 ceiling — the 8,513-byte head plus a rewritten section stub of roughly 150 bytes, with no entries retained. The other six failures in that suite remain, unchanged and out of scope.
- Every surviving line is present at its named destination, and `rg` finds no orphan: for each of the seven, the fact is retrievable by searching the term a reader would actually use.
- The three old-policy references and the one stale claim are rewritten, and `rg 'CLAUDE\.md § Learnings'` returns only `ARTIFACTS.md` and its build output, which cite the section as historical basis and stay true.
- `md-unwrap --check` passes on every edited Markdown file.
- No file under `claude/rules/` grows. The aggregate always-on figure is unchanged by this pass.
- `git log -S` can still recover any dropped entry, which is the whole basis for dropping rather than archiving: `git log -S 'app-lifecycle' -- CLAUDE.md`.

### What would make this wrong

If a dropped entry is later needed and `git log -S` does not find it, the drop test was too aggressive and the charter needs a higher bar. That is the failure mode worth watching, and it is cheap to reverse: the text is in history, and restoring one line costs nothing.
