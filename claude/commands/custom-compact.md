---
argument-hint: [focus instructions]
description: Compact current work with optional focus
---

# Compact current work

First, generate the summary: Use @agent-context-summariser to compact the current work, focusing on preserving user instructions and clarifications, and the exact inputs/outputs/commands.

Additional focus: $ARGUMENTS

Then, replace the current context window with this new summary, using /compact or otherwise
