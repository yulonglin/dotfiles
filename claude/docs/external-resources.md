# External Resources & Inspiration

**Consult this doc before improving the Claude Code setup.** When the user wants to extend skills/rules/output-styles, sync memory across machines, or borrow a workflow — start here, then web-search only for what's missing. Aggregators and named voices below already cover most of the public state of the art; pulling from training data alone tends to miss the last 6 months.

Skim quarterly; pull patterns that fit, ignore the rest. On-demand reading, not auto-loaded — pointed to from `~/.claude/CLAUDE.md`.

## Aggregators

- [Good AI List](https://goodailist.com/repos) — Chip Huyen's daily-updated directory of AI repos and developers, with star/fork trends
- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — skills, hooks, slash-commands, agents, plugins
- [awesome-claude-code-output-styles](https://github.com/hesreallyhim/awesome-claude-code-output-styles-that-i-really-like) — curated output styles
- [ykdojo/claude-code-tips](https://github.com/ykdojo/claude-code-tips) — 45 practical tips, status line scripts, system-prompt trimming
- [Claude Code in Action](https://anthropic.skilljar.com/claude-code-in-action) — Anthropic's official course

## Voices to follow

Each emphasises a different lens — read for the lens, not the prescriptions.

- **Boris Cherny** (Claude Code creator) — output styles, customization philosophy, "compounding engineering" (update CLAUDE.md any time Claude does something wrong). [howborisusesclaudecode.com](https://howborisusesclaudecode.com/) · [@bcherny on X](https://x.com/bcherny) · [12 Ways to Customize](https://snowan.gitbook.io/study-notes/ai-blogs/boris-cherny-customize-claude-code)
- **Cat Wu** (Anthropic, Claude Code PM) — product perspective on adoption, dev workflows, what's coming. Worth following alongside Boris for the "where Claude Code is heading" lens rather than current-tips. [@_catwu on X](https://x.com/_catwu)
- **Thariq Shihipar** (Anthropic, Claude Code) — skills taxonomy (verification, monitoring, automation), session management (rewind via double-Esc), spec interviews for long-running tasks. [Lessons on skills](https://www.linkedin.com/pulse/lessons-from-building-claude-code-how-we-use-skills-thariq-shihipar-iclmc) · [tips digest](https://github.com/shanraisshan/claude-code-best-practice/tree/main/tips)
- **Mitchell Hashimoto** — "harness engineering" (when an agent makes a mistake, build a checker it can call); always-running-agent mindset. [My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey) · [Zed: Agentic Engineering in Action](https://zed.dev/blog/agentic-engineering-with-mitchell-hashimoto)
- **Simon Willison** — context-awareness discipline, iterate-from-simple, plan-as-meta-program for refactors. [simonwillison.net/tags/claude-code](https://simonwillison.net/tags/claude-code/) · [How I use LLMs to write code](https://simonw.substack.com/p/how-i-use-llms-to-help-me-write-code)
- **Andrej Karpathy** — workflow shift to 80% agent coding, treating CLAUDE.md as behavioural spec. [Coding workflow notes](https://x.com/karpathy/status/2015883857489522876)

## Cross-machine memory & state sync

The dotfiles repo already syncs **durable config** (CLAUDE.md, rules/, skills/, agents/, settings.json) across machines via Git. Per-project auto-memory under `~/.claude/projects/<repo>/memory/` does **not** sync — it's local. If a coaching memory or feedback pattern only fires on one laptop, the noticing-loop ("hit this 3 times across machines → promote") is broken.

Ready-made tools (none battle-tested by us; survey before adopting):

- [claude-mem](https://github.com/thedotmack/claude-mem) — most popular (~46K+ stars). Compresses sessions and stores searchable memory; integrates via hooks. Single-machine focus, but a sync layer is straightforward
- [claude-mem-sync](https://github.com/lopadova/claude-mem-sync) — sync extension for the above; cross-device shared memory
- [claude-brain](https://github.com/toroleapinc/claude-brain) — git-backed memory store ("brain" repo) shared across machines; each session reads/writes structured notes
- [claude-cowork](https://github.com/yang1997434/claude-cowork) — multi-agent + multi-machine coordination; broader than just memory
- [Claude Sync (CLI)](https://www.npmjs.com/package/claude-sync) — generic settings/skills sync between machines via Git
- [Anthropic issue #25739](https://github.com/anthropics/claude-code/issues/25739) — official thread tracking native cross-machine memory; subscribe rather than waiting

Decision lens before adopting: does this sync the **durable patterns** (rules, skills, learnings worth carrying) or just **session noise** (todos, scratch context)? We want the former. The simplest viable path is probably extending the existing dotfiles git repo to cover `~/.claude/projects/*/memory/` rather than adopting a new tool.

## Output styles for learning/growing

Directly relevant to the stakes-tiered Effortful Learning framework in `claude/output-styles/effortful-learning.md`.

- **Built-in `/output-style explanatory`** — narrates *why* during edits; use when ramping into a new codebase or unfamiliar framework
- **Built-in `/output-style learning`** — drops `TODO(human)` markers asking you to write 5-10 lines yourself; pair-programmer feel
- [Anthropic `learning-output-style` plugin](https://github.com/anthropics/claude-code/blob/main/plugins/learning-output-style/README.md) — official extended version
- [Output styles docs](https://code.claude.com/docs/en/output-styles) — `/output-style:new` to scaffold custom

### When to switch styles (learning loops)

The built-in `learning` style leaves `TODO(human)` markers asking you to write 5-10 lines yourself; pair-programmer feel. The `explanatory` style narrates *why* while still writing the code. Different bets:

| Goal | Style | Why |
|------|-------|-----|
| Building procedural skill in a new domain (frontend, Rust ownership, a new framework) | `learning` | Production beats reflection for muscle memory |
| Ramping into an unfamiliar codebase or protocol | `explanatory` | Narrates *why* while still writing the code |

Switch with `/output-style <name>`. No reason to commit to one — toggle per task.

## Where to send patterns you discover

- One-off insight → `## Learnings` in project CLAUDE.md
- Recurring across projects → promote to global CLAUDE.md or a `rules/*.md`
- Reusable workflow → skill or slash command
- Reference / quarterly skim material → `docs/`
- Behavioural rule under a specific style → that style's `.md`
