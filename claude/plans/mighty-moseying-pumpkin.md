# Plan: Visual Layout Quality Guidance (v3 — stronger edge/spacing coverage)

## Context

AI coding agents produce visual outputs with overlapping elements, content touching container edges, crisscrossing arrows, and spacing inconsistencies. This affects TikZ diagrams, Slidev presentations, and web layouts (Astro/Tailwind/HTML/CSS).

**Root cause (from real failure case):** Claude dismissed code reviewer feedback about fragile CSS (per-child padding) as "theoretical." The issue is behavioral (not verifying, dismissing feedback) as much as technical (wrong patterns).

## Deduplication Analysis

Before adding anything, here's what existing plugins already cover:

| Failure mode | ui-ux-pro-max (design profile) | viz-toolkit TikZ pitfalls | frontend-design | Gap? |
|---|---|---|---|---|
| Overlapping elements | z-index management, Pre-Delivery Checklist | Pitfalls #1, #2, #5 | **Encourages** overlap (line 33) with zero guardrails | **Yes — frontend-design pushes toward this failure** |
| Content touching edges | "Content padding", "Floating navbar spacing" | inner sep defaults in .sty | Nothing | **Yes — ui-ux-pro-max has rules but they're still not preventing it in practice; frontend-design has ZERO coverage** |
| Crisscrossing arrows | N/A (web-only) | Pitfall #2 (feedback arcs) | N/A | **Yes — no concrete routing rules** |
| Spacing inconsistencies | "Consistent max-width" | No spacing reference table | Nothing | **TikZ**: yes. **CSS**: partially covered by ui-ux-pro-max but not always loaded |
| Container vs per-child padding | Not mentioned | N/A | N/A | **Yes — novel insight from real failure** |
| Verify visual output before declaring done | Not mentioned | Not mentioned | Not mentioned | **Yes — behavioral, not in any rule** |
| Act on reviewer feedback | `refusal-alternatives.md` covers feedback in general | N/A | N/A | **Partial — not visual-specific** |

**Key insight (v3):** frontend-design can be active *without* ui-ux-pro-max. frontend-design actively encourages overlap/asymmetry (SKILL.md line 33: "Unexpected layouts. Asymmetry. **Overlap.**") but provides zero structural safety (no padding rules, no spacing constraints, no layout quality checks). When only frontend-design is loaded, there's no guardrail at all. Even when ui-ux-pro-max IS loaded, "content touching edges" still occurs — the existing rules are too abstract ("Content padding") without concrete minimums.

**Decision:** Same structure as v2 (no web-layout skill, no separate global rule file), but:
1. **Strengthen** the auto-loaded behavioral rules with concrete minimum values (not just principles)
2. **Expand** the on-demand doc to include essential CSS spacing patterns as a safety net for when ui-ux-pro-max isn't loaded
3. TikZ improvements unchanged from v2

---

## Implementation (3 changes, ~95 lines total new content)

### Step 1: Add behavioral rules to `rules/coding-conventions.md` (~15 lines)

Append a new section after "## CLI Tools Available":

```markdown
## Visual Output Quality

When generating any visual output (TikZ, HTML/CSS, Slidev, matplotlib):

- **Verify visually** — CSS/TikZ/layout changes MUST be checked against rendered output (Playwright screenshot, compiled PDF, browser preview). Accessibility snapshots do NOT reveal spacing issues
- **Act on reviewer layout feedback immediately** — visual bugs from CSS fragility are invisible in code review; when a reviewer flags it, fix it
- **Use layout systems, not manual coordinates** — flexbox/grid (CSS), `positioning` library (TikZ), CSS Grid (Slidev). Manual pixel/pt values drift and overlap
- **Container padding > per-child padding** — pad the container itself, not each child with `> :not(x)` selectors. Markdown renderers produce varying DOM structures
- **Test with variable content** — would this layout still work if text were 20% longer or a list had 2x items?

### Minimum Spacing (hard floor — never go below)

| Domain | Container padding | Content-to-edge gap | Between sibling elements |
|--------|------------------|--------------------|-----------------------|
| **HTML/CSS** | `p-3` / `0.75rem` / `12px` | `p-2` / `0.5rem` / `8px` | `gap-2` / `0.5rem` |
| **TikZ** | `inner sep>=10pt` | `inner sep>=8pt` | `node distance>=1.5cm` |
| **Slidev** | `p-4` / `1rem` on slide content | `p-2` on nested elements | `gap-3` / `0.75rem` |
```

**Why stronger than v2:** The v2 rules were principles ("use layout systems", "container padding > per-child padding") — good for understanding, but Claude still produces zero-padding containers. The hard-floor table gives concrete minimums that are checkable. Auto-loaded but still compact (~15 lines).

**File:** `claude/rules/coding-conventions.md` (66 lines → ~81 lines)

