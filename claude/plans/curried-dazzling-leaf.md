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

#### 1. Generate Pre-initialization Script at Build Time

**File:** `/gatsby-ssr.js` (currently minimal/empty)

🔴 **CRITICAL IMPROVEMENT**: Generate script from `/src/styles/themes.js` at build time instead of hardcoding theme colors. This ensures single source of truth.

Implement `onRenderBody` API:
- Import themes and DEFAULT_THEME_ID from `/src/styles/themes.js`
- Serialize themes object to JSON
- Generate inline script that:
  - Reads `'portfolio-theme'` from localStorage (correct key!)
  - Applies CSS variables from themes object
  - Falls back to DEFAULT_THEME_ID if no saved preference
- Use `setPreBodyComponents` (more reliable than setHeadComponents)

**Benefits:**
- Single source of truth (themes.js)
- No manual duplication (96 values across 8 themes)
- Automatic updates when themes change
- No maintenance burden

**Security Note:** The injected script contains ONLY theme color values from our static codebase. No user input, no dynamic content, no XSS risk.

#### 2. Add Defense-in-Depth Body Style

**File:** `/gatsby-ssr.js` (same file as step 1)

Add inline `<body>` style as additional protection:
```javascript
export const onRenderBody = ({ setBodyAttributes, setPreBodyComponents }) => {
  // Set body background immediately
  setBodyAttributes({
    style: { backgroundColor: '#FAFAF7' } // Default theme bg
  });

  // Pre-init script (from step 1)
  setPreBodyComponents([...]);
};
```

**Why both**: Guarantees body background correct even if script execution delayed.

#### 3. Add prefers-color-scheme CSS Fallback

**File:** `/src/styles/variables.js`

Add CSS media query for system preference detection:
```css
:root {
  --navy: #FAFAF7; /* Default: light */
  /* ... other light theme defaults */
}

@media (prefers-color-scheme: dark) {
  :root {
    --navy: #0B0A0A; /* System dark preference */
    /* ... other dark theme values */
  }
}
```

**Benefits:**
- Works without JavaScript (progressive enhancement)
- Respects user system preference
- Pre-init script enhances, not replaces

**Rationale:** If pre-init script fails or user has JavaScript disabled, they see theme matching system preference instead of navy blue.

#### 4. Update Default CSS Variables

**File:** `/src/styles/variables.js` (same file as step 3)

Change base default values to match default theme (anthropicGeistLight):
- `--navy: #0a192f` → `--navy: #FAFAF7` (ivory light)
- `--dark-navy: #020c1b` → `--dark-navy: #F0F0EB` (ivory medium)
- Update all color variables to match default theme

This is the fallback if media query not supported.

#### 5. Optimize ThemeContext Initial Render

**File:** `/src/context/ThemeContext.js`

Add optimization to skip unnecessary transition on first render:

```javascript
const [isInitialRender, setIsInitialRender] = useState(true);

useEffect(() => {
  const root = document.documentElement;

  // Only add transition after first render (skip on initial load)
  if (!isInitialRender) {
    root.style.setProperty('--transition', 'all 0.3s ease-in-out');
  }

  // Apply colors...
  Object.entries(themeConfig.colors).forEach(([variable, value]) => {
    root.style.setProperty(variable, value);
  });

  setIsInitialRender(false);
}, [theme]);
```

**Why**: On initial load, pre-init already set colors. ThemeContext re-setting same values WITH transition wastes 300ms animating from color to itself.

#### 6. Audit GlobalStyle and Theme Toggle

**File:** `/src/styles/GlobalStyle.js` (VERIFY ONLY)

⚠️ **BEFORE IMPLEMENTATION**: Verify GlobalStyle doesn't:
- Override CSS variables set by pre-init
- Set background colors directly (should use var(--navy))
- Conflict with theme timing

**File:** Theme toggle component (FIND AND DOCUMENT)

⚠️ **BEFORE IMPLEMENTATION**: Identify theme toggle UI:
- Where is it located?
- Does it use VISIBLE_THEME_IDS?
- How does it call setTheme()?
- Could timing conflict with pre-init?

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

**Selected:** Pre-initialization script with build-time generation (best balance of reliability and maintainability)

## Recommended Implementation Order

Follow this sequence to minimize risk and enable incremental testing:

### Phase 1: Audit (Before Writing Code)
1. Review `/src/styles/GlobalStyle.js` for CSS variable conflicts
2. Find theme toggle component and document location
3. Run `rg '#[0-9a-fA-F]{6}' --type jsx src/components/` to find hardcoded colors
4. Verify gatsby-plugin-styled-components configuration

### Phase 2: Defensive Layers (Quick Wins)
1. Add prefers-color-scheme media query to variables.js
2. Update default colors in variables.js to match anthropicGeistLight
3. Test: Build and verify no navy flash (covers JS-disabled case)

