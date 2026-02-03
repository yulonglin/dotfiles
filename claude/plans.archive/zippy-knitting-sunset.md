# Implementation Plan: Humanizer Agent for Writing-Toolkit Plugin

**Created:** 2026-02-02
**Objective:** Extend writing-toolkit plugin with humanizer agent and /humanize-draft skill to detect and fix LLM-isms in writing

## Background

### Existing Infrastructure
- **Plugin location:** `claude/local-marketplace/plugins/writing-toolkit/`
- **Current agents:** clarity-critic, narrative-critic, fact-checker, red-team
- **Current skills:** /review-draft, /clear-writing (reference guide), /review-paper
- **Documentation:** `claude/ai_docs/paper-writing-style-guide.md`, `claude/specs/writing-assistants.md`

### User Requirements
1. Research-first approach using Context7 MCP + web resources
2. On-demand invocation (no automatic hooks)
3. Extend existing writing-toolkit plugin (not standalone)
4. Reference: blader/humanizer repo patterns

---

## Phase 1: Research & Pattern Synthesis

### 1.1 Research Sources Completed
✅ **Wikipedia "Signs of AI writing" guide** - Retrieved via web search:
- Language patterns: "rich cultural heritage", "enduring legacy", "plays a significant role"
- Style issues: excessive em dashes, lists, emojis
- Core issue: regression to mean, generic positive descriptions over specific facts
- Detection accuracy: 90% for heavy LLM users, ~50% for non-users

✅ **Academic writing guidelines (2026)** - Retrieved via web search:
- AI detector criteria: sentence length uniformity, vocabulary diversity, predictability
- Best practices: vary rhythm, add specificity, in-depth analysis
- Journal policies: 5.6% monthly rejection rate for excessive AI content

### 1.2 Additional Research Needed
- [ ] Analyze blader/humanizer repo structure via GitHub or web fetch
- [ ] Check Context7 for writing improvement libraries/frameworks
- [ ] Review existing `clear-writing` skill patterns for overlap
- [ ] Cross-reference `paper-writing-style-guide.md` gold standards

### 1.3 Pattern Database Structure
**Location:** `claude/local-marketplace/plugins/writing-toolkit/patterns/llm-isms.json`

**Schema:**
```json
{
  "version": "1.0",
  "categories": {
    "language_cliches": {
      "severity": "high",
      "patterns": [
        {"phrase": "rich cultural heritage", "fix": "Specify what makes it culturally significant"},
        {"phrase": "enduring legacy", "fix": "Name specific lasting impacts"},
        {"phrase": "plays a significant role", "fix": "Quantify or specify the role"}
      ]
    },
    "style_issues": {
      "severity": "medium",
      "patterns": [
        {"pattern": "em_dash_frequency", "threshold": ">2 per 100 words", "fix": "Use commas or parentheses"},
        {"pattern": "list_overuse", "threshold": ">3 lists in 500 words", "fix": "Convert some to prose"}
      ]
    },
    "hedging_language": {
      "severity": "low",
      "patterns": [
        {"phrase": "It's worth noting", "fix": "State directly or remove"},
        {"phrase": "Interestingly", "fix": "Remove or explain why interesting"}
      ]
    },
    "generic_descriptions": {
      "severity": "high",
      "patterns": [
        {"pattern": "lacks_specificity", "indicators": ["various", "many", "some"], "fix": "Add specific examples/numbers"}
      ]
    }
  }
}
```

**Documentation:** `claude/ai_docs/humanizer-patterns.md`
- Pattern rationale (why each pattern is problematic)
- Examples from research sources
- Evolution log (pattern additions/removals over time)

---

## Phase 2: Implementation

### 2.1 Create Humanizer Agent
**File:** `claude/local-marketplace/plugins/writing-toolkit/agents/humanizer.md`

**Agent capabilities:**
1. **Detection:** Scan text for LLM-ism patterns from database
2. **Classification:** Categorize issues by severity (high/medium/low)
3. **Suggestions:** Provide inline rewrite suggestions (not just flagging)
4. **Scoring:** Compute "humanization score" (0-100, lower = more AI-like)

