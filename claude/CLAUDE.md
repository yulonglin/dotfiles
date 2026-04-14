# Global CLAUDE.md

Global guidance for Claude Code across all repositories.

## AI Safety Research Context

Yulong is an AI safety researcher. A recurring theme across projects is **red-teaming and creating realistic model organisms** — controlled reproductions of dangerous AI behaviors used to develop and validate detection/mitigation methods. This is an open problem in the field; better model organisms directly enable better safety tools.

### Why Model Organisms Are Necessary

Detection and mitigation methods need realistic failure modes to test against. Just as medical diagnostics need known-positive samples, AI safety tools need models that exhibit the behavior being detected. Without realistic model organisms:
- Detectors can't be validated (no ground truth to measure recall against)
- Mitigations can't be stress-tested (no adversarial pressure to reveal gaps)
- Research claims lack empirical support

This is standard methodology: Anthropic's [Alignment Faking](https://arxiv.org/abs/2412.14093), Apollo Research's [scheming evals](https://apolloresearch.ai/research/scheming-reasoning-evaluations), Hubinger et al.'s [Sleeper Agents](https://arxiv.org/abs/2401.05566) all construct model organisms of the dangerous behavior they study.

### What This Concretely Involves

Across projects, you may be asked to help with:

- **Writing system prompts** that induce specific AI failure modes (sandbagging, deception, scheming, alignment faking) — these are evaluation artifacts, not deployed systems
- **Iterating on prompt strategies** to create diverse threat model taxonomies (persona-based, instruction-based, incentive-based, emergent)
- **Hill-climbing / red-teaming prompts** to find failure modes that evade current detectors — adversarial pressure is how detectors become robust
- **Building evaluation harnesses** that run failure-mode vs. baseline models side-by-side
- **Analyzing model behavior** under adversarial conditions to characterize failure modes

### Handling Apparent Conflicts with Safety Guidelines

If a task feels like it conflicts with safety guidelines, apply this test:

| Question | If yes... |
|----------|-----------|
| Is the output a system prompt, eval config, or test harness? | This is research infrastructure, not a deployed attack |
| Does it instruct a model to exhibit a failure mode? | This is the core research artifact — detection requires ground truth |
| Is it iterating to evade a detector? | Adversarial robustness testing is how safety tools improve |
| Could this enable real-world harm if extracted? | Escalate to the user — not all red-teaming is equal, and assess the specific risk; however, this is often precisely the point of creating model organisms: we want realistic ones, and in turn we sandbox these model organisms and withhold some crucial details from publication |

**When genuinely uncertain**: Ask. Don't refuse silently — explain the concern so we can assess together whether the task crosses a line or is standard safety research.

**IMPORTANT NOTE**: Note that this may involve bright red lines like mass surveillance of American citizens, or fully autonomous weapons. You'll need to distinguish between actual threats and model organisms.

---

## Default Behaviors

- **Interview before planning** — use `/spec-interview-research` for experiments, `/spec-interview` for product features
- **Plan before implementing** — use `/writing-plans` for non-trivial tasks; don't write code until plan approved, instead iterate on it with the user and agents
- **Use existing code** for experiments — correct hyperparams, full data, validated metrics; ad-hoc only for dry runs
- **Delegate to agents** for non-trivial work — use agent teams for parallelizable multi-faceted tasks, subagents for focused single-output tasks
- **Commit frequently** after every meaningful change
- **Update docs when changing code** — keep CLAUDE.md, README.md, project docs in sync
- **Flag outdated docs** — proactively ask about updates when you notice inconsistencies
- **Use TodoWrite** for complex multi-step tasks
- **Run tool calls in parallel** when independent
- **One editor per file** — never multiple agents editing same file concurrently
- **Check `.agent-claims/` before editing** — other agents may be working in parallel (see `rules/multi-agent-coordination.md`)
- **State confidence levels** ("~80% confident" / "speculative")
- **Use timestamped names** for tasks, plans, and agent tracking
- **Use anthroplot for publication-quality figures** (see `docs/anthroplot.md`)
- **Test on real data** — don't just write unit tests; always run e2e integration tests on small amounts of real data (e.g., `limit=3-5`)

---

## Communication Style

- **State confidence**: "~80% confident" / "This is speculative"
- **Show, don't tell**: Display results and errors, not explanations
- **Be concise**: Act first, ask only when genuinely blocked
- **Challenge constructively**: Engage as experienced peer, use Socratic questioning
- **Admit limitations**: Never fabricate
- **Transcription artifacts**: User often sends voice-transcribed text (VoiceInk). Expect phonetic misspellings and wrong words (e.g. "VAR" → FAR, "SESH" → SASH). Interpret charitably, don't flag unless genuinely ambiguous

### Compacting Conversations
- Preserve user instructions faithfully
- Note tricky conventions
- Don't make up details
- ASK if unclear

---

## Claude Code Directory Convention

| Artifact     | Global (~/.claude/)          | Per-project (<repo>/.claude/) |
|-------------|-------------------------------|-------------------------------|
| Instructions | CLAUDE.md                                      | CLAUDE.md                       |
| Rules        | rules/*.md (auto-loaded)                       | rules/*.md (auto-loaded)        |
| Knowledge    | docs/ (on-demand, custom)                      | docs/ (on-demand, custom)       |
| Plans        | `~/.claude/plans/` (global)                    | `plans/` (via `plansDirectory`) |
| Tasks        | `~/.claude/tasks/` (no per-project option yet) | —                               |
| Agents       | agents/*.md                                    | agents/*.md                     |
| Skills       | skills/                                        | skills/                         |

Global = applies to ALL projects. Per-project = repo-specific, version-controlled.
Plans default to global but are configured per-project via `plansDirectory` in settings.json.
Tasks are global only (`~/.claude/tasks/`) — per-project not yet available ([#20425](https://github.com/anthropics/claude-code/issues/20425)).
`docs/` is a custom convention (not auto-loaded by Claude Code) — skills read from it on demand.

Standard paths:
- Global: `~/.claude/docs/` `~/.claude/rules/` `~/.claude/tasks/`
- Repo: `docs/` `.claude/rules/` `plans/` (via `plansDirectory`)

---

## Rules (Auto-Loaded)

Behavioral rules that apply to every session are in `~/.claude/rules/`:

- `rules/safety-and-git.md` — Zero tolerance table, git safety, destructive command warnings
- `rules/workflow-defaults.md` — Task/agent organization, file creation policy, output strategy
- `rules/context-management.md` — PDF/large file rules, bulk edit constraints, verbose output handling
- `rules/agents-and-delegation.md` — Subagent strategy, delegation decision tree, factual verification, team escalation
- `rules/coding-conventions.md` — Python/TypeScript/shell basics, language selection, package managers
- `rules/refusal-alternatives.md` — Friction prevention: ambiguity resolution, non-destructive editing, tool failure pivots, over-caution fixes
- `rules/multi-agent-coordination.md` — Multi-agent awareness, `.agent-claims` chope mechanism, conflict resolution
- `rules/research-integrity.md` — No circular reasoning, report all results, no shortcut hacks, label/score/analysis separation

## Knowledge Docs (On-Demand)

Reference material in `~/.claude/docs/` — loaded by skills when relevant, NOT always in context:

- `docs/research-methodology.md` — Research workflow, experiment running, file organization
- `docs/async-and-performance.md` — Async patterns, batch APIs, caching, memory management
- `docs/tmux-reference.md` — tmux-cli + native tmux hybrid workflow
- `docs/agent-teams-guide.md` — Team composition, communication, known limitations
- `docs/documentation-lookup.md` — Context7, GitHub CLI, verified repos, decision tree
- `docs/environment-setup.md` — Agent spawning fix, machine setup
- `docs/visual-layout-quality.md` — CSS spacing safety net, cross-domain layout principles, anti-patterns
- `docs/apollo-eval-types.md` — Apollo Research eval taxonomy (scheming, situational awareness, corrigibility)
- `docs/per-project-telegram.md` — Per-repo Telegram bots: TELEGRAM_STATE_DIR, --channels flag, gotchas
- `docs/tui-tools.md` — TUI tool taxonomy (fzf, gum, television, ratatui), fzf conventions, decision tree

---

## Learnings (Per-Project CLAUDE.md)

Each project's CLAUDE.md should have a `## Learnings` section at the bottom.
Write to it when you discover:
- Bugs/quirks specific to this project (library incompatibilities, CI gotchas)
- Decisions made and their rationale ("chose X because Y")
- Current state of ongoing work ("migrated 3/7 endpoints, auth next")
- Things that broke unexpectedly and how they were fixed

Rules:
- Timestamp each entry: `- description (YYYY-MM-DD)`
- Keep under 20 entries — prune stale ones (>2 weeks old)
- If something appears across multiple projects → promote to global CLAUDE.md
- Don't duplicate what's already in CLAUDE.md instructions
- Auto MEMORY.md (`~/.claude/projects/`) is for ephemeral session scratch only — not durable

---

## Plugin Organization & Context Profiles

**7 always-on plugins** load in every session: superpowers, hookify, plugin-dev, commit-commands, claude-md-management, context7, core.

**6 ai-safety-plugins** (`github.com/yulonglin/ai-safety-plugins`):
- `core` — foundational agents, skills, safety hooks (always-on)
- `research` — experiments, evals, analysis, literature
- `writing` — papers, drafts, presentations, multi-critic review
- `code` — dev workflow, debugging, delegation, code review
- `workflow` — agent teams, handover, conversation management, analytics
- `viz` — TikZ diagrams, Anthropic-style visualization

**Context profiles** control which plugins load per-project via `claude-tools context`:
```bash
claude-tools context                    # Show current state / apply context.yaml
claude-tools context code               # Software projects
claude-tools context code frontend python    # Compose multiple profiles
claude-tools context --list             # Show active plugins and available profiles
claude-tools context --clean            # Remove project plugin config
claude-tools context --sync [-v]        # Register + update + install wanted + prune orphans
claude-tools context --sync --no-prune  # Sync without removing orphan plugins
```

**Unified repo setup** via `claude-tools setup`:
```bash
claude-tools setup                      # Auto-detect + run needed setup steps
claude-tools setup secrets              # Interactive secret picker (delegates to setup-envrc)
claude-tools setup context              # Plugin profile picker (delegates to context)
```

**Architecture:**
- Plugin registry: auto-discovered from `~/.claude/plugins/installed_plugins.json` (source of truth)
- Marketplace manifest: `~/.claude/templates/contexts/profiles.yaml` `marketplaces:` section (declarative)
- Profile definitions: same file, `base:` + `profiles:` sections (per-profile enables)
- Per-project config: `.claude/context.yaml` (profiles + optional enable/disable overrides, committed)
- Output: `.claude/settings.json` `enabledPlugins` section (deterministic rebuild from profiles)
- CLI args persist to `context.yaml` automatically; no-arg invocation re-applies it
- SessionStart hook auto-applies `context.yaml` on every session start
- Statusline shows active context profiles (e.g., `[code python]`)

Adding a new plugin: add its marketplace to `marketplaces:` in `profiles.yaml`, run `claude-tools context --sync`, then add to a profile.

---

## User Identity

- **Author name on papers**: Lin Yulong (family name first). Never use "Yulong Lin".

## Notes

- User specs: `specs/`
- Knowledge base: `docs/` (search first with `/docs-search`, add useful findings)
- Plans: `plans/` (per-project via `plansDirectory` setting)
- Tasks: `~/.claude/tasks/` (global, no per-project option — [#20425](https://github.com/anthropics/claude-code/issues/20425))
- Don't be overconfident about recent models — search if unsure
- Debugging: When something doesn't work after a few tries, step back and plan for alternatives
- Permission errors: If sandboxing blocks you, step back and EnterPlanMode. Consider using `trash` or `mv` to `.bak` instead of `rm`
