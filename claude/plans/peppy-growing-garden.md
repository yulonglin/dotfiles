# Plan: Real-time search with keyboard navigation on Writing page

## Context

The writing page uses Pagefind (build-time search index) with 200ms debounce — not instant. The page also has visual clutter above the post list (header + subtitle + search + tags = 4 elements). User wants snappy real-time filtering and keyboard-driven article navigation.

## Layout Change

**Before:** Header → Subtitle → Pagefind Search → Tags → Posts
**After:** Header → Subtitle → Filter Input → Posts → Tags

Tags move below the post list (exploratory, not primary). Search stays at top (controls what's visible below).

## Implementation

### Step 1: Replace `<Search />` with inline filter input

Remove the Pagefind `<Search />` import. Add a `<input type="search" id="post-filter">` with the same visual style (search icon, `bg-[var(--bg-alt)]`, rounded-lg, accent focus border). Reuse the existing styling patterns from `Search.astro`.

### Step 2: Add `data-search` attribute to each article

At build time, concatenate title + description + tags + tldr into a single pre-lowercased `data-search` attribute on each `<article>`:

```astro
<article
  data-search={[
    post.data.title,
    post.data.description,
    post.data.tags.join(' '),
    post.data.tldr || '',
  ].join(' ').toLowerCase()}
>
```

**Why this over JSON?** Simpler — no parse step, no index mapping. Pre-lowercasing avoids repeated `.toLowerCase()` at filter time. With only 4 posts, the DOM duplication is trivial.

### Step 3: Client-side filter (`<script>` bundled, not `is:inline`)

Use Astro's bundled `<script>` (like ThemeToggle and Nav do). Astro emits `type="module"` — deferred by spec, DOM guaranteed ready, no wrapper needed.

On each `input` event (no debounce — instant for ~4-15 articles):
1. Get query, lowercase
2. For each article, check `el.dataset.search.includes(query)`
3. Toggle `el.hidden = !match`
4. Toggle "No results" message
5. Reset keyboard `activeIndex` to -1

### Step 4: CSS-only border handling

Remove the `i > 0 && 'border-t border-default'` conditional from the Astro template. Use a CSS sibling selector instead:

```css
#post-list article:not([hidden]) ~ article:not([hidden]) {
  border-top: 1px solid var(--border);
}
```

This automatically shows borders only between consecutive *visible* articles. When filtering hides articles, borders adapt with zero JS.

### Step 5: Keyboard navigation

Track `activeIndex` (-1 = no highlight). Input retains focus while articles get visually highlighted:

- **ArrowDown**: increment (clamp at end of visible list)
- **ArrowUp**: decrement (clamp at 0)
- **Enter** (with active highlight): navigate to `article.querySelector('a').href`
- **Escape**: clear input, show all, blur

Visual highlight: `background-color: var(--bg-alt)` with `border-radius: 0.5rem` — subtle, editorial. Use `scrollIntoView({ block: 'nearest' })` for off-screen articles.

Reset `activeIndex` on every input change (visible set shifts).

### Step 6: Move tags below posts

Move the `<nav aria-label="Filter by tag">` below the post list. Add a top border separator: `mt-12 pt-8 border-t border-default`. Tags remain as links to `/writing/tags/[tag]` (server-rendered pages, not inline filtering).

### Step 7: "No results" state

Add `<p id="no-results" hidden>No posts match your filter.</p>` below the post list. Toggle visibility in the filter function.

## User contribution: matching function

The `matchPost(query, searchText)` function is a meaningful design decision — simple substring, word-boundary matching, or multi-word AND matching all produce different UX. Will request user implementation.

## File to modify

| File | Change |
|------|--------|
| `src/pages/writing/index.astro` | Remove `<Search />` import, add filter input, `data-search` attrs on articles, remove conditional border classes, add `<style>` for CSS borders + highlight, add bundled `<script>` for filter logic + keyboard nav, move tag nav below posts, add no-results message |

No new files. `src/components/Search.astro` left untouched.

## Verification

1. `bun dev` → `/writing` — type in filter, confirm posts hide/show instantly
2. Test keyboard: ArrowDown/Up highlights, Enter navigates, Escape clears
3. Verify borders display correctly between visible articles (especially mid-list filtering)
4. Test "no results" message appears/disappears
5. Test tags section renders below posts with border separator
6. `bun run build` → verify no build errors
7. Verify Pagefind still works on other pages (we only removed it from writing index)
