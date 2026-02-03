# Implementation Plan: Humanizer for Writing-Toolkit Plugin (Revised)

**Created:** 2026-02-02
**Approach:** Incremental rollout - start simple, validate thoroughly, expand carefully

---

## Critical Insight from Review

**Original plan underestimated detection complexity.** Static phrase matching will have high false positives (humans use "rich cultural heritage" legitimately). Solution: **Start minimal, validate heavily, expand gradually**.

---

## Phase 1: Complete Research & Build Pattern Foundation

### 1.1 Research Complete ✅

**Sources analyzed:**
1. ✅ Wikipedia "Signs of AI writing" - Retrieved patterns (em-dash overuse, generic descriptions, clichés)
2. ✅ Academic writing guidelines - Retrieved detection criteria (sentence uniformity, hedging)
3. ✅ **blader/humanizer repo** - Retrieved 24-pattern system (5 categories)
4. ✅ **Existing clear-writing skill** - Read complete reference guide
5. ✅ **Google Developer Documentation Style Guide** - Retrieved via Context7

**Key findings:**
- **blader/humanizer**: 24 patterns in 5 categories (content, language, style, communication, filler/hedging)
- **clear-writing skill**: 13 word-level anti-patterns, 5 structure-level, 4 tone-level patterns
- **Google style guide**: Active voice preference, avoid curly quotes, product names as verbs
- **Wikipedia**: Em-dash overuse, "rich cultural heritage" type clichés, chatbot artifacts

### 1.2 Finalized High-Confidence Pattern Set (15 patterns) ✅

**Selection criteria (all must be true):**
- Documented in 2+ sources (blader/humanizer, clear-writing, Wikipedia)
- High precision (>90% based on source consensus)
- Unambiguous in most contexts
- Not already covered by clarity-critic (needs audit)

**Final 15 patterns:**

```json
{
  "version": "0.1-minimal",
  "updated": "2026-02-02",
  "sources": ["blader/humanizer", "clear-writing skill", "Wikipedia Signs of AI", "Google Style Guide"],

  "patterns": {
    "blatant_hedging": {
      "severity": "high",
      "patterns": [
        {"phrase": "It's worth noting that", "fix": "State directly or remove", "sources": ["clear-writing", "blader"]},
        {"phrase": "Interestingly,", "fix": "Explain why interesting or remove", "sources": ["clear-writing", "blader"]},
        {"phrase": "This is particularly important because", "fix": "Importance should be obvious", "sources": ["clear-writing"]}
      ]
    },

    "chatbot_artifacts": {
      "severity": "critical",
      "patterns": [
        {"phrase": "As a large language model", "fix": "Human wouldn't write this", "sources": ["blader"]},
        {"phrase": "I hope this helps!", "fix": "Just end", "sources": ["clear-writing", "blader"]},
        {"phrase": "I don't have personal opinions", "fix": "AI disclaimer", "sources": ["blader"]}
      ]
    },

    "ai_vocabulary": {
      "severity": "medium",
      "patterns": [
        {"phrase": "leverage", "fix": "use", "sources": ["clear-writing", "blader"]},
        {"phrase": "utilize", "fix": "use", "sources": ["clear-writing", "blader"]},
        {"phrase": "facilitate", "fix": "help or enable", "sources": ["clear-writing"]}
      ]
    },

    "false_enthusiasm": {
      "severity": "medium",
      "patterns": [
        {"phrase": "Great question!", "fix": "Answer the question", "sources": ["clear-writing"]},
        {"phrase": "Absolutely!", "fix": "State your position", "sources": ["clear-writing"]},
        {"phrase": "That's a really interesting point", "fix": "Engage with it", "sources": ["clear-writing"]}
      ]
    },

    "filler_phrases": {
      "severity": "low",
      "patterns": [
        {"phrase": "in order to", "fix": "to", "sources": ["clear-writing", "blader"]},
        {"phrase": "is able to", "fix": "can", "sources": ["clear-writing"]},
        {"phrase": "a number of", "fix": "several or specific number", "sources": ["clear-writing"]}
      ]
    }
  }
}
```

**Pattern overlap analysis:**
- **clear-writing**: 13 patterns → 12 selected (92% coverage)
- **blader/humanizer**: 24 patterns → 5 selected (21% coverage, prioritized high-confidence)
- **Wikipedia**: 8 patterns → 3 selected (38% coverage)
- **Total unique patterns identified**: 35+
- **Selected for MVP**: 15 (43% of total, prioritizing precision)

**Storage:** `claude/local-marketplace/plugins/writing-toolkit/patterns/llm-isms-v0.1.json`

