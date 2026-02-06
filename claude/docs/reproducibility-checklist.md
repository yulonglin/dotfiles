# NeurIPS Paper Reproducibility Checklist

Source: https://neurips.cc/public/guides/PaperChecklist

## Overview

The NeurIPS Paper Checklist promotes responsible ML research by addressing reproducibility, transparency, ethics, and societal impact. **Papers without the checklist face desk rejection.** The checklist follows references and supplementary material but doesn't count toward page limits.

When deciding how many pages to cut, count only the main content. Do not include:
- References
- Acknowledgements
- Appendices or supplementary material
- Impact or ethics statements
- LLM or AI usage statements
- Compute or resource statements
- Similar compliance or metadata sections

## Response Format

For each question, answer: **Yes**, **No**, or **N/A** with optional justification (1–2 sentences). Answers are visible to reviewers, area chairs, senior area chairs, and ethics reviewers.

## Key Principles

- **"Yes" is preferable but not required**—proper justification for "No" is acceptable
- All supporting evidence may appear in main paper or appendix
- Reviewers won't penalize transparent discussion of limitations
- Answers are integral to peer review and final publication

---

## The 16 Checklist Questions

### 1. Claims
**Question:** Do primary claims in the abstract and introduction accurately reflect contributions and scope?

**Guidelines:** Results should match theoretical/experimental evidence regarding generalizability. Include assumptions and limitations clearly.

### 2. Limitations
**Question:** Does the paper include a dedicated "Limitations" section?

**Guidelines:** Create a separate "Limitations" section addressing:
- **Strong assumptions:** What assumptions does your method rely on?
- **Robustness to violations:** What happens if assumptions don't hold?
- **Scope constraints:** Limited to few datasets, specific domains, small-scale experiments
- **Performance factors:** What affects when method works well vs. poorly?
- **Real-world implications:** Practical deployment considerations

**Important:** "Reviewers will be specifically instructed to not penalize honesty." Transparent limitations discussion demonstrates scientific rigor and won't hurt your acceptance chances.

### 3. Theory, Assumptions & Proofs
**Question:** Are all theoretical results accompanied by complete proofs and stated assumptions?

**Guidelines:** State full assumptions for all theoretical results. Include complete proofs (main paper or supplement). Provide proof sketches in supplementary material for intuition.

### 4. Experimental Reproducibility
**Question:** Have you described steps taken to ensure reproducibility or verifiability?

**Guidelines:** Provide "reasonable avenue for reproducibility" appropriate to contribution type:
- **Algorithms:** Paper must clarify reproduction methodology with sufficient algorithmic detail
- **Model architectures:** Full architectural description required (layers, dimensions, activation functions, etc.)
- **Large models:** Either enable model access OR provide reproduction instructions (e.g., open-source datasets, construction guidelines)
- **Closed-source models:** Limited access acceptable if "other researchers have some path to reproducing or verifying results"

The key is ensuring readers can verify results through appropriate means, whether full reproduction or verification.

### 5. Open Access to Data & Code
**Question:** Do you provide code, data, and instructions for reproducing main results?

**Guidelines:** Should include:
- **Exact commands** and environment specifications for result reproduction
- Coverage of **main experimental results** (your new method + baselines)
- Note which experiments are reproducible if only providing partial coverage
- **Anonymous versions** required at submission for blind review
- Acceptable "No" justifications: "code is proprietary", central contribution doesn't require code release
- Can provide URL to code repository or include in supplementary material

While strongly encouraged, code/data release isn't mandatory if properly justified.

### 6. Experimental Settings/Details
**Question:** Are training details specified (data splits, hyperparameters, selection methods)?

**Guidelines:** Provide sufficient detail for readers to "appreciate the results and make sense of them":
- **Data splits:** Train/validation/test partitioning, cross-validation folds
- **Hyperparameters:** Learning rates, batch sizes, number of epochs, regularization parameters
- **Hyperparameter selection methodology:** Grid search, random search, Bayesian optimization, manual tuning
- **Other settings:** Random seeds, initialization methods, optimization algorithms

**Where to put details:**
- **Main paper:** Important details necessary to understand results
- **Code/supplement:** Full exhaustive details and minor parameters

The goal is ensuring readers can understand what you did without requiring code archaeology.

### 7. Statistical Significance
**Question:** Do you report error bars, confidence intervals, or statistical significance tests for main claims?

**Guidelines:** For each error bar or confidence interval, specify:

**1. What variability it captures:**
- Train/test split randomness
- Initialization randomness
- Random parameter drawing (e.g., dropout masks)
- Multiple runs with different seeds
- Cross-validation folds

