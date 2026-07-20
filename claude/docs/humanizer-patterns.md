# Humanizer Pattern Database

## Overview

This document explains the 31 high-confidence LLM-ism patterns used by the humanizer agent. Each pattern is documented with:
- **Why it's problematic** - with citations
- **False positive scenarios** - when NOT to flag
- **Fix suggestions** - concrete rewrites
- **Confidence level** - how certain we are it's LLM-generated

**Goal**: Precision >90% (very few false positives) and recall >70% (catch most obvious patterns).

**Categories**: 8 categories — Blatant Hedging (5), Chatbot Artifacts (4), AI Vocabulary (4), Em-Dash and Dash Misuse (2), False Enthusiasm (2), Filler Phrases (2), Structural/Rhetorical Tropes (9), Formatting Tells (3).

**Philosophy — detector, not rewriter**: This set flags and scores; it never rewrites. Upstream rewriter tools (e.g. blader/humanizer) mandate eliminating all em-dashes; we deliberately do not. Em-dashes are flagged on *frequency*, not presence — see Category 4.

---

## Pattern Catalogue

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

### Category 2: Chatbot Artifacts (4 patterns)

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

#### Knowledge-cutoff disclaimers
- **Why problematic**: "As of my last knowledge update" / "As of my training data" / "I may not have information about events after" are pure model-provenance artifacts. A human author has no knowledge cutoff to disclaim.
- **Confidence**: 97% (near-zero legitimate uses outside writing *about* LLMs)
- **Sources**: blader/humanizer (v0.4 addition)
- **False positives**: Writing that discusses LLM limitations and quotes such a disclaimer as an example. Check whether the phrase is quoted or attributed.
- **Fix**: Remove the disclaimer and date the claim explicitly if recency matters
  - ❌ "As of my last knowledge update, the model was state of the art."
  - ✅ "As of March 2026, the model was state of the art."

---

### Category 3: AI Vocabulary (4 patterns)

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

#### Promotional language (puffery)
- **Why problematic**: "rich cultural heritage", "stands as a testament to", "plays a vital role in", "a game-changer", "breathtaking". LLMs default to brochure register when they lack specifics — evaluative adjectives substitute for facts. Wikipedia's "Signs of AI writing" lists puffery as a primary tell.
- **Confidence**: 84% (register-dependent — legitimate in marketing copy, near-zero in technical or research writing)
- **Sources**: Wikipedia AI writing signs, blader/humanizer (v0.4 addition)
- **False positives**: Genuine marketing/advertising copy, travel writing, arts criticism where evaluative language is the point. Do not flag in those registers.
- **Fix**: Replace the evaluation with the evidence that would justify it
  - ❌ "The library plays a vital role in the modern Python ecosystem."
  - ✅ "The library is a dependency of pandas, scikit-learn, and PyTorch."
- **Note**: This partially subsumes the "generic positive descriptions" item previously deferred to the v0.4 roadmap.

---

### Category 4: Em-Dash and Dash Misuse (2 patterns)

LLMs vastly overuse em-dashes for parenthetical asides. This creates a distinctive "AI voice" even when individual word choices are fine.

#### Em-dash (—) parenthetical asides
- **Why problematic**: LLMs insert em-dashes at 3-5x the rate of human writers. Used as a crutch to shoehorn extra information into sentences instead of restructuring. A hallmark of AI-generated text per Wikipedia's "Signs of AI writing" (Ferenc Huszár).
- **Confidence**: 75% per instance (frequency-dependent — 1-2 per page is fine; 3+ per page is a strong signal)
- **Sources**: Wikipedia AI writing signs, blader/humanizer, clear-writing.md
- **False positives**: Legitimate stylistic use (Emily Dickinson, informal blogs). 1-2 per page is normal. Flag when clustered or when commas/parentheses would work better.
- **Fix**: Restructure using commas, parentheses, or separate sentences
  - ❌ "The model — which was trained on 1B tokens — achieved SOTA results."
  - ✅ "The model, trained on 1B tokens, achieved SOTA results."
  - ✅ "The model (trained on 1B tokens) achieved SOTA results."

