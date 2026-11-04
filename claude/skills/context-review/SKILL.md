---
name: context-review
description: Act on the monthly context review — read the latest `context-review` report, propose keep, trim or drop for each flagged skill, agent, rule, handoff and Learnings entry with its evidence, put the proposals on a reviewable page, then apply only what the user approves, reversibly. Use on /context-review, "review my context cost", "act on the context review", or when the SessionStart nudge names an unreviewed context review.
---

# Context review

The monthly `context-review.timer` runs `context-review run`, which measures and changes nothing. This skill is the half that acts, and it acts only on what the user approves. The scan itself is `custom_bins/context-review` (`--help` lists its flags); the report says what each number means.

## Steps, in order

1. **Find the report.** Run `context-review status`. If it says there is no run, or the last run is more than 40 days old, run `context-review run` first. Read `<state>/<date>/report.md` and `summary.json` from the paths it prints.
2. **Build the proposal list** from what the report flags, one item per thing, each with its evidence (cost, uses in 30 and 90 days, last use, add date, age):
   - unused skills, agents and commands (zero uses in 90 days);
   - always-on files that grew since the last run, or are past 200 lines;
   - stale `remember.md` handoffs, and Learnings entries past two weeks;
   - auto-memory indexes that look bloated (many entries, or entries a rule or skill now covers).
3. **Propose one state per item**: `keep`, `trim` or `drop`. Moving procedure out of an always-on rule into a skill is a `trim`: name the destination skill in the item. Before proposing `drop` for something unused, check the two blind spots the report names. Usage counts cover only this machine's transcripts. And a skill can be in use without being invoked: a rule may route to it by name, so `rg` the name across `claude/`.
4. **Render the page.** Write the list to a Markdown file under the scratch directory, one `- [ ]` item per proposal with the lean first: "**`debrief`** (skill, ~156 tok, 0 uses / 90 d, added 2026-10-02) — lean drop: …". Then run `md2artifact --states keep,trim,drop <file>.md` and publish the HTML with the capabilities from `md2artifact --capabilities` (mechanics: `artifact-writing`). Put each item's starting state in the prose, since `[ ]` starts every item at `keep`.
5. **Stop and hand back** the page link, plus a 3-5 line summary: how many items in each lean, and the largest token saving on offer. Wait for the user's export (`- [drop] …` lines) or a reply in chat. Do nothing to any file before that.
6. **Apply only the approved items**, each reversibly, then commit with explicit pathspecs:
   - dotfiles skill, `drop`: `git mv claude/skills/<name> archive/<YYYY-MM-DD>_<name>/`. Remove its row from `claude/skills/catalog/SKILL.md`, and fix any rule or skill that names it.
   - dotfiles agent, `drop`: `git mv claude/agents/<name>.md archive/<YYYY-MM-DD>_<name>/`. A **generated** agent (the report marks it) is switched off in `config/model-router.toml`, followed by `model-router-wire apply`. Never edit or move its `.md`.
   - plugin component: the plugin is the unit. Propose turning the plugin off in `enabledPlugins` and list everything else that plugin brings. Changing `claude/settings.json` needs the user's explicit yes, and the three-key check in `.claude/rules/dotfiles-settings.md` afterwards.
   - rule or CLAUDE.md, `trim`: edit the text, moving procedure to the named skill or checklist. Never delete passages that `tests/test_memory_tier_budget.py` protects.
   - stale handoff or Learnings entry: refresh it with the `remember` skill, or move the entry to the file that owns its topic. Never delete a `remember.md`.
   - transcripts: never touched. Retention is deliberate.
7. **Acknowledge** with `context-review ack --note "<one line: what was applied>"`. This silences the SessionStart nudge until the next run. If the user defers the whole review, ack with `--note "deferred"` only when they say so.

## When to stop

Stop at step 5 every time: the page is the decision point, and nothing is applied without the user's states. Also stop and ask before any change to `claude/settings.json`, hooks or a plugin. And stop when an item's evidence conflicts, for example zero uses but a rule routes to it.

## What to hand back

The page link. After applying: what changed, as one line per item with its commit, what was deferred, and the ack note. Then name anything still waiting on the user (a settings change, a plugin to disable), with your lean.
