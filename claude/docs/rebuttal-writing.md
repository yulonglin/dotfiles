# Rebuttal Writing Reference

Synthesized from Devi Parikh's rebuttal guide and ML conference reviewing best practices.
Source: https://deviparikh.medium.com/how-we-write-rebuttals-dc84742fece1

---

## 1. Mindset

- **Two audiences**: the reviewers AND the Area Chair.
- The AC may only read the reviews and your rebuttal, not the paper itself. Write accordingly.
- **Litmus test**: "Would a neutral third-party who hasn't read the paper be convinced by this rebuttal alone?"
- This is a sociopolitical interaction, not a purely scientific one. Tone, framing, and perceived reasonableness matter as much as technical correctness.
- Peer review is "a large crowded marketplace" -- messy, chaotic, limited attention. You are competing for goodwill and careful reading. Make it easy for busy people to side with you.
- Reviewers have ego invested in their reviews. You will not change their mind by proving them wrong -- you change their mind by making them feel heard and then showing the evidence.
- Your goal is not to "win the argument." Your goal is to give the AC enough ammunition to champion your paper.

---

## 2. Process (4 Steps)

1. **Itemize** -- Extract every reviewer comment into a spreadsheet. One row per point. Columns: reviewer, comment, severity (critical / important / minor), response status.

2. **Brain dump** -- Each author independently drafts responses to all points. No coordination yet. This prevents groupthink and ensures the strongest arguments surface.

3. **Draft rebuttal** -- Merge the best responses into a single document. Identify shared concerns across reviewers and consolidate them. Prioritize by impact on the accept/reject decision.

4. **Review against originals** -- Re-read each review in full. Check: Did we miss anything? Did we address the spirit of the concern, not just the letter? Reorder by strength -- strongest responses first.

---

## 3. Structure Template

```
[POSITIVE SUMMARY]
Brief reminder of what the paper contributes and what reviewers praised.
Grounds the AC in the paper's strengths before addressing concerns.

[CONSOLIDATED RESPONSES]
Shared concerns raised by multiple reviewers, answered once.
"Reviewers A and C both raised..."

[REVIEWER-SPECIFIC RESPONSES]
Organized by reviewer, strongest responses first within each section.
For each concern: quote the comment -> direct answer -> explanation.

[ADDITIONAL EXPERIMENTS / RESULTS]
New evidence produced during the rebuttal period.
Tables, figures, or statistics that directly address concerns.

[SUMMARY OF CHANGES]
Bullet list of concrete revisions made or committed to.
```

**Formatting tips**:
- Color-code or clearly label by reviewer (R1, R2, R3) for easy scanning.
- Bold your direct answers so a skimming AC can extract your position instantly.
- Use the venue's rebuttal formatting conventions (most allow limited Markdown or LaTeX).
- Front-load: the AC may stop reading after the first page.

---

## 4. Response Patterns

### Direct Answer

**When to use**: Any factual or yes/no question.

> R2: "Did you evaluate on datasets beyond GPQA?"

**We evaluated on three datasets: GPQA Diamond, USACO, and MATH Level 5** (Section 4, Table 2). We additionally tested on WMDP for the password-locked setting (Section 5.1). We chose these to span multiple-choice, open-ended, and code generation formats.

*Principle*: Lead with the answer. "Yes, we did X" or "No, because Y." Then provide supporting detail.

---

### Intent Response

**When to use**: The literal question misses the reviewer's real concern.

> R1: "Why not use GPT-4 as a baseline?"

The underlying concern appears to be whether our method generalizes beyond the models tested. **We address this directly**: our evaluation spans 7 model families (Table 1) including both open and closed-weight models. We chose baselines that represent published detection methods rather than specific model families. We are happy to add GPT-4 results if the reviewer believes this would strengthen the evaluation.

*Principle*: Address what they actually care about, not just what they literally asked.

---

### Already-in-Paper

**When to use**: The answer is clearly in the paper but the reviewer missed it.

> R3: "The paper does not discuss computational overhead."

**We discuss computational costs in Section 4.3, paragraph 2 (lines 312-318)**, where we report that our method requires K paraphrases per question, adding approximately 5x the compute of a single evaluation pass. We will make this more prominent in the revised version by adding a dedicated "Computational Cost" paragraph header.

*Principle*: Always cite the specific section, figure, or line numbers. Never just say "it's in the paper." Restate the key point so the AC doesn't have to look it up. Offer to make it more visible.

---

### Data-Backed Disagreement

**When to use**: You believe the reviewer is factually wrong and you have evidence.

> R2: "The improvement over the baseline is not statistically significant."

**The improvement is statistically significant** (p < 0.01 by paired bootstrap test, 10,000 resamples). Specifically, our method achieves 67% recall at 5% FPR vs. 4% for the strongest baseline -- a 16.8x improvement (Table 3). We report 95% confidence intervals in Appendix B: [62.1%, 71.4%] for our method vs. [2.1%, 6.3%] for the baseline. These intervals do not overlap.

*Principle*: Lead with the numbers. Then provide intuition. Confidence intervals and effect sizes are more persuasive than p-values alone.

---

### Do-Don't-Promise

**When to use**: A reviewer asks for additional experiments or analysis.

> R1: "How does performance vary with the number of paraphrases K?"

**We ran this ablation during the rebuttal period.** Results below:

| K (paraphrases) | Recall@5%FPR | Runtime multiplier |
|---|---|---|
| 3 | 52.3% | 3x |
| 5 | 61.8% | 5x |
| 10 | 67.0% | 10x |
| 15 | 68.1% | 15x |

