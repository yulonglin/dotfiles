# Writing Toolkit

Academic writing plugin with specialized critics for papers, drafts, and presentations.

## Skills

### `/clear-writing` - Clarity Guidelines

Reference guide for clear, human-quality technical writing. Covers:
- Word choices to avoid
- Sentence structure
- Tone and voice

**Usage**:
```bash
/clear-writing              # Show full guide
/clear-writing query        # Search guide
```

### `/review-draft` - Comprehensive Writing Review

Run 4 specialized critics on a draft (parallel):
- **clarity-critic** - Sentence-level readability
- **narrative-critic** - Structure and argument flow
- **fact-checker** - Claim verification
- **red-team** - Counterexamples and objections

**Usage**:
```bash
/review-draft paper.md                              # All critics
/review-draft paper.md --critics=clarity            # Just clarity
/review-draft paper.md --sensitivity=aggressive     # Stricter
```

**Output**: Feedback files in `feedback/` directory

### `/humanize-draft` - LLM-ism Detection (v0.1 MVP)

Detect 15 high-confidence LLM clichés and chatbot artifacts.

**Current scope**:
- Phrase detection only (exact string matching)
- 15 high-confidence patterns
- Confidence-scored matches with context checking

**Patterns detected**:
- **Blatant hedging**: "It's worth noting that", "Interestingly,"
- **Chatbot artifacts**: "As a large language model", "I hope this helps!"
- **AI vocabulary**: "leverage", "utilize", "facilitate"
- **False enthusiasm**: "Great question!", "Absolutely!"
- **Filler phrases**: "in order to", "is able to"

**Usage**:
```bash
/humanize-draft paper.md            # Scan entire paper
/humanize-draft chapter.md          # Scan one chapter
```

**Output**:
- Humanization score (0-100)
- High/medium confidence issues
- Inline suggestions for each match

**Coming in future versions**:
- v0.2: Statistical analysis (em-dash frequency, sentence length variance)
- v0.3: Generic description detection
- v1.0: Full integration with `/review-draft`

**Note**: Currently standalone only. Not integrated with `/review-draft` yet.

### `/review-paper` - Academic Paper Review

Specialized review for research papers using narrative-critic, fact-checker, and red-team.

**Usage**:
```bash
/review-paper paper.pdf
/review-paper paper.md
```

### `/research-presentation` - Presentation Guide

Structure and content guide for research presentations.

### `/fix-slide` - Slidev Presentation Fixer

Identify and fix slides with content overflow or blank pages.

### `/slidev` - Slidev Framework Helper

Support for Slidev presentation framework.

---

## Agents

The plugin uses specialized agents for different writing tasks:

- **clarity-critic** - Flags vague pronouns, hedging, run-ons, jargon, passive voice, buried ledes
- **narrative-critic** - Evaluates argument structure, flow, hooks, conclusions
- **fact-checker** - Verifies claims, flags unsupported assertions, finds citations
- **paper-writer** - Drafts academic paper sections
- **application-writer** - Drafts job and fellowship applications
- **humanizer** - Detects LLM-isms and chatbot artifacts (v0.1 MVP)

---

## Humanizer Details

### What It Does

The humanizer agent scans your writing for 15 high-confidence patterns that strongly indicate LLM-generated content:

| Severity | Pattern | Count |
|----------|---------|-------|
| Critical | Chatbot artifacts | 3 |
| High | Blatant hedging | 5 |
| Medium | AI vocabulary | 3 |
| Medium | False enthusiasm | 2 |
| Low | Filler phrases | 2 |

### What It Doesn't Do (v0.1)

❌ Statistical analysis (em-dash counting, sentence length variance)
❌ Generic description detection (complex heuristics)
❌ Full AI writing assessment (use `/review-draft` instead)

### Confidence Scoring

Each match gets a confidence score (0-100):
- **90-100%**: Definitely LLM-generated (flag unconditionally)
- **70-89%**: Very likely problematic (check context)
- **50-69%**: Ambiguous (might be intentional)

