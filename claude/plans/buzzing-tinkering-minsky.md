# Implementation Plan: Anthropic Theme Option

## Context

Add a theme switcher to the portfolio website that allows toggling between the current design and an Anthropic-inspired aesthetic. The Anthropic theme will be based on the exact design language from anthropic.com, featuring their distinctive terra-cotta orange accent, warm cream backgrounds, and refined minimalist aesthetic.

## Design Decision: Anthropic Color Palette

Based on **official Anthropic brand guidelines** from multiple authoritative sources, we'll implement **MULTIPLE themes**:

### Core Themes:
1. **Default (Current)** - Yellow/Navy scheme (existing)

### Anthropic Theme Variants (3 versions for each light/dark):
2. **Anthropic Official Light** - From anthropic-style skill (`#d97757` orange, `#faf9f5` light)
3. **Anthropic Official Dark** - From anthropic-style skill (`#d97757` orange, `#141413` dark)
4. **Anthropic Geist Light** - Extended Geist palette (Ivory/Cloud/Slate ranges)
5. **Anthropic Geist Dark** - Extended Geist palette (Slate Dark `#191919`)
6. **Anthropic Brandfetch Light** - Brandfetch variant (Antique Brass `#CC785C`)
7. **Anthropic Brandfetch Dark** - Brandfetch variant (Antique Brass `#CC785C`)

**Total: 7 themes** (1 default + 6 Anthropic variants)

Users can explore subtle differences between official interpretations and choose their preferred aesthetic.

### Official Anthropic Brand Colors (Source: anthropic-style skill + Geist/Brandfetch)

**Core Brand Colors (from anthropic-style skill - AUTHORITATIVE):**
- **Dark:** `#141413` - Primary text and dark backgrounds
- **Light:** `#faf9f5` - Light backgrounds and text on dark
- **Mid Gray:** `#b0aea5` - Secondary elements
- **Light Gray:** `#e8e6dc` - Subtle backgrounds
- **Orange (Primary Accent):** `#d97757` - Primary accent color
- **Blue (Secondary Accent):** `#6a9bcc` - Secondary accent
- **Green (Tertiary Accent):** `#788c5d` - Tertiary accent

**Extended Palette (Geist/Brandfetch):**
- **Antique Brass:** `#CC785C` / `rgb(204, 120, 92)` - Alternative orange
- **Slate Dark:** `#191919` - Pure dark background
- **Slate Medium:** `#262625`
- **Slate Light:** `#40403E`
- **Cloud Dark:** `#666663`
- **Cloud Medium:** `#91918D`
- **Cloud Light:** `#BFBFBA`
- **Ivory Dark:** `#E5E4DF`
- **Ivory Medium:** `#F0F0EB`
- **Ivory Light:** `#FAFAF7`
- **Kraft:** `#D4A27F` - Warm tan
- **Manilla:** `#EBDBBC` - Light tan
- **Focus Blue:** `#61AAF2`
- **Error Red:** `#BF4D43`

