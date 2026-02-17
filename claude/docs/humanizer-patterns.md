# Humanizer Pattern Database

## Overview

This document explains the 15 high-confidence LLM-ism patterns used by the humanizer agent. Each pattern is documented with:
- **Why it's problematic** - with citations
- **False positive scenarios** - when NOT to flag
- **Fix suggestions** - concrete rewrites
- **Confidence level** - how certain we are it's LLM-generated

**Goal**: Precision >90% (very few false positives) and recall >70% (catch most obvious patterns).

---

## v0.1 Patterns (Current Release)

### Category 1: Blatant Hedging (5 patterns)

Excessive qualification that adds no information and signals AI-generated content.

#### "It's worth noting that"
- **Why problematic**: Pure filler phrase. Adds zero information. Humans don't use this.
- **Confidence**: 95% (zero legitimate uses)
- **Sources**: clear-writing.md, blader/humanizer repo
- **False positives**: None known. Always safe to remove.
- **Fix**: State directly or remove
  - ❌ "It's worth noting that the algorithm is fast."
  - ✅ "The algorithm is fast."

#### "Interestingly,"
- **Why problematic**: Lazy signposting. If something is interesting, explain why instead of just saying so.
- **Confidence**: 90% (context-dependent: academic writing might use for transitions)
- **Sources**: clear-writing.md, blader/humanizer
- **False positives**: Academic writing sometimes uses as transition signal
- **Fix**: Explain why interesting or remove
  - ❌ "Interestingly, the results showed X."
  - ✅ "Surprisingly, the results showed X, contradicting prior work on Y."

#### "This is particularly important because"
- **Why problematic**: Tells rather than shows. Good writing lets importance be implicit.
- **Confidence**: 92%
- **Sources**: clear-writing.md
- **False positives**: Rare. Might appear in pedagogical writing explaining emphasis.
- **Fix**: Remove and let importance be obvious
  - ❌ "This is particularly important because alignment matters."
  - ✅ "Misaligned systems pose existential risks."

#### "As a matter of fact,"
- **Why problematic**: Filler hedge used to reinforce trivial points.
- **Confidence**: 94%
- **Sources**: clear-writing.md
- **False positives**: Very rare (might appear in dated writing)
- **Fix**: Remove - pure filler
  - ❌ "As a matter of fact, humans prefer clarity."
  - ✅ "Humans prefer clarity."

#### "In fact, (when not emphatic)"
- **Why problematic**: Often used as filler before stating the obvious
- **Confidence**: 85% (context-dependent - can be emphatic)
- **Sources**: clear-writing.md
- **False positives**: Can be used for emphasis in good writing
- **Fix**: State directly without filler
  - ❌ "In fact, the code works."
  - ✅ "The code works." or ✅ "Notably, the code works." (if emphasizing surprise)

---

### Category 2: Chatbot Artifacts (3 patterns)

Explicit AI self-references that only appear in LLM-generated text.

#### "As a large language model"
- **Why problematic**: 100% indicator of LLM output. No human would write this.
- **Confidence**: 99% (zero legitimate uses)
- **Sources**: blader/humanizer
- **False positives**: None. This ONLY appears in AI disclaimers.
- **Fix**: Remove entirely
  - ❌ "As a large language model, I should note that..."
  - ✅ Remove the entire phrase

#### "I hope this helps!"
- **Why problematic**: Classic chatbot sign-off. Never appears in real content.
- **Confidence**: 98%
- **Sources**: clear-writing.md, blader/humanizer
- **False positives**: None in formal writing. Might appear in overly casual personal emails, but shouldn't in professional content.
- **Fix**: Just end the response
  - ❌ "...and that's why the approach works. I hope this helps!"
  - ✅ "...and that's why the approach works."

#### "I don't have personal opinions"
- **Why problematic**: Explicit AI self-identification. Only LLM output uses this.
- **Confidence**: 99%
- **Sources**: blader/humanizer
- **False positives**: None. This is a pure AI disclaimer.
- **Fix**: Remove entirely
  - ❌ "I don't have personal opinions, but X is important..."
  - ✅ "X is important..."

---

### Category 3: AI Vocabulary (3 patterns)

Business/technical jargon heavily overused by LLMs. Humans prefer simpler alternatives.

