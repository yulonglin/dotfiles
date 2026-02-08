# Replace Paper Icon with PDF-Specific Icon + Commit

## Context

The research page redesign is complete but needs to be committed. The current paper link icon is a generic document (folded corner + text lines) — user wants a more PDF-focused icon, like a document with "PDF" text inside.

## Steps

### 1. Commit current research page redesign
Run `/commit` for all changes (schema, component, 10 content files, config toggle).

### 2. Replace paper SVG icon in `src/components/ResearchCluster.astro`

**Current** (lines 167-172): Generic document with folded corner + horizontal text lines.

**New**: Document with folded corner + "PDF" text label inside. Same `w-3.5 h-3.5` size, same `currentColor` theming. The "PDF" text will be rendered as an SVG `<text>` element sized to fit within the document body.

```svg
<svg class="w-3.5 h-3.5 inline-block" viewBox="0 0 24 24" fill="none">
  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6z" fill="currentColor" opacity="0.15" />
  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
  <path d="M14 2v6h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
  <text x="12" y="17" text-anchor="middle" fill="currentColor" font-size="7" font-weight="bold" font-family="system-ui, sans-serif">PDF</text>
</svg>
```

Key change: Replace the two horizontal line paths (`M8 13h8M8 17h5`) with a centered "PDF" `<text>` element.

### 3. Verify
- `bun run build` — ensure no build errors
- Visual check in browser that icon renders at 14×14px with legible "PDF" text

## File
- `src/components/ResearchCluster.astro` (lines 167-172 only)