**Note:** The anthropic-style skill uses `#d97757` for orange (slightly different from Brandfetch's `#CC785C`). We'll use `#d97757` as it's from the official skill.

### Anthropic Light Theme Colors:
- **Orange (Primary Accent):** `#d97757` - primary CTA color (official from anthropic-style skill)
- **Dark (Text):** `#141413` - primary text/foreground
- **Light (Background):** `#faf9f5` - main background
- **Light Gray:** `#e8e6dc` - subtle backgrounds (cards)
- **Mid Gray:** `#b0aea5` - secondary text and borders
- **Blue (Secondary Accent):** `#6a9bcc` - links and secondary accents
- **Green (Tertiary Accent):** `#788c5d` - tertiary accent (optional)

### Anthropic Dark Theme Colors:
- **Orange (Primary Accent):** `#d97757` - main accent color (official from anthropic-style skill)
- **Slate Dark (Background):** `#191919` - main background
- **Slate Medium:** `#262625` - cards/elevated surfaces
- **Slate Light:** `#40403E` - borders
- **Cloud Light (Text):** `#BFBFBA` - primary text
- **Cloud Medium:** `#91918D` - secondary text
- **Light:** `#faf9f5` - headings/emphasis
- **Blue (Secondary Accent):** `#6a9bcc` - links and secondary accents

### Current Site Colors (Default Theme):
- **Yellow Accent:** `#ffcf50`
- **Navy Background:** `#0a192f`
- **Dark Navy:** `#020c1b`
- **Slate Text:** `#8892b0`

## Architecture: CSS Variables + Theme Toggle

We'll implement theme switching using:
1. **CSS Variables approach** - minimal changes, leverages existing architecture
2. **React Context** - manages theme state globally
3. **localStorage** - persists user preference across sessions
4. **Theme Toggle Component** - allows manual switching between themes
5. **Optional: System preference detection** - respects `prefers-color-scheme`

## Implementation Steps

### 1. Create Theme Definitions

**File: `/src/styles/themes.js`** (NEW)
- Export theme configurations as objects with CSS variable mappings
- Define `defaultTheme` (current yellow/navy scheme)
- Define multiple Anthropic theme variants:
  - `anthropicOfficialLight` / `anthropicOfficialDark` - from anthropic-style skill
  - `anthropicGeistLight` / `anthropicGeistDark` - from Geist design system
  - `anthropicBrandfetchLight` / `anthropicBrandfetchDark` - from Brandfetch
- Each theme object contains all CSS variable values
- Group themes logically for theme selector UI

### 2. Create Theme Context

**File: `/src/context/ThemeContext.js`** (NEW)
- Create React Context for theme state
- Implement `ThemeProvider` component that:
  - Manages active theme state
  - Loads theme preference from localStorage on mount
  - Provides `toggleTheme()` function
  - Applies theme by setting CSS variables on `:root`
  - Optional: Detects system color scheme preference

**File: `/src/hooks/useTheme.js`** (NEW)
- Export custom hook to access theme context
- Returns: `{ theme, toggleTheme, availableThemes }`

### 3. Update Layout to Use Theme Context

**File: `/src/components/layout.js`** (MODIFY)
- Wrap existing content with `ThemeProvider`
- ThemeProvider should wrap around the existing ThemeProvider from styled-components
- Structure:
  ```jsx
  <ThemeProvider> {/* Our new theme context */}
    <StyledThemeProvider theme={styledTheme}> {/* Existing styled-components */}
      <GlobalStyle />
      {/* existing content */}
    </StyledThemeProvider>
  </ThemeProvider>
  ```

### 4. Create Theme Toggle Component

**File: `/src/components/ThemeToggle.js`** (NEW)
- Multi-option theme selector component
- Uses `useTheme()` hook to access theme state and toggle function
- **Position: Top-right of navigation bar** (user preference)
- **7 theme options** organized hierarchically:
  - Default
  - Anthropic Official (Light/Dark)
  - Anthropic Geist (Light/Dark)
  - Anthropic Brandfetch (Light/Dark)
- Design considerations:
  - Nested dropdown or grouped menu UI
  - Category headers: "Default", "Anthropic Official", "Anthropic Geist", "Anthropic Brandfetch"
  - Sub-options for Light/Dark variants
  - Clear labels with optional color swatches
  - Smooth transition animation
  - Accessible (keyboard navigation, ARIA labels, logical tab order)
  - Compact enough to fit in nav without cluttering
  - Matches active theme's aesthetic

### 5. Update Global Styles

**File: `/src/styles/GlobalStyle.js`** (MODIFY)
- Remove hardcoded CSS variable definitions from `:root`
- CSS variables will now be set dynamically by ThemeContext
- Keep other global styles (resets, body styles, etc.)

### 6. Add Theme Toggle to Navigation

**File: `/src/components/nav.js`** (MODIFY)
- Import and render `<ThemeToggle />` component
- Position in appropriate location (likely top-right of nav)

### 7. Ensure Smooth Transitions

**File: `/src/styles/themes.js`** (UPDATE)
- Add CSS transition property to `:root` for smooth color changes
- Example: `transition: background-color 0.3s ease, color 0.3s ease;`

## Critical Files to Modify/Create

### New Files:
- `/src/styles/themes.js` - Theme definitions
- `/src/context/ThemeContext.js` - Theme state management
- `/src/hooks/useTheme.js` - Theme access hook
- `/src/components/ThemeToggle.js` - Toggle UI component

### Modified Files:
- `/src/components/layout.js` - Wrap with ThemeProvider
- `/src/components/nav.js` - Add theme toggle button
- `/src/styles/GlobalStyle.js` - Remove hardcoded CSS vars

## Anthropic Theme Details

### Color Mappings - Light Theme (Official Brand Colors from anthropic-style skill)

```javascript
anthropicLightTheme = {
  // Backgrounds
  '--navy': '#faf9f5',              // Light (main background - official)
  '--dark-navy': '#e8e6dc',          // Light Gray (secondary bg)
  '--light-navy': '#FFFFFF',         // Pure white for cards
  '--lightest-navy': '#e8e6dc',      // Light Gray (borders/dividers)

  // Text colors
  '--slate': '#141413',              // Dark (primary text - official)
  '--light-slate': '#b0aea5',        // Mid Gray (secondary text - official)
  '--lightest-slate': '#141413',     // Dark (headings)
  '--white': '#141413',              // Dark text on light bg
  '--dark-slate': '#b0aea5',         // Mid Gray (muted text)

  // Accent colors
  '--green': '#d97757',              // Orange (primary accent - official)
  '--green-tint': 'rgba(217, 119, 87, 0.1)', // Orange tint

  // Secondary accents
  '--pink': '#788c5d',               // Green (tertiary - official)
  '--blue': '#6a9bcc',               // Blue (secondary - official)

  // Shadows
  '--navy-shadow': 'rgba(20, 20, 19, 0.08)', // Light shadow
}
```

### Color Mappings - Dark Theme (Official Brand Colors from anthropic-style skill)

```javascript
anthropicOfficialDark = {
  // Backgrounds
  '--navy': '#141413',              // Dark (main background - official)
  '--dark-navy': '#000000',          // Pure black
  '--light-navy': '#262625',         // Slate Medium (cards)
  '--lightest-navy': '#40403E',      // Slate Light (borders)

  // Text colors
  '--slate': '#faf9f5',              // Light (primary text - official inverted)
  '--light-slate': '#b0aea5',        // Mid Gray (secondary text - official)
  '--lightest-slate': '#faf9f5',     // Light (headings)
  '--white': '#FFFFFF',              // Pure white for high contrast
  '--dark-slate': '#b0aea5',         // Mid Gray (muted text)

  // Accent colors
  '--green': '#d97757',              // Orange (primary accent - official)
  '--green-tint': 'rgba(217, 119, 87, 0.15)', // Orange tint (more visible on dark)

  // Secondary accents
  '--pink': '#788c5d',               // Green (tertiary - official)
  '--blue': '#6a9bcc',               // Blue (secondary - official)

  // Shadows
  '--navy-shadow': 'rgba(0, 0, 0, 0.5)', // Dark shadow
}
```

### Color Mappings - Geist Light Theme (Extended Palette)

```javascript
anthropicGeistLight = {
  // Backgrounds (Ivory range)
  '--navy': '#FAFAF7',              // Ivory Light (main background)
  '--dark-navy': '#F0F0EB',          // Ivory Medium (secondary bg)
  '--light-navy': '#FFFFFF',         // Pure white for cards
  '--lightest-navy': '#E5E4DF',      // Ivory Dark (borders/dividers)

  // Text colors
  '--slate': '#141413',              // Cod Gray (primary text)
  '--light-slate': '#91918D',        // Cloud Medium (secondary text)
  '--lightest-slate': '#141413',     // Cod Gray (headings)
  '--white': '#141413',              // Dark text on light bg
  '--dark-slate': '#666663',         // Cloud Dark (muted text)

  // Accent colors
  '--green': '#CC785C',              // Book Cloth (primary accent - warmer)
  '--green-tint': 'rgba(204, 120, 92, 0.1)', // Book Cloth tint

  // Secondary accents
  '--pink': '#D4A27F',               // Kraft (warm tan)
  '--blue': '#6a9bcc',               // Focus Blue

  // Shadows
  '--navy-shadow': 'rgba(20, 20, 19, 0.08)', // Light shadow
}
```

### Color Mappings - Geist Dark Theme (Extended Palette)

```javascript
anthropicGeistDark = {
  // Backgrounds (Slate range)
  '--navy': '#191919',              // Slate Dark (main background)
  '--dark-navy': '#000000',          // Pure black
  '--light-navy': '#262625',         // Slate Medium (cards)
  '--lightest-navy': '#40403E',      // Slate Light (borders)

  // Text colors (Cloud range)
  '--slate': '#BFBFBA',              // Cloud Light (primary text)
  '--light-slate': '#FAFAF7',        // Ivory Light (emphasis)
  '--lightest-slate': '#FAFAF7',     // Ivory Light (headings)
  '--white': '#FFFFFF',              // Pure white for high contrast
  '--dark-slate': '#91918D',         // Cloud Medium (muted text)

  // Accent colors
  '--green': '#CC785C',              // Book Cloth (primary accent)
  '--green-tint': 'rgba(204, 120, 92, 0.15)', // Book Cloth tint

  // Secondary accents
  '--pink': '#D4A27F',               // Kraft
  '--blue': '#61AAF2',               // Focus Blue (brighter)

  // Shadows
  '--navy-shadow': 'rgba(0, 0, 0, 0.5)', // Dark shadow
}
```

### Color Mappings - Brandfetch Light Theme

```javascript
anthropicBrandfetchLight = {
  // Backgrounds
  '--navy': '#F0EFEA',              // Cararra (main background - warmer than Geist)
  '--dark-navy': '#E5E4DF',          // Ivory Dark (secondary bg)
  '--light-navy': '#FFFFFF',         // Pure white for cards
  '--lightest-navy': '#E5E4DF',      // Ivory Dark (borders)

  // Text colors
  '--slate': '#141413',              // Cod Gray (primary text)
  '--light-slate': '#828179',        // Friar Gray (secondary text - warmer)
  '--lightest-slate': '#141413',     // Cod Gray (headings)
  '--white': '#141413',              // Dark text on light bg
  '--dark-slate': '#828179',         // Friar Gray (muted text)

  // Accent colors
  '--green': '#CC785C',              // Antique Brass (primary - exact Brandfetch)
  '--green-tint': 'rgba(204, 120, 92, 0.1)', // Antique Brass tint

  // Secondary accents
  '--pink': '#D4A27F',               // Kraft
  '--blue': '#6a9bcc',               // Focus Blue

  // Shadows
  '--navy-shadow': 'rgba(20, 20, 19, 0.08)', // Light shadow
}
```

### Color Mappings - Brandfetch Dark Theme

```javascript
anthropicBrandfetchDark = {
  // Backgrounds
  '--navy': '#141413',              // Cod Gray (main background - exact Brandfetch)
  '--dark-navy': '#000000',          // Pure black
  '--light-navy': '#262625',         // Slate Medium (cards)
  '--lightest-navy': '#40403E',      // Slate Light (borders)

  // Text colors
  '--slate': '#F0EFEA',              // Cararra (primary text)
  '--light-slate': '#828179',        // Friar Gray (secondary text)
  '--lightest-slate': '#F0EFEA',     // Cararra (headings)
  '--white': '#FFFFFF',              // Pure white for high contrast
  '--dark-slate': '#828179',         // Friar Gray (muted text)

  // Accent colors
  '--green': '#CC785C',              // Antique Brass (exact Brandfetch)
  '--green-tint': 'rgba(204, 120, 92, 0.15)', // Antique Brass tint

  // Secondary accents
  '--pink': '#D4A27F',               // Kraft
  '--blue': '#6a9bcc',               // Focus Blue

  // Shadows
  '--navy-shadow': 'rgba(0, 0, 0, 0.5)', // Dark shadow
}
```

### Typography Considerations

**Official Anthropic Brand Typography:**
- **Headings (24pt+):** Poppins (with Arial fallback)
- **Body Text:** Lora (with Georgia fallback)

**Current Site Typography:**
- **Sans-serif:** Calibre, Inter, San Francisco, SF Pro Text
- **Monospace:** SF Mono, Fira Code, Fira Mono, Roboto Mono

**Implementation Decision:**
For the MVP, we'll **keep the existing Calibre/SF Mono fonts** but adjust weights and spacing for the Anthropic theme. This avoids adding new font files and maintains site performance.

**Optional Enhancement (Future):**
- Add Poppins and Lora font files for true brand alignment
- Implement fluid typography with `clamp()` for responsive scaling
- This can be added later as a typography refinement

### Border Radius

Anthropic uses more generous rounded corners (`24px`). Consider:
- Updating `--border-radius` from `4px` to `24px` when Anthropic theme is active
- This affects buttons, cards, and other UI elements

## Design Philosophy: Anthropic Aesthetic

The Anthropic theme embodies:
- **Modern Purposeful Minimalism** - clean, functional, no ornamental flourishes
- **Warm & Approachable** - cream backgrounds instead of stark white
- **High Contrast** - excellent readability with dark text on light backgrounds
- **Terra-cotta Orange** - reserved for CTAs and interactive elements (not overused)
- **Generous Whitespace** - breathing room, not cramped
- **Accessibility-first** - focus states, semantic HTML, reduced motion support

## Verification Steps

After implementation:

1. **Visual Check:**
   - Run `bun preview` to build and serve production version
   - Toggle between all 7 themes and verify:
     - All colors change appropriately
     - Text remains readable in all light and dark variants
     - No layout shifts or glitches
     - Smooth transitions between themes
     - Accent colors (orange/blue/green) are visible and distinct

2. **Functionality Check:**
   - Theme preference persists after page reload
   - Theme selector UI shows all options clearly
   - Switching between variants works smoothly
   - All pages/sections render correctly in all themes
   - Default theme still works as expected

3. **Accessibility Check:**
   - Keyboard navigation works for theme selector (arrow keys, Enter, Escape)
   - Focus states are visible in all 7 themes
   - Color contrast ratios meet WCAG AA standards for all variants
   - Screen readers announce theme changes properly

4. **Cross-browser Check:**
   - Test in Chrome, Firefox, Safari
   - Check responsive behavior (mobile, tablet, desktop)
   - Verify theme selector UI works on mobile (doesn't overflow nav)

5. **Theme Comparison:**
   - Verify subtle differences between Official/Geist/Brandfetch are visible
   - Official: `#d97757` orange (slightly more red)
   - Geist/Brandfetch: `#CC785C` orange (warmer, more brass-like)
   - Light backgrounds differ: `#faf9f5` (Official) vs `#FAFAF7` (Geist) vs `#F0EFEA` (Brandfetch)

## Future Enhancements (Out of Scope)

- **Anthroplot/Petri plotting styles:** If these are internal Anthropic tools with specific design guidelines, they could be integrated as additional themes or plotting style configurations
- **System preference detection:** Auto-detect and respect `prefers-color-scheme: dark`
- **Per-section themes:** Allow different sections to have different theme overrides
- **Smooth page transitions:** Animate between themes more elaborately
- **Theme preview:** Show thumbnail previews of each theme before switching

## Brand Resources Referenced (In Priority Order)

**Official Anthropic brand styling sourced from:**

1. **anthropic-style Skill** (PRIMARY/AUTHORITATIVE) - `/anthropic-style`
   - **Main Colors:** Dark `#141413`, Light `#faf9f5`, Mid Gray `#b0aea5`, Light Gray `#e8e6dc`
   - **Accent Colors:** Orange `#d97757`, Blue `#6a9bcc`, Green `#788c5d`
   - **Typography:** Poppins (headings 24pt+), Lora (body text)
   - **This is the canonical source** - all colors and typography follow this

2. **Geist Design Agency** - https://geist.co/work/anthropic
   - Created Anthropic's comprehensive design system
   - Extended palette with Slate, Cloud, Ivory ranges for additional UI elements
   - Confirms core colors and provides expanded palette

3. **Brandfetch** - https://brandfetch.com/anthropic.com
   - Alternative source: Antique Brass `#CC785C` (vs official `#d97757`)
   - Cross-reference for brand consistency

4. **MCP Brand Guidelines Skill** - mcpservers.org/claude-skills/anthropic/brand-guidelines
   - Focus/Error states: `#61AAF2` (blue), `#BF4D43` (red)
   - Confirms Poppins/Lora typography

**Implementation uses anthropic-style skill colors as primary source** for maximum brand fidelity.

## Notes

- **Anthroplot/Petri:** User confirmed to skip for now, can add later if design docs become available
- No `docs/petri-plotting.md` file exists in the codebase currently
- The implementation preserves the existing styled-components architecture and adds theming on top
- Three-theme approach (Default, Anthropic Light, Anthropic Dark) provides flexibility
- Typography kept as Calibre/SF Mono for MVP (can add Poppins/Lora fonts later)
