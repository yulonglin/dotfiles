# Paper Writing Style Guide

Gold standard style reference extracted from two exemplary ICML 2024 AI safety papers:
- **Debaters**: "Debating with More Persuasive LLMs Leads to More Truthful Answers" (Khan et al.)
- **AI Control**: "AI Control: Improving Safety Despite Intentional Subversion" (Greenblatt et al.)

---

## Title Patterns

| Style | Pattern | When to Use |
|-------|---------|-------------|
| **Empirical finding** | `[Verb-ing] with [Condition] [Verb] [Outcome]` | When main contribution is a surprising empirical result |
| **New concept** | `[Concept]: [Gerund] [Goal] Despite [Challenge]` | When introducing new terminology or methodology |

**Effective title elements:**
- Action-oriented gerund ("Debating", "Improving")
- Specific mechanism or condition
- Causal language (hedged: "Leads to", not "causes")
- Tension/counterintuitive element creates intrigue
- 8-12 words ideal

---

## Abstract Structure (5 Parts, ~200-250 words)

### 1. Problem Context (2-3 sentences)
Establish current limitation and future stakes.
> "Common methods for aligning LLMs with desired behaviour heavily rely on human-labelled data. However, as models grow increasingly sophisticated, they will surpass human expertise..."

### 2. Research Question (1 sentence)
Pose the core question explicitly.
> "In anticipation of this, we ask: can weaker models assess the correctness of stronger models?"

### 3. Method/Setup (2-3 sentences)
Describe experimental paradigm with concrete instantiation.
> "We investigate a setting in which we want to solve a sequence of programming problems without ever submitting subtly wrong code, using access to a powerful but untrusted model (in our case, GPT-4)..."

### 4. Key Results (2-3 sentences)
Specific quantitative findings with baselines.
> "We find that debate consistently helps both non-expert models and humans answer questions, achieving 76% and 88% accuracy respectively (naive baselines obtain 48% and 60%)."

### 5. Broader Implications (1 sentence)
State significance without overclaiming.
> "Our results provide encouraging empirical evidence for the viability of aligning models with debate in the absence of ground truth."

**Key techniques:**
- Parenthetical definitions: "(protocols)", "(in our case, GPT-4)"
- Concrete instantiation of abstract concepts
- Compare to baselines explicitly

---

## Introduction Structure (~1.5-2 pages)

### Opening: Problem Motivation (1 paragraph)
- Start with current practice, pivot to limitation
- Use forward-looking language for urgency
- "However... Consequently" structure for logical inevitability

> "Most existing approaches to align LLMs rely on the availability of labelled data. However, faced with models that can answer questions in increasingly broad context, obtaining such data requires domain expertise. As these systems continue to advance, they will surpass expert knowledge. Consequently, there will be no ground truth to rely on, rendering most alignment approaches unusable."

### Solution Space (1 paragraph)
- Name the broader research agenda with citations
- Use established terminology: "scalable oversight"

> "We need mechanisms that provide scalable oversight (Amodei et al., 2016; Christiano et al., 2018): alignment methods that scale with model capability."

### Research Question & Approach (1 paragraph)
- Frame as clear question
- Explain experimental paradigm concisely

> "Towards addressing the challenge of evaluating models without ground truth, we investigate the question: can debate aid weaker judges in evaluating stronger models?"

### Contributions (enumerated list)
Each item: **Bold claim** + supporting detail with numbers + baseline comparison

> "1. **Weak judges can supervise strong debaters.** The result holds both when using LLMs and when using humans to judge outputs. Specifically, for the most persuasive models we find that non-expert human judges achieve 88% and non-expert LLM judges achieve 76% accuracy with debate, where naive performance is 60% and 48% respectively."

### Scope & Significance (closing paragraph)
- Acknowledge limitations briefly
- Frame as future work opportunity

> "Although greater access to information is only one way in which future models may be stronger than their supervisors, our results pave the way for further research on adversarial oversight methods."

---

## Writing Style

### Sentence Rhythm
- **Short sentences** for key claims: "We call this approach AI control."
- **Longer sentences** for explanations with embedded citations
- Mix creates readable pace

### No Em Dashes
Em dashes (---) have become strongly associated with LLM-generated text. Never use them. Restructure using parentheses, colons, commas, semicolons, or separate sentences.

### Avoid LLM-isms
Never use: "Notably", "Importantly", "Crucially", "Interestingly" as openers; "This underscores/highlights"; "delve", "leverage", "utilize", "facilitate"; rhetorical questions as transitions; lists of three with ascending drama.