**2. How it was calculated:**
- Closed-form formula (cite equation/theorem)
- Library function (name function and package)
- Bootstrap or Monte Carlo sampling
- Standard statistical tests (t-test, ANOVA, etc.)

**3. What the numbers represent:**
- Standard deviation vs. standard error (clarify explicitly!)
- Confidence level (e.g., 95% CI)
- Number of samples/runs used

**4. Special considerations:**
- For non-normal distributions, avoid symmetric error bars that "yield results that are out of range" (e.g., negative probabilities)
- Reference figures/tables in text, explaining calculations

**Internal methodology:** See `~/.claude/docs/ci-standards.md` for our standardized CI computation (n = questions not seeds, paired comparisons, power analysis)

### 8. Compute Resources
**Question:** Do you provide information on required compute resources?

**Guidelines:** Specify compute requirements in detail:

**Per experimental run:**
- **Compute type:** CPU vs GPU vs TPU
- **Hardware specifics:** GPU model (e.g., NVIDIA A100), number of workers
- **Memory:** RAM and VRAM requirements
- **Storage:** Disk space needed
- **Execution time:** Wall-clock time per run or experiment

**Overall project compute:**
- **Total compute budget:** Sum across all experiments
- **Cloud provider:** If using AWS, GCP, Azure, etc. (helps with cost estimation)
- **Additional experiments:** Disclose whether full project required more compute than experiments reported in paper

**Example good disclosure:**
"Each training run used 8x NVIDIA A100 GPUs (40GB VRAM) with 512GB RAM, taking ~48 hours. Total project compute: ~20,000 GPU-hours across 50 experimental runs and hyperparameter sweeps."

This helps readers assess reproducibility feasibility and environmental impact.

### 9. Code of Ethics
**Question:** Do you confirm compliance with the NeurIPS Code of Ethics?

**Guidelines:** Explain any deviations due to special circumstances while maintaining anonymity.

### 10. Broader Impacts
**Question:** Do you discuss potential negative societal impacts?

**Guidelines:** Address negative societal impacts where applicable:

**When required:** Distinguish between foundational research (minimal direct applications) vs. work with clear deployment paths

**What to cover:**
- **Malicious uses:** Potential for disinformation, surveillance, harmful content generation
- **Fairness concerns:** Bias amplification, disparate impact on different groups
- **Privacy issues:** Data leakage, re-identification risks
- **Security vulnerabilities:** Attack surfaces, adversarial exploitation

**Harm categories to consider:**
- **Intended use harms:** Problems even when used as designed
- **Malfunction harms:** Issues from bugs, failures, edge cases
- **Misuse harms:** Deliberate weaponization or abuse

**Mitigation strategies (if relevant):**
- Gated release policies
- Defensive mechanisms
- Monitoring and auditing systems
- Usage guidelines or restrictions

### 11. Safeguards
**Question:** For high-risk models, have you implemented appropriate safeguards?

**Guidelines:** Models with high misuse risk need "controlled use" mechanisms:

**When applicable:** Language models, dual-use systems, models trained on sensitive data

**Safeguard types:**
- **Usage guidelines:** Clear documentation of intended/prohibited uses
- **Access restrictions:** API keys, rate limiting, tiered access
- **Technical controls:** Content filters, output monitoring
- **Terms of service:** Legal agreements for model access

**For internet-scraped datasets:**
- Describe how you "avoided releasing unsafe images" or harmful content
- Document filtering/moderation procedures
- Explain any manual review processes

### 12. Licenses
**Question:** Do you cite original creators and respect licenses for existing assets?

**Guidelines:** For all existing assets (code, data, models) used:

**Required information:**
- **Original papers/creators:** Proper citations
- **URLs:** Links to source repositories or datasets
- **Asset versions:** Specific version numbers or commit hashes
- **License names:** E.g., MIT, Apache 2.0, CC-BY 4.0, GPL
- **Terms of service:** Check and comply with usage terms

**For scraped data:**
- Document data sources with copyright information
- Verify compliance with websites' terms of service
- Note any restrictions on redistribution

**Why this matters:** Protects both you (legally) and original creators (credit), enables proper reproducibility (exact versions).

### 13. Assets
**Question:** For new releases, have you documented datasets/models/code with structured templates?

**Guidelines:** Document new assets via structured templates (e.g., Datasheets for Datasets, Model Cards):

**What to include:**
- **Training details:** How the dataset was collected, how the model was trained
- **Licensing:** What license you're releasing under
- **Limitations:** Known issues, biases, failure modes
- **Intended use:** What the asset is designed for
- **Out-of-scope uses:** What it shouldn't be used for

**Human data considerations:**
- **Consent:** Discuss whether people whose data was used gave informed consent
- **Privacy:** Describe anonymization or de-identification procedures
- **Compensation:** If applicable, how participants were compensated