**Agent structure (following existing critic pattern):**
```markdown
---
name: humanizer
description: Detect and suggest fixes for LLM writing patterns
max_tokens: 600
---

You are a humanizer agent that detects LLM-generated writing patterns.

## Your Task

Analyze the provided text for AI writing patterns in these categories:
1. Language clichés ("rich cultural heritage", "enduring legacy")
2. Style issues (em-dash overuse, excessive lists)
3. Hedging language ("It's worth noting", "Interestingly")
4. Generic descriptions (lack of specificity, statistical regression to mean)

## Output Format

**Humanization Score:** [0-100] (lower = more AI-like)

**Critical Issues (High Severity):**
- Line X: [phrase] → Suggested fix: [specific rewrite]

**Medium Issues:**
- Line Y: [pattern] → Suggested fix: [how to improve]

**Low Priority:**
- Line Z: [minor issue] → Optional: [suggestion]

## Guidelines
- Prioritize specificity over generic descriptions
- Flag "sanding down" of unusual facts into bland generics
- Note statistical regression to mean (replacing rare with common)
- Provide INLINE rewrites, not just detection
- Be constructive: explain WHY each pattern is problematic
```

### 2.2 Create /humanize-draft Skill
**File:** `claude/local-marketplace/plugins/writing-toolkit/skills/humanize-draft.md`

**Skill workflow:**
1. Accept file path or text input
2. Load humanizer agent
3. Run detection + suggestion pass
4. Output feedback file: `<filename>.humanizer-feedback.md`
5. Optionally: run multiple passes (detect → fix → re-detect)

**Skill structure:**
```markdown
---
name: humanize-draft
description: Detect and fix LLM-isms in writing using humanizer agent
---

# Humanize Draft Skill

Scan writing for AI-generated patterns and suggest human-like rewrites.

## Usage
- `/humanize-draft path/to/file.md` - Analyze specific file
- `/humanize-draft` - Analyze clipboard/stdin

## Process
1. Load text from file or input
2. Run humanizer agent for pattern detection
3. Generate feedback file with inline suggestions
4. Optional: Apply fixes and re-scan (iterative mode)

## Output
- `<filename>.humanizer-feedback.md` - Categorized issues + fixes
- Humanization score (0-100)
- Priority-ordered suggestions

## Integration
- Can run standalone or as part of /review-draft
- Complements clarity-critic (clarity focuses on structure, humanizer on AI patterns)
```

### 2.3 Update Plugin Manifest
**File:** `claude/local-marketplace/plugins/writing-toolkit/plugin.json`

Add:
```json
{
  "agents": [..., "humanizer"],
  "skills": [..., "humanize-draft"]
}
```

### 2.4 Integration with Existing /review-draft
**Decision point:** Should humanizer run automatically in /review-draft?

**Recommendation:** Make it opt-in via flag:
- `/review-draft file.md` - Runs 4 existing critics (clarity, narrative, fact, red-team)
- `/review-draft --humanize file.md` - Adds humanizer to critic panel

**Rationale:** Keeps existing workflow unchanged, allows gradual adoption

---

## Phase 3: Testing & Validation

