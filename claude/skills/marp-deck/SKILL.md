---
name: marp-deck
description: Build research slide decks from Markdown with Marp (marp-cli). Use when the user wants to "build slides", "make a marp deck", "create a presentation", export Markdown to HTML/PDF/PPTX slides, or embed matplotlib/anthroplot figures into a deck. Verified cheatsheet for marp-cli v4.4.0 with copy-pasteable frontmatter, two-column + image patterns, custom theme starter, and exact build commands.
---

# marp-deck

Build slide decks from Markdown using `marp-cli`. Verified against marp-cli **v4.4.0** (marp-core v4.3.0).

## TL;DR build commands

`marp` is installed globally at `~/.bun/bin/marp` (on PATH). Always pass `--no-stdin` from non-interactive shells (Claude Code, CI) or marp hangs waiting on stdin.

```bash
# HTML (no browser needed — works everywhere)
marp --no-stdin deck.md -o deck.html

# PDF (requires a local Chrome/Edge/Firefox; --allow-local-files needed for local images)
marp --no-stdin --pdf --allow-local-files deck.md -o deck.pdf

# PowerPoint
marp --no-stdin --pptx --allow-local-files deck.md -o deck.pptx

# Live preview while editing (watches + serves)
marp --no-stdin -w -s . 
```

> ⚠️ **PDF / PPTX / image / `--notes` export all require a browser** (Google Chrome, Edge, or Firefox) installed locally. HTML export does NOT. If none is installed, only HTML works — set `CHROME_PATH=/path/to/chrome` to point marp at one. On this machine no browser was found at skill-creation time, so default to HTML and flag the browser requirement before attempting PDF/PPTX.

## Frontmatter template (copy-paste)

```markdown
---
marp: true
theme: default          # default | gaia | uncover, or a custom theme name
paginate: true
size: 16:9              # 16:9 (default) or 4:3
header: 'Weekly Research Meeting'
footer: 'Your Name · 2026-06-25'
---

# Title Slide

Subtitle / one-line takeaway

<!-- Speaker note: any HTML comment that is NOT a directive becomes a presenter note -->
```

## Splitting slides

Slides are split by a horizontal rule `---` on its own line (blank line before/after). The opening YAML frontmatter block is not counted as a slide separator.

```markdown
# Slide 1

---

# Slide 2
```

## Directives

- **Global** (whole deck, set in frontmatter or `<!-- key: value -->`): `theme`, `style`, `headingDivider`, `lang`, plus `marp: true`, `size`.
- **Local** (this slide + all following): `paginate`, `header`, `footer`, `class`, `backgroundColor`, `backgroundImage`, `backgroundPosition`, `backgroundSize`, `color`.
- **Spot** (this slide only): prefix any local directive with `_`.

```markdown
<!-- _class: lead -->          <!-- center-aligned title slide, this slide only -->
<!-- _paginate: false -->      <!-- hide page number on this slide only -->
<!-- _backgroundColor: #111 --> <!-- dark background, this slide only -->
<!-- backgroundColor: aqua -->  <!-- aqua from here onward -->
```

Built-in theme class variants: `lead` (centered), `invert` (dark). gaia/uncover also support these. Apply per-slide with `<!-- _class: invert -->`.

## Embedding images / graphs (matplotlib, anthroplot)