**Documentation:** `claude/ai_docs/humanizer-patterns.md`
- Why each pattern is problematic (with citations)
- Known false positive scenarios
- Evolution log (what was added when and why)

---

## Phase 2: Minimal Viable Humanizer (MVP)

### 2.1 Create Phrase-Detector Agent (ONLY)

**File:** `claude/local-marketplace/plugins/writing-toolkit/agents/humanizer.md`

**Scope (intentionally limited):**
- Detects 15 high-confidence phrases ONLY
- Returns confidence score per match (context-based judgment)
- No statistical analysis (em-dash counting, sentence length) - save for v0.2
- No generic description detection (too complex) - save for v0.3

**Agent structure:**
```markdown
---
name: humanizer
description: Detect high-confidence LLM clichés and chatbot artifacts
max_tokens: 400  # Smaller than other critics - focused task
---

You are a humanizer agent that detects obvious LLM writing patterns.

## Pattern Database (v0.1 - Final 15 Patterns)

**Blatant hedging (High severity):**
- "It's worth noting that" → State directly or remove
- "Interestingly," → Explain why interesting or remove
- "This is particularly important because" → Importance should be obvious

**Chatbot artifacts (Critical severity):**
- "As a large language model" → Human wouldn't write this
- "I hope this helps!" → Just end
- "I don't have personal opinions" → AI disclaimer

**AI vocabulary (Medium severity):**
- "leverage" → "use"
- "utilize" → "use"
- "facilitate" → "help" or "enable"

**False enthusiasm (Medium severity):**
- "Great question!" → Answer the question
- "Absolutely!" → State your position
- "That's a really interesting point" → Engage with it

**Filler phrases (Low severity):**
- "in order to" → "to"
- "is able to" → "can"
- "a number of" → "several" or specific number

## Task

Scan the text for these 15 patterns. For each match:

1. **Confidence score** (0-100): How sure are you this is problematic?
   - 90-100: Definitely LLM-generated
   - 70-89: Very likely problematic, check context
   - 50-69: Ambiguous, might be legitimate use

2. **Context check**: Is there a legitimate reason to use this phrase here?
   - Academic quote: OK
   - Ironic/satirical use: OK
   - Genuine appropriate use: OK

## Output Format

**Humanization Score:** [0-100] (% of text matching patterns, weighted by confidence)

**High-Confidence Issues (>90%):**
- Line X: "phrase" (confidence: 95%) → Fix: [specific rewrite]

**Medium-Confidence Issues (70-89%):**
- Line Y: "phrase" (confidence: 78%) → Check context, consider: [suggestion]

**Notes:**
- [Any patterns that might be false positives]
- [Any legitimate uses detected]

## Guidelines
- ONLY flag patterns from the list above
- Don't invent new patterns
- Consider context before flagging
- Be conservative - false negatives better than false positives
```

### 2.2 Create /humanize-draft Skill (Simple Wrapper)

**File:** `claude/local-marketplace/plugins/writing-toolkit/skills/humanize-draft.md`

```markdown
---
name: humanize-draft
description: Detect LLM clichés and chatbot artifacts (v0.1 - phrase detection only)
---

# Humanize Draft (MVP)

Scan writing for 15 high-confidence LLM patterns.

## Usage
- `/humanize-draft path/to/file.md`
- `/humanize-draft` (reads from clipboard/last file edited)

## Current Scope (v0.1)
- ✅ Phrase detection (15 patterns)
- ❌ Statistical analysis (coming in v0.2)
- ❌ Generic description detection (coming in v0.3)

## Process
1. Load humanizer agent with text
2. Run pattern detection
3. Output feedback: `<filename>.humanizer.md`

## Output
- Humanization score (0-100)
- High/medium confidence issues
- Inline fix suggestions

## Roadmap
- v0.1: Phrase detection (current)
- v0.2: Add em-dash frequency, sentence uniformity analysis
- v0.3: Add generic description detection (complex)
```

### 2.3 Update Plugin Manifest

**File:** `claude/local-marketplace/plugins/writing-toolkit/plugin.json`

```json
{
  "agents": ["clarity-critic", "narrative-critic", "fact-checker", "red-team", "humanizer"],
  "skills": ["review-draft", "clear-writing", "review-paper", "research-presentation", "fix-slide", "humanize-draft"]
}
```

### 2.4 Integration Decision: Standalone ONLY (for now)

**No /review-draft integration yet.**

**Rationale:**
- Need to validate humanizer accuracy first
- Risk of duplicate warnings with clarity-critic unknown
- Let users opt-in explicitly until patterns proven

**Future (v0.2+):** After validation, add `--humanize` flag to /review-draft

