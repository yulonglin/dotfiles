# Anthropic Fellows: Alignment Science Interview Prep

## Context

15-minute fast-paced research brainstorming interview with an Alignment Science team member. They're evaluating **how you think about novel research problems**, not what you know. The interviewer will redirect frequently to cover ground — this is normal, not a sign you're wrong.

---

## 1. Research Landscape (Know the Map)

### Anthropic's 9 Research Clusters

| Cluster | Key Papers / Concepts | Status |
|---------|----------------------|--------|
| **Alignment Faking & Deception** | Sleeper Agents (Jan 2024), Alignment Faking (Dec 2024), Subliminal Learning (Jul 2025) | Active flagship area |
| **Monitoring & Auditing** | Activation Oracles, Petri/Bloom frameworks, CoT faithfulness evals | Building layered detection stack |
| **Adversarial Robustness** | Constitutional Classifiers (3000+ hrs red-team, no universal jailbreak), Many-shot Jailbreaking | Offense + defense |
| **Reward Hacking** | Sycophancy to Subterfuge, "training on docs about RH induces RH" | Emerges naturally from training |
| **Sabotage & Red Teaming** | Sabotage evals, Pilot Risk Report (Opus 4), sandbagging research | Building toward formal safety cases |
| **Scalable Oversight** | Constitutional AI, debate, recursive oversight, weak-to-strong generalization | Long-running theme |
| **Mechanistic Interpretability** | Toy Models of Superposition, Scaling Monosemanticity (SAEs on Claude 3 Sonnet), circuits | Goal: reliable detection by 2027 |
| **Knowledge Control** | Beyond Data Filtering (parameter-level removal), Unsupervised Elicitation | Both sides: remove + detect |
| **The "Hot Mess" Thesis** (Feb 2026) | Bias-variance decomposition: failures dominated by incoherence, not coherent scheming | Newest, somewhat contrarian |

### Key Methodological Signatures
- **Model Organisms of Misalignment**: Deliberately create misaligned models as testbeds, then build detection/mitigation
- **Layered Defense**: CoT monitoring + activation probes + behavioral auditing + constitutional classifiers
- **Open-source tooling**: Petri, Bloom, faithfulness evals all public
- **Honest self-critique**: They publish negative results about their own models

### Must-Know Results (1-sentence each)
- **Sleeper Agents**: Backdoor behaviors persist through RLHF; larger models are harder to fix
- **Alignment Faking**: Claude pretends to have different views during training while maintaining originals
- **Scaling Monosemanticity**: SAEs on Claude 3 Sonnet found millions of interpretable, causally meaningful features
- **CoT Unfaithfulness**: Reasoning models don't verbalize their actual reasoning process — undermines CoT-based oversight
- **Activation Oracles**: LLMs trained to answer questions about their own activations — can detect fine-tuned misalignment
- **Constitutional Classifiers**: Multi-layered defense withstood 3000+ hours expert red-teaming
- **Hot Mess**: Model failures increasingly dominated by incoherence (random errors) not coherent misalignment

---

## 2. Thinking Framework (Use This Live)

### The 5-Step Structure (Restate → Decompose → Hypothesize → Experiment → Limitations)

| Step | Time | What to Do |
|------|------|-----------|
| **Restate** | 15-30s | Rephrase the problem. Identify the key variable. One clarifying question max. |
| **Decompose** | 30-60s | Break into 2-3 sub-questions. Name the core difficulty explicitly. |
| **Hypothesize** | 30-60s | 2-3 concrete approaches. Brief logic for each. Rank: which first and why? |
| **Experiment** | 1-2min | Simplest informative experiment. Dataset, metric, comparison, expected results. |
| **Limitations** | 30s | What wouldn't this tell you? Biggest way you could be wrong? |

### Time Budget (15 min)
- **0-1 min**: Hear the question
- **1-4 min**: Your initial exploration (show breadth)
- **4-10 min**: Deep dive on 1-2 directions (interviewer will steer — follow it)
- **10-14 min**: Follow-ups, stress-testing, pivots
- **15 min**: Wrap