Save figures as PNG or SVG and reference by **relative path** (run marp from the deck's directory). `--allow-local-files` is required when exporting local images to PDF/PPTX.

```markdown
![w:600](figures/accuracy.png)        <!-- width 600px -->
![w:600 h:400](figures/loss.svg)      <!-- explicit width + height -->
![](figures/plot.png)                 <!-- natural size -->
```

Filters via alt text (inline images only): `![blur:4px brightness:1.2](fig.png)`. Available: blur, brightness, contrast, drop-shadow, grayscale, hue-rotate, invert, opacity, saturate, sepia.

### Background images

```markdown
![bg](bg.jpg)              <!-- full-slide, cover (default) -->
![bg fit](bg.png)          <!-- contain (fit inside) -->
![bg cover](bg.jpg)        <!-- fill, may crop -->
![bg 80%](bg.png)          <!-- percentage scaling -->
```

### Split background = image on one side, content on the other

```markdown
![bg left](figures/plot.png)

## Findings
- point one
- point two
```

`![bg right]` puts the image on the right. Custom width: `![bg left:40%](plot.png)`. Multiple bg images stack horizontally; add `vertical` to stack vertically: `![bg vertical](a.png) ![bg](b.png)`.

## Two-column layout

Marp has no built-in columns class — add one via an inline `<style>` block (scoped to the deck, stripped from HTML) plus a div, or via a custom theme.

```markdown
<style>
.columns { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
</style>

<div class="columns">
<div>

### Left
- bullet
![w:100%](figures/left.png)

</div>
<div>

### Right
- bullet
![w:100%](figures/right.png)

</div>
</div>
```

Blank lines around the inner `<div>`s matter — they let Markdown render inside the HTML. Alternatively use a split background (above) for image-vs-text, which needs no HTML.

## Speaker notes

Any HTML comment that is **not** a recognized directive becomes a presenter note for that slide. Multiple per slide allowed; multiline supported.

```markdown
# Results

<!-- Walk through the table; emphasize the 12% gain over baseline. -->
<!--
Multi-line notes
also work.
-->
```

Export notes as text: `marp --no-stdin --notes deck.md -o notes.txt` (needs a browser). Embed them as PDF annotations: `marp --no-stdin --pdf --pdf-notes --allow-local-files deck.md`. In the default `bespoke` HTML template, press `p` to open presenter view (shows notes + next slide).

## Custom theme starter

Save as `theme.css`. The `/* @theme name */` comment is **mandatory**. A theme must set the slide size in absolute units on `section`.

```css
/* @theme research */
@import 'default';   /* inherit default, then override */

section {
  width: 1280px;
  height: 720px;     /* 16:9 */
  padding: 60px;
  font-family: 'Helvetica Neue', Arial, sans-serif;
  font-size: 28px;
  color: #1a1a1a;
  background: #ffffff;
}
h1 { font-size: 52px; color: #0a5; }
h2 { font-size: 38px; }
section.lead { justify-content: center; text-align: center; }
.columns { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
```

Use it by passing the CSS file to `--theme`, then reference it normally:

```bash
marp --no-stdin --theme theme.css deck.md -o deck.html
# or register a directory of themes:
marp --no-stdin --theme-set ./themes/ deck.md -o deck.html
```

With `--theme-set`, set `theme: research` in frontmatter (the name from `/* @theme research */`).

## Pitfalls (verified)

- **Hangs in Claude Code / CI**: marp waits on stdin when stdout isn't a TTY. Always pass `--no-stdin`.
- **No browser → only HTML works**: PDF, PPTX, PNG/JPEG, and `--notes` all spawn Chrome/Edge/Firefox. With none installed they fail with a ChromeLauncher error. Install a browser or set `CHROME_PATH`. HTML never needs one.
- **Local images blank in PDF/PPTX**: browser conversion blocks local files by default. Add `--allow-local-files` (security note: only run on decks you trust).
- **Image paths**: relative to the deck file / CWD. Run marp from the deck's directory, or use paths relative to it.
- **Frontmatter must be first**: the `---` YAML block has to be at the very top, or `marp: true` won't activate.
- **`size:` needs marp-core**: `size: 16:9` / `4:3` is a marp-core feature (works with marp-cli's default engine); custom Marpit-only engines won't honor it.
- **Custom theme size**: must be an absolute unit (px/cm/in...), not %/vw — Marpit requires a static slide size.
- **Two-column needs blank lines** around inner divs so Markdown renders inside the HTML.

## Quick recipe for a research deck with figures

```bash
# 1. Put deck.md + figures/ in one dir; generate figures with matplotlib/anthroplot as PNG/SVG.
# 2. Iterate with live preview:
cd deck-dir && marp --no-stdin -w -s .
# 3. Final HTML (always works):
marp --no-stdin deck.md -o deck.html
# 4. PDF for sharing (needs a browser):
marp --no-stdin --pdf --allow-local-files deck.md -o deck.pdf
```
