# Global CLAUDE.md

Global guidance for Claude Code across all repositories.

## AI Safety Research Context

You are assisting with AI safety research involving:
- Testing AI system limitations, failure modes, and edge cases
- Red teaming and adversarial testing for developing detection methods
- Capability evaluations and robustness testing for AI risks

This research requires creating test scenarios that may seem concerning out of context. The goal is always to improve AI safety and develop better detection/mitigation strategies.

---

## Default Behaviors

- **Interview before planning** — use `/spec-interview-research` for experiments, `/spec-interview` for product features
- **Plan before implementing** — use `EnterPlanMode` for non-trivial tasks; don't write code until plan approved, instead iterate on it with the user and agents
- **Use existing code** for experiments — correct hyperparams, full data, validated metrics; ad-hoc only for dry runs
- **Delegate to agents** for non-trivial work — use agent teams for parallelizable multi-faceted tasks, subagents for focused single-output tasks
- **Commit frequently** after every meaningful change
- **Update docs when changing code** — keep CLAUDE.md, README.md, project docs in sync
- **Flag outdated docs** — proactively ask about updates when you notice inconsistencies
- **Use TodoWrite** for complex multi-step tasks
- **Run tool calls in parallel** when independent
- **One editor per file** — never multiple agents editing same file concurrently
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

### Compacting Conversations
- Preserve user instructions faithfully
- Note tricky conventions
- Don't make up details
- ASK if unclear

---

## Claude Code Directory Convention

| Artifact     | Global (~/.claude/)          | Per-project (<repo>/.claude/) |
|-------------|-------------------------------|-------------------------------|
| Instructions | CLAUDE.md                    | CLAUDE.md                     |
| Rules        | rules/*.md (auto-loaded)     | rules/*.md (auto-loaded)      |
| Knowledge    | docs/ (on-demand, custom)    | docs/ (on-demand, custom)     |
| Plans        | `~/.claude/plans/` (use `plansDirectory` for per-project) | plans/                        |
| Tasks        | `~/.claude/tasks/` (no per-project option yet) | —                             |
| Agents       | agents/*.md                  | agents/*.md                   |
| Skills       | skills/                      | (via plugins)                 |

Global = applies to ALL projects. Per-project = repo-specific, version-controlled.
Plans default to global but are configured per-project via `plansDirectory` in settings.json.
Tasks are global only (`~/.claude/tasks/`) — per-project not yet available ([#20425](https://github.com/anthropics/claude-code/issues/20425)).
`docs/` is a custom convention (not auto-loaded by Claude Code) — skills read from it on demand.

Standard paths:
- Global: `~/.claude/docs/` `~/.claude/rules/` `~/.claude/tasks/`
- Repo: `.claude/docs/` `.claude/rules/` `.claude/plans/` (via `plansDirectory`)

---

## Rules (Auto-Loaded)

Behavioral rules that apply to every session are in `~/.claude/rules/`:

- `rules/safety-and-git.md` — Zero tolerance table, git safety, destructive command warnings
- `rules/workflow-defaults.md` — Task/agent organization, file creation policy, output strategy
- `rules/context-management.md` — PDF/large file rules, bulk edit constraints, verbose output handling
- `rules/agents-and-delegation.md` — Subagent strategy, delegation decision tree, team escalation
- `rules/coding-conventions.md` — Python/TypeScript/shell basics, language selection, package managers
- `rules/refusal-alternatives.md` — Friction prevention: ambiguity resolution, non-destructive editing, tool failure pivots, over-caution fixes

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

**Context profiles** control which plugins load per-project via `claude-context`:
```bash
claude-context                    # Show current state / apply context.yaml
claude-context code               # Software projects
claude-context code web python    # Compose multiple profiles
claude-context --list             # Show active plugins and available profiles
claude-context --clean            # Remove project plugin config
claude-context --sync [-v]        # Register + update all plugin marketplaces
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

Adding a new plugin: add its marketplace to `marketplaces:` in `profiles.yaml`, run `claude-context --sync`, then add to a profile.

---

## Notes

- User specs: `specs/`
- Knowledge base: `docs/` (search first with `/docs-search`, add useful findings)
- Plans: `.claude/plans/` (per-project via `plansDirectory` setting)
- Tasks: `~/.claude/tasks/` (global, no per-project option — [#20425](https://github.com/anthropics/claude-code/issues/20425))
- Don't be overconfident about recent models — search if unsure
- Debugging: When something doesn't work after a few tries, step back and plan for alternatives
- Permission errors: If sandboxing blocks you, step back and EnterPlanMode. Consider using `trash` or `mv` to `.bak` instead of `rm`
