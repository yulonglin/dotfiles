# Response Structure for Critical Analysis

## 1. Empathetic Context Setting

"This paper makes some bold claims about X, so it's worth carefully examining the evidence…"

## 2. Methodological Breakdown

- **Key decisions**: "The authors made several critical choices: (1) using dataset X because…, (2) excluding baseline Y due to…, (3) focusing on metric Z rather than…"
- **Sensitivity factors**: "Based on the ablations (Table 4), the results seem most sensitive to…"
- **Implementation details**: "A crucial detail buried in Appendix C shows they…"

## 3. Evidence Assessment

- **Strong evidence**: "The claim about X is well-supported by experiments across Y datasets…"
- **Weak spots**: "The evidence for Y is more limited - they only test on…"
- **Missing pieces**: "I don't see validation of assumption Z, which could affect…"

## 4. Positioning and Context

- **Relationship to field**: "This extends [Prior Work] but differs crucially in…"
- **Controversial aspects**: "Their claim that X contradicts the general view that…"
- **Missing comparisons**: "Notable that they don't compare against [Recent Method] which…"

## Quality Safeguards

**For methodological analysis:**

- Only describe choices explicitly mentioned or clearly inferable from results/figures
- Distinguish between what authors acknowledge as limitations vs. your assessment
- When critiquing, base it on what's presented (or notably absent) in the paper

**For evidence evaluation:**

- Point to specific experiments, sample sizes, statistical tests when assessing strength
- Separate correlation from causation based on experimental design
- Note when authors themselves express uncertainty about robustness

**Example responses:**

**Good**: "The authors test their method on 3 datasets (Section 4.1) but acknowledge in Section 6 that all are from similar domains. The performance drop from 85% to 72% when changing hyperparameter X (Figure 5) suggests results are quite sensitive to this choice."

**Avoid**: "The method seems robust and generalizable." [Not grounded in specific evidence]

**When evidence is mixed**: "The paper provides strong evidence for claim X through randomized trials (Table 2), but their support for claim Y relies mainly on correlational analysis (Section 4.3) which the authors note 'suggests but doesn't prove' the relationship."
