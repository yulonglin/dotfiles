# Plan: Add Structural/Rhetorical LLM Tropes to Humanizer

## Context

User shared a LinkedIn post listing AI writing tropes that go beyond word-level clichés into **structural and rhetorical patterns** — things like false suspense transitions, patronizing analogies, and gerund fragments. These are higher-level patterns not currently covered by the v0.1 humanizer (which focuses on phrase-level detection).

## New Patterns (8 total — Category 6: Structural/Rhetorical Tropes)

From the post:
1. **Negative parallelism** — "It's not bold. It's backwards." (false contrast for drama)
2. **Self-posed rhetorical questions** — "The worst part? Nobody saw it coming." (manufactured suspense)
3. **False ranges** — "From innovation to implementation to cultural transformation." (fake breadth)
4. **Gerund sentence fragments** — "Shipping faster. Moving quicker. Delivering more." (staccato filler)
5. **False suspense transitions** — "Here's where it gets interesting." (patronizing buildup)
6. **Patronizing analogies** — "Think of it as a Swiss Army knife for your workflow." (dumbed-down comparison)
7. **Historical analogies** — "Every major technological shift — the web, mobile, social, cloud — followed the same pattern." (false authority via enumeration)
8. **Asserting obviousness** — "The reality is simpler and less flattering." (claims insight without delivering it)

## Files to Update

### 1. Agent: humanizer.md (source)
**Path:** `/Users/yulong/code/marketplaces/ai-safety-plugins/plugins/writing/agents/humanizer.md`

- Update count: "15 patterns" → "23 patterns" in PURPOSE
- Add new `## Structural/Rhetorical Tropes (8 patterns)` section after Filler Phrases
- Update CONSTRAINTS to reference 23 patterns
- Keep existing patterns untouched

### 2. Agent cache copy
**Path:** `/Users/yulong/code/dotfiles/claude/plugins/cache/ai-safety-plugins/writing/1.0.0/agents/humanizer.md`

- Mirror exact same changes as source

### 3. Docs: humanizer-patterns.md
**Path:** `/Users/yulong/code/dotfiles/claude/docs/humanizer-patterns.md`

- Add `### Category 6: Structural/Rhetorical Tropes (8 patterns)` with full documentation per pattern (why problematic, confidence, false positives, fix suggestions)
- Update overview count (15 → 23)
- Add source citation (LinkedIn post / Helmuth Rosales masterpiece)
- Add to Evolution Log as v0.2 entry
- Move some v0.2 planned items to v0.3

## Confidence Levels (proposed)

| Pattern | Confidence | Rationale |
|---------|-----------|-----------|
| Gerund fragments | 92% | Almost never natural in prose |
| False suspense | 90% | "Here's where it gets interesting" = pure AI |
| Patronizing analogies | 88% | "Think of it as..." pattern is distinctive |
| Negative parallelism | 85% | Can appear in good rhetoric, but LLMs overuse |
| Self-posed rhetorical | 85% | The "X? Y." pattern is very LLM-coded |
| False ranges | 87% | "From X to Y to Z" tricolon with abstract nouns |
| Historical analogies | 82% | Can be legitimate, but the dash-enumeration form is LLM |
| Asserting obviousness | 80% | Most context-dependent — legitimate in opinion pieces |

## Verification

1. Check that the masterpiece example text triggers multiple new patterns
2. Ensure old patterns still documented and unchanged
3. Verify cache and source are in sync

## Not changing
- `humanize-draft/SKILL.md` — deprecated, just a redirect
- `review-draft/SKILL.md` — dispatches to humanizer agent, no pattern knowledge
- `clear-writing/SKILL.md` — separate concern (prose quality, not LLM detection)