#### "leverage"
- **Why problematic**: LLM favorite. Humans say "use". Formal and abstract.
- **Confidence**: 88% (context-dependent: can be used literally about levers)
- **Sources**: clear-writing.md, blader/humanizer
- **False positives**: Can mean literal lever action in mechanical/physics writing
- **Fix**: Use 'use', 'apply', 'harness', or 'deploy' instead
  - ❌ "We leverage machine learning to improve accuracy."
  - ✅ "We use machine learning to improve accuracy."
  - ✅ "The lever provides mechanical advantage." (literal use OK)

#### "utilize"
- **Why problematic**: Unnecessarily formal. "Use" is simpler and more human.
- **Confidence**: 89%
- **Sources**: clear-writing.md, blader/humanizer
- **False positives**: Rare. Might appear in formal technical writing, but almost always replaceable.
- **Fix**: Use 'use' instead
  - ❌ "We utilize a transformer-based architecture."
  - ✅ "We use a transformer-based architecture."

#### "facilitate"
- **Why problematic**: Abstract and formal. Humans prefer concrete verbs.
- **Confidence**: 87%
- **Sources**: clear-writing.md, Google Style Guide
- **False positives**: Can be correct in some formal contexts (e.g., "facilitated discussion")
- **Fix**: Use concrete alternatives: 'help', 'enable', 'make possible', 'support'
  - ❌ "This framework facilitates better design decisions."
  - ✅ "This framework enables better design decisions."
  - ✅ "This framework helps teams make better decisions."

---

### Category 4: False Enthusiasm (2 patterns)

Performative engagement without substance. Signals AI-generated filler.

#### "Great question!"
- **Why problematic**: Validation without content. Skip directly to answering.
- **Confidence**: 91%
- **Sources**: clear-writing.md
- **False positives**: Very rare. Might appear in extremely casual writing.
- **Fix**: Answer the question directly instead
  - ❌ "Great question! The algorithm works because..."
  - ✅ "The algorithm works because..."

#### "Absolutely!"
- **Why problematic**: Performative agreement without specifics. Humans are more concrete.
- **Confidence**: 86%
- **Sources**: clear-writing.md
- **False positives**: Can be used for emphatic agreement in dialogue/emails
- **Fix**: State your actual position instead
  - ❌ "Absolutely! That's what we should do."
  - ✅ "Yes. That approach has three advantages: X, Y, Z."

---

### Category 5: Filler Phrases (2 patterns)

Unnecessarily wordy substitutes for simpler words. Pure wordiness indicator.

#### "in order to"
- **Why problematic**: Always replaceable with "to". Wordiness is a classic LLM signal.
- **Confidence**: 92%
- **Sources**: clear-writing.md, blader/humanizer
- **False positives**: None. "To" is always clearer and shorter.
- **Fix**: Use 'to' instead
  - ❌ "We conducted tests in order to verify correctness."
  - ✅ "We conducted tests to verify correctness."

#### "is able to"
- **Why problematic**: Formal avoidance of "can". Always replaceable.
- **Confidence**: 93%
- **Sources**: clear-writing.md
- **False positives**: None. "Can" is always preferable.
- **Fix**: Use 'can' instead
  - ❌ "The system is able to handle 10k requests/sec."
  - ✅ "The system can handle 10k requests/sec."

---

## Patterns NOT Included (v0.1 MVP)

These high-value patterns are saved for v0.2+ because they require statistical analysis:

### Statistical Patterns (v0.2)
- **Em-dash overuse**: >2 per 100 words
- **Sentence length uniformity**: Low variance (40-50 words consistently)
- **List overuse**: >3 lists per 500 words
- **Paragraph length uniformity**: Similar length throughout

### Detection Heuristics (v0.3)
- **Generic positive descriptions**: "rich cultural heritage", "comprehensive approach", "significant implications"
- **Vague metrics**: "notably", "significantly", "substantially" without numbers
- **Sanding down specific facts**: Loss of precision in paraphrasing
- **Regression to mean**: Arguments becoming more generic over text

---

## Evolution Log

### v0.1 (2026-02-02)
- **Status**: Initial MVP release
- **Patterns**: 15 high-confidence patterns
- **Approach**: Phrase detection only (exact string matching)
- **Scope**: Prioritized precision over recall
- **Coverage**: ~43% of total identified patterns (15 out of 35+)
- **Test Corpus**: 50 samples (10 per category)
- **Success Criteria**: Precision >90%, Recall >70%

**Selection rationale**:
- Analyzed 4 sources (blader/humanizer, clear-writing, Wikipedia, Google docs)
- Identified 35+ total patterns
- Selected top 15 with >2 source agreement
- Excluded statistical/heuristic patterns for MVP simplicity

