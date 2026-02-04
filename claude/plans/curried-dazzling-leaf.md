# Fix Flash of Navy Blue (FOUC) Before Page Renders

## Problem Summary

The website shows a flash of navy blue (#0a192f) before the correct theme colors (ivory #FAFAF7 for light theme) render. This is a classic FOUC (Flash of Unstyled Content) caused by a timing mismatch between initial HTML render and React theme hydration.

## Root Cause

1. **Initial HTML** uses default CSS variables with navy blue background (#0a192f) from `/src/styles/variables.js`
2. **ThemeContext** updates CSS variables in a `useEffect` hook (Lines 26-47 of `/src/context/ThemeContext.js`)
3. **useEffect runs AFTER initial render**, creating a visible flash: navy → theme color

### Why Current Architecture Fails

```
Timeline:
  1. HTML loads with --navy: #0a192f (default)
  2. React hydrates, renders with default colors
  3. ThemeContext useEffect fires (50-100ms later)
  4. CSS variables update to theme colors
  5. User sees: Navy flash → Correct colors
```

## Solution: Pre-initialize Theme Before React Hydration

Apply theme colors **before** React starts rendering by injecting an inline script in the HTML `<head>` that:
1. Reads saved theme from localStorage
2. Applies CSS variables to `:root` immediately
3. Ensures first paint uses correct colors

### Implementation Plan

#### 1. Create Theme Pre-initialization Script

**File:** `/src/utils/themePreInit.js` (new file)

Create a self-contained function that:
- Reads `theme` from localStorage
- Maps theme ID to color values (same logic as ThemeContext)
- Sets CSS variables on `document.documentElement` synchronously
- Runs before any React code

**Key requirements:**
- Must be vanilla JS (no React/imports)
- Must inline the theme color mappings (can't import from themes.js)
- Must handle missing localStorage gracefully (default to anthropicGeistLight)

#### 2. Inject Script via Gatsby SSR

**File:** `/gatsby-ssr.js` (currently minimal/empty)

Implement `onRenderBody` API to inject the pre-init script:
- Use `setHeadComponents` to add inline `<script>` in `<head>`
- Script must run **before** any stylesheets or React hydration
- Inline the script content directly (no external file)

**Security Note:** The injected script contains ONLY hardcoded theme color values (static strings from our codebase). No user input, no dynamic content, no XSS risk. This is safe use of inline scripts for performance-critical initialization.

**Reference:** Gatsby SSR API docs for preventing FOUC patterns

#### 3. Update Default CSS Variables

**File:** `/src/styles/variables.js`

Change default values to match the default theme (anthropicGeistLight):
- `--navy: #0a192f` → `--navy: #FAFAF7` (ivory light)
- `--dark-navy: #020c1b` → `--dark-navy: #F0F0EB` (ivory medium)
- Update all color variables to match default theme

**Rationale:** If pre-init script fails or user has JavaScript disabled, they see the default theme colors instead of navy blue.

#### 4. Ensure ThemeContext Doesn't Conflict

**File:** `/src/context/ThemeContext.js`

The existing `useEffect` (Lines 26-47) should continue working as-is:
- It will update CSS variables when theme changes via toggle
- On initial load, it will be redundant (variables already set by pre-init)
- No changes needed, but verify no race conditions

### Alternative Approaches Considered

#### Option A: SSR with gatsby-plugin-styled-components
- **Pros:** Proper server-side rendering of styles
- **Cons:** Complex setup, may conflict with existing styled-components config, doesn't solve localStorage theme persistence issue

#### Option B: CSS-only solution with data attributes
- **Pros:** No JavaScript needed
- **Cons:** Can't read localStorage without JS, doesn't support dynamic theme switching

#### Option C: Inline style on `<body>` tag
- **Pros:** Simple, no script needed
- **Cons:** Hard to maintain, doesn't read saved theme, overrides cascade issues

**Selected:** Pre-initialization script (best balance of reliability and maintainability)

## Critical Files to Modify

1. `/src/utils/themePreInit.js` (NEW)
   - Theme pre-initialization script

2. `/gatsby-ssr.js` (MODIFY)
   - Inject pre-init script in `<head>`

3. `/src/styles/variables.js` (MODIFY)
   - Update default colors to match default theme

4. `/src/context/ThemeContext.js` (VERIFY ONLY)
   - Ensure no conflicts with pre-init

## Verification Plan

### Test Scenarios

1. **Fresh visit (no localStorage)**
   - Expected: Page renders with default theme (anthropicGeistLight) immediately
   - No flash of navy blue

2. **Return visit with saved theme**
   - Expected: Page renders with saved theme immediately
   - No flash of any other color

3. **Theme toggle interaction**
   - Expected: Smooth transition when user clicks theme toggle
   - ThemeContext useEffect handles the switch

4. **JavaScript disabled**
   - Expected: Page renders with default theme colors (from variables.js)
   - No functionality lost (theme toggle won't work but acceptable degradation)

### Testing Steps

```bash
# 1. Build for production (FOUC only visible in production build)
bun clean
bun run build
bun run serve

# 2. Test in browser
# - Open DevTools Network tab, enable "Disable cache"
# - Hard refresh (Cmd+Shift+R) several times
# - Watch for color flash during load

# 3. Test theme persistence
# - Toggle theme to dark
# - Hard refresh
# - Verify dark theme loads immediately without flash

# 4. Test localStorage scenarios
# - Clear localStorage
# - Refresh → should see default theme
# - Toggle → refresh → should see toggled theme
```

### Success Criteria

- [ ] No visible flash of navy blue on initial page load
- [ ] Saved theme from localStorage applied before first paint
- [ ] Theme toggle continues to work correctly
- [ ] Default theme (anthropicGeistLight) displays if no saved preference
- [ ] Graceful degradation if JavaScript disabled

## Technical Notes

### Theme ID Mapping (for pre-init script)

From `/src/styles/themes.js`:
- `anthropicGeistLight`: ivory colors (#FAFAF7, #F0F0EB, etc.)
- `anthropicGeistDark`: dark colors (#0B0A0A, #1A1818, etc.)
- Default theme ID: `anthropicGeistLight` (Line 5)

### localStorage Key

From `/src/context/ThemeContext.js` (Line 10):
```javascript
const THEME_KEY = 'theme';
```

### CSS Variables to Pre-initialize

From `/src/styles/themes.js`, minimum required:
- `--navy` (body background)
- `--dark-navy` (loader background, darker elements)
- `--light-navy` (hover states)
- `--lightest-navy` (borders)
- `--slate` (text color)
- `--light-slate` (secondary text)
- `--lightest-slate` (subtle text)
- `--white` (primary text)
- `--green` (accent color)
- `--green-tint` (accent tint)

All variables should be pre-initialized to prevent any partial styling issues.

## Potential Risks

1. **Script execution timing**
   - Mitigation: Place in `<head>`, not `<body>`, ensure runs before stylesheets

2. **Theme mapping duplication**
   - Risk: Pre-init script hardcodes theme colors, ThemeContext.js also has them
   - Mitigation: Document clearly, consider future refactor to share theme source

3. **localStorage read performance**
   - Impact: Minimal (synchronous localStorage.getItem is fast)
   - Mitigation: Keep script minimal, no heavy processing

4. **Browser compatibility**
   - Risk: Very old browsers may not support CSS variables
   - Mitigation: Acceptable tradeoff (CSS variables widely supported since 2016)

## Future Improvements

- Refactor to share theme definitions between pre-init script and ThemeContext
- Consider build-time generation of pre-init script from themes.js
- Add prefers-color-scheme media query fallback for system theme detection
