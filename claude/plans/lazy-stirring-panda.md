# Plan: Style `<details>/<summary>` in Blog Posts + Re-translate Chinese

## Context

The "Choose Your Path" section in the AI guide uses `<details>/<summary>` HTML in markdown. Currently these elements get **zero custom styling** — just browser defaults (tiny triangle, no hover, no background). Readers may not realize the summaries are clickable.

The site has an editorial aesthetic (Crimson Pro headings, Lora body, warm orange accent `#d97757`, dark/light themes via CSS variables). The existing Timeline and about page already have polished `<details>` patterns, but those are component-scoped and don't reach markdown content.

## Step 1: CSS Styling

**File:** `src/pages/writing/[slug].astro` — add `:global(details/summary)` rules after the existing table styles (~line 419), before `</style>`.

### Design decisions

- **Card pattern** is the right choice for "choose one" UX in a long-form article — familiar, obviously interactive, works in markdown without complex HTML
- **No visual differentiation between paths** (no different accent colors/icons) — the text labels already differentiate clearly, and adding color-coding would imply a recommendation bias
- **No grid animation** — instant toggle feels decisive for a "choose your path" UX; native `::details-content` animation is coming to browsers anyway
- **CSS-only chevron** via `::before` pseudo-element (no SVG needed in markdown)

### CSS rules (incorporating codex critique)

```css
/* Collapsible sections (used in AI guide "Choose Your Path") */
.prose-content :global(details) {
  margin: 0.75rem 0;
  border: 1px solid var(--border);
  border-radius: 0.5rem;
  overflow: hidden;
}

.prose-content :global(summary) {
  cursor: pointer;
  list-style: none;
  padding: 0.875rem 1.25rem 0.875rem 2.5rem;
  font-family: var(--font-heading);
  font-weight: 600;
  color: var(--text);
  background: var(--bg-alt);
  position: relative;
  transition: background-color 0.15s ease;
}

.prose-content :global(summary:hover) {
  background: color-mix(in srgb, var(--bg-alt) 70%, var(--accent) 30%);
}

/* Hide default browser markers (webkit + Firefox) */
.prose-content :global(summary::-webkit-details-marker) {
  display: none;
}
.prose-content :global(summary::marker) {
  content: '';
}

/* Focus-visible for keyboard navigation */
.prose-content :global(summary:focus-visible) {
  outline: 2px solid var(--accent);
  outline-offset: -2px;
}

/* CSS-only chevron indicator */
.prose-content :global(summary::before) {
  content: '';
  position: absolute;
  left: 1rem;
  top: 50%;
  transform: translateY(-50%);
  width: 0;
  height: 0;
  border-left: 6px solid var(--text-muted);
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
  transition: transform 0.2s ease;
}

/* Rotate chevron when open */
.prose-content :global(details[open] > summary::before) {
  transform: translateY(-50%) rotate(90deg);
}

/* Separator between summary and content */
.prose-content :global(details[open] > summary) {
  border-bottom: 1px solid var(--border);
}

/* Content padding inside expanded details */
.prose-content :global(details > :not(summary)) {
  padding: 0 1.25rem;
}

/* Top spacing for first element after summary */
.prose-content :global(details > summary + *) {
  margin-top: 1.25rem;
}

/* Bottom spacing for last element */
.prose-content :global(details > :last-child) {
  margin-bottom: 1.25rem;
}
```

### Key improvements from codex review
- `summary::marker { content: '' }` — Firefox marker removal
- `summary + *` instead of `:not(summary):first-of-type` — more reliable adjacent sibling selector
- `details > :last-child { margin-bottom }` — prevents content hitting bottom border
- `summary:focus-visible` — keyboard accessibility
- Shorthand padding to avoid override issues

## Step 2: Chinese Re-translation

Use the repo's existing translation script which calls DeepSeek v3.2 (a strong Chinese model) via OpenRouter:

```bash
bun scripts/translate-to-zh.ts src/content/writing/ai-guide.md
```

This reads the English `ai-guide.md`, translates the full file (frontmatter + body), and writes to `ai-guide-zh.md`. The script handles frontmatter translation, preserves markdown formatting, and uses `temperature: 0.3` for consistent output.

**File:** `src/content/writing/ai-guide-zh.md` (overwritten by script)

## Step 3: Verification

1. `bun dev` — navigate to `/writing/ai-guide`
2. Playwright screenshot collapsed state — both paths should look like clickable cards
3. Click each path — verify expand, content padding, no layout issues
4. Toggle theme — verify light and dark modes
5. Switch to Chinese — verify styling applies and translation reads naturally
6. `bun run build` — no errors
7. Run `superpowers:code-reviewer` on all changes