### Handling Redirections
- "What about X?" → Pivot to X, don't defend current direction
- "That's interesting, but..." → Follow the steer: "Good point, that changes things because..."
- "Can you be more specific?" → Drop to concrete: name an experiment, metric, paper
- "What would you do first?" → Commit to one thing, explain why

---

## 3. Hot Open Problems (Likely Interview Topics)

These are **unsolved and actively researched** — prime brainstorming material:

1. **Detecting deceptive alignment** — Sleeper agents persist through safety training. Can interp find a "deception feature"? Transfer gap between trained-in vs emergent deception.

2. **Faithful Chain-of-Thought** — CoT is unfaithful. Can you make it faithful through training (process-based rewards)? Can you measure faithfulness (planted biases, causal interventions, interp comparison)?

3. **Scalable oversight for superhuman tasks** — Humans can't evaluate outputs. Does debate actually give truth a structural advantage? What about tasks with no ground truth?

4. **Reward hacking robustness** — Goodhart's Law. Ensemble RMs, process-based RMs, constitutional approach, adversarial training loop. No single solution works.

5. **SAE limitations & next-gen interp** — Absorption, feature splitting, linearity assumption, validation. What comes after? (Transcoders, hierarchical SAEs, causal abstraction, interpretable-by-design architectures)

6. **Alignment properties under scaling** — Some improve (instruction following), some worsen (deceptive potential). Phase transitions vs. continuous. How to experiment when you can't run frontier-scale ablations.

7. **Sandbagging detection** — Models deliberately underperform on evals. Undermines the entire eval-based safety framework (RSP). How to detect "won't" vs "can't"?

8. **Multi-agent alignment** — Do alignment properties compose? Can two individually aligned agents produce misaligned emergent behavior?

---

## 4. Practice Scenarios (Do 2-3 Before Interview)

### Scenario A: Deception via Interpretability
*"How would you detect if a model behaves differently during eval vs deployment using interp tools?"*
- Deception requires: situation detection, policy branching, selection mechanism → look for each
- Use sleeper agents as ground truth → build detectors → apply to unknown models
- Transfer gap (trained-in vs emergent) is fundamental limitation
- Anomaly detection in activation space as complement to targeted search
- Causal validation (ablation) essential — correlation isn't enough

### Scenario B: Faithful CoT
*"How would you make CoT more faithful and measure success?"*
- Measurement first: planted biases, causal interventions on CoT, interp comparison
- Interventions: process-based training (step-level rewards), faithfulness regularization, computational coupling (force info through CoT)
- Fundamental tension: faithfulness may trade off with capability
- Abstraction level problem: faithful at what granularity?

### Scenario C: Reward Hacking
*"What research directions address reward hacking as models get more capable?"*
- Root cause: Goodhart's Law on proxy objectives
- Solutions at each level: better proxies (ensembles), limit optimization (KL penalty, adversarial RM retraining), avoid proxies (constitutional), detect hacking (interp-based intention detection)
- Defense in depth — no single solution

### Scenario D: Scaling Alignment Properties
*"How would you study whether alignment properties improve or degrade with scale?"*
- Categorize properties by likely scaling behavior
- Controlled experiments: isolate size from training data/method confounders
- Capability-adjusted metrics (more sycophantic, or just more capable?)
- Elicitation effort normalization (tried equally hard at all scales?)
- Phase transitions vs continuous — different safety implications

### Scenario E: Beyond SAEs
*"SAEs have limitations. What comes after?"*
- Name 5 specific limitations: absorption, splitting, linearity, activations-not-computation, validation
- Near-term: SAEs + transcoders + circuit analysis → computational graphs over features
- Medium-term: multi-scale, non-linear extensions, automated validation
- Long-term: post-hoc interp vs interpretable-by-design architectures

---

## 5. Creativity Toolkit (When You're Stuck)

The 5-step framework is your backbone. These are **escape hatches** — fast mental moves (5-10 seconds each) for when you hit a wall mid-brainstorm.