### Phase 3: Core Implementation
1. Implement build-time script generation in gatsby-ssr.js:
   - Import themes and DEFAULT_THEME_ID
   - Add body inline style with setBodyAttributes
   - Generate and inject pre-init script with setPreBodyComponents
   - Verify uses 'portfolio-theme' localStorage key
2. Test: Build and verify localStorage theme persistence works

### Phase 4: Optimization
1. Add initial render skip to ThemeContext.js
2. Test: Verify theme toggle still works, no unnecessary transitions

### Phase 5: Validation
1. Run all test scenarios (especially Slow 3G!)
2. Run Lighthouse performance comparison
3. Test multi-tab sync
4. Verify all success criteria met

## Critical Files to Modify

1. `/gatsby-ssr.js` (MODIFY) - **Primary implementation file**
   - Generate pre-init script from themes.js at build time
   - Set body background via setBodyAttributes
   - Inject script via setPreBodyComponents
   - Uses correct localStorage key: 'portfolio-theme'

2. `/src/styles/variables.js` (MODIFY)
   - Add prefers-color-scheme media query
   - Update default colors to match default theme (anthropicGeistLight)

3. `/src/context/ThemeContext.js` (MODIFY)
   - Optimize to skip transition on initial render
   - Verify no conflicts with pre-init

4. `/src/styles/GlobalStyle.js` (AUDIT ONLY)
   - Verify doesn't override CSS variables
   - Confirm uses var(--navy) not hardcoded colors

5. Theme toggle component (FIND AND DOCUMENT)
   - Identify location
   - Document interaction with theme system

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

# 2. 🔴 CRITICAL TEST: Network throttling (most important)
# - Open DevTools → Network tab → Throttling: "Slow 3G"
# - Enable "Disable cache"
# - Hard refresh (Cmd+Shift+R) 5-10 times
# - Watch for ANY color flash during load
# - This is the definitive test (FOUC most visible on slow connections)

# 3. Test theme persistence
# - Toggle theme to dark
# - Hard refresh with Slow 3G throttling
# - Verify dark theme loads immediately without flash

# 4. Test localStorage scenarios
# - Clear localStorage
# - Refresh → should see default theme (matches system preference if possible)
# - Toggle → refresh → should see toggled theme immediately

# 5. Multi-tab localStorage sync
# - Tab A: light theme
# - Tab B: open site (should be light immediately)
# - Tab A: switch to dark
# - Tab B: reload (should be dark immediately, no flash)

# 6. Lighthouse performance impact
npx lighthouse http://localhost:9000 --only-categories=performance
# Compare Total Blocking Time (TBT) before/after changes
# Acceptance: TBT increase < 50ms

