# Plan: Critique & Improve "Agents in the Wild" Workshop Paper

## Source Analysis

Three parallel analyses identified issues across three dimensions:

### A. Inconsistencies with main.tex

| Issue | Workshop Paper | Main Paper | Data Source | Fix |
|-------|---------------|------------|-------------|-----|
| **GSM8K C³ recall** | 36.0% (correct) | 36.9% (wrong) | pw-gsm8k.md: 0.360 | Workshop correct; flag main.tex for separate fix |
| **TM-Haiku GSM8K** | Removed (correct) | Still present: "34.7%" (line 687) | pw-gsm8k.md: 0.347 | Workshop correctly removed; main.tex needs separate fix |
| **"Fundamentally harder"** | Used 2x (lines 65, 79) | Used ~3x | N/A | Soften to "substantially" — own results refute "fundamental" |
| **Figure 4 bars** | 4 bars (C³, TM-3B, LD, BP) | 5 bars (includes TM-Haiku) | N/A | Workshop correct; main.tex figure needs separate update |

**Note**: main.tex inconsistencies are out of scope for this plan. This plan fixes only `agents-in-the-wild.tex`.

### B. Workshop Fit (7.5/10 → target 9/10)

**Biggest risk**: Desk rejection because paper evaluates static benchmarks, not agents. The "Agents in the Wild" workshop expects multi-step agent scenarios, tool use, environment interaction.

**What's strong**: WMDP/Hendrycks connection, black-box approach, defense-in-depth, external auditor context.

**What's weak**: Generic LLM evaluation framing, no agent deployment pipeline specifics, no multi-step agent discussion.

### C. Research Quality Issues (Red-Team)

| Priority | Issue | Lines | Fix |
|----------|-------|-------|-----|
| **HIGH** | "Fundamentally harder" overclaimed — refuted by 36% GSM8K, 19% Meinke, 4.7% adversarial | 65, 79, 112 | Replace with "substantially" or "empirically" |
| **HIGH** | Agent framing unsupported by experiments | 64, 73, 81, 290 | Strengthen framing or be honest about scope |
| **HIGH** | 100% recall claims without CIs | 275 | Add bootstrap CIs |
| **MODERATE** | Adversarial results dismissed as "unrealistic" (line 259) | 259 | Reframe — deterministic recipes are informative |
| **MODERATE** | Embedding space unvalidated — no ablation on model choice | 147-152 | Acknowledge as limitation |
| **LOW** | Writing: "Why it fails" in italics reads as editorial | 162 | Rephrase |
| **LOW** | Temperature not reported for response generation | N/A | Add to methodology |

---

## Improvement Plan

### Step 1: Soften "Fundamentally Harder" Claims (3 locations)

**File**: `agents-in-the-wild.tex`

**Rationale**: The paper's own results (36% GSM8K, 19% Meinke, 4.7% adversarial) show the asymmetry is *not* fundamental — gradient optimization can learn consistent deception. Overclaiming undermines credibility.

1. **Line 112 (Section 3)**: "fundamentally harder to maintain" + "a fundamental asymmetry"
   → Change "fundamental asymmetry" to "empirical asymmetry"; change "fundamentally harder" to "empirically harder to maintain across independent API calls" and add caveat: "though this asymmetry diminishes under fine-tuning (Section~\ref{sec:password-locked})"

2. **Line 275 (Section 4.8)**: "remains fundamentally difficult"
   → Change to "remains difficult in practice" or "remains empirically difficult"

3. **Line 414 (Appendix)**: Same text as line 275 — "remains fundamentally difficult"
   → Change to match line 275 fix

4. **Line 595**: "fundamentally inverted" — this is inside a sandbagging prompt example text, keep as-is

### Step 2: Strengthen Agent Deployment Framing (Introduction + Discussion)

**Rationale**: This is the #1 desk rejection risk. The paper needs to explicitly connect static benchmark detection to agent safety pipelines without overclaiming.

**Introduction (lines 70-81)**:
- Add 2-3 sentences after the opening paragraph connecting sandbagging detection to **agent deployment gates**: "Before deploying autonomous agents with tool access, organizations must verify capability evaluations are genuine. An agent that evades dangerous capability evaluations could gain deployment access---including tool use, internet access, or code execution---that safety gates were designed to prevent."
- Mention that agents face **pre-deployment evaluation windows** with limited time (days, not weeks) matching our k=10 regime