### Hedging Language (match certainty to evidence)
| Strength | Phrases |
|----------|---------|
| Strong | "we find that", "demonstrates" |
| Medium | "suggests that", "provides evidence for" |
| Weak | "might", "could", "may indicate" |
| Framing | "provides encouraging empirical evidence", "pave the way for" |

### Citation Style
- **Grouped** for established concepts: "(Amodei et al., 2016; Christiano et al., 2018; Irving et al., 2018)"
- **Single** for specific methods: "(Michael et al., 2023)"
- **Footnotes** for clarifying notes

### Voice
- **Active** for contributions: "We investigate", "We find", "We introduce"
- **Passive** for established methods: "Judges are not allowed access to..."

### Inline Definitions
- Parenthetical: "pipelines of safety techniques (protocols)"
- Appositive: "experts (i.e. stronger)" and "non-experts (i.e. weaker)"
- Italicized key terms: "We say a solution is *backdoored* if..."

---

## Figure & Table Design

### Hero Figure (Page 1-2)
**Purpose:** Main result visible at a glance

**Caption structure:**
1. **Bold main finding** (first sentence)
2. What the figure shows (technical)
3. Key definitions
4. Specific observations
5. Experimental details

> "**Across all judges, using debate helps to answer questions better than baselines.** Accuracy of non-expert judges using expert(s) to answer comprehension questions, and base- and toplines. Experts and expert judges have access to the underlying text. Non-expert judges do not..."

### Methods Figure (Page 2-3)
**Purpose:** Visual explanation of experimental setup

### Tables
**Caption structure:**
1. Summary statement
2. Variable definitions: "T is a trusted model (GPT-3.5), U is untrusted (GPT-4)..."
3. Metric definitions

**Design principles:**
- Figures near first mention in text
- Captions self-contained (understandable without body text)
- Consistent color coding across figures
- ~100 words for complex figure captions

---

## Rhetorical Moves

### Establishing Novelty
- Frame as forward-looking: "As these systems continue to advance..."
- Use anticipation language: "In anticipation of this, we ask..."
- Distinguish from prior work: "taking inspiration from Irving et al. (2018), but operationalised differently"

### Establishing Importance
- Connect to fundamental challenge: "rendering most alignment approaches unusable"
- Use field terminology: "scalable oversight"
- Cite foundational work liberally

### Establishing Contribution
- Enumerated findings with bold headers
- Specific numbers in claims
- Explicit baseline comparisons: "where naive performance is 60%"
- State result AND implication

### Handling Limitations
- Acknowledge scope directly but briefly
- Frame as future work opportunity: "pave the way for further research"
- List multiple possible causes (hedging)

### Adversarial Framing (for robustness work)
- Named teams: "blue team", "red team"
- Clear winning conditions
- Explicit resource enumeration

---

## Page Count Rules

When deciding how many pages to cut, count only the main content. Do not include:
- References
- Acknowledgements
- Appendices or supplementary material
- Impact or ethics statements
- LLM or AI usage statements
- Compute or resource statements
- Similar compliance or metadata sections

---

## Checklist

### Title
- [ ] States method/concept, condition, and outcome
- [ ] Uses mild causal language (not overclaiming)
- [ ] Contains tension or counterintuitive element
- [ ] 8-12 words

### Abstract
- [ ] 5 clear parts: problem, question, method, results, implications
- [ ] Concrete numbers with baseline comparisons
- [ ] Parenthetical definitions for new terms
- [ ] ~200-250 words

### Introduction
- [ ] Opens with current practice → limitation pivot
- [ ] Research question stated explicitly ("we ask", "we investigate")
- [ ] Contributions enumerated with bold claims + specifics
- [ ] Numbers include baseline comparisons
- [ ] Limitations acknowledged with forward-looking framing

### Figures
- [ ] Hero figure on page 1-2 showing main result
- [ ] Captions begin with bold summary finding
- [ ] Captions self-contained (~100 words for complex figures)
- [ ] Consistent visual language across figures

### Writing Style
- [ ] Hedging matches evidence strength
- [ ] Active voice for contributions
- [ ] Inline definitions via parentheticals
- [ ] Mixed sentence lengths for rhythm
- [ ] Citations grouped for concepts, single for specific methods

---

## Source Papers

- **Debaters**: Khan et al. (2024). "Debating with More Persuasive LLMs Leads to More Truthful Answers." ICML 2024. https://arxiv.org/abs/2402.06782
- **AI Control**: Greenblatt et al. (2024). "AI Control: Improving Safety Despite Intentional Subversion." ICML 2024. https://openreview.net/forum?id=KviM5k8pcP
