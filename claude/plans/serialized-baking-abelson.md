# Plan: Simplify Writing Page Header

## Context

The writing page (`/writing`) currently has three vertical sections before the post list:
1. **Header row** — "writing" h1 + RSS icon (flex row)
2. **Tagline** — "Notes on AI safety, machine learning, and things I find useful." (separate paragraph, `mb-8`)
3. **Search/filter input** — full-width search bar (`mb-12`)

With only 5 posts, the tagline and prominent search bar feel like overhead. The user wants to:
- **Remove the tagline** (line 29–31)
- **Collapse the search bar inline** beside the heading, saving vertical space

## Changes

**File:** `src/pages/writing/index.astro`

### 1. Remove the tagline paragraph

Delete lines 29–31:
```html
<p class="text-muted mb-8 max-w-xl leading-relaxed">
  Notes on AI safety, machine learning, and things I find useful.
</p>
```

### 2. Move filter input inline with the heading row

Current header row (line 15–28):
```html
<div class="flex items-center justify-between mb-4">
  <h1>writing</h1>
  <a ...rss icon...>
</div>
```

New header row — heading left, filter + RSS right:
```html
<div class="flex items-center justify-between gap-4 mb-12">
  <h1 class="text-4xl md:text-5xl font-heading font-bold">writing</h1>
  <div class="flex items-center gap-3">
    <!-- Compact inline filter -->
    <div class="relative">
      <svg class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted pointer-events-none" ...search icon... />
      <input
        id="post-filter"
        type="search"
        placeholder="Filter..."
        class="w-40 md:w-48 pl-8 pr-3 py-1.5 text-sm bg-[var(--bg-alt)] text-[var(--text)] border border-[var(--border)] rounded-lg focus:outline-none focus:border-[var(--accent)] transition-colors placeholder:text-[var(--text-muted)]"
        ...existing aria attributes...
      />
    </div>
    <!-- RSS icon -->
    <a href="/rss.xml" ...existing attributes... />
  </div>
</div>
```

Key design decisions:
- **Filter width**: `w-40 md:w-48` — compact but usable; expands slightly on desktop
- **Placeholder**: shortened to "Filter..." (concise, doesn't need to say "posts")
- **Padding**: `py-1.5` instead of `py-2` — smaller to match the heading's visual weight
- **Icon**: slightly smaller (`w-3.5 h-3.5`) to match the compact input
- **Spacing**: `mb-12` on the header row replaces the separate `mb-8` + `mb-12` that tagline + search had
- **RSS icon** stays rightmost, grouped with the filter

### 3. Remove the standalone filter `<div>` block

Delete the old filter section (lines 33–60) since it's now part of the header row.

### 4. Keep all JavaScript and accessibility unchanged

The `<script>` block, ARIA attributes, keyboard navigation, no-results message, and filter-status live region all remain exactly the same — they reference `#post-filter` by ID which is preserved.

## Design Rationale

- **Vertical space**: Removes ~100px of vertical overhead (tagline + full-width search). Posts are immediately visible.
- **Proportional to content**: A 5-post page doesn't need a prominent search bar. The inline filter is discoverable but unobtrusive.
- **Consistency**: Research page has heading + tagline but no search. With the tagline removed from writing, both pages become `h1` → content, keeping the site consistent. (The research tagline serves a different purpose — framing the research narrative.)
- **Progressive enhancement**: As the blog grows, the search can be made more prominent again. The `"/"` keyboard shortcut for focus still works.

## Files Modified

- `src/pages/writing/index.astro` — only file touched

## Verification

1. `bun dev` → navigate to `/writing`
2. Confirm: heading and inline filter on one row, no tagline, posts immediately below
3. Type in filter → posts filter correctly
4. Press `/` → filter focuses
5. Arrow keys + Enter → keyboard navigation works
6. Resize to mobile → filter stacks or shrinks gracefully
7. Check dark mode toggle → filter input themed correctly
8. `bun run build` → no build errors