**Discussion (lines 288-298)**:
- Expand "agent deployment pipelines" paragraph to be explicit about:
  - How C³ fits into staged deployment gates (evaluate → detect sandbagging → deploy)
  - Why black-box, zero-shot matters for external auditors evaluating agent capabilities
  - Cross-capability detection (§4.2) as directly relevant to agent versioning: generation N+1 mimicking generation N

**Section 4.2 cross-capability (lines 200-205)**:
- Add framing sentence: "This scenario directly mirrors agent deployment: when a frontier lab upgrades from generation N to N+1 agents, the newer agent could strategically match the older agent's evaluation profile to avoid triggering additional safety review."

### Step 3: Add Confidence Intervals for 100% Recall Claims

**Rationale**: Reporting "100% recall" without uncertainty quantification is a red flag for reviewers. With k=10 and 1000 bootstrap iterations, the CI is informative.

**Lines affected**: 275 (consistency instructions), 205 (cross-capability GPQA)

- Change "100% recall" to "100% recall (95% CI: [X, 100%])" — need to look up or compute the actual CIs from bootstrap data
- If CIs not available, acknowledge: "100% recall in our bootstrap evaluation (k=10, 1000 iterations); with finite samples, the true recall may be slightly lower"

### Step 4: Fix Adversarial Section Framing (§4.7)

**Lines 255-262**:

**Current problem**: Line 259 dismisses adversarial results as "unrealistic threat model" — but deterministic error recipes could emerge from RL fine-tuning, not just external instruction.

**Fix**: Reframe from "unrealistic" to "informative about C³'s failure mode":
- "These results reveal C³'s core limitation: when sandbagging follows a deterministic rule (e.g., always subtract 1), responses become consistent across paraphrases, eliminating C³'s signal. This represents a qualitatively different threat from prompted sandbagging — the space of possible wrong answers collapses to a single deterministic choice. While such recipes require specific engineering in prompted scenarios, fine-tuned models could potentially learn analogous deterministic patterns through gradient optimization."

### Step 5: Acknowledge Embedding Space Limitation

**Rationale**: Single embedding model with no ablation weakens the "framework agnostic" claim.

**Location**: Limitations paragraph (line 292)

**Add**: "Our current instantiation relies on a single embedding model (text-embedding-3-small); we have not ablated embedding model choice, though the framework is agnostic to the specific consistency metric."

### Step 6: Minor Writing Fixes

1. **Line 162**: Change "Why it fails:" italics to "Limitation:" — more scientific
2. **Line 162, 169, 173**: Apply same pattern to all baseline method descriptions (currently uses inconsistent "Why it fails" vs other patterns)
3. **Methodology**: Add response generation temperature to Section 3.1 if not already present

---

## Files to Modify

| File | Changes |
|------|---------|
| `workshops/iclr-2026/agents-in-the-wild/agents-in-the-wild.tex` | All changes above (Steps 1-6) |

## Verification

After edits:
```bash
cd workshops/iclr-2026/agents-in-the-wild && latexmk -pdf agents-in-the-wild.tex
```

Check:
- [ ] 0 undefined references
- [ ] No "fundamentally" when referring to the consistency-deception asymmetry
- [ ] Introduction explicitly connects to agent deployment gates
- [ ] Discussion expanded with agent deployment pipeline specifics
- [ ] 100% recall claims have CI caveats
- [ ] Adversarial section reframed constructively
- [ ] Embedding limitation acknowledged
- [ ] Paper compiles, ≤ 20 pages (same as before — changes are word-level, not structural)

## Scope Exclusions

These are flagged but NOT addressed in this plan:
- **main.tex C³ GSM8K number**: Reports 36.9% but data says 36.0% — needs separate fix
- **main.tex TM-Haiku**: Still shows 5-bar figure — needs separate figure regeneration
- **Adding agent-specific experiments**: Would require new data (SWE-bench, tool-use); not feasible for workshop deadline
- **Embedding model ablation**: Would require new experiments; acknowledge as limitation instead
