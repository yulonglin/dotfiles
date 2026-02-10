# Plan: Fix LaTeX Delimiter Support in DatasetRenderer

## Context

Steps 1-4 of the previous markdown+LaTeX plan are **already implemented** (react-markdown + remark-math + rehype-katex pipeline, typography plugin, followup-viewer integration). Build passes.

**Remaining problem**: Model responses and GPQA questions use `\[...\]` (block) and `\(...\)` (inline) LaTeX delimiters — confirmed in actual data (e.g., `out/archive/2026-01-21/gpqa-v3.2-problematic-paraphrases.json`). `remark-math` v6 only recognizes `$...$` / `$$...$$`, so `\[...\]` content renders as raw text.

## Approach

Add a `normalizeLatexDelimiters()` preprocessing function in `dataset-renderer.tsx` that converts:
- `\[...\]` → `$$...$$` (block math)
- `\(...\)` → `$...$` (inline math)

This is **not** a custom parser — it's a 5-line data normalizer that adapts the stored delimiter format to what the remark-math library expects. All actual math parsing stays in remark-math + rehype-katex.

**Codex second opinion confirmed**: this is the recommended approach over alternatives (MathJax swap = larger bundle; remark-math has no config for these delimiters; auto-detecting bare `\sqrt{}` is too fragile).

## File to Modify

| File | Change |
|------|--------|
| `web/components/dataset-renderer.tsx` | Add `normalizeLatexDelimiters()`, call it in rendering pipeline |

## Implementation

Add before `preprocessMCQ`:

```typescript
/**
 * Normalize LaTeX delimiters to dollar-sign format that remark-math understands.
 * Converts \[...\] → $$...$$ and \(...\) → $...$
 */
function normalizeLatexDelimiters(text: string): string {
  // Block math: \[...\] → $$...$$
  text = text.replace(/\\\[([\s\S]*?)\\\]/g, "$$$$$1$$$$");
  // Inline math: \(...\) → $...$
  text = text.replace(/\\\((.*?)\\\)/g, "$$$1$$");
  return text;
}
```

Update the component to call it:

```typescript
export function DatasetRenderer({ content, dataset, compact }: DatasetRendererProps) {
  const normalized = normalizeLatexDelimiters(content);
  const processed = dataset === "gpqa" ? preprocessMCQ(normalized) : normalized;
  // ... rest unchanged
}
```

**Order matters**: normalize delimiters FIRST, then MCQ preprocessing (which may contain `\(` in option text).

## Execution

Delegate to `code-toolkit:codex` — the spec is precise enough for single-shot implementation:
- Edit `dataset-renderer.tsx` (add function + update component)
- Run `bun run build` to verify

## Verification

1. `cd web && bun run build` — no build errors
2. `bun run dev` — check GPQA samples with `\[...\]` equations render as formatted math
3. Check model responses with `\(...\)` inline math render correctly
4. Check that `$...$` / `$$...$$` content still works (regression check)