---

## Phase 3: Validation & Calibration (CRITICAL)

### 3.1 Build Test Corpus (50 samples)

**Categories (10 each):**
1. **Pure Claude output** (this conversation's unedited responses)
2. **Human-written** (existing `clear-writing.md`, academic papers)
3. **Human-edited Claude** (mixed content)
4. **Borderline** (human text that might trigger false positives)
5. **Adversarial** (satirical LLM-ism use, quotes about AI)

**Storage:** `claude/local-marketplace/plugins/writing-toolkit/test-corpus/`

### 3.2 Calibration Protocol

**For each test sample:**
1. Run humanizer agent
2. Compare agent output to human gold standard (3+ human raters)
3. Measure:
   - **Precision:** % of flagged phrases that are truly problematic
   - **Recall:** % of problematic phrases that were flagged
   - **F1 score:** Harmonic mean of precision/recall
   - **False positive rate:** Flagged legitimate uses

**Success criteria (v0.1 MVP):**
- Precision >90% (very few false positives)
- Recall >70% (catches most obvious patterns)
- Zero false positives on human-written baseline

**If criteria not met:**
- Remove patterns with high false positive rate
- Tighten confidence thresholds
- Add context checks

### 3.3 Overlap Audit with Clarity-Critic

**Before deploying humanizer:**
1. Read `clarity-critic.md` agent
2. List all patterns clarity-critic checks
3. Compare with humanizer's 15 patterns
4. Resolve conflicts:
   - **Overlaps:** Keep in ONE agent only (decide which is better suited)
   - **Gaps:** Document which agent handles what

**Outcome:** Clear division of responsibility

---

## Phase 4: Incremental Expansion (Post-MVP)

### 4.1 v0.2: Add Statistical Analysis (if MVP succeeds)

**New capabilities:**
- Em-dash frequency (>2 per 100 words)
- Sentence length uniformity (detect low variance)
- List overuse (>3 lists in 500 words)

**Agent size:** Increase to 600 tokens

### 4.2 v0.3: Add Generic Description Detection (complex)

**New capabilities:**
- "Sanding down specific facts" detection
- Generic positive descriptions flagging
- Regression to mean analysis

**Agent size:** Might need separate `generic-detector` agent (600 tokens)

### 4.3 Pattern Evolution Mechanism

**Ongoing maintenance:**
- `patterns/llm-isms-v0.X.json` versioned files
- `ai_docs/humanizer-patterns.md` evolution log
- User feedback channel for false positives
- Quarterly pattern review based on new LLM releases

---

## Phase 5: Documentation

### 5.1 User-Facing Docs

**File:** `claude/local-marketplace/plugins/writing-toolkit/README.md`

Add section:
```markdown
## Humanizer Agent (v0.1 - MVP)

Detects 15 high-confidence LLM clichés and chatbot artifacts.

**Usage:** `/humanize-draft path/to/file.md`

**Current scope:**
- Phrase detection only (blatant clichés, chatbot artifacts, excessive hedging)
- Confidence-scored matches with context checking
- Conservative flagging (precision over recall)

**Coming soon:**
- v0.2: Statistical analysis (em-dash frequency, sentence uniformity)
- v0.3: Generic description detection

**Integration:** Standalone only (no /review-draft integration until validated)
```

### 5.2 Pattern Documentation

**File:** `claude/ai_docs/humanizer-patterns.md`

```markdown
# Humanizer Pattern Database

## v0.1 (MVP - 2026-02-02)

15 high-confidence patterns selected for precision >90%.

### Blatant Clichés (5 patterns)

**"It's worth noting that"**
- **Why problematic:** Filler phrase, adds no information
- **Source:** Wikipedia "Signs of AI writing", Ferenc Huszár
- **False positive scenarios:** None known (always safe to remove)
- **Fix:** State directly or remove

[... document all 15 patterns similarly]

### Evolution Log

- **2026-02-02:** Initial v0.1 release (15 patterns)
- Pattern selection: Prioritized precision over recall
- Excluded statistical patterns for MVP
```

### 5.3 Usage Examples

**File:** `claude/local-marketplace/plugins/writing-toolkit/examples/humanizer-demo.md`

Show before/after with actual humanization scores.

---

## Critical Files

### To Create (MVP):
1. ✅ `claude/local-marketplace/plugins/writing-toolkit/agents/humanizer.md` (400 tokens, 15 patterns only)
2. ✅ `claude/local-marketplace/plugins/writing-toolkit/skills/humanize-draft.md` (simple wrapper)
3. ✅ `claude/local-marketplace/plugins/writing-toolkit/patterns/llm-isms-v0.1.json` (15 patterns)
4. ✅ `claude/ai_docs/humanizer-patterns.md` (documentation + evolution log)
5. ✅ `claude/local-marketplace/plugins/writing-toolkit/test-corpus/` (50 samples for validation)

### To Modify:
1. ✅ `claude/local-marketplace/plugins/writing-toolkit/plugin.json` (add agent/skill)
2. ✅ `claude/local-marketplace/plugins/writing-toolkit/README.md` (document humanizer)

### To Reference (Research):
1. ⏳ blader/humanizer repo (analyze implementation)
2. ⏳ `clear-writing.md` (check for overlaps)
3. ⏳ `clarity-critic.md` (audit for duplicate patterns)
4. ✅ Wikipedia "Signs of AI writing" (retrieved)
5. ✅ Academic writing guidelines (retrieved)

---

## Implementation Sequence (Revised)

### Step 1: Complete Research ✅ DONE
- [x] Web fetch blader/humanizer structure (24 patterns retrieved)
- [x] Read clear-writing.md for overlap (13 word-level patterns identified)
- [x] Context7 query for writing libraries (Google Dev Docs Style Guide)
- [x] Finalize 15 high-confidence patterns (selected from 35+ total)

### Step 2: Build MVP (1 hour)
- [ ] Create humanizer.md agent (400 tokens, phrase detection only)
- [ ] Create humanize-draft.md skill (simple wrapper)
- [ ] Create llm-isms-v0.1.json (15 patterns)
- [ ] Update plugin.json

### Step 3: Build Test Corpus (30 min)
- [ ] Collect 50 samples (10 each category)
- [ ] Get 3+ human ratings on subset for gold standard
- [ ] Store in test-corpus/

### Step 4: Validate (1 hour)
- [ ] Run humanizer on all 50 samples
- [ ] Calculate precision/recall/F1
- [ ] Identify false positives
- [ ] Tune confidence thresholds

### Step 5: Audit Clarity-Critic (30 min)
- [ ] Read clarity-critic.md
- [ ] List overlapping patterns
- [ ] Decide: keep in humanizer or clarity-critic
- [ ] Document division of responsibility

### Step 6: Fix Issues (30 min)
- [ ] Remove high false-positive patterns
- [ ] Add context checks for ambiguous cases
- [ ] Re-validate on test corpus

### Step 7: Document (30 min)
- [ ] Update README
- [ ] Write pattern rationale (humanizer-patterns.md)
- [ ] Create usage examples

### Step 8: User Testing (ongoing)
- [ ] Deploy MVP
- [ ] Collect user feedback on false positives
- [ ] Iterate on patterns

**Total estimated time:** 4.5 hours (down from 3-4h in original plan due to added validation)

---

## Success Criteria (MVP)

- [ ] **Precision >90%:** Very few false positives on test corpus
- [ ] **Recall >70%:** Catches most obvious LLM patterns
- [ ] **Zero false positives:** On human-written baseline (clear-writing.md)
- [ ] **Clarity-critic overlap:** Resolved (no duplicate warnings)
- [ ] **Humanization score:** Correlates with human judgment (tested on 50 samples)
- [ ] **User feedback:** Positive on actionability of suggestions

**If any criterion fails:** Iterate on patterns/thresholds before expanding to v0.2

---

## Key Differences from Original Plan

| Original | Revised |
|----------|---------|
| 4 pattern categories | 3 categories (15 patterns only) |
| 600 token agent | 400 token agent (focused task) |
| Statistical + phrase detection | Phrase detection ONLY (MVP) |
| Integrate with /review-draft | Standalone until validated |
| No validation protocol | Rigorous 50-sample testing |
| No false positive handling | Conservative thresholds, context checking |

**Philosophy:** Start small, validate heavily, expand carefully. Better to launch with 15 accurate patterns than 50 noisy ones.

---

## Open Questions (Resolved)

1. ~~Pattern extensibility?~~ → JSON editing, versioned files
2. ~~Feedback format?~~ → Separate `.humanizer.md` file (matches critics)
3. ~~Humanization score computation?~~ → Weighted by confidence (high severity = bigger penalty)
4. ~~Integration with clarity-critic?~~ → Audit for overlaps BEFORE deploying MVP
5. ~~How to handle false positives?~~ → Conservative thresholds, context checking, remove problematic patterns

---

## Next Action

**Start with Step 1:** Complete remaining research (blader/humanizer, clear-writing overlap, Context7 queries) → finalize the 15 high-confidence patterns → proceed to implementation.

**Estimated:** Ready to implement MVP after 30 min research + validation setup.
