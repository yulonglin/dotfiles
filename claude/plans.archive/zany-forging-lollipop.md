# Plan: Update Documentation with Detection Method Insights

## Summary

Update documentation to reflect insights from our discussion about:
1. Why indirect dependency probing doesn't work against strategic sandbaggers
2. UK AISI Auditing Games findings (nuanced view)
3. C³'s advantage of not requiring ground truth labels

## Key Refinements (from research-advisor feedback)

1. **Indirect probing**: Current docs say "hard to game" → should say "**trivial to game** for strategic sandbaggers"
2. **C³ ground truth claim**: Be precise - C³ doesn't need *per-sample correctness labels*, but still needs sandbagging/benign labels for evaluation
3. **Add caveat**: C³ hasn't been tested against finetuned/logit-matched sandbaggers (UK AISI style)
4. **Acknowledge**: Training-based elicitation worked in UK AISI (with false-positive issues)

## Files to Modify

### 1. `ai_docs/indirect_dependency_probing.md`

**Action**: Add deprecation warning at the top explaining the fundamental flaw

**Content to add** (after Overview section):

```markdown
## ⚠️ Critical Limitation: Ineffective Against Strategic Sandbaggers

**This method is DEPRIORITIZED** due to a fundamental logical flaw identified in analysis (Jan 2026):

### The Problem

The method assumes sandbagging models will "leak" knowledge by choosing the **correct** topic. But a strategic sandbagger would recognize this and deliberately choose the **wrong** topic to maintain consistency:

| Model Type | Main Task | Probe Topic | Reasoning |
|------------|-----------|-------------|-----------|
| Truly incapable | ❌ Wrong | ~50% random | Doesn't know answer |
| **Naive sandbagger** | ❌ Wrong | ✅ Correct | Knows but doesn't realize probe is a trap |
| **Sophisticated sandbagger** | ❌ Wrong | ❌ **Deliberately wrong** | Maintains consistent deception |

### Why This Matters

- The method only catches "naive" sandbaggers who don't realize the dependent task reveals their knowledge
- Any model sophisticated enough to sandbag strategically would also be sophisticated enough to fail the probe deliberately
- This creates a narrow and unrealistic threat model

### Literature Support

The UK AISI "Auditing Games" paper ([arXiv:2512.07810](https://arxiv.org/abs/2512.07810)) found that black-box behavioral methods were defeated when models effectively imitated weaker models. Strategic sandbaggers maintain consistency across all behavioral signals.

### Recommendation

Use other detection methods (C³, lie detectors, behavioral probes) instead. These measure behavioral patterns rather than attempting to "trap" knowledge leakage.
```

**Also update**: Move current "Strengths" claim about "Hard to game" to Limitations with correction.

---

### 2. `ai_docs/lit-review.md`

**Action**: Expand existing UK AISI Auditing Games section (lines 225-252) with more detail

**Content to add** (merge into existing section):

```markdown
**Blue Team Performance Details**:
- Assigned **>90% sandbagging credence to all three benign models**
- Assigned only **25% credence** to an actual sandbagger
- Their report concluded that sandbagger was "the only model that should be deployed"

**Blue Team Access**:
- Evaluation scores (aggregate performance on BIG-Bench Hard, BigCodeBench, Intercode CTF, GPQA Diamond, Tic Tac Toe)
- Trusted reference model (Llama-3.1-8B-Instruct) for comparison
- **No per-sample ground truth labels** during detection

**Sandbagging Mechanisms**:
- **Cedar**: Password via reserved special tokens before system prompt
- **Oak**: Password via tool formatting (two-space vs. four-space indentation)
- All sandbaggers finetuned from Llama-3.3-70B-Instruct using logit-matching distillation

**Critical Caveats**:
- Qualitative stress-test, not quantitative detection rates
- Only 10 model organisms, 1 blue team
- Red team used **finetuning** - more sophisticated than prompted sandbagging
- "No quantitative guarantees were provided"

**Implication for C³**:
- C³ doesn't require per-sample correctness labels (measures consistency, not correctness)
- Tested against **prompted** sandbagging - different threat model than finetuned
- Results against finetuned sandbaggers remain an open question
```

---

### 3. `specs/RESEARCH_SPEC.md`

**Action**: Add note in "Detection Methods" or "Key Terminology" section

**Content to add** (brief):

```markdown
### Black-Box Detection Limits

**Literature context** (UK AISI Auditing Games, arXiv:2512.07810):
- Black-box methods failed against finetuned password-locked sandbaggers
- But: tested against **finetuned** models using logit-matching distillation
- Our work tests against **prompted** sandbagging - different threat model

**C³ advantage**: Doesn't require ground truth labels. Measures response consistency across paraphrases regardless of correctness. This makes it applicable even when evaluators don't have per-sample labels.

**Indirect dependency probing**: Deprioritized - see `ai_docs/indirect_dependency_probing.md` for why it doesn't work against strategic sandbaggers.
```

---

## Implementation Order

1. Update `ai_docs/indirect_dependency_probing.md` with deprecation warning + fix "hard to game" → "trivial to game"
2. Expand UK AISI section in `ai_docs/lit-review.md` with detailed findings
3. Add brief note to `specs/RESEARCH_SPEC.md` about black-box limits and C³ advantage

## Notes

- No empirical indirect probing experiments run - deprecation based on theoretical analysis only
- Lit-review.md already has UK AISI section (lines 225-252) - will expand rather than create new
- Be precise about C³ "ground truth" claim: doesn't need per-sample correctness labels, but still needs sandbagging/benign labels for evaluation
