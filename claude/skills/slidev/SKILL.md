---
name: slidev
description: Slidev presentation framework helper. Use when creating slides, fixing Slidev issues, exporting to PDF, or when user mentions Slidev, slides.md, presentation export, or slide overflow.
---

# Slidev Skill

## Quick Reference

**Export**: `bunx slidev export slides.md --timeout 120000 --output out.pdf`

**Fix issues**: Run `/fix-slide` command

## Critical Pitfalls

1. **`---` in comments breaks parser** - Comment content and dividers separately:
   ```markdown
   <!-- # Slide 1 -->
   <!-- --- -->
   <!-- # Slide 2 -->
   ```

2. **Image paths** - Use `/week19/img.png`, not `/public/week19/img.png`

3. **Subpage exports** - Export from `slides.md`, not `pages/*.md` (images won't resolve)
