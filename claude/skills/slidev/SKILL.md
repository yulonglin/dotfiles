---
name: slidev
description: Slidev presentation framework helper. Use when creating slides, fixing Slidev issues, exporting to PDF, or when user mentions Slidev, slides.md, presentation export, or slide overflow.
---

# Slidev Skill

**Dev server**: `bunx slidev slides.md`
**Export**: `bunx slidev export slides.md --timeout 120000 --output out.pdf`
**Fix overflow/blank pages**: Run `/fix-slide`

Always export from root `slides.md`, not `pages/*.md` (images won't resolve from subpages).

## Context Management (CRITICAL)

⚠️ **Use subagent to read exported PDFs** - They can consume the entire context window.

```
Task tool → subagent_type: "general-purpose"
Prompt: "Read [path/to/slides.pdf] and [describe what to look for]"
```

The `/fix-slide` command handles this automatically.