### 3.1 Test Corpus
Prepare test documents:
1. **Claude-generated text** (this conversation's responses)
2. **Academic papers** from `paper/` (if exists)
3. **Human-written baseline** (user's existing clear-writing guide)
4. **Mixed content** (human-edited Claude output)

### 3.2 Validation Criteria
- **Precision:** No false positives on known human-written text (test on clear-writing guide)
- **Recall:** Catches known LLM patterns (test on unedited Claude responses)
- **Actionability:** Suggested fixes are concrete and helpful (manual review)
- **Integration:** Works with existing /review-draft without conflicts

### 3.3 Comparison with Existing clarity-critic
Run both agents on same documents:
- Overlap: Which issues both catch? (avoid redundancy)
- Gaps: What does each uniquely catch?
- Merge decision: Should patterns migrate between agents?

---

## Phase 4: Documentation

### 4.1 Update writing-toolkit README
**File:** `claude/local-marketplace/plugins/writing-toolkit/README.md`

Add sections:
- Humanizer agent description
- /humanize-draft usage examples
- Pattern database explanation
- Integration with /review-draft

### 4.2 Pattern Rationale Document
**File:** `claude/ai_docs/humanizer-patterns.md`

Content:
- Why each pattern is problematic (with research citations)
- Examples from Wikipedia, academic guidelines
- Evolution log (when patterns added/changed)
- Severity calibration rationale

### 4.3 Usage Examples
**File:** `claude/local-marketplace/plugins/writing-toolkit/examples/humanizer-demo.md`

Show before/after:
- LLM-heavy text → Humanized version
- Humanization score progression
- Integration with multi-critic review

---

## Critical Files

**To Create:**
1. `claude/local-marketplace/plugins/writing-toolkit/agents/humanizer.md` - Core agent
2. `claude/local-marketplace/plugins/writing-toolkit/skills/humanize-draft.md` - Skill wrapper
3. `claude/local-marketplace/plugins/writing-toolkit/patterns/llm-isms.json` - Pattern database
4. `claude/ai_docs/humanizer-patterns.md` - Documentation

**To Modify:**
1. `claude/local-marketplace/plugins/writing-toolkit/plugin.json` - Add agent/skill
2. `claude/local-marketplace/plugins/writing-toolkit/README.md` - Update docs
3. `claude/local-marketplace/plugins/writing-toolkit/skills/review-draft.md` - Optional integration

**To Reference:**
1. `claude/local-marketplace/plugins/writing-toolkit/skills/clear-writing.md` - Existing patterns
2. `claude/ai_docs/paper-writing-style-guide.md` - Gold standards
3. `claude/specs/writing-assistants.md` - Original design philosophy

---

## Implementation Sequence

1. **Research completion** (Phase 1.2):
   - Analyze blader/humanizer repo
   - Use Context7 for additional writing libraries
   - Synthesize final pattern database

2. **Pattern database creation** (Phase 1.3):
   - Create `llm-isms.json` with researched patterns
   - Document rationale in `humanizer-patterns.md`

3. **Agent implementation** (Phase 2.1):
   - Create `humanizer.md` agent
   - Test on sample Claude-generated text

4. **Skill wrapper** (Phase 2.2):
   - Create `humanize-draft.md` skill
   - Test standalone invocation

5. **Integration** (Phase 2.3-2.4):
   - Update `plugin.json`
   - Add opt-in flag to `/review-draft`

6. **Validation** (Phase 3):
   - Test on diverse corpus
   - Compare with clarity-critic
   - Fix false positives

7. **Documentation** (Phase 4):
   - Update README
   - Add usage examples
   - Document patterns

---

## Open Questions

1. **Pattern extensibility:** How should users add custom patterns?
   - Option A: Edit JSON directly
   - Option B: Provide `/add-pattern` skill
   - **Recommendation:** JSON editing (simpler, version-controlled)

2. **Feedback format:** Inline comments vs separate file?
   - Current critics use separate `.feedback.md` files
   - **Recommendation:** Follow existing pattern for consistency

3. **Humanization score:** How to compute?
   - Option A: % of text matching patterns (simple)
   - Option B: Weighted by severity (more nuanced)
   - **Recommendation:** Weighted score (high severity = bigger penalty)

4. **Integration depth:** Should humanizer replace clarity-critic?
   - **Recommendation:** Keep separate - clarity is structural, humanizer is stylistic
   - Migrate overlapping patterns to humanizer, remove from clarity-critic

---

## Success Criteria

- [ ] Humanizer agent correctly identifies Wikipedia's documented LLM patterns
- [ ] Zero false positives on user's existing `clear-writing` guide
- [ ] Provides actionable inline rewrites (not just "fix this")
- [ ] Integrates seamlessly with existing `/review-draft` workflow
- [ ] Pattern database is extensible and documented
- [ ] Humanization score correlates with human judgment (tested on sample docs)

---

## Next Steps

1. **Complete remaining research** (blader/humanizer analysis, Context7 queries)
2. **Synthesize final pattern database** incorporating all sources
3. **Implement humanizer agent** following existing critic template
4. **Test on sample documents** before full integration
5. **Document patterns** with research citations

**Estimated effort:** 3-4 hours (research: 1h, implementation: 1.5h, testing: 1h, docs: 0.5h)