### Humanization Score

Overall score (0-100) based on pattern density:
- **0-10**: Clean writing, no obvious LLM patterns
- **10-20**: Minor patterns (1-2 filler phrases)
- **20-40**: Some LLM-isms, fix flagged issues
- **40-100**: Heavy LLM patterns, needs humanization

### Test Results

Validated on 50-sample test corpus:
- **Target precision**: >90% (very few false positives)
- **Target recall**: >70% (catches most obvious patterns)
- **Status**: Validation pending (Phase 3)

### Integration Status

- ✅ Standalone `/humanize-draft` skill (ready)
- ⏳ Integration with `/review-draft` (planned for v1.0 after validation)

---

## Workflow Examples

### Quick Draft Check
```bash
/humanize-draft draft.md
# Review humanization score and fix flagged patterns
```

### Comprehensive Review
```bash
/review-draft paper.md                    # Get all critics
# Then run:
/humanize-draft paper.md                  # Check for LLM-isms
```

### Publication-Ready Check
```bash
# 1. Structure and arguments
/review-draft paper.md --critics=narrative

# 2. Check facts and claims
/review-draft paper.md --critics=facts

# 3. Find weak points
/review-draft paper.md --critics=redteam

# 4. Polish clarity
/review-draft paper.md --critics=clarity

# 5. Remove LLM patterns
/humanize-draft paper.md

# 6. Final read-through with /clear-writing reference
/clear-writing
```

---

## Pattern Documentation

For detailed information about each pattern:
- **Why it's problematic** - Cognitive/communication reasoning
- **False positive scenarios** - When NOT to flag
- **Fix suggestions** - Concrete rewrites with examples
- **Sources** - Research basis and citations

See: `docs/humanizer-patterns.md`

---

## Overlap with Other Critics

| Critic | Coverage |
|--------|----------|
| **clarity-critic** | Vague pronouns, hedging, run-ons, passive voice |
| **humanizer** | LLM-specific clichés and artifacts (15 patterns) |
| **clear-writing** | Reference guide (word/tone/structure) |

**Design**: Humanizer focuses on "this is AI-generated" signals. Clarity-critic focuses on "this is hard to read" issues. Use both for complete coverage.

---

## Version History

### v1.0.1 (2026-02-02)
- Added humanizer agent (v0.1 MVP)
- Added `/humanize-draft` skill
- Added pattern database (15 patterns)
- Added humanizer-patterns.md documentation
- Added test corpus framework

### v1.0.0
- Initial writing-toolkit release
- Skills: clear-writing, review-draft, review-paper, research-presentation, fix-slide
- Agents: clarity-critic, narrative-critic, fact-checker, paper-writer, application-writer

---

## Roadmap

### Phase 2 - Post-MVP Validation
- [ ] Run 50-sample test corpus validation
- [ ] Calculate precision/recall/F1 metrics
- [ ] Identify and remove high false-positive patterns
- [ ] Audit clarity-critic overlap
- [ ] Fine-tune confidence thresholds

### Phase 3 - v0.2 (Statistical Analysis)
- [ ] Add em-dash frequency detection
- [ ] Add sentence length uniformity detection
- [ ] Add list overuse detection
- [ ] Expand to 20-25 patterns

### Phase 4 - v0.3 (Generic Detection)
- [ ] Implement generic description detection
- [ ] May require separate agent
- [ ] Complex heuristics and contextual analysis

### Phase 5 - v1.0 (Full Integration)
- [ ] Integrate humanizer with `/review-draft`
- [ ] Add optional `--humanize` flag
- [ ] User feedback loop
- [ ] Production stability

---

## Getting Help

See individual skill documentation:
- `/clear-writing` - Writing best practices
- `/review-draft` - Multi-critic review workflow
- `/humanize-draft` - LLM-ism detection

Or check pattern documentation:
- `docs/humanizer-patterns.md` - Detailed pattern rationale
- `test-corpus/README.md` - Test corpus structure
