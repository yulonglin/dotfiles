# ML Paper Excellence Reference

Consolidated advice from three sources for writing papers that win awards and survive peer review.

**Sources:**
- **[Nanda]** Neel Nanda, "Highly Opinionated Advice on How to Write ML Papers" (Alignment Forum)
- **[Carlini]** Nicholas Carlini, "How to Win a Best Paper Award" (2026)
- **[Parikh]** Devi Parikh, "How We Write Rebuttals"

**Companion doc:** `paper-writing-style-guide.md` covers sentence-level style, hedging language, and LaTeX formatting patterns extracted from gold-standard ICML papers. This document covers the higher-level strategic decisions.

---

## 1. Problem Selection & Research Design

### Choosing What to Work On

| Principle | Detail | Source |
|-----------|--------|--------|
| **Taste is the bottleneck** | The critical skill is identifying which problems are important before others do. Technical execution is necessary but not sufficient. | [Carlini] |
| **Read everything, then ignore it** | Survey the field deeply so you know what exists. Then set it aside to avoid unconsciously copying bad methodology or accepting bad framings. | [Carlini] |
| **Pick for impact, not publishability** | Avoid the "minimal publishable unit" mindset. Ask: would I still work on this if it weren't publishable? The best papers come from genuine intellectual obsession. | [Carlini] |
| **Paper = 1-3 specific claims** | A paper is not "an exploration of X." It is a small number of concrete, falsifiable claims bound by a cohesive theme. Define these before you start experiments. | [Nanda] |

### De-risking and Failing Fast

| Principle | Detail | Source |
|-----------|--------|--------|
| **Test the most-likely-to-fail component first** | Don't build infrastructure before checking whether the core idea works. Run the riskiest experiment in the first week. | [Carlini] |
| **Kill papers not working** | Sunk cost kills papers. If the core idea doesn't hold after honest testing, stop. Time spent on a dead paper is time stolen from a live one. | [Carlini] |
| **Pre-register your hypotheses** | Before running experiments, write down what you expect to find and why. This forces clarity and prevents post-hoc rationalization. | [Nanda] |

### Research Process

- **Write the paper as you research, not after.** The act of writing exposes gaps in your argument that experiments alone won't reveal. [Nanda]
- **Get feedback early and often.** Show the paper to colleagues when you think it's "not ready." Their confusion points directly at your weakest arguments. [Nanda]
- **Iterate the narrative, not just the results.** A paper with mediocre results and a compelling story beats a paper with great results and no story. [Nanda]

---

## 2. Writing the Paper

### Narrative & Claims

**One idea, expressible in a few words.** Every sentence in the paper should connect to this central idea. If an experiment doesn't serve the narrative, cut it regardless of how interesting it is. [Carlini]

| Do | Don't | Source |
|----|-------|--------|
| Define your 1-3 claims before writing | Let the paper's message emerge from the experiments | [Nanda] |
| Every section serves the narrative: intro motivates, experiments distinguish hypotheses | Include a section because "papers usually have one" | [Nanda] |
| State what changed your mind during research | Present results as if the outcome was always obvious | [Nanda] |
| Be precise with language; define terms on first use | Use jargon without definition or overload existing terms | [Nanda] |

### Abstract

**Structure (from [Carlini]):** Topic sentence > specific problem > your results (with numbers) > key details > why it matters.

- Include concrete numbers. "Our method achieves 67% recall at 5% FPR" not "Our method outperforms baselines." [Carlini]
- The abstract is the only part every reviewer reads carefully. Many ACs read only abstract + reviews + rebuttal. [Parikh]

### Introduction

**Write as a story [Carlini]:**
1. Where the reader is now (shared knowledge)
2. What bridge they need to cross into your world (the gap/problem)
3. What your contribution is (the payoff)

- The introduction is your one chance to frame how the reviewer interprets everything that follows. [Nanda]
- Enumerate contributions with bold claims and specific numbers. [Nanda]
- Acknowledge scope limitations briefly, frame as future work. [Nanda]

### Experiments & Evidence

**Quality over quantity.** Three compelling experiments beat ten mediocre ones. Each experiment should clearly distinguish between your hypothesis and an alternative. [Nanda]

| Requirement | Why | Source |
|-------------|-----|--------|
| **Strong baselines** | Weak baselines instantly trigger reviewer skepticism. Use the best known method, not a strawman. | [Nanda] |
| **Ablation studies** | For any method with multiple components, show which parts matter and by how much. | [Nanda] |
| **Statistical rigor** | Report confidence intervals. For exploratory results, aim for p < 0.001. Be transparent about which analyses were pre-registered vs. post-hoc. | [Nanda] |
| **Be locally optimal** | No obvious improvement should be left undone. If a reviewer can think of a straightforward extension, you should have already run it. | [Carlini] |
| **Anticipate skeptical questions** | Before submission, list every question a hostile reviewer would ask. Answer as many as possible in the paper. | [Carlini] |
| **Red-team your own claims** | Actively try to disprove your results. If you find holes, fix them or acknowledge them. | [Nanda] |