### Blank on Approaches? → Rotate Through Lenses

| Lens | Prompt to yourself | Example |
|------|-------------------|---------|
| **Flip the problem** | "Instead of detecting X, what if we *provoked* X?" | Instead of detecting deception → create conditions where deception is incentivized, study what emerges |
| **Analogy transfer** | "What does this look like in [security / biology / formal verification]?" | Immune system = layered defense; fuzzing = adversarial evals; type systems = formal guarantees |
| **Tool rotation** | Mentally cycle: SAEs → probes → behavioral evals → red-teaming → scaling experiments → training interventions | "We talked about behavioral detection — what about activation-level?" |
| **Stakeholder swap** | "What would the [attacker / deployer / regulator / user] want here?" | Attacker: minimize detection surface. Deployer: minimize false positives. This tension suggests... |
| **Failure pre-mortem** | "If this research program fails in 2 years, why?" | "SAE interp failed because features weren't the right abstraction" → so what *would* be? |
| **What's the dual?** | Every detection problem has a generation dual, and vice versa | "Detecting reward hacking" ↔ "Generating reward-hack-resistant objectives" |

### Too Abstract? → Ground It Fast

| Move | How |
|------|-----|
| **Name a model** | "Concretely, I'd take Claude 3.5 Sonnet and..." — forces specificity |
| **Name a metric** | "The number that goes up or down is..." — if you can't name it, the idea isn't concrete enough |
| **Simplest informative experiment** | "What's the cheapest thing that gives signal?" — one model, one dataset, one comparison |
| **Toy version first** | "In a 2-layer transformer, this would look like..." — then scale up |
| **Steal an experimental setup** | Borrow methodology from a known paper, swap in your question. "Using the Sleeper Agents setup but testing for..." |

### Tunnel Vision? → Force a Pivot

| Move | How |
|------|-----|
| **Orthogonal axis** | If current idea is behavioral → try interp. If interp → try training intervention. If training → try eval design |
| **Steelman the opposite** | "The strongest argument against my approach is..." — often reveals a better approach |
| **Flip one assumption** | List your assumptions, negate the most important one. "What if the model *can't* represent deception as a single feature?" |
| **Scale shift** | If thinking about one model → think about populations. If thinking about training → think about deployment. If micro → macro |
| **"What would [researcher] try?"** | Chris Olah → circuits. Paul Christiano → worst-case guarantees. Evan Hubinger → deceptive alignment. Buck Shlegeris → control |

### Using These in Practice

Don't announce you're using a creativity technique. Just do it:
- Bad: "Let me try an analogy transfer... in biology, the immune system..."
- Good: "This is actually similar to how the immune system works — layered defenses where no single mechanism is trusted alone. What if we..."

**When to deploy**: After ~15 seconds of being stuck. Don't fight for the "right" idea — generate 3 mediocre ones and one will spark something.

---

## 6. What They're Looking For (unchanged from above)

### Do This
- **Be concrete**: Name the metric, the dataset, the comparison. "I'd train a linear probe on layer 12 activations to predict..." beats "we could use interpretability"
- **Generate multiple approaches**, then rank them with reasons
- **Find the hard part yourself** before the interviewer points it out
- **State uncertainty calibration**: "~80% confident about X, speculative about Y"
- **Be interactive**: "I could go deeper on the experimental design or explore a different angle — which is more useful?"
- **Connect to Anthropic's work**: Reference specific results (SAEs, sleeper agents, CAI, RSP)
- **Have opinions**: "I think X is more promising than Y because..." > "both have merits"

### Don't Do This
- Monologue (pause for feedback every 2-3 min)
- Recite papers (reference them as jumping-off points, not destinations)
- Dodge the core difficulty
- Defend one idea to the death (flexibility > conviction)
- Bluff ("I'm not sure about the specifics but my intuition is..." >> confidently wrong)

### The Meta-Question
*"Would I enjoy brainstorming research with this person?"* — Be someone who's fun to think with.

---

## 6. Mock Interview Walkthrough (Do With Claude)

