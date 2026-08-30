# Paper Review Rubric

Based on Neel Nanda's guide on writing ML papers.

## 1. Core Narrative Quality

- **Clear Claims**: 1-3 specific, concrete claims within a cohesive theme
- **Strong Motivation**: Why should readers care? ("So what?")
- **Proper Context**: Claims situated in existing literature; novelty explained
- **Compelling Takeaway**: Clear impact and implications for the field

## 2. Experimental Evidence Rigor

- **Hypothesis Distinction**: Experiments distinguish between competing hypotheses
- **Statistical Rigor**: Appropriate thresholds (p < 0.001 for exploratory work)
- **Trustworthy Results**: Reliability evidence, proper sample sizes, noise handling
- **Strong Baselines**: Meaningful comparisons, not just "decent" performance
- **Ablation Studies**: For complex methods, each component's contribution isolated
- **Diverse Evidence**: Multiple qualitatively different lines of evidence
- **Quality Over Quantity**: Compelling experiments over many mediocre ones

## 3. Scientific Integrity

- **Thorough Red-teaming**: Authors actively seek to break their own claims
- **Honest Limitations**: Weaknesses and boundaries acknowledged
- **Avoids Overclaiming**: Claims hedged appropriately based on evidence
- **Reproducibility**: Sufficient detail and ideally code for replication
- **Pre vs Post-hoc**: Clear distinction between predicted and observed results

## 4. Writing and Communication

- **Effective Abstract**: Motivates problem, states claims, indicates evidence, explains impact
- **Comprehensive Introduction**: Extended abstract with context and literature review
- **Clear Figures**: Visualizations communicate key results; good captions
- **Accessible Language**: Precise but not unnecessarily complex; key terms defined
- **Logical Structure**: Each section supports the overall narrative
- **Technical Detail**: Sufficient methods and results detail for expert evaluation

## 5. Novelty and Context

- **Clear Novelty Claims**: Explicitly states what is and isn't novel
- **Proper Citations**: Work contextualized within existing literature
- **Literature Integration**: Findings related to and extending prior work
- **Professional Critique**: Constructive, not dismissive, when discussing prior work

## 6. Process Indicators

- **Iterative Development**: Evidence of refinement
- **Compression First**: Core insights distilled before expansion
- **Evidence-Claim Alignment**: Experiments genuinely support stated claims
- **Reader-Centric**: Sufficient context; addresses illusion of transparency

## Red Flags

Flag these explicitly when found:

- **Cherry-picking**: Only the most favorable examples, no context
- **Weak Statistical Standards**: Marginal significance (0.01 < p < 0.05) presented as strong
- **Missing Baselines**: No comparison against reasonable alternatives
- **Overcomplexity**: Jargon or verbosity that obscures rather than clarifies
- **Narrative-Evidence Mismatch**: Claims not well-supported by experiments
- **Poor Reproducibility**: Insufficient detail for replication