### Figures & Tables

| Principle | Source |
|-----------|--------|
| Each figure must be interpretable without reading the body text. The caption should contain the takeaway. | [Carlini] |
| Reviewers skim figures, abstract, and conclusion first. Your figures ARE your first impression. | [Nanda] |
| Figures should have clear, specific takeaways stated in the caption (bold first sentence). | [Nanda] |
| Conclusion is NOT the abstract in past tense. Answer "so what?" -- what should the field do differently now? | [Carlini] |

### Writing Quality

**From [Carlini]:**
- Read your paper aloud. Clumsy phrasing that looks fine on screen sounds obviously wrong when spoken.
- Watch for dual meanings and ambiguous pronoun references.
- Alternate long explanatory sentences with short declarative ones. This creates rhythm and aids comprehension.
- Know your specific reader: write for your 6-months-younger self. Would that person follow every step?

**From [Nanda]:**
- Be precise. "Our method works well" is meaningless. "Our method achieves 67% recall at 5% FPR on held-out USACO problems" is a claim.
- Define every term on first use. Assume the reader knows the field but not your specific setup.
- Cut mercilessly. If removing a paragraph doesn't weaken the argument, the paragraph was not contributing.

---

## 3. Reviewer Psychology

### How Reviewers Actually Read

| Fact | Implication | Source |
|------|-------------|--------|
| Reviewers spend 1-4 hours on your paper | Front-load your strongest material. Bury nothing important after page 6. | [Nanda] |
| They skim figures, abstract, conclusion first | These three elements must each independently convey the paper's value. | [Nanda] |
| They form an impression in the first 2 pages | Your intro must be airtight. A confused reviewer at page 2 stays confused. | [Nanda] |
| They are looking for reasons to reject | Make their job easy by anticipating and pre-empting objections. | [Nanda] |
| They have papers of their own they'd rather be working on | Respect their time. Eliminate every source of unnecessary cognitive load. | [Carlini] |

### Making the Reviewer's Job Easy

- **Signpost your arguments.** "We now show X" before showing X. "This rules out Y" after ruling out Y. [Nanda]
- **Address objections inline.** If a reasonable reader might object at paragraph 3, address it in paragraph 4, not in the appendix. [Nanda]
- **Put "unreasonable effort" into polish.** Typos, misaligned figures, and inconsistent notation signal carelessness. If you were careless with presentation, maybe you were careless with experiments too. [Carlini]

---

## 4. Responding to Reviews

### Know Your Audience

| Audience | What they read | What they need | Source |
|----------|---------------|----------------|--------|
| **Reviewer** | Full paper + their own review + your response | Evidence their concern was addressed | [Parikh] |
| **Area Chair** | Reviews + rebuttal (maybe skimmed paper) | Quick assessment of whether concerns are resolved | [Parikh] |
| **Neutral third party** | Only the reviews + rebuttal | Self-contained understanding of what was raised and how it was resolved | [Parikh] |

**Litmus test:** Would someone reading ONLY the reviews and rebuttal conclude that every concern was substantively addressed? [Parikh]

### Rebuttal Structure

1. **Open positive.** Remind the AC of strengths reviewers mentioned. Reviewers who gave mixed reviews often said good things -- highlight those. [Parikh]
2. **Order strongest responses first.** The AC might stop reading. Lead with your most decisive answers. [Parikh]
3. **Quote the concern, then answer DIRECTLY.** First sentence of your response should be the answer. Then explain. Not the reverse. [Parikh]
4. **Respond to intent, not just literal words.** A reviewer asking "why didn't you compare to X?" might really mean "I'm not convinced your method is better than existing work." Address the underlying doubt. [Parikh]

### Tactical Advice

