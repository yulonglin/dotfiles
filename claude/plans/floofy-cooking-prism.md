# Plan: Add Markdown + LaTeX Rendering for Human Baseline Annotation UI

## Context

Model inputs/outputs displayed in the annotation interface contain markdown formatting (`**bold**`, lists, headers) and LaTeX math (`$x^2$`, `$$\sum$$`). Currently, LaTeX renders via KaTeX but **markdown syntax shows as raw text** — hurting readability for annotators evaluating human baselines. The `followup-viewer.tsx` also bypasses `DatasetRenderer` entirely (raw `<p>` tags), missing both markdown and LaTeX rendering.

## Approach

Replace the custom regex parser in `DatasetRenderer` with a `react-markdown` + `remark-math` + `rehype-katex` pipeline. This handles all markdown AND LaTeX in a single unified rendering pass. Use `@tailwindcss/typography` prose classes for clean default styling.

## Files to Modify

| File | Change |
|------|--------|
| `web/package.json` | Add 5 deps, remove 2 |
| `web/components/dataset-renderer.tsx` | **Rewrite** — ReactMarkdown pipeline replaces custom parser |
| `web/components/followup-viewer.tsx` | Use `DatasetRenderer` instead of raw `<p>` tags |
| `web/app/globals.css` | Add `@plugin "@tailwindcss/typography"` + prose overrides |

## Steps

### 1. Install packages

```bash
cd web
bun add react-markdown remark-math rehype-katex remark-gfm @tailwindcss/typography
bun remove react-katex @types/react-katex
```

**Keep**: `katex` (peer dep of rehype-katex), `react-syntax-highlighter`
**Remove**: `react-katex` + types (replaced by rehype-katex which outputs raw KaTeX HTML)

### 2. Add typography plugin + prose overrides to `globals.css`

After existing `@import` lines, add:
```css
@plugin "@tailwindcss/typography";
```

Add prose overrides at the end:
```css
/* Tighter paragraph spacing for annotation UI */
.prose :where(p):not(:where([class~="not-prose"], [class~="not-prose"] *)) {
  margin-top: 0.75em;
  margin-bottom: 0.75em;
}

/* KaTeX block math: horizontal scroll for wide equations */
.prose .katex-display {
  margin: 1em 0;
  overflow-x: auto;
}

/* Inline code: match existing muted style */
.prose :where(code):not(:where(pre *, [class~="not-prose"], [class~="not-prose"] *)) {
  background-color: var(--muted);
  padding: 0.125rem 0.375rem;
  border-radius: 0.25rem;
  font-size: 0.875em;
}

/* Remove prose backtick decorations on inline code */
.prose :where(code):not(:where(pre *, [class~="not-prose"], [class~="not-prose"] *))::before,
.prose :where(code):not(:where(pre *, [class~="not-prose"], [class~="not-prose"] *))::after {
  content: none;
}
```

### 3. Rewrite `dataset-renderer.tsx`

Replace the entire file. Key architecture:

- **Plugin pipeline**: `remarkMath` + `remarkGfm` → `rehypeKatex({ throwOnError: false })`
- **Code blocks**: Custom `components.code` distinguishes inline vs fenced (by `className="language-*"`), uses `SyntaxHighlighter` for fenced
- **MCQ pre-processing**: `preprocessMCQ()` converts `(A) text (B) text` into markdown list `- **(A)** text` before passing to ReactMarkdown
- **Error handling**: `rehypeKatex({ throwOnError: false, errorColor: "#cc0000" })` replaces SafeInlineMath/SafeBlockMath try-catch pattern
- **Props**: Add `compact?: boolean` — uses `prose-sm` for smaller contexts
- **Wrapper**: `<div className="prose dark:prose-invert max-w-none">` (`max-w-none` prevents 65ch width cap)
- **Remove**: `parseContent()`, `Segment` type, `renderSegment()`, `SafeInlineMath`, `SafeBlockMath`, `formatMCQOptions()`, `react-katex` import, redundant KaTeX CSS import (keep the one in `layout.tsx`)

### 4. Update `followup-viewer.tsx`

- Import `DatasetRenderer`
- Replace `<p className="text-xs ...">{followup.question}</p>` with `<div className="text-xs ..."><DatasetRenderer content={followup.question} compact /></div>`
- Replace `<p className="text-sm ...">{followup.response}</p>` with `<div className="text-sm"><DatasetRenderer content={followup.response} compact /></div>`

### 5. Delegate to codex agent

Use `code-toolkit:codex` for the implementation — the spec is precise enough for it. Steps 2-4 can be implemented by codex with clear instructions.

## Verification

1. `cd web && bun run build` — no build errors
2. `bun run dev` — visually verify:
   - MATH questions: LaTeX equations render as formatted math
   - Model responses with `**bold**`, `*italic*`, `- lists`, `## headers` render properly
   - GPQA: MCQ options `(A)(B)(C)(D)` render as formatted list with bold labels
   - Code blocks in USACO responses render with syntax highlighting
   - Follow-up probe responses (Tier 4) now render markdown/LaTeX
   - Invalid LaTeX shows red error text, doesn't crash
   - Dark mode: `prose-invert` applies correctly
3. Check no regressions in existing annotation flow (calibration, paraphrase comparison)