#### Hyphens used as em-dashes ( - as parenthetical separator)
- **Why problematic**: LLMs frequently use ` - ` (space-hyphen-space) as a parenthetical separator, mimicking em-dash usage with worse typography. This is a strong LLM signal because human writers who use dashes typically use proper em-dashes or `--`.
- **Confidence**: 82% (LLMs do this frequently; humans rarely use bare ` - ` for asides)
- **Sources**: Typography conventions, AI writing detection
- **False positives**: Markdown list items, code contexts, plain-text emails where em-dash input isn't available.
- **Fix**: Restructure to avoid the aside, or use commas/parentheses
  - ❌ "The system - built last year - handles 10k req/s."
  - ✅ "The system, built last year, handles 10k req/s."
- **Note**: Double-hyphens (`--`) are not flagged as an LLM-ism since LLMs don't typically produce them, though they are typographically ugly.

---

### Category 5: False Enthusiasm (2 patterns)

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

### Category 6: Filler Phrases (2 patterns)

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

### Category 7: Structural/Rhetorical Tropes (9 patterns)

Higher-level structural patterns that go beyond individual phrases. These are rhetorical moves that LLMs overuse to create false drama, breadth, or authority.

**Source**: LinkedIn post by editors (via Helmuth Rosales), identifying common AI writing tropes that signal machine-generated content.

#### Negative parallelism
- **Why problematic**: "It's not X. It's Y." creates false drama through contrast. LLMs use this to sound punchy without substance.
- **Confidence**: 85% (can appear in skilled rhetoric, but LLMs overuse dramatically)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Deliberate rhetorical contrast in speeches, opinion pieces, or advertising copy
- **Fix**: State the actual point without the dramatic setup
  - ❌ "It's not bold. It's backwards."
  - ✅ "This approach is backwards."

#### Self-posed rhetorical questions
- **Why problematic**: "The worst part? Nobody saw it coming." manufactures suspense. LLMs use this as a structural crutch to create drama.
- **Confidence**: 85% (the "X? Y." fragment pattern is distinctive)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Genuine rhetorical questions in persuasive essays or speeches
- **Fix**: Integrate the point into the paragraph naturally
  - ❌ "The worst part? Nobody saw it coming."
  - ✅ "Nobody anticipated the failure."

#### False ranges
- **Why problematic**: "From X to Y to Z" tricolons with abstract nouns create an illusion of breadth without specifics. LLMs use these to sound comprehensive.
- **Confidence**: 87% (the "From [abstract] to [abstract] to [abstract]" form is distinctive)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Concrete, specific ranges ("from 10ms to 500ms to 3s")
- **Fix**: Be specific about what you actually mean
  - ❌ "From innovation to implementation to cultural transformation."
  - ✅ "We need to build it, ship it, and get teams to adopt it."

#### Gerund sentence fragments
- **Why problematic**: "Shipping faster. Moving quicker. Delivering more." Staccato fragments create false energy. LLMs use these for rhythm without content.
- **Confidence**: 92% (almost never natural in prose — very distinctive pattern)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Rare. Creative writing might use deliberately for effect.
- **Fix**: Write complete sentences with actual content
  - ❌ "Shipping faster. Moving quicker. Delivering more."
  - ✅ "We shipped three features this quarter with half the QA time."

#### False suspense transitions
- **Why problematic**: "Here's where it gets interesting" / "Here's the kicker" / "But here's the thing" — patronizing buildup that tells the reader to be excited instead of writing something actually interesting.
- **Confidence**: 90% (zero legitimate uses in professional writing)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Very rare. Casual blog posts might use ironically.
- **Fix**: Just state the interesting thing
  - ❌ "Here's where it gets interesting."
  - ✅ [Just write the interesting part directly]

