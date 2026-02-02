# Plan: Extract PDF Styling Specifications for LaTeX Template

**Goal**: Extract detailed visual styling, structural elements, and formatting conventions from "Copy of Technical AI Governance Challenge submission template.pdf" to create a matching LaTeX style file.

## Approach

### Step 1: PDF Analysis via Subagent
Since PDFs can consume significant context and produce verbose output, use a `general-purpose` subagent to:
- Read the PDF file at `/Users/yulong/projects/technical-ai-governance-hackathon/submission-template/Copy of Technical AI Governance Challenge submission template.pdf`
- Extract and document all styling specifications

### Step 2: Information to Extract

**Visual Styling Details:**
- Font families for: body text, headings (all levels), captions, code blocks
- Exact font sizes in points for: title, authors, section headings (H1, H2, H3), body text, captions, footnotes, references
- Line spacing/leading (e.g., 1.0, 1.15, 1.5)
- Paragraph spacing (space before/after paragraphs)
- Page margins (top, bottom, left, right in inches or cm)
- Colors (RGB or hex values): text color, heading colors, link colors, box backgrounds/borders
- Column layout (single column, double column, or mixed)

**Structural Elements:**
- Complete list of section titles exactly as they appear
- Numbering scheme (e.g., "1.", "1.1", "1.1.1" or unnumbered)
- Which sections are required vs optional
- Page limits or word counts mentioned
- Abstract requirements (word limit, special formatting)

**Formatting Conventions:**
- How authors and affiliations are displayed (format, separator, positioning)
- Abstract formatting (indentation, font size difference from body, spacing)
- Section heading format at each level (bold/italic/all-caps, spacing above/below)
- Subsection and sub-subsection heading formats
- Figure captions (position relative to figure, font size, numbering format like "Figure 1:")
- Table captions (position, font, numbering)
- Reference/bibliography format (style guide, font size, spacing)
- Code block formatting (font, background, borders, indentation)

**Special Elements:**
- LLM usage statement box:
  - Exact required text
  - Border style (solid/dashed, thickness, color)
  - Background color
  - Text formatting inside box
  - Positioning requirements (e.g., "appears on first page after abstract")
- Any other callout boxes or highlighted sections
- Header content (if any)
- Footer content (if any)
- Page numbering style and position
- Logos or branding elements (size, position)
- Special formatting for: equations, algorithms, pseudocode, bullet lists, numbered lists

**Content Requirements:**
- Word limits for specific sections (Introduction, Methods, etc.)
- Required acknowledgment text
- Data availability statement format
- Code availability statement format
- Conflict of interest statement
- Funding disclosure requirements

### Step 3: Organize Output
Structure the extracted information in clear categories with precise measurements that can be directly translated to LaTeX package parameters (geometry, titlesec, caption, etc.).

### Step 4: Deliverable
Provide a comprehensive specification document organized by category, with exact measurements where visible (e.g., "Section headings: 14pt bold, 18pt space above, 6pt below" rather than vague "sections are larger and bold").

## Constraints
- Since PDFs can be verbose, must use subagent to prevent context pollution
- Need precise measurements, not approximations
- Must capture all special formatting elements (boxes, colors, spacing)
- Output should be directly usable for creating LaTeX style files

## Execution Notes
Once plan is approved, spawn a `general-purpose` subagent with the task of reading and analyzing the PDF according to the specifications above.
