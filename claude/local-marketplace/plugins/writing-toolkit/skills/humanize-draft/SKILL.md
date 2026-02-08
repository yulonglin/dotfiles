---
name: humanize-draft
description: "DEPRECATED: Use /review-draft --critics=humanizer instead. LLM cliche detection is now integrated into review-draft."
---

# Humanize Draft (Deprecated)

This skill has been merged into `/review-draft` as the `humanizer` critic.

## Migration

```bash
# Old (deprecated):
/humanize-draft paper.md

# New (recommended):
/review-draft paper.md --critics=humanizer
```

The humanizer critic in `/review-draft` provides the same phrase detection with the same output format, plus integrates with clarity, narrative, facts, and red-team critics when you want comprehensive review.