#### Patronizing analogies
- **Why problematic**: "Think of it as a Swiss Army knife for your workflow." Dumbed-down comparisons that assume the reader can't handle the actual concept.
- **Confidence**: 88% (the "Think of it as..." pattern is very LLM-coded)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Genuine pedagogical writing for beginners, children's content
- **Fix**: Explain the actual thing, or use a precise analogy
  - ❌ "Think of it as a Swiss Army knife for your workflow."
  - ✅ "It handles formatting, linting, and testing in one tool."

#### Historical dash-enumeration
- **Why problematic**: "Every major shift — the web, mobile, social, cloud — followed the same pattern." Uses em-dash lists of historical examples to manufacture false authority and inevitability.
- **Confidence**: 82% (can be legitimate in historical analysis, but LLMs use it to avoid specifics)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Actual historical analysis with specific evidence for each example
- **Fix**: Pick one example and make a specific argument
  - ❌ "Every major technological shift — the web, mobile, social, cloud — followed the same pattern."
  - ✅ "Mobile adoption followed the same infrastructure-then-apps pattern we saw with the web."

#### Asserting obviousness
- **Why problematic**: "The reality is simpler and less flattering." / "Let's break this down." Claims insight or simplicity without delivering it. Used as a transition that sounds smart but says nothing.
- **Confidence**: 80% (most context-dependent — can appear in opinion pieces legitimately)
- **Sources**: LinkedIn AI tropes list
- **False positives**: Opinion journalism, analysis pieces where the author then delivers the insight
- **Fix**: Just deliver the insight without announcing it
  - ❌ "The reality is simpler and less flattering."
  - ✅ "The model memorized the training data."

#### Superficial "-ing" significance clauses
- **Why problematic**: A trailing participial clause that asserts importance without adding information: "…, highlighting the importance of collaboration." / "…, underscoring the need for caution." / "…, reflecting a broader trend in the industry." The clause restates the sentence at a higher altitude instead of extending it. LLMs use it to close paragraphs on a note of significance.
- **Confidence**: 86% (the trailing-comma-plus-participle-of-significance form is distinctive; bare participial clauses are normal English)
- **Sources**: blader/humanizer (v0.4 addition), Wikipedia AI writing signs
- **False positives**: Participial clauses that carry real content ("…, cutting latency from 400ms to 90ms"). The tell is a vacuous abstract object (importance, need, trend, shift, evolution), not the grammar itself.
- **Fix**: Delete the clause, or replace it with the concrete consequence
  - ❌ "Adoption doubled last quarter, highlighting the importance of developer experience."
  - ✅ "Adoption doubled last quarter, and support tickets fell 40%."

---

### Category 8: Formatting Tells (3 patterns)

Presentation-layer habits rather than word choice. These survive paraphrasing, which makes them useful signals even when the prose itself has been edited.

#### Decorative emoji in headings and bullets
- **Why problematic**: 🚀 ✨ 🎯 🔑 prefixed to headings or list items. Chat-tuned models add these as visual garnish; the emoji carries no information the heading doesn't already have.
- **Confidence**: 88% (high in professional prose, much lower in chat/social contexts)
- **Sources**: blader/humanizer (v0.4 addition)
- **False positives**: Chat messages, social posts, READMEs with an established emoji convention, status legends where the emoji is load-bearing (✅/❌ in a results table).
- **Fix**: Remove the emoji; keep the heading
  - ❌ "## 🚀 Getting Started"
  - ✅ "## Getting Started"

#### Excessive boldface
- **Why problematic**: Bold scattered across many mid-paragraph phrases. When everything is emphasised nothing is, and LLMs bold far more aggressively than human writers. Flag on density, not presence.
- **Confidence**: 78% (frequency-dependent — 1-2 bolded terms per section is normal; several per paragraph is the signal)
- **Sources**: blader/humanizer (v0.4 addition)
- **False positives**: Reference docs and glossaries where bold marks defined terms; tables and checklists where bold marks labels. This document's own pattern entries are a legitimate case.
- **Fix**: Keep bold for genuinely scannable labels; unbold in-sentence emphasis
  - ❌ "This is **critical** because the **latency budget** is **tight**."
  - ✅ "This matters because the latency budget is tight."