### Step 2: Expand TikZ diagram-pattern-catalog.md (~35 lines)

This is the genuine gap all critics agreed on. TikZ output can't be visually verified by the agent, so explicit spacing rules are essential.

**File:** `claude/local-marketplace/plugins/viz-toolkit/skills/tikz-diagrams/references/diagram-pattern-catalog.md`

**2a. Add 5 pitfall items** after item 10 (line ~617):

11. **Insufficient node distance** — set `node distance>=1.5cm`; default is too tight for readable diagrams
12. **Arrows routing through nodes** — use waypoints: `(A.east) -- ++(1,0) |- (C.west)` to route around obstacles
13. **Text touching box edges** — verify `inner sep>=8pt` on all text-containing nodes (basebox default is 8pt — if overriding, don't go below)
14. **Inconsistent spacing between similar elements** — use `positioning` library with uniform `node distance` rather than manual coordinates
15. **Container too tight around children** — for `fit` nodes use `inner sep>=15pt`; for `groupbox` use `inner sep>=10pt` (matches .sty defaults)

**2b. Add "Spacing Quick Reference" subsection** after Common Pitfalls:

```markdown
## Spacing Quick Reference

Values match `anthropic-tikz.sty` defaults. Override only when necessary.

| Element type | `inner sep` (in .sty) | Min gap between siblings |
|-------------|----------------------|--------------------------|
| basebox (content nodes) | 8pt | 1.5cm (node distance) |
| card (containers) | 12pt | 1cm |
| groupbox (dashed groups) | 10pt | 0.8cm |
| fit nodes wrapping children | 15pt (manual) | N/A |
| Labels/annotations | N/A | >=0.3cm below label |

### Arrow Routing Rules

1. Same-axis flow → straight horizontal/vertical arrows
2. Cross-axis → 90-degree elbows: `(A.east) -| (B.north)` or `(A.north) |- (B.west)`
3. Feedback/backward arcs → route above/below: `(C.north) -- ++(0,0.8) -| (A.north)`
4. **Never** diagonal arrows crossing through other nodes
5. Multiple parallel arrows → offset anchors: `A.north east` to `B.south west`
```

### Step 3: Create on-demand reference doc `docs/visual-layout-quality.md` (~55 lines)

A concise reference that skills can load on-demand. NOT auto-loaded — zero context cost unless explicitly requested. **Serves as the CSS spacing safety net when ui-ux-pro-max isn't loaded** (e.g., when only frontend-design is active).

```markdown
# Visual Layout Quality Reference

On-demand reference for visual output quality. Loaded by skills, not auto-loaded.

## Cross-Domain Principles

1. **Use layout systems, not manual coordinates** — flexbox/grid (CSS), positioning library (TikZ), CSS Grid (Slidev)
2. **Container padding, not per-child padding** — `> :not(x)` selectors break with varying DOM structures
3. **No negative margins for spacing** — use gap/node distance instead
4. **Verify rendered output** — screenshots (Playwright), compiled PDF, browser preview

## Domain-Specific Guidance

| Domain | Primary guide | Gap-filling guidance |
|--------|--------------|---------------------|
| **HTML/CSS** | ui-ux-pro-max plugin (Layout & Spacing, Pre-Delivery Checklist) | This doc (safety net when ui-ux-pro-max not loaded) |
| **TikZ** | viz-toolkit → tikz-diagrams (Spacing Quick Reference, Arrow Routing Rules) | — |
| **Slidev** | writing-toolkit → fix-slide | — |
| **matplotlib** | `docs/petri-plotting.md`, anthropic.mplstyle | — |

## CSS Spacing Safety Net

These rules apply ALWAYS, even when frontend-design encourages "overlap" and "asymmetry." Intentional overlap means z-index layering with visual breathing room — NOT content touching container edges.

### Hard Rules

1. **Every content container must have padding** — minimum `p-2`/`0.5rem`/`8px`. No exceptions
2. **Text must never touch its container edge** — if text is inside a box/card/section, there must be padding
3. **Siblings need gap** — use `gap-2`/`0.5rem` minimum between adjacent elements (flex/grid gap, not margin hacks)
4. **Full-bleed elements get negative margin, not zero-padding parents** — if a child needs to touch edges, use negative margin on that child, not remove padding from parent

### Anti-Patterns (with fixes)

```css
/* BAD — per-child padding (breaks with markdown content) */
details > :not(summary) { padding: 0 1.25rem; }
/* GOOD — container padding */
details { padding: 0 1.25rem; }
details > summary { margin: 0 -1.25rem; padding: 0 1.25rem; }

/* BAD — no padding on content card */
.card { border: 1px solid; border-radius: 0.5rem; }
/* GOOD — content has breathing room */
.card { border: 1px solid; border-radius: 0.5rem; padding: 1rem; }

/* BAD — fixed heights causing overflow */
.container { height: 200px; overflow: hidden; }
/* GOOD — min-height or auto with padding */
.container { min-height: 200px; padding: 1rem; }

/* BAD — absolute positioning without container padding */
.parent { position: relative; }
.child { position: absolute; top: 0; left: 0; }
/* GOOD — offset from edges */
.parent { position: relative; padding: 0.5rem; }
.child { position: absolute; top: 0.5rem; left: 0.5rem; }
```

### Pre-Ship Spacing Check (when ui-ux-pro-max not loaded)

Before declaring CSS work complete, verify:
- [ ] No text touching container edges (inspect with browser dev tools)
- [ ] All cards/sections have visible padding
- [ ] Sibling elements have consistent gaps (not zero)
- [ ] Layout survives 20% longer text content
- [ ] Mobile viewport doesn't clip or overflow
```

**File:** `claude/docs/visual-layout-quality.md`

---

## Files to Modify

| File | Action | Lines added |
|------|--------|-------------|
| `claude/rules/coding-conventions.md` | **EDIT** — add "## Visual Output Quality" section with hard-floor spacing table | +15 |
| `claude/local-marketplace/plugins/viz-toolkit/skills/tikz-diagrams/references/diagram-pattern-catalog.md` | **EDIT** — expand Common Pitfalls + add Spacing Quick Reference | +35 |
| `claude/docs/visual-layout-quality.md` | **CREATE** — on-demand reference with CSS spacing safety net | ~55 |

**Total: ~105 lines across 2 edits + 1 new file.** Up from ~85 in v2 (extra CSS safety net content), still less than half of v1's 225 lines.

## What Was Removed (and why)

| v1 component | Removed because |
|---|---|
| `rules/visual-layout-quality.md` (55-line global rule) | Context cost too high for ~10% of sessions. Behavioral rules (10 lines) go into existing `coding-conventions.md` instead |
| `viz-toolkit/skills/web-layout/SKILL.md` | ~80% duplicates ui-ux-pro-max (Layout & Spacing, Pre-Delivery Checklist, z-index management) |
| `viz-toolkit/skills/web-layout/references/layout-quality-checklist.md` | Same duplication. Novel insights moved to `docs/visual-layout-quality.md` |
| Plugin manifest update | No new skill created, no update needed |
| Global CLAUDE.md cross-reference update | No new rule file to reference |

## Verification

1. **Behavioral rules load**: Start a new Claude Code session in this repo, verify `coding-conventions.md` shows "Visual Output Quality" section with the Minimum Spacing table in loaded rules
2. **frontend-design-only scenario**: With only frontend-design enabled (no ui-ux-pro-max), verify the auto-loaded coding-conventions rules provide concrete spacing minimums. Ask Claude to build a card component — it should have padding, not zero-padding containers
3. **TikZ guidance reachable**: With viz-toolkit enabled, invoke tikz-diagrams skill, verify expanded Common Pitfalls (15 items) and Spacing Quick Reference are present
4. **On-demand doc accessible**: Skills can read `docs/visual-layout-quality.md` when doing visual work — verify the CSS Safety Net section and Pre-Ship Spacing Check are present
5. **Complementary with ui-ux-pro-max**: The docs file references ui-ux-pro-max as the primary guide (not restating its rules) while providing the concrete anti-patterns and hard rules that ui-ux-pro-max lacks
6. **Context cost**: coding-conventions.md grows by ~15 lines (66 → 81), well within acceptable range

## What Changed v2 → v3

| Component | v2 | v3 | Why |
|---|---|---|---|
| Deduplication table | "CSS: covered" for content touching edges | "CSS: still failing in practice; frontend-design has ZERO coverage and encourages overlap" | User observed the failure mode persisting despite ui-ux-pro-max |
| coding-conventions.md | 10 lines, principles only | 15 lines, principles + hard-floor spacing table | Principles alone didn't prevent zero-padding containers |
| docs/visual-layout-quality.md | 40 lines, single CSS anti-pattern | 55 lines, CSS Safety Net section with 4 hard rules, 4 anti-pattern examples, pre-ship checklist | Serves as safety net when ui-ux-pro-max not loaded |
| frontend-design analysis | Not mentioned | Explicitly called out as pushing toward overlap without guardrails | frontend-design can be active without ui-ux-pro-max |

## Deferred

- **Hookify Stop rule**: Block completion if CSS/TikZ files edited but no visual verification. Add only if issue recurs after rules are in place.
- **Upstream contribution to ui-ux-pro-max**: Add "container-vs-child padding", minimum padding values, and "no negative margins" as explicit rules. Requires PR to external plugin.
- **frontend-design guardrails**: Consider contributing a "Structural Safety" addendum to frontend-design that pairs with its aesthetic encouragement of overlap. The overlap it encourages should mean z-index layering, not content touching edges.