**Submission requirements:**
- **Anonymize assets** at submission time (for blind review)
- Can provide anonymous links or include in supplementary material

### 14. Crowdsourcing & Human Subjects
**Question:** Do you include full participant instructions, screenshots, and compensation details?

**Guidelines:** For studies involving crowdsourcing or human subjects:

**Required documentation:**
- **Full participant instructions:** Exact text shown to participants
- **Screenshots:** Visual documentation of interfaces/tasks
- **Compensation details:** Payment amounts and structure
- Can include in supplementary material unless human subjects are the main contribution

**Critical requirement:** "You must pay workers...at least the minimum wage" per NeurIPS Code of Ethics

**Where to document:**
- Main paper: Overview and key details
- Supplement: Full instructions, all screenshots, detailed protocols

### 15. IRB Approvals
**Question:** Have you obtained Institutional Review Board approval where required?

**Guidelines:** Follow IRB requirements per your jurisdiction and institution:

**What to include:**
- **Description of participant risks:** Physical, psychological, privacy risks
- **IRB approval statement:** Clear statement of approval status
- **Relevant details:** Protocol number, approval date (if not breaking anonymity)

**Important considerations:**
- State approval "clearly without breaking anonymity" during initial submission
- Follow "NeurIPS Code of Ethics and guidelines for your institution"
- Different jurisdictions have different IRB requirements
- Some low-risk research may be exempt (document exemption)

**If no IRB required:** Briefly explain why (e.g., "Study used only publicly available data with no identifiable information")

### 16. LLM Usage Declaration
**Question:** Do you describe LLM usage if it's an important methodology component?

**Guidelines:** Declare LLM usage only in specific circumstances:

**Declaration required when:**
- LLMs are part of core methodology
- LLM usage is "important, original, or non-standard"
- LLMs generate training data, perform evaluations, or augment experiments
- Novel prompting techniques or LLM-based pipelines

**Declaration NOT required when:**
- LLM use limited to writing, editing, or formatting text
- Standard use as writing assistant
- Grammar checking or text polishing

**What to describe (when required):**
- Which LLM(s) used (model name, version)
- How LLMs were integrated into methodology
- Prompts or prompt templates (especially if novel)
- Why LLM approach was chosen

---

## Quick Reference: Answer Format

**Response options:** Yes, No, N/A (with 1-2 sentence justification)

- **N/A** = question inapplicable OR information unavailable
- **"No" with justification** is acceptable and won't hurt acceptance
- **"Yes" should reference** supporting sections in paper/supplement
- Evidence may appear in main paper OR appendix

---

## Quick Reference: Common "Yes" Requirements

**Must have for most papers:**
- ✓ Clear claims matching evidence (Q1)
- ✓ Dedicated Limitations section (Q2)
- ✓ Reproducibility pathway described (Q4)
- ✓ Experimental settings detailed (Q6)
- ✓ Statistical significance reported (Q7)
- ✓ Compute resources specified (Q8)
- ✓ Ethics compliance confirmed (Q9)
- ✓ Proper licensing/citations (Q12)

**Context-dependent (often N/A):**
- Q3: Proofs - only for theoretical papers
- Q5: Code/data release - encouraged but not mandatory unless central to contribution
- Q10: Broader impacts - required where applicable (deployment paths vs. foundational)
- Q11: Safeguards - for high-risk models only (LLMs, dual-use systems)
- Q13: Assets documentation - only for new releases
- Q14-Q15: Human subjects - only if using crowdsourcing/human data
- Q16: LLM declaration - only if LLMs are important/original methodology component

---

## Common Pitfalls to Avoid

**Q4-Q6 (Reproducibility):**
- ❌ "Code will be released" without anonymous submission link
- ❌ Missing hyperparameter selection methodology
- ❌ No random seeds or initialization details
- ✓ Provide enough detail that informed reader could reimplement

**Q7 (Statistical Significance):**
- ❌ Error bars without explaining what they represent
- ❌ Not clarifying standard deviation vs. standard error
- ❌ Symmetric error bars for bounded quantities (probabilities)
- ❌ Using n = seeds instead of n = questions (see `~/.claude/docs/ci-standards.md`)
- ✓ Explicitly state: what varies, how calculated, what numbers mean

**Q8 (Compute):**
- ❌ "We used GPUs" without model/count
- ❌ No mention of total project compute vs. reported experiments
- ✓ Specific hardware, memory, time per run, total budget

**Q12 (Licenses):**
- ❌ Using code/data without checking license compatibility
- ❌ Missing version numbers for datasets/models
- ✓ Cite creators, specify licenses, document versions