Performance plateaus around K=10. We will add this table and discussion to the camera-ready.

*Principle*: Show the result in the rebuttal itself. "We will run this experiment" is worth almost nothing. "Here are the results" is worth everything.

---

### Transparent Constraint

**When to use**: A requested experiment is genuinely infeasible and you want to explain why honestly.

> R3: "You should evaluate on frontier models with >100B parameters."

We agree this would strengthen the paper. **We were unable to run these experiments due to API cost constraints** -- evaluating our full pipeline on a frontier model would require approximately 50K API calls at ~$0.03/call ($1,500 per model), exceeding our compute budget for this study. We do evaluate on the largest openly available models (70B parameters). We will add this limitation explicitly to Section 6.

*Principle*: Be honest about constraints. Reviewers respect transparency more than hand-waving. Quantify the constraint if possible.

---

### Bad-Faith Spotlight

**When to use**: A reviewer makes claims that are unsubstantiated, contradicted by the paper, or apply an unreasonable standard. Use carefully and rarely.

> R2: "This is just paraphrasing inputs, which is trivial."

We respectfully note that this characterization does not engage with the paper's contribution. Paraphrasing is the mechanism; **the contribution is the theoretical framework connecting strategic underperformance to detectable inconsistency patterns** (Section 3), the detection algorithm (Section 3.2), and the empirical validation across 7 model families and 3 datasets (Section 4-5). We note that Reviewers 1 and 3 both highlighted the theoretical framework as a strength.

*Principle*: Do not attack the reviewer. State the facts. Let the AC draw conclusions. Highlight when other reviewers contradict the problematic one -- this gives the AC social permission to discount the outlier.

---

### Premise Disagreement

**When to use**: The reviewer's concern rests on an assumption you believe is incorrect.

> R1: "The threat model is unrealistic because model developers would simply prevent sandbagging through RLHF."

**We respectfully disagree with this premise.** The assumption that alignment training prevents sandbagging is precisely what recent work has challenged: Anthropic (2024) demonstrated that RLHF-trained models can still exhibit sandbagging behavior, and van der Weij et al. (2024) showed that password-locked sandbagging survives safety training. Our work addresses the detection problem *because* prevention is insufficient. This is discussed in Section 2.1 (Related Work) and Section 1 (Introduction, paragraph 3).

*Principle*: Name the disagreement explicitly. Provide citations. Don't pretend to agree when you don't -- ACs can tell, and it weakens your other responses.

---

## 5. Common Mistakes

- **Being defensive or combative.** The reviewer feels attacked and doubles down. Even when they are wrong, frame your response as clarification, not correction.
- **Promising future changes instead of showing them.** "We will add this" is weak. "Here is the result" is strong. If you can run it during the rebuttal period, do it.
- **Ignoring the AC as audience.** Everything you write should be legible to someone who has read only the reviews and your rebuttal.
- **Not citing specific lines/figures when claiming "it's in the paper."** Vague references ("as discussed in our paper") signal that it might not actually be there. Always: "Section X, lines Y-Z" or "Figure N, caption."
- **Burying strong responses after weak ones.** Your best evidence should appear in the first half of the rebuttal. Reviewers and ACs read front-to-back with declining attention.
- **Assuming the reviewer will re-read the paper.** They almost certainly will not. Restate key information in the rebuttal itself.
- **Not consolidating shared concerns.** If two reviewers raise the same issue, answer it once clearly rather than giving slightly different answers in each section. This also signals to the AC that you see the pattern.
- **Over-apologizing.** Acknowledging limitations is good. Excessive "we agree this is a weakness" language gives the AC reasons to reject rather than accept.

---

## 6. AC-Specific Tactics

- **Frame your strongest evidence early.** The AC decides the paper's fate. Put your best material where they will actually read it -- the first page of the rebuttal.
- **Make the AC's job easy.** The ideal outcome is that the AC can write: "The authors adequately addressed all major concerns raised during review." Write your rebuttal so that this sentence is obviously true.
- **If a reviewer is clearly wrong or acting in bad faith**, provide concrete evidence (line numbers, citations, contradictions with other reviewers) so the AC has justification to discount that review. Never ask the AC to discount a review without evidence.
- **Highlight inter-reviewer disagreements that favor you.** "We note that R1 and R3 specifically praised the theoretical framework that R2 characterizes as trivial." This gives the AC social proof.
- **Quantify consensus.** "Two of three reviewers rated novelty as high" is more persuasive than arguing novelty in the abstract.
- **Signal good faith.** Acknowledge the one or two points where reviewers genuinely identified room for improvement. ACs trust authors who concede valid points and distrust those who concede nothing.

---

## 7. Pre-Submission Checklist

- [ ] Every reviewer comment has a response (check against your itemized spreadsheet)
- [ ] Strongest responses appear in the first half of the rebuttal
- [ ] Shared concerns are consolidated, not duplicated across reviewer sections
- [ ] All "it's in the paper" claims include specific section/line/figure references
- [ ] New experiments or analyses are shown in the rebuttal, not just promised
- [ ] Tone check: would a stranger reading this think the authors are reasonable?
- [ ] AC test: can someone who hasn't read the paper follow the rebuttal?
- [ ] No promises without delivery -- every "we will add" is backed by concrete content
- [ ] Format fits within the venue's rebuttal page/word limit
- [ ] At least one co-author has reviewed the rebuttal against the original reviews end-to-end