| Do | Don't | Source |
|----|-------|--------|
| Use **bold** for key points -- ACs skim | Write dense paragraphs | [Parikh] |
| Cite specific line/figure numbers from the paper | Say "as discussed in the paper" without a reference | [Parikh] |
| Provide data, not arguments ("we ran the experiment; results in Table R1") | Promise future work ("we will add this experiment") | [Parikh] |
| Make responses self-contained (reader won't re-read paper) | Assume the AC remembers your paper's details | [Parikh] |
| Be transparent about compute/time constraints | Pretend you can do everything | [Parikh] |
| Get credit for things already in the paper ("see Section 4.2, lines 234-248") | Assume the reviewer noticed everything | [Parikh] |
| Actually add the requested experiment/discussion in a revision | Promise to add it in the camera-ready | [Parikh] |

### Handling Bad-Faith Reviews

- Spotlight it carefully. An AC is more likely to discount a clearly unreasonable review if you make the unreasonableness obvious without being combative. [Parikh]
- Remember: this is a sociopolitical interaction, not purely scientific. Tone matters. Be firm but collegial. [Parikh]
- If a reviewer is factually wrong, state the correction plainly with evidence. No sarcasm, no defensiveness. [Parikh]

---

## 5. Common Mistakes & Red Flags

### Fatal Sins

| Mistake | Why it kills your paper | Source |
|---------|------------------------|--------|
| **Overclaiming** | The #1 sin. Reviewers calibrate trust on your weakest claim. One overclaim poisons everything. | [Nanda] |
| **Weak baselines** | Signals either incompetence or dishonesty. Use the best known method. | [Nanda] |
| **Cherry-picking results** | If you only show the runs that worked, reviewers will assume the ones you hid didn't. | [Nanda] |
| **No ablations** | "Did component X actually help, or did Y do all the work?" If you don't answer this, the reviewer will. | [Nanda] |
| **Post-hoc as pre-hoc** | Presenting exploratory findings as if they were predicted. Be transparent. | [Nanda] |

### Avoidable Weaknesses

| Mistake | Fix | Source |
|---------|-----|--------|
| **Underselling** | State your contribution clearly and specifically. False modesty wastes the reviewer's pattern-matching. | [Nanda] |
| **Weak statistics** | Confidence intervals, not just point estimates. Multiple seeds. Report variance. | [Nanda] |
| **Figures that need the text** | If a figure requires reading three paragraphs to interpret, redesign the figure. | [Carlini] |
| **Conclusion = abstract (past tense)** | The conclusion should answer "so what?" and point forward. | [Carlini] |
| **Obvious experiments left undone** | If you can think of it in 5 minutes, the reviewer will too. Run it. | [Carlini] |
| **Sloppy presentation** | Typos, inconsistent notation, misaligned figures. Signals you didn't care enough. | [Carlini] |

---

## 6. Pre-Submission Checklist

### Problem & Claims
- [ ] Paper has exactly ONE central idea, expressible in a few words [Carlini]
- [ ] 1-3 specific, falsifiable claims clearly stated [Nanda]
- [ ] Each claim is supported by at least one experiment [Nanda]
- [ ] Pre-registered hypotheses are distinguished from post-hoc findings [Nanda]
- [ ] You have red-teamed your own claims and addressed the strongest counter-arguments [Nanda]

### Experiments
- [ ] Baselines are the strongest available, not strawmen [Nanda]
- [ ] Ablation studies show which components matter [Nanda]
- [ ] Confidence intervals or error bars on all quantitative results [Nanda]
- [ ] Multiple random seeds where applicable [Nanda]
- [ ] No obvious experiment a reviewer could request in 5 minutes [Carlini]
- [ ] Negative results and failure modes discussed honestly [Nanda]

### Narrative & Writing
- [ ] Abstract contains specific numbers and baseline comparisons [Carlini]
- [ ] Introduction tells a story: shared ground > gap > your contribution [Carlini]
- [ ] Every section serves the central narrative; nothing is "just because papers have this section" [Nanda]
- [ ] All terms defined on first use [Nanda]
- [ ] Read aloud with no stumbles [Carlini]
- [ ] Conclusion answers "so what?" and is not the abstract in past tense [Carlini]

### Figures & Presentation
- [ ] Every figure interpretable from caption alone [Carlini]
- [ ] Captions state the takeaway (bold first sentence) [Nanda]
- [ ] Consistent notation and color coding throughout [Nanda]
- [ ] No typos, misaligned figures, or formatting errors [Carlini]
- [ ] Page/word limits met (count main content only, not references/appendices)

### Reviewer-Proofing
- [ ] Anticipate the 3 most likely objections; they are addressed in the paper [Nanda, Carlini]
- [ ] No overclaiming -- weakest claim does not undermine strongest [Nanda]
- [ ] Strongest results appear in first 2 pages (figures or text) [Nanda]
- [ ] Abstract, figures, and conclusion each independently convey the paper's value [Nanda]

### Rebuttal Readiness
- [ ] Line/figure numbers easily citable in responses [Parikh]
- [ ] Key results have enough detail to be self-contained when quoted [Parikh]
- [ ] Limitations section is honest enough that reviewers can't "discover" unacknowledged weaknesses [Nanda, Parikh]
