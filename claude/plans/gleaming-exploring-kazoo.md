# Plan: Port Hackathon Template to LaTeX using ICLR Style

## Approach

Use ICLR conference style as the base, extending it with custom commands for hackathon-specific sections. This leverages a proven, professional template while adding the unique requirements of the Technical AI Governance Challenge.

## Implementation Strategy

### 1. Base Template Selection
- **Use**: `iclr2026_conference.sty` (already downloaded)
- **Location**: `/Users/yulong/Downloads/iclr2026/`
- **Why**: Standard AI/ML conference format, well-maintained, professional appearance
- **Action**: Copy ICLR 2026 files to submission-template directory

### 2. Custom Extensions Needed

The hackathon template has sections not in standard ICLR:

#### New Sections to Support:
- **Code and Data** (mandatory section for reproducibility)
  - GitHub/GitLab repository links
  - Dataset links
  - Optional artifacts (demos, videos, Hugging Face Spaces)

- **LLM Usage Statement** (mandatory disclosure)
  - Disclosure of LLM assistance
  - Verification statement for claims

- **Author Contributions** (optional)
  - Project roles and responsibilities

#### Modifications to Existing:
- **Abstract**: Must support word count guidance (150-250 words)
- **Discussion and Limitations**: Combined section (not separate)
- **Future Work**: As unnumbered subsection under Discussion

### 3. Files to Create

#### `tagc2026.sty` (Custom package extending ICLR)
```latex
\NeedsTeXFormat{LaTeX2e}
\ProvidesPackage{tagc2026}[2026/01/01 Technical AI Governance Challenge 2026 Template]

% Load ICLR base
\RequirePackage{iclr2026_conference}

% Custom commands:
% - \codedata{repo_url}{dataset_url}{artifacts} - Code and Data section
% - \llmusage{disclosure}{verification} - LLM Usage Statement
% - \contributions{text} - Author Contributions section
```

#### `example-submission.tex` (Complete working example)
Full paper demonstrating all sections with:
- Front matter (title, authors, abstract)
- All required sections with placeholder content
- Figures/tables with proper captions
- References using BibTeX
- Appendix example
- Code and Data section
- LLM Usage Statement

#### `README.md` (Usage documentation)
- Installation instructions (required packages)
- Compilation instructions
- Section-by-section guidance
- Common customizations

### 4. Implementation Details

#### Custom Commands Design

**\codedata command:**
```latex
\newcommand{\codedata}[3]{%
  \section{Code and Data}
  \paragraph{Code Repository:} \url{#1}
  \paragraph{Datasets:} #2
  \ifx&#3&% check if #3 is empty
  \else
    \paragraph{Additional Artifacts:} #3
  \fi
}
```

**\llmusage command:**
```latex
\newcommand{\llmusage}[2]{%
  \section{LLM Usage Statement}
  \paragraph{LLM Assistance:} #1
  \paragraph{Verification:} #2
}
```

**\contributions command:**
```latex
\newcommand{\contributions}[1]{%
  \section{Author Contributions}
  #1
}
```

#### Section Customizations

Redefine section headers for hackathon-specific titles if needed:
- Ensure "Discussion and Limitations" renders as single section
- Support unnumbered "Future Work" subsection

### 5. Verification Plan

**Compilation Test:**
```bash
# Copy ICLR 2026 files to working directory
cp /Users/yulong/Downloads/iclr2026/*.sty .
cp /Users/yulong/Downloads/iclr2026/*.bst .
cp /Users/yulong/Downloads/iclr2026/math_commands.tex .

# Compile example
pdflatex example-submission.tex
bibtex example-submission
pdflatex example-submission.tex
pdflatex example-submission.tex

# Verify output
open example-submission.pdf
```

**Visual Checks:**
- [ ] Title and authors render correctly
- [ ] Abstract is properly formatted
- [ ] All standard sections (Intro, Methods, Results, Discussion) compile
- [ ] Custom sections (Code and Data, LLM Usage Statement) appear
- [ ] References compile with BibTeX
- [ ] Figures and tables have proper captions
- [ ] Page count ~4 pages (excluding references/appendix)

**Functionality Checks:**
- [ ] `\codedata` command works with URLs
- [ ] `\llmusage` command renders both paragraphs
- [ ] `\contributions` command creates proper section
- [ ] Multiple authors with affiliations display correctly
- [ ] Hyperlinks in PDF are clickable

## Critical Files

**To copy from /Users/yulong/Downloads/iclr2026/:**
- `iclr2026_conference.sty` - ICLR base style
- `iclr2026_conference.bst` - Bibliography style
- `fancyhdr.sty` - Page headers/footers
- `natbib.sty` - Bibliography management
- `math_commands.tex` - Math shortcuts (optional)
- `iclr2026_conference.bib` - Example bibliography (for reference)

**To create:**
- `tagc2026.sty` - Custom style package extending ICLR
- `example-submission.tex` - Complete working example for hackathon
- `references.bib` - Example bibliography for hackathon
- `README.md` - Documentation for hackathon template

## Trade-offs

**Why ICLR 2026 over custom:**
- ✅ Professional, proven template used by major AI/ML conference
- ✅ Well-maintained, handles edge cases (long author lists, etc.)
- ✅ Familiar to AI/ML researchers submitting to ICLR
- ✅ Already downloaded and available locally
- ✅ Saves ~80% of styling work
- ✅ Appropriate page limits (~4 pages body, similar to hackathon requirement)
- ⚠️ Has ICLR-specific header ("Under review as a conference paper at ICLR 2026") that should be customized

**Why extend vs. fork:**
- Extending with `\RequirePackage{iclr2026_conference}` maintains ICLR's proven formatting
- Custom commands in separate .sty (`tagc2026.sty`) keep hackathon-specific additions modular
- Clear separation: ICLR handles page layout, tagc2026 adds custom sections

## Open Questions

None - user confirmed ICLR base, full styling + example file desired.
