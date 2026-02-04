# Summary of #technical_questions Slack Channel

Based on analyzing 180 days of discussions from the MATS #technical_questions channel, here's what the community has found helpful:

## 🛠️ Most Valuable Tools

### **GoodFire Scribe** ⭐
- **What it is**: Research agent with custom Jupyter kernel integration
- **Why people like it**: Makes notebook writing much easier for experimentation
- **Resources**:
  - [GitHub repo](https://github.com/goodfire-ai/scribe)
  - [Blog: Lessons from using agents for interpretability research](https://www.goodfire.ai/blog/you-and-your-research-agent)
- **Gotcha**: `beartype==0.22.9` breaks fastmcp imports - version conflict to watch for
- **Debug tip**: Run `.venv/bin/python -m scribe.notebook.notebook_mcp_server 2>&1 | head -20` to diagnose issues

### **Inspect AI**
- **What it is**: Open-source LLM evaluation framework from UK AISI
- **Critical gotcha**: Default behavior parses ALL `<think>` tags into `ContentReasoning` blocks, even for non-reasoning models - this catches people by surprise
- **Link**: [inspect.aisi.org.uk/reasoning.html](https://inspect.aisi.org.uk/reasoning.html)

### **Claude Code**
- Widely used but challenges managing 5-hour usage limits with long-running agents
- HPC deployment issues: Binary installation often blocked, workarounds needed

---

## 💡 Workflows That Work

### GPU-less Fine-tuning Pipeline
Proposed by researchers for cost-effective model development:
1. Fine-tune using **Together AI API** (no GPU needed)
2. Upload model to **Hugging Face Hub**
3. Run evals using **HF Inference Endpoints**

### Few-Shot Eval Methodology
- **Use fixed set** of k-shot examples for all eval samples (not random per sample)
- Try a few different fixed sets to check sensitivity
- Typically sensitivity doesn't matter much (Teun Van Der Weij)

### Research Code Best Practices
- **Speed over extensibility** when exploring (Wen Xing, ex-Meta SWE)
- Use LLMs to quickly explore with rough code
- Then ask LLM to rewrite extensible version when ready to scale
- **Resources**:
  - [Tips for Empirical Alignment Research](https://www.alignmentforum.org/posts/dZFpEdKyb9Bf4xYn7/tips-for-empirical-alignment-research)
  - [Clément's SPAR mentee guide](https://docs.google.com/document/d/15PoKNgCtq_Frdw6xiUiGAN9Ojikxs-_roM69kZzyTQo/edit?usp=sharing)

### Pipeline Management
For multi-step research pipelines:
- **Hydra-core** recommended for experiment configs and sweeps
  - [Complex example](https://github.com/science-of-finetuning/diffing-toolkit/tree/main/configs)
  - [Simple example](https://github.com/Butanium/emergent-misalignment/tree/main/open_models%2Fconf)
- **DVC** suggested for dependency management between steps (though "a bit heavyweight")

---

## ⚠️ Common Pitfalls

### Prompt Optimization Reality Check
**DsPY GEPA is showing diminishing returns** with frontier models:
- Used to give great improvements over handwritten prompts
- Now: Opus 4.5 generates 8 prompts → pick best manually → GEPA gives only marginal improvements
- Often makes prompts "awkwardly detailed/overfitty to train set"
- Multiple researchers confirmed same experience

### Claude Code on HPCs
**Problem**: Many HPCs block binary installation

**Workaround discovered**:
- Use npm instead (Anthropic deprecating this, but it works)
- Set `Claude Code: Claude Process Wrapper` in settings to point at binary manually
- [GitHub issue #13526](https://github.com/anthropics/claude-code/issues/13526) for ARM Neoverse-V2 CPU issues

### Playwright MCP Efficiency
- Takes 25k token accessibility screenshot on EVERY page change
- Slow and wasteful for concurrent windows
- `--isolated` flag helps prevent interference but requires separate terminal tabs

---

## 🔬 Popular Frameworks by Task

| Task | Tool | Community Notes |
|------|------|-----------------|
| **RL Training for LLMs** | veRL (preferred), TRL, OpenRLHF, rLLM | TRL "not very flexible"; Unsloth buggy for multi-GPU; veRL preferred by Constellation team |
| **General RL** | cleanRL | Research-friendly, high-quality single-file implementations |
| **LLM Evaluation** | Inspect AI | Watch for default `<think>` tag parsing |
| **Experiment Config** | Hydra-core | Recommended for managing configs and sweeps |
| **Model Inference** | vLLM | Standard for fast inference |

---

## 🎯 Major Opportunities

### **OpenAI Chain-of-Thought Access** 🌟
[Slack thread](https://mats.slack.com/archives/C0475H9K9CZ/p1767817490448059)

- Wen Xing has OpenAI contact willing to discuss CoT output access for MATS
- Would make MATS "one of very few external groups" with research access
- **Needs someone to drive it forward**:
  1. Compile interested scholars + example projects
  2. Address device security concerns (YubiKey solution proposed)
  3. Coordinate with OpenAI contact

**Reactions**: 17 sparkles, 8 eyes (very high interest)

---

## 🔍 Unsolved Problems (Opportunities!)

1. **LessWrong/Alignment Forum citations** for LaTeX/BibTeX - Zotero+Overleaf munges them, seeking principled solution
2. **Chatbot export workflow** - Want anonymized exports with LaTeX rendering, easy automation
3. **Claude Code agent session management** - Managing 5-hour limits without hitting Extra Usage
4. **Activation extraction speed** - Seeking "vLLM but for activations" for fast extraction from large models

---

## 💡 Key Insights

**Three key patterns emerge from these discussions**:

1. **Tooling maturity gap**: Many "hacky" workarounds mentioned - the ecosystem hasn't caught up to AI research workflows yet. Opportunities for better solutions.

2. **Frontier model shifts**: Traditional prompt optimization (GEPA) shows diminishing returns with models like Opus 4.5. The field is evolving past techniques that worked 6-12 months ago.

3. **Infrastructure friction**: HPC integration, token limits, GPU access create constant friction. Researchers spend significant time on infrastructure rather than research - hence interest in GPU-less workflows and managed services.

---

## 🚀 Action Items

- **For CoT research**: Contact Wen Xing about OpenAI access initiative
- **For HPC users**: Check npm installation workaround for Claude Code
- **For eval work**: Remember Inspect AI's `<think>` tag default behavior
- **For research pipelines**: Consider Hydra-core for experiment management
- **For RL training**: Try veRL over TRL based on community experience

---

*Last updated: February 2026*
*Source: MATS #technical_questions Slack channel (180-day analysis)*
