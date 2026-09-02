# Context audit

Measures what every Claude Code component costs in context, and how often it is actually used. Produces the [Context Ledger](https://claude.ai/code/artifact/439482e4-0d10-4715-a7d1-add2805e614a) artifact.

Run in order, from this directory's parent repo root:

```bash
python3 scripts/context-audit/inventory.py   # walk dotfiles + enabled plugin caches -> inventory.json
python3 scripts/context-audit/usage.py       # attach invocation counts mined from ~/.claude/projects
python3 scripts/context-audit/build.py       # attach clusters + leans -> payload.json
python3 scripts/context-audit/asciify.py     # entity-escape template.html (idempotent)
python3 scripts/context-audit/emit.py        # inject payload -> context-ledger.html
annotate-html context-ledger.html            # required by the PreToolUse artifact hook
```

Scripts read and write beside themselves, so copy `template.html` in alongside them first, or run them from a scratch directory holding all six files.

## Three things that are easy to get wrong

**Enabled != installed.** Only plugins listed in `enabledPlugins` in `~/.claude/settings.json` load, and they load from `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, not from the marketplace clones. Scanning `~/code/marketplaces/` alone both double-counts (that repo and the cache hold the same components) and misattributes, because the plugin directory is the parent of `skills/`, not the first path segment.

**Renames hide usage.** `git log --diff-filter=R -- claude/skills` is not optional. On 2026-08-28 `grilling` became `interview-me` and `pastelplot` + `anthropic-style` became `house-plots`; counting only current names reports the most-used skill in the repo as dead. `usage.py` carries an `ALIASES` map for exactly this.

**Frontmatter is real YAML.** Many skills write `description: >-` as a folded scalar over several lines. A line-by-line regex silently truncates those to empty, understating the always-loaded cost of the most verbose skills.

## Two output hazards

Skill bodies contain literal HTML. `emit.py` escapes every `<` in the payload as `<`, because otherwise the embedded `</body>` inside the superpowers brainstorm source makes `annotate-html` splice its layer into the middle of the data script. The page is also kept pure ASCII so it survives any host that serves it without a charset.

Token counts are `characters / 4`, not a real tokenizer. Treat them as +/-15% and comparable to each other, not exact.
