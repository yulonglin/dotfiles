# Humanizer Test Corpus

50-sample test corpus for validating the humanizer agent's 15-pattern detection.

## Corpus Structure

### Categories (10 samples each)

1. **Pure Claude Output** (`claude-output/`)
   - Unedited responses from Claude
   - High density of LLM-isms expected
   - Baseline: should score 60-100

2. **Human-Written** (`human-written/`)
   - Professional writing (papers, blog posts, documentation)
   - Source of gold standard (clean writing)
   - Baseline: should score 0-10

3. **Human-Edited Claude** (`human-edited-claude/`)
   - Claude output with human edits removing LLM-isms
   - Mixed content
   - Baseline: should score 20-40

4. **Borderline Cases** (`borderline/`)
   - Human text that might trigger false positives
   - Academic writing with hedging
   - Legitimate use of "in fact", "absolutely", etc.
   - Baseline: should score 5-25

5. **Adversarial** (`adversarial/`)
   - Satirical use of LLM-isms
   - Quotes about AI writing
   - Intentional LLM-speak
   - Baseline: context-dependent (10-50)

## Validation Protocol

For each sample, the humanizer should:

1. **Run pattern detection** across all 15 patterns
2. **Assign confidence scores** for each match
3. **Output humanization score** (0-100)
4. **Note context** for ambiguous cases

## Success Criteria (MVP)

| Metric | Target | Status |
|--------|--------|--------|
| **Precision** | >90% | TBD (after testing) |
| **Recall** | >70% | TBD (after testing) |
| **F1 Score** | >75% | TBD (after testing) |
| **False Positives** | <10% | TBD (after testing) |

**Gold Standard**: 3+ human raters review subset for consensus

## Test Results

### Phase 3: Validation (Pending)

After running humanizer on all 50 samples:
- [ ] Calculate precision/recall/F1
- [ ] Identify high false-positive patterns
- [ ] Tighten confidence thresholds if needed
- [ ] Remove problematic patterns if necessary
- [ ] Re-validate on test corpus
- [ ] Document results

## Usage

```bash
# Run humanizer on corpus
for file in test-corpus/**/*.md; do
  /humanize-draft "$file"
done

# Collect results
mkdir -p test-corpus/results
mv test-corpus/**/feedback/* test-corpus/results/

# Analyze results
python analyze_results.py test-corpus/results/
```

## Adding Samples

To add a new sample:

1. Create file in appropriate category directory
2. Name format: `{description}-{id}.md` (e.g., `claude-response-001.md`)
3. Include ~200-500 words of text
4. Add metadata (source, expected score range, notes)

**Metadata template** (top of file):
```markdown
---
source: {URL or description}
expected_score_range: {0-10 | 10-40 | etc}
category: {pure_claude | human_written | edited | borderline | adversarial}
notes: {any special context}
---

[Sample text here]
```

## Known Issues

None yet (MVP just released).

## Future Extensions

- [ ] Automated scoring comparison against human gold standard
- [ ] Pattern-by-pattern accuracy breakdown
- [ ] False positive analysis by category
- [ ] Confidence threshold tuning script
