---
name: humanize-draft
description: Detect LLM clichés and chatbot artifacts (phrase detection only)
---

# Humanize Draft

Detect 15 high-confidence LLM-isms and chatbot artifacts in your writing.

## What This Does

Scans drafts for obvious LLM patterns:
- **Blatant hedging**: "It's worth noting that", "Interestingly,"
- **Chatbot artifacts**: "As a large language model", "I hope this helps!"
- **AI vocabulary**: "leverage", "utilize", "facilitate"
- **False enthusiasm**: "Great question!", "Absolutely!"
- **Filler phrases**: "in order to", "is able to"

## What This Doesn't Do (v0.1)

- ❌ Statistical analysis (em-dash frequency, sentence length variance)
- ❌ Generic description detection (complex, coming in v0.3)
- ❌ Full AI writing assessment (use `/review-draft` for comprehensive review)

## Usage

```bash
/humanize-draft path/to/draft.md
```

## Output

Creates feedback file:
- `feedback/{filename}_humanizer.md`

Contains:
- **Humanization score** (0-100, % of text matching patterns)
- **High-confidence issues** (>85% - definitely problematic)
- **Medium-confidence issues** (70-85% - check context)
- **Confidence scores** for each match (helps prioritize)

## Examples

```bash
/humanize-draft paper.md              # Scan entire paper
/humanize-draft section.md            # Scan one section
/humanize-draft notes.txt             # Works with any text file
```

## Score Interpretation

- **0-10**: Clean writing, no obvious LLM patterns
- **10-20**: Minor patterns (1-2 filler phrases)
- **20-40**: Some LLM-isms present, fix flagged issues
- **40-100**: Heavy LLM patterns, needs humanization

## Integration Note

**Standalone only** (for now). Use alongside:
- `/clear-writing` - General writing quality
- `/review-draft` - Comprehensive multi-critic review

## Roadmap

- **v0.1** (current): Phrase detection (15 patterns)
- **v0.2** (coming): Statistical analysis (em-dash frequency, sentence length)
- **v0.3** (coming): Generic description detection
- **v1.0** (future): Full integration with `/review-draft`

## Known Limitations

- May flag legitimate uses in academic/quoted context (noted in output)
- Doesn't catch statistical patterns (frequency analysis)
- Doesn't detect generic descriptions (complex heuristics)

## FAQ

**Q: Why can't it do X?**
A: Phase detection only in v0.1. Statistical features come in v0.2.

**Q: How accurate is it?**
A: Designed for high precision (>90%) on 15 core patterns. Tested on corpus of 50 samples.

**Q: Can I use it with `/review-draft`?**
A: Not yet. Validated on 15 patterns first. Future versions will integrate.

**Q: What's a "humanization score"?**
A: Percentage of text containing patterns, weighted by confidence. 0 = all human, 100 = pure AI speak.
