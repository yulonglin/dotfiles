# External Resources & Inspiration

Curated reference for keeping the workflow current. Skim quarterly; pull patterns that fit, ignore the rest.

This is on-demand reading, not auto-loaded. Pointed to from `~/.claude/CLAUDE.md`.

## Aggregators

- [Good AI List](https://goodailist.com/repos) — Chip Huyen's daily-updated directory of AI repos and developers, with star/fork trends
- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — skills, hooks, slash-commands, agents, plugins
- [awesome-claude-code-output-styles](https://github.com/hesreallyhim/awesome-claude-code-output-styles-that-i-really-like) — curated output styles
- [ykdojo/claude-code-tips](https://github.com/ykdojo/claude-code-tips) — 45 practical tips, status line scripts, system-prompt trimming
- [Claude Code in Action](https://anthropic.skilljar.com/claude-code-in-action) — Anthropic's official course

## Voices to follow

Each emphasises a different lens — read for the lens, not the prescriptions.

- **Boris Cherny** (Claude Code creator) — output styles, customization philosophy, "compounding engineering" (update CLAUDE.md any time Claude does something wrong). [howborisusesclaudecode.com](https://howborisusesclaudecode.com/) · [@bcherny on X](https://x.com/bcherny) · [12 Ways to Customize](https://snowan.gitbook.io/study-notes/ai-blogs/boris-cherny-customize-claude-code)
- **Thariq Shihipar** (Anthropic, Claude Code) — skills taxonomy (verification, monitoring, automation), session management (rewind via double-Esc), spec interviews for long-running tasks. [Lessons on skills](https://www.linkedin.com/pulse/lessons-from-building-claude-code-how-we-use-skills-thariq-shihipar-iclmc) · [tips digest](https://github.com/shanraisshan/claude-code-best-practice/tree/main/tips)
- **Mitchell Hashimoto** — "harness engineering" (when an agent makes a mistake, build a checker it can call); always-running-agent mindset. [My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey) · [Zed: Agentic Engineering in Action](https://zed.dev/blog/agentic-engineering-with-mitchell-hashimoto)
- **Simon Willison** — context-awareness discipline, iterate-from-simple, plan-as-meta-program for refactors. [simonwillison.net/tags/claude-code](https://simonwillison.net/tags/claude-code/) · [How I use LLMs to write code](https://simonw.substack.com/p/how-i-use-llms-to-help-me-write-code)
- **Andrej Karpathy** — workflow shift to 80% agent coding, treating CLAUDE.md as behavioural spec. [Coding workflow notes](https://x.com/karpathy/status/2015883857489522876)

## Output styles for learning/growing

Directly relevant to the stakes-tiered Effortful Learning framework in `claude/output-styles/10x-mentor.md`.

- **Built-in `/output-style explanatory`** — narrates *why* during edits; use when ramping into a new codebase or unfamiliar framework
- **Built-in `/output-style learning`** — drops `TODO(human)` markers asking you to write 5-10 lines yourself; pair-programmer feel
- [Anthropic `learning-output-style` plugin](https://github.com/anthropics/claude-code/blob/main/plugins/learning-output-style/README.md) — official extended version
- [Output styles docs](https://code.claude.com/docs/en/output-styles) — `/output-style:new` to scaffold custom
- Custom: `claude/output-styles/10x-mentor.md` — your own; modelling-over-explaining, max one coaching moment per response

### When to switch styles (learning loops)

`10x-mentor` is reflection-after-action — Claude writes the code, then maybe coaches. The built-in `learning` style is the opposite — Claude leaves `TODO(human)` markers and you write 5-10 lines yourself. Different bets:

| Goal | Style | Why |
|------|-------|-----|
| Daily work, judgment + design coaching | `10x-mentor` (default) | Reflection builds judgment, doesn't slow execution |
| Building procedural skill in a new domain (frontend, Rust ownership, a new framework) | `learning` | Production beats reflection for muscle memory |
| Ramping into an unfamiliar codebase or protocol | `explanatory` | Narrates *why* while still writing the code |
| Drafting communication / message critique | `10x-mentor` | COMM track is tuned for this |

Switch with `/output-style <name>`. No reason to commit to one — toggle per task.

## Where to send patterns you discover

- One-off insight → `## Learnings` in project CLAUDE.md
- Recurring across projects → promote to global CLAUDE.md or a `rules/*.md`
- Reusable workflow → skill or slash command
- Reference / quarterly skim material → `docs/`
- Behavioural rule under a specific style → that style's `.md`