### v0.2 (Coming Soon)
- Add statistical analysis (em-dash frequency, sentence length variance)
- Increase patterns to ~20-25
- Agent size: 600 tokens

### v0.3 (Coming Later)
- Add generic description detection
- Requires custom heuristics (complex)
- Might be separate `generic-detector` agent

### v1.0 (Future)
- Full integration with `/review-draft`
- Possible `--humanize` flag for `/review-draft`
- Consensus patterns from user feedback

---

## Usage Guidelines

### When to Flag

Flag a pattern if:
1. Exact phrase match found in text
2. Confidence score supports flagging (context-dependent)
3. No legitimate reason (not a quote, not ironic, not literal)

### When NOT to Flag

Don't flag if:
- **Academic quote**: Citing another author's work
- **Ironic/satirical use**: Intentionally using LLM-speak to mock
- **Rhetorical emphasis**: Using phrase for effect (note in output)
- **Proper noun**: Part of a name/product
- **Literal interpretation**: "Facilitate" as actual facilitation, "leverage" as physics

### Confidence Scoring

- **90-100**: Definitely LLM-generated. Flag automatically.
- **70-89**: Very likely problematic. Flag with context note.
- **50-69**: Ambiguous. Flag cautiously, explain uncertainty.
- **<50**: Probably OK. Don't flag.

---

## False Positive Prevention

The 15 patterns were selected specifically to minimize false positives:

| Pattern | False Positive Risk | Mitigation |
|---------|-------------------|------------|
| "As a large language model" | 0% | No legitimate use |
| "I hope this helps!" | 0% | Only in casual emails |
| "in order to" | 0% | Always replaceable |
| "leverage" (phrase) | Low | Literal lever use rare |
| "facilitate" | Low | Usually replaceable |
| "Interestingly," | Medium | Academic transitions |
| "Absolutely!" | Medium | Can be emphatic |
| "In fact," | Medium | Can be emphatic |

**Conservative approach**: If uncertain, don't flag. False negatives are better than false positives.

---

## Integration with Other Critics

**clear-writing skill**: Covers general prose quality and word-level issues. Humanizer focuses on LLM-specific patterns.

**clarity-critic agent** (separate plugin): Checks for vague pronouns, hedging, run-ons, passive voice. Overlaps with humanizer's hedging patterns.

**Future alignment**: Once humanizer validated, integrate with `/review-draft` as optional `--humanize` flag.

---

## Research Basis

### Sources

1. **blader/humanizer** - GitHub repo with 24 LLM-ism patterns
   - Analyzed category system and pattern reasoning
   - Selected 5 patterns with highest confidence

2. **clear-writing skill** (local)
   - 13 word-level anti-patterns
   - 5 structure-level patterns
   - 4 tone-level patterns
   - Selected 12 overlapping patterns

3. **Wikipedia: "Signs of AI writing"** (Ferenc Huszár)
   - 8 indicators of AI-generated text
   - Em-dash overuse, clichés, uniformity
   - Selected 3 phrase-level patterns

4. **Google Developer Documentation Style Guide**
   - Voice and tone guidance
   - Preference for active voice, concrete verbs
   - Validated pattern selections

### Pattern Selection Criteria

Each selected pattern met ALL of:
- Documented in 2+ sources
- High precision (>90% based on source consensus)
- Unambiguous in most contexts
- Not already covered by clarity-critic
- Zero or rare false positive scenarios

---

## Testing Results

### Validation Protocol (Phase 3)

For MVP validation, 50-sample test corpus:
- 10 pure Claude output (unedited)
- 10 human-written (clear-writing.md, papers)
- 10 human-edited Claude (mixed)
- 10 borderline (human text with false-positive triggers)
- 10 adversarial (ironic LLM-ism use, quotes about AI)

**Success criteria**:
- Precision >90%: Very few false positives
- Recall >70%: Catches most obvious patterns
- F1 score: Harmonic mean of precision/recall

---

## Contributing New Patterns

When considering new patterns:

1. **Two-source requirement**: Must appear in 2+ independent sources
2. **Precision test**: Run on test corpus - must achieve >85% precision
3. **False positive check**: Identify all legitimate uses
4. **Confidence scoring**: Assign appropriate level
5. **Documentation**: Add to this file with rationale

Propose in: GitHub issues or discussion thread

---

## Feedback & Iteration

User feedback channel (TBD): Submit false positives, missed patterns, or refinements

This pattern set will evolve based on:
- User feedback on accuracy
- New LLM releases and their characteristic patterns
- Integration feedback from writing plugin users
