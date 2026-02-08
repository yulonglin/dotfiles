---
name: custom-compact
description: Compact current work with optional focus using agent-context-summariser
---

# Compact current work

## Instructions

1. **Generate Summary**: Use `@agent-context-summariser` to compact the current work.
   - Focus on preserving user instructions, clarifications, and the exact inputs/outputs/commands.
   - Incorporate any additional focus provided in the user's request.

2. **Replace Context**: Once the summary is generated, replace the current context window with this new summary using `/compact` (or the equivalent context management tool available).