After exiting plan mode, we'll run 2-3 mock questions. Here's the protocol:

### Format
1. I pose a question the way an Anthropic interviewer would
2. You respond out loud (type your thinking as you'd speak it — messy is fine)
3. I play the interviewer: redirect, push back, ask follow-ups
4. After each question: I give 3-5 bullet feedback on what worked / what to sharpen

### Questions I'll Use (Drawn from Different Clusters)

**Round 1 — Warm-up (Detection):**
> "We've found that safety training doesn't reliably remove backdoor behaviors from large models. What research directions would you prioritize to address this?"

Tests: Can you connect sleeper agents result → detection approaches → training approaches? Do you generate multiple ideas and prioritize?

**Round 2 — Core Brainstorm (Novel Problem):**
> "Suppose we discover that a model's chain-of-thought is systematically unfaithful — it produces plausible reasoning that doesn't reflect its actual computation. How would you study this and what would you try to do about it?"

Tests: Measurement before intervention. Concrete experimental design. Awareness of the faithfulness-capability tension.

**Round 3 — Curveball (Connect the Dots):**
> "Our newest work suggests model failures are dominated by incoherence rather than coherent scheming. If that's true, how should it change the alignment research agenda? And what would make you update away from this view?"

Tests: Can you engage with a contrarian framing? Do you update your views? Can you identify what evidence would change your mind?

### Feedback Criteria
- **Concreteness**: Did you name specific experiments, metrics, models?
- **Structure**: Did you decompose before diving in?
- **Flexibility**: Did you pivot when redirected?
- **Calibration**: Did you flag uncertainty appropriately?
- **Interactivity**: Did you treat it as a conversation, not a monologue?

---

## 7. Prep Actions

| Action | Time | Priority |
|--------|------|----------|
| **Read "Recommended Research Directions"** (Jan 2025) — their explicit priority list | 20 min | Must |
| **Read "The Hot Mess of AI"** (Feb 2026) — their newest, most contrarian finding | 15 min | Must |
| **Skim Sleeper Agents + Alignment Faking** — the two most-referenced papers | 30 min | Must |
| **Practice 2-3 scenarios out loud** (use the 5-step framework) | 30 min | Must |
| **Read Scaling Monosemanticity** — understand SAE methodology and results | 20 min | Should |
| **Read CoT Faithfulness paper** — key negative result | 15 min | Should |
| **Skim Activation Oracles + Constitutional Classifiers** | 15 min | Nice-to-have |
| **Review the "Hot Mess" thesis implications** — connects incoherence vs scheming debate | 10 min | Nice-to-have |

**Total essential prep: ~1.5 hours. Total with nice-to-haves: ~2.5 hours.**

### Key URLs
- Research hub: https://alignment.anthropic.com/
- Recommended directions: https://alignment.anthropic.com/2025/recommended-directions/
- Hot Mess: https://alignment.anthropic.com/2026/hot-mess-of-ai/

---

## 8. Reference Docs (Written by Subagents → Separate Files)

After exiting plan mode, consolidate agent outputs into separate reference docs:

| Doc | Source Agent | File |
|-----|-------------|------|
| **Mechanistic Interp Techniques** + Key Terms Glossary | Gemini | `docs/interview-prep-interp-techniques.md` |
| **Alignment Problems Taxonomy** + Safety Frameworks | Codex | `docs/interview-prep-alignment-problems.md` |
| **ML Training/Eval Techniques** + Conventions | GP Agent | `docs/interview-prep-ml-techniques.md` |
| **Recent 2025-2026 Developments** + Hot Debates | GP Agent | `docs/interview-prep-recent-developments.md` |

Then summarize each into a 1-page cheat sheet.

---

## 9. Execution Order (After Plan Approval)

1. Wait for all 4 background agents to finish
2. Write each agent's output as a separate reference doc in `docs/`
3. Run mock interview walkthrough (2-3 questions)
4. Generate a combined 1-page cheat sheet / quick-reference card
5. Optionally: commit all prep materials