#### Title Case headings
- **Why problematic**: "How To Configure The Server" — LLMs default to Title Case for headings; most house styles (Google, Microsoft, AP-for-web) prescribe sentence case. Consistent Title Case across every heading is a stylistic fingerprint.
- **Confidence**: 72% (lowest-confidence pattern in the set — many legitimate house styles *do* use Title Case; flag only when it conflicts with the document's own prevailing style)
- **Sources**: Google Developer Documentation Style Guide, blader/humanizer (v0.4 addition)
- **False positives**: Publications whose style guide mandates Title Case; book and article titles; proper nouns. Never flag in isolation — flag only on inconsistency with surrounding headings.
- **Fix**: Match the document's prevailing heading case
  - ❌ "## Configuring The Retry Policy" (in a sentence-case document)
  - ✅ "## Configuring the retry policy"

---

## Patterns NOT Included

These high-value patterns still require statistical analysis the agent can't do by reading alone:

### Statistical Patterns (v0.5)
- **Em-dash frequency analysis**: Per-instance detection added in v0.3; statistical frequency threshold (>2 per 100 words) still pending
- **Boldface density threshold**: Per-instance detection added in v0.4; a real density metric is still pending
- **Sentence length uniformity**: Low variance (40-50 words consistently)
- **List overuse**: >3 lists per 500 words
- **Paragraph length uniformity**: Similar length throughout

### Detection Heuristics (v0.5)
- **Vague metrics**: "notably", "significantly", "substantially" without numbers
- **Sanding down specific facts**: Loss of precision in paraphrasing
- **Regression to mean**: Arguments becoming more generic over text

### Deliberately Rejected

| Pattern | Source | Why rejected |
|---------|--------|--------------|
| Zero-tolerance em-dash elimination | blader/humanizer | Conflicts with our frequency-based stance (Category 4). Em-dashes are legitimate punctuation; 1-2 per page is normal human writing. Adopting this would tank precision |
| Diff-anchored writing | blader/humanizer | Coding-agent artifact (prose that describes a change rather than the resulting state). Out of scope for draft review |
| Copula avoidance | blader/humanizer | Deferred, not rejected. We lack a characterisation precise enough to hit the >90% precision bar — needs a worked definition and test cases before adoption |

---

## Evolution Log

### v0.1 (2026-02-02)
- **Status**: Initial MVP release
- **Patterns**: 15 high-confidence patterns
- **Approach**: Phrase detection only (exact string matching)
- **Scope**: Prioritized precision over recall
- **Coverage**: ~43% of total identified patterns (15 out of 35+, phrase-level only)
- **Test Corpus**: 50 samples (10 per category)
- **Success Criteria**: Precision >90%, Recall >70%

**Selection rationale**:
- Analyzed 4 sources (blader/humanizer, clear-writing, Wikipedia, Google docs)
- Identified 35+ total patterns
- Selected top 15 with >2 source agreement
- Excluded statistical/heuristic patterns for MVP simplicity

### v0.2 (2026-03-11)
- **Status**: Added 8 structural/rhetorical trope patterns (Category 6)
- **Patterns**: 23 total (15 phrase-level + 8 structural)
- **New source**: LinkedIn AI tropes list (via Helmuth Rosales)
- **New patterns**: Negative parallelism, self-posed rhetorical questions, false ranges, gerund fragments, false suspense transitions, patronizing analogies, historical dash-enumeration, asserting obviousness
- **Key shift**: From phrase-only detection to structural pattern recognition

### v0.3 (2026-03-18)
- **Status**: Added em-dash and dash misuse patterns (Category 4)
- **Patterns**: 25 total (15 phrase-level + 2 dash misuse + 8 structural)
- **New patterns**: Em-dash parenthetical overuse, hyphens/double-hyphens used as em-dashes
- **Key shift**: Em-dash overuse moved from "statistical v0.3" to phrase-level detection (per-instance flagging with frequency context)

### v0.4 (2026-07-19)
- **Status**: Upstream reconciliation against blader/humanizer (33-pattern set) + three-way drift fix
- **Patterns**: 31 total (15 phrase-level + 2 dash misuse + 9 structural + 3 formatting + 2 vocabulary/artifact additions)
- **New patterns**: Knowledge-cutoff disclaimers, promotional language (puffery), superficial "-ing" significance clauses, decorative emoji, excessive boldface, Title Case headings
- **New category**: Formatting Tells (Category 8) — presentation-layer signals that survive paraphrasing
- **Key decision**: Adopted upstream's *patterns* but not its *philosophy*. blader/humanizer is a rewriter that mandates removing all em-dashes; we remain a detector with frequency-based em-dash scoring. See "Deliberately Rejected" above
- **Drift fix**: `llm-isms.json` had gone stale at 15 patterns / 5 categories while the doc and agent carried 25 / 7; the agent additionally claimed both "25" and "23" in different sections. All three now regenerate from this document
- **Canonical source**: This file. The agent prompt and patterns JSON in `ai-safety-plugins/plugins/writing/` are derived from it

### v0.5 (Planned)
- Statistical analysis: sentence length variance, list overuse, em-dash and boldface density thresholds
- Requires custom heuristics beyond phrase matching; might be a separate `generic-detector` agent

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

All 31 patterns were selected specifically to minimize false positives:

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
| Em-dash asides | Medium | 1-2 per page normal |
| Hyphen-as-em-dash | Low | Plain-text/code |
| Gerund fragments | Low | Rare creative use |
| False suspense | Low | Very rare ironic use |
| Patronizing analogies | Low | Pedagogical writing |
| Negative parallelism | Medium | Skilled rhetoric |
| Self-posed rhetorical | Medium | Persuasive essays |
| False ranges | Low | Concrete ranges OK |
| Historical dash-enum | Medium | Real historical analysis |
| Asserting obviousness | Medium | Opinion journalism |
| Knowledge-cutoff disclaimer | 0% | Only quoted-as-example |
| Promotional language | Medium | Marketing/travel/arts registers exempt |
| Superficial "-ing" clauses | Medium | Contentful participles OK |
| Decorative emoji | Low | Chat, README conventions, status legends |
| Excessive boldface | Medium | Glossaries, defined terms, table labels |
| Title Case headings | **High** | Only flag on inconsistency with document's own style |

**Conservative approach**: If uncertain, don't flag. False negatives are better than false positives.

---

## Integration with Other Critics

**clear-writing skill**: Covers general prose quality and word-level issues. Humanizer focuses on LLM-specific patterns.

**clarity-critic agent** (separate plugin): Checks for vague pronouns, hedging, run-ons, passive voice. Overlaps with humanizer's hedging patterns.

**Current integration**: Shipped as a critic on `/review-draft --critics=humanizer`. The former standalone `humanize-draft` skill is deprecated and now only points at that command.

**Consumers of this document** (regenerate when patterns change):
- `ai-safety-plugins/plugins/writing/agents/humanizer.md` — agent prompt
- `ai-safety-plugins/plugins/writing/patterns/llm-isms.json` — machine-readable pattern set

---

## Research Basis

### Sources

1. **blader/humanizer** — GitHub repo, 33 LLM-ism patterns in 5 groups as of the 2026-07-19 review (grown from 24 at first analysis)
   - Analyzed category system and pattern reasoning
   - Selected 5 patterns with highest confidence at v0.1; re-reviewed at v0.4 and adopted 6 more
   - **Philosophy differs**: blader is a rewriter that transforms text and mandates zero em-dashes. We are a detector. Patterns are portable across that boundary; the em-dash policy is not
   - Source: https://github.com/blader/humanizer

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

5. **LinkedIn AI Writing Tropes List** (via Helmuth Rosales)
   - 8 structural/rhetorical tropes commonly used by LLMs
   - Focus on higher-level patterns beyond individual phrases
   - Source for Category 6 patterns (v0.2)

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
