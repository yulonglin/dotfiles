---
name: sweep-ai-safety
description: Sweep recent AI safety research from curated sources (Anthropic alignment science / red team, OpenAI, GDM, Apollo, Redwood, METR, FAR AI, Truthful AI, alphaxiv, arXiv) and surface items matching tracked topic terms (inoculation prompting, reward hacking, exploration hacking, metagaming, eval gaming, OOCR, scheming, alignment faking, sandbagging, etc.). Use when asked to "sweep AI safety", "what's new in alignment", "any recent papers on X", "weekly safety digest", or for staying current on AI safety literature.
---

# Sweep AI Safety Research

A hybrid skill: a curated **source registry** + **topic glossary** Claude can consult during research, and a **Python script** that fetches feeds and produces a dated markdown digest of the last 7 days.

## When to invoke

- User asks: "what's new in AI safety", "sweep alignment research", "any recent papers on <term>", "weekly safety digest", "what did Anthropic/Apollo/Redwood post recently"
- Before research planning — to check whether a question is already addressed by recent work
- When a user mentions an unfamiliar term (inoculation prompting, OOCR, exploration hacking, metagaming) — consult `terms.md`
- Periodic — schedule via `/loop 7d /sweep-ai-safety` or a cron routine

## Quick start

```bash
# Default: last 7 days, all sources, markdown to stdout
uv run ~/.claude/skills/sweep-ai-safety/sweep.py

# Save to a dated file
uv run ~/.claude/skills/sweep-ai-safety/sweep.py --output digest.md

# Wider window
uv run ~/.claude/skills/sweep-ai-safety/sweep.py --since 30d

# Filter by topic term (matches in title/summary)
uv run ~/.claude/skills/sweep-ai-safety/sweep.py --term "reward hacking"

# Single source
uv run ~/.claude/skills/sweep-ai-safety/sweep.py --source anthropic-alignment

# arXiv keyword search (uses term registry by default)
uv run ~/.claude/skills/sweep-ai-safety/sweep.py --arxiv-only
```

## Architecture

```
sweep-ai-safety/
├── SKILL.md          # this file
├── sources.yaml      # source registry (orgs, blogs, feed URLs)
├── terms.md          # topic-term glossary with short definitions
└── sweep.py          # fetcher (PEP 723, uv run directly)
```

### Source registry (`sources.yaml`)

One entry per source. Fields:

```yaml
- key: anthropic-alignment        # short id used in --source
  org: Anthropic
  name: Alignment Science blog
  url: https://alignment.anthropic.com/
  rss: https://alignment.anthropic.com/rss.xml   # null if no feed
  kind: blog | papers | aggregator | researcher
  verified: false                  # flip to true after first successful fetch
  notes: ...
```

The script does NOT trust `rss:` blindly — on first run, it reports which feeds resolved and which need manual URL correction. Edit `sources.yaml` to fix.

### Topic glossary (`terms.md`)

A flat list of tracked terms with one-sentence definitions and (where useful) seminal paper anchors. Used:

1. By Claude as a reference when a user mentions a term — read the entry and the linked paper
2. By `sweep.py` for cross-reference: items mentioning any registered term are tagged in the digest

Add a new term: append to `terms.md`. Optionally add it to the `arxiv_search_terms:` list in `sources.yaml` so the script searches arXiv for it.

## Reference-mode workflow (no script)

When the user mentions a term or asks about recent work without wanting a full sweep:

1. Open `terms.md` — does the term have a glossary entry? Read it
2. Open `sources.yaml` — identify the likely source(s) (e.g., scheming → Apollo; sandbagging → Anthropic alignment / METR; inoculation prompting → Truthful AI / Owain Evans)
3. Use `WebSearch` or `WebFetch` on the relevant source's blog / publications page
4. If a paper title is mentioned, look it up via arXiv API:
   - `curl -sL "http://export.arxiv.org/api/query?search_query=ti:%22<title%20words>%22&max_results=5"` (Atom XML)

## Sweep-mode workflow (script)

1. `uv run ~/.claude/skills/sweep-ai-safety/sweep.py --output "$HOME/scratch/safety-digest-$(utc_date).md"`
2. Review the digest. Flag any failed fetches — they indicate URLs that drifted
3. Update `sources.yaml` if URLs need correction; mark `verified: true` for ones that worked
4. Read the high-signal items (matched-term or known-author hits) in full via WebFetch

## Failure modes & gotchas

| Issue | Why | Fix |
|-------|-----|-----|
| **Most sources return 0 items** | RSS URL drifted or site has no feed | Open the org's blog page, find the actual feed URL, update `sources.yaml`. If no feed exists, the org has to be checked manually via WebFetch |
| **arXiv requests get throttled** | arXiv rate-limits at ~5 req/3s; sticky penalty 30-60s if exceeded | Script already batches arXiv term searches. If still throttled, wait 60s |
| **Same paper appears under multiple sources** | A paper can be on arXiv + an org blog + alphaxiv | Script dedupes by arXiv ID and by title-similarity (Jaccard 0.85) |
| **Term doesn't match because of variant spelling** | "OOCR" vs "out-of-context reasoning" vs "out of context reasoning" | Add aliases to the term entry in `terms.md` and the regex in `sources.yaml` |
| **Sandbox blocks external HTTP** | Most non-allowlisted hosts return connection error from Claude Code's sandbox | Run with `dangerouslyDisableSandbox: true`, or run from a normal shell |
| **Item is in the right time window but old content** | Some blogs republish/redate posts | Cross-check the canonical URL date; trust arXiv `submittedDate` over blog dates |

## Verification policy (research integrity)

This skill surfaces candidates. **Always verify before acting on a finding:**

- Don't cite a paper from the digest without WebFetching the actual source
- Don't claim a term is "from paper X" without checking — the script's glossary is a starting point, not ground truth
- If the digest says "no items from <source> in last 7d", that means either nothing was published OR the feed isn't working — distinguish before relying on the absence

## Adapting

- **Add a source**: append to `sources.yaml`, set `verified: false`, run sweep, update if it works
- **Add a tracked term**: append to `terms.md` with a one-line definition; optionally add to `sources.yaml` `arxiv_search_terms:` for arXiv inclusion
- **Different cadence**: pass `--since 14d` / `--since 30d`; or schedule via `/loop 14d /sweep-ai-safety` (or as a routine via `/schedule`)
- **JSON output for programmatic use**: pass `--json` (emits one item per line, NDJSON)