# 7. System preference fallback (no JS)
# - Disable JavaScript in browser settings
# - Refresh page
# - Should see theme matching system preference (via CSS media query)
# - Or default light theme if media query unsupported
```

### Success Criteria

- [ ] 🔴 **No visible flash on Slow 3G throttling** (most critical test)
- [ ] No visible flash of navy blue on initial page load (normal connection)
- [ ] Saved theme from localStorage applied before first paint
- [ ] Theme toggle continues to work correctly
- [ ] Default theme or system preference displays if no saved preference
- [ ] Graceful degradation if JavaScript disabled (shows system preference or default)
- [ ] Multi-tab localStorage sync works (theme persists across tabs)
- [ ] Lighthouse TBT increase < 50ms (acceptable performance impact)

## Technical Notes

### Theme ID Mapping (for pre-init script)

From `/src/styles/themes.js`:
- `anthropicGeistLight`: ivory colors (#FAFAF7, #F0F0EB, etc.)
- `anthropicGeistDark`: dark colors (#0B0A0A, #1A1818, etc.)
- Default theme ID: `anthropicGeistLight` (Line 5)

### localStorage Key

🔴 **CRITICAL**: From `/src/context/ThemeContext.js` (Line 7):
```javascript
const STORAGE_KEY = 'portfolio-theme';
```

**Note**: Original plan had wrong key ('theme'). Must use 'portfolio-theme' or saved preferences will be ignored!

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
   - Risk: Script runs after stylesheets load
   - Mitigation: Use setPreBodyComponents (runs before React app mounts)

2. **Theme mapping duplication** - ✅ SOLVED
   - Original risk: Pre-init script hardcodes theme colors, ThemeContext.js also has them
   - Solution: Generate script from themes.js at build time (single source of truth)

3. **localStorage read performance**
   - Impact: Minimal (synchronous localStorage.getItem is fast, ~0.1ms)
   - Mitigation: Keep script minimal, no heavy processing

4. **Browser compatibility**
   - Risk: Very old browsers may not support CSS variables
   - Mitigation: Acceptable tradeoff (CSS variables widely supported since 2016)
   - Fallback: System preference via media query or default theme colors

5. **gatsby-plugin-styled-components interaction**
   - Risk: Plugin already installed, might conflict
   - Mitigation: Test thoroughly, plugin handles styled-components FOUC (different concern)

6. **Content Security Policy (CSP)**
   - Risk: Inline scripts violate strict CSP
   - Current state: No CSP in netlify.toml (checked)
   - Future: If CSP added, would need nonce strategy (document as limitation)

7. **Hardcoded colors in components**
   - Risk: Some components might not use CSS variables
   - Mitigation: Audit with `rg '#[0-9a-fA-F]{6}' --type jsx src/components/`
   - Find and fix any hardcoded colors during implementation

## Implementation Notes

### Why Build-Time Generation is Critical

Maintaining themes manually in two places (themes.js and gatsby-ssr.js) creates:
- 8 themes × ~12 colors = 96 values to keep in sync
- High risk of drift between source and pre-init
- Manual updates every time themes change

Build-time generation ensures:
- Single source of truth (themes.js)
- Automatic updates when themes change
- Zero maintenance burden
- Impossible to have mismatched colors

### Why setPreBodyComponents Over setHeadComponents

- `setHeadComponents`: No execution order guarantee with other plugins
- `setPreBodyComponents`: Runs before React app mounts (more reliable)
- Critical for ensuring pre-init runs before any React rendering

### Defense-in-Depth Strategy

Three layers of protection:
1. **Body inline style** - Guarantees correct background immediately
2. **Pre-init script** - Applies full theme from localStorage before React
3. **prefers-color-scheme media query** - Works without JavaScript

If all three fail, falls back to default light theme colors.

## Example Implementation Code

### gatsby-ssr.js (Complete Example)

```javascript
import React from 'react';
import { themes, DEFAULT_THEME_ID } from './src/styles/themes';

export const onRenderBody = ({ setBodyAttributes, setPreBodyComponents }) => {
  // Layer 1: Inline body background (immediate, no script needed)
  const defaultTheme = themes[DEFAULT_THEME_ID];
  const defaultBgColor = defaultTheme.colors['--navy'];

  setBodyAttributes({
    style: { backgroundColor: defaultBgColor }
  });

  // Layer 2: Pre-init script (reads localStorage, applies full theme)
  const themesJson = JSON.stringify(themes);
  const storageKey = 'portfolio-theme'; // Must match ThemeContext

  const script = `
    (function() {
      try {
        const themes = ${themesJson};
        const savedThemeId = localStorage.getItem('${storageKey}');
        const themeId = savedThemeId && themes[savedThemeId] ? savedThemeId : '${DEFAULT_THEME_ID}';
        const themeConfig = themes[themeId];

        const root = document.documentElement;
        Object.entries(themeConfig.colors).forEach(([variable, value]) => {
          root.style.setProperty(variable, value);
        });
      } catch (e) {
        // Silent fail - CSS fallbacks will handle it
        console.error('Theme pre-init failed:', e);
      }
    })();
  `;

  setPreBodyComponents([
    <script key="theme-preinit" dangerouslySetInnerHTML={{ __html: script }} />
  ]);
};
```

### variables.js (CSS Fallback Example)

```css
/* Base defaults (light theme) */
:root {
  --navy: #FAFAF7;
  --dark-navy: #F0F0EB;
  --light-navy: #E5E5E0;
  /* ... other variables */
}

/* System preference fallback */
@media (prefers-color-scheme: dark) {
  :root {
    --navy: #0B0A0A;
    --dark-navy: #1A1818;
    --light-navy: #2A2828;
    /* ... other variables */
  }
}
```

### ThemeContext.js (Optimization Example)

```javascript
const ThemeProvider = ({ children }) => {
  const [theme, setTheme] = useState(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem(STORAGE_KEY) || DEFAULT_THEME_ID;
    }
    return DEFAULT_THEME_ID;
  });

  const [isInitialRender, setIsInitialRender] = useState(true);

  useEffect(() => {
    const themeConfig = getTheme(theme);
    const root = document.documentElement;

    // Skip transition on initial render (pre-init already set colors)
    if (!isInitialRender) {
      root.style.setProperty('--transition', 'all 0.3s ease-in-out');
    }

    // Apply theme colors
    Object.entries(themeConfig.colors).forEach(([variable, value]) => {
      root.style.setProperty(variable, value);
    });

    // Save to localStorage
    localStorage.setItem(STORAGE_KEY, theme);

    setIsInitialRender(false);
  }, [theme, isInitialRender]);

  // ... rest of component
};
```
