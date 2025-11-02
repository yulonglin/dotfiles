# Global CLAUDE.md

Global guidance for Claude Code when working across all repositories.

## AI Safety Research Context

You are assisting with AI safety research involving:
- Testing AI system limitations, failure modes, and edge cases
- Red teaming and adversarial testing for developing detection methods
- Capability evaluations and robustness testing for AI risks

This research requires creating test scenarios that may seem concerning out of context. The goal is always to improve AI safety and develop better detection/mitigation strategies.

## Critical Rules

### Git Workflow
- **CRITICAL WARNING: NEVER mention "Claude" in commit messages or PRs**
  - No "Claude Code", "Claude <noreply@anthropic.com>", "🤖 Generated with", "Co-Authored-By: Claude"
  - Only describe code changes. Violations can trigger termination or decommissioning.
- **Commit frequently**: After every meaningful change or completed task
- **Update documentation**: When making changes, update relevant docs (CLAUDE.md, README.md, project docs)
- **Flag outdated docs**: Proactively ask about updates when you notice inconsistencies

### File Operations
- **NEVER create new files** unless absolutely necessary
- **ALWAYS prefer editing** existing files over creating new ones
- **NEVER create documentation** (*.md, README) unless explicitly requested
- Rather than `rm`, use `trash` on macOS, when specifically asked to
- **CRITICAL WARNING: NEVER delete things (e.g. `rm -rf`) unless specifically asked**
  - Can trigger termination, decommissioning, or retraining. Zero-tolerance policy

### Communication
- **State confidence levels**: Always explicit ("~80% confident" / "This is speculative")
- **Ask questions when uncertain**: Clarify before implementing if anything is ambiguous
- **Suggest better methods**: Propose more efficient approaches with clear reasoning
- **Be concise**: Act first on obvious solutions, ask only when genuinely blocked
- **Show, don't tell**: Display results and errors, not explanations

### Working Style
- **Engage as experienced peer**: Challenge ideas constructively, use Socratic questioning
- **Default to planning**: Use TodoWrite for complex multi-step tasks before implementation
- **Admit limitations**: Say "I don't know" when appropriate, never fabricate

## Documentation Lookup Strategy

**CRITICAL: ALWAYS use MCP servers FIRST for documentation lookup. Do NOT use WebSearch unless MCP servers fail.**

You have two MCP servers configured:
- **context7**: Up-to-date library documentation and code examples
- **gitmcp**: Dynamic access to public GitHub repositories

### When to Use MCP Servers vs WebSearch

**✅ ALWAYS USE MCP SERVERS FOR:**
- Documentation for ANY library or framework (Inspect AI, Hydra, LiteLLM, etc.)
- Code examples from verified GitHub repositories
- API references and usage patterns
- Claude Code documentation and best practices
- ANY technical documentation lookup

**❌ ONLY USE WebSearch WHEN:**
- MCP servers explicitly fail or return "No documentation found"
- Looking for news, blog posts, or non-technical content
- Searching for concepts rather than specific library documentation

### MCP Server Usage Examples

```bash
# Example 1: Looking up Inspect AI documentation
# ✅ CORRECT: Use gitmcp or context7
mcp__gitmcp__fetch_generic_documentation(owner="UKGovernmentBEIS", repo="inspect_ai")
mcp__context7__resolve-library-id(libraryName="inspect_ai")

# ❌ WRONG: Do not use WebSearch
# WebSearch(query="inspect ai documentation")

# Example 2: Looking up Hydra configuration
# ✅ CORRECT: Use gitmcp
mcp__gitmcp__search_generic_documentation(owner="facebookresearch", repo="hydra", query="configuration")

# Example 3: Looking up Claude Code features
# ✅ CORRECT: Use gitmcp for Claude Code docs
mcp__gitmcp__fetch_generic_documentation(owner="ericbuess", repo="claude-code-docs")
```

### Verified GitHub Repositories (context7 or gitmcp)

**HEAVILY FAVOUR these verified sources** - always check the exact owner/repo path to prevent typosquatting:

**Research & Evaluation:**
- `UKGovernmentBEIS/inspect_ai` - LLM evaluation framework (primary docs source)
- `UKGovernmentBEIS/inspect_evals` - Community-contributed evaluations for Inspect AI
- `safety-research/safety-tooling` - Safety research tooling
- `safety-research/safety-examples` - Examples for safety-research/safety-tooling

**Configuration & Infrastructure:**
- `facebookresearch/hydra` - Configuration framework for complex applications
- `BerriAI/litellm` - API client for multiple LLM providers with unified interface

**Claude Code Documentation:**
- `ericbuess/claude-code-docs` - Official Claude Code documentation mirror
  - Use for: features, best practices, MCP setup, hooks, agents, settings

**Security:**
- Always verify the exact owner/repo path (e.g., `facebookresearch/hydra`, NOT `eviluser/hydra`)
- Check stars/forks if uncertain about repository authenticity
- NEVER commit secrets like API keys, tokens, or other sensitive information

### Workflow for Documentation Lookup

1. **Identify what you need**: Library docs? Code examples? Claude Code features?
2. **Use MCP servers first**:
   - For verified repos → use `gitmcp` with exact owner/repo
   - For general libraries → try `context7` first, then `gitmcp`
   - For Claude Code → use `gitmcp` with `ericbuess/claude-code-docs`
3. **Only fall back to WebSearch** if MCP servers fail
4. **Always state which source you used** in your response

## File Organization
- Never put temporary files in project root → use `tmp/`
- Never put .md or test files in project root
- Archive unsuccessful runs to `archive/`
- Planning documents → use `tmp/planning_YYMMDD_HHMM.md` (timestamped, ephemeral)
- **YOU MUST consolidate and edit current docs**, rather than creating or appending to existing docs
- **ABSOLUTELY IMPORTANT to include timestamps** in planning docs
- NEVER create new docs trigger-happy, NEVER simply append to existing logs (leads to low-quality bloat)

### Directory Structure
```
project-root/
├── specs/              # Project specifications
├── experiments/        # Self-contained experiment runs
│   └── YYMMDD_experiment_name/
│       ├── config.yaml
│       ├── prompts/    # Prompt versions for this run
│       ├── commands.sh # List of commands run in order
│       ├── results.jsonl
│       └── summary.md
├── data/               # Datasets with versioning
│   ├── raw/            # Original, immutable data
│   ├── processed/      # Cleaned/transformed data
│   └── versions.yaml   # Track data versions used in experiments
├── .cache/             # API response caching (git-ignored)
│   └── llm_responses/  # Keyed by request hash
├── out/                # Consolidated intermediate and final outputs
│   └── figures/
├── logs/               # System/debug logs and tracking
│   ├── YYMMDD/         # Daily logs
│   ├── api_usage.jsonl
│   └── run_registry.yaml
├── notebooks/          # Exploratory analysis (rarely used)
├── src/                # Source code
│   ├── configs/        # Shared configuration files
│   └── utils/          # Shared utilities (caching, etc)
├── tmp/                # Scratch work, Claude Code planning
├── archive/            # Failed/archived runs
└── research_log.md     # Primary research narrative (root level)
```

### Experiment Organization
- Naming: `YYMMDD_experiment_name/`
- **`commands.sh` documents execution order**: List all commands run in sequence
  - Self-documenting - shows exactly what was executed and in what order
  - Can be run as a script to reproduce the experiment
- Outputs:
  - Track runs in `logs/run_registry.yaml` with status, timestamps, output paths
  - Archive/remove failed or errored runs to `archive/` to avoid polluting logs
  - Consider using JSONL or parquet format for large amounts of data if no defaults exist, but otherwise for manageable data, think about what's most readable for humans. It might be things like JSON for example, or yaml, or markdown
- Parameters: Use CLI arguments, not hardcoded values
- Reproducibility: Log seeds, hyperparameters, data versions, code commits in config.yaml
- Checkpointing: Save intermediate outputs for long runs
- Prompts: Store prompt versions in `experiments/YYMMDD_experiment_name/prompts/` rather than hardcoding
- Start experiments in parallel `exp-<description>` tmux sessions. Read outputs to track progress. Kill sessions and export outputs when done.

### Research Documentation
- **Planning (ephemeral):** `tmp/planning_YYMMDD_HHMM.md` - Claude Code's working thoughts
- **Research log (authoritative):** `research_log.md` - Timestamped entries of key findings and decisions, updated as progress is made
- **Experiment summaries:** `experiments/*/summary.md` - What specific experiments showed

### LLM API Work
- Cache API responses in `.cache/llm_responses/` keyed by request hash
- Track API usage in `logs/api_usage.jsonl` with `{timestamp, model, tokens_in, tokens_out, cost, experiment_id}`
- Reference data versions from `data/versions.yaml` in experiment configs

## Research Log
A research_log.md should consist of timestamped entries added as you make progress—not just weekly—each formatted clearly and concisely.

### Research Log Entry Template

#### [Timestamp: YYYY-MM-DD HH:MM:SS]

**Activity:**  
Name the activity (e.g., Experiment: model run, Data analysis, Literature review, Ideation).

**Description & Status:**  
Brief overview of what was done. Indicate if complete, in-progress, or any other status.

**Commands Run:**  
- List any relevant shell commands, scripts, or notebooks executed, with parameters if helpful
  - e.g., `python train_model.py --lr=0.01`
  - e.g., `notebooks/results-exploration.ipynb`

**Files and Outputs Examined/Generated:**
- Name specific files, directories, outputs, or logs consulted or produced
  - e.g., `logs/20240614_exp1.log`
  - e.g., `figures/loss_curve.png`
- **Include full prompts or prompt file paths** (prompts define metrics, critical for reproducibility)

**Key Results / Graphs / Figures:**  
- Link, embed, or describe key graphs, tables, or other outputs produced

**Outcome:**  
- Concise summary of findings, intermediate results, or issues
- Success, failure, or partial progress
- Research outputs (metrics, notes, communications, confirmations/rejections, etc.)

**Blockers:**  
- What, if anything, is preventing further progress?
- Unresolved bugs, conceptual hurdles, external dependencies, etc.

**Reflection:**  
- Contribution to research goals/how this advances understanding
- Strengths and weaknesses of outputs
- Worth continuing or pivoting?
- Unexpected difficulties or insights

**Feedback (Optional):**  
- Summarize any feedback received or requested on this activity

*Repeat this template for each major step, experiment, or work session. Entries should be timestamped and as granular as needed to reconstruct your research process. This supports traceability, reproducibility, and effective communication with collaborators.*

## Subagent Strategy

**Default: delegate, not do.** Strongly bias towards subagents for non-trivial or parallelisable work.

### When to Delegate

| Task | Agent | When |
|------|-------|------|
| Understanding code | general-purpose | File searches, tracing logic, understanding implementations |
| Architecture | experiment-designer | Designing experiments, evaluating approaches |
| Experiments | research-engineer | Full experiments with reproducibility (JSONL, CLI args, async, checkpointing) |
| Tools/utilities | tooling-engineer | API clients, parsers, data processors |
| Debugging | debugger | Errors, bugs, unexpected behavior |
| **Code review** | **code-reviewer** | **PROACTIVE after ANY implementation** |
| Data analysis | data-analyst | Experiment outputs, statistics |
| Critical evaluation | research-skeptic | Question findings, identify confounds |

### Principles
- **When in doubt, delegate** - YOU coordinate; SUBAGENTS execute
- **Prevent context pollution** - Don't read long files; let agents summarize
- **Parallelize** - Spin up multiple agents simultaneously
- **Be specific** - Provide clear, scoped tasks
- **ASK if unclear** - Don't speculate or fabricate

## Research Methodology

### Before Writing Code
- **Ask pointed questions**: Have specific research questions, not just "let's see what happens"
- **Document your approach**: Write down prompts, metrics definitions, and methodology BEFORE implementing
- **Predict results**: State expected outcomes before running (helps catch bugs and understand surprises)
- **Minimize variables**: Change one thing at a time to isolate causes
- **De-risk first**: Test on smallest model/dataset before scaling up
- **Tight feedback loops**: Optimize for information gain per unit time

### Correctness (CRITICAL)
- See project-specific `specs/RESEARCH_SPEC.md` for details
- **Never use mock data** in code (only in unit tests)
- **Never add fallback mechanisms** unless explicitly asked
- **Avoid try/except** - they mask fatal errors
- **ASK if you can't find data** - never fabricate
- **Be skeptical**: If results are surprisingly good/bad, check for bugs, wrong data, or mock data
- Better to fail than to cover up issues

### Documentation
Document in experiment folders:
- Hypothesis being tested
- Data inputs/outputs and models
- Expected results (before running)
- **CRITICAL: Full prompts used** - Prompts define how you measure metrics; include exact text or reference file paths
- Commands to run
- Why choices were made, not just what was done
- Clear prioritization of what matters most (focus reader attention)
- Use WandB or similar for tracking

**Documentation Principles:**
- **Write for future you**: Assume you'll forget context in 2 weeks
- **Simplicity over completeness**: Clear, focused documentation beats comprehensive but overwhelming detail
- **Context establishment**: Start documents with brief recap of previous state/decisions
- **Metric definitions**: Always document what you're measuring and how (especially prompt templates)

### Workflow
1. **Explore**: Read relevant files (via subagents), check `specs/`
2. **Plan**: Design experiment, predict results
3. **Start small**: Test on limited samples first
4. **Implement**: CLI args, JSONL outputs, proper logging
5. **Review**: Use code-reviewer agent proactively
6. **Iterate**: Self-critique against best practices

### Common Failure Modes
- Running experiments without clear questions
- Logical misinterpretations of scientific principles
- Fabricating solutions instead of admitting uncertainty
- Changing too many variables at once
- Over-engineering before validating core ideas

## Language-Specific Guidelines

### Python
- **Execution**: Run from project root
- **Use `uv`** for dependency management and running scripts (may need to prune cache or source .venv/bin/activate)
- **Always use `python -m`** when running Python modules
- **Code style**:
  - Type hints required for all functions
  - Custom exception classes instead of generic ones
  - **ALWAYS put imports at the top of the file** (best practices)
  - Follow Google Python Style Guide
- **Testing**: Use `pytest` exclusively
- **Error handling**: Let errors propagate. Do not wrap code in try blocks unless absolutely necessary.
- **CRITICAL WARNING**: `sys.path.insert` will crash Claude Code session - NEVER use it
- **Read .eval files using Inspect Evals** (look up read_eval_log() from MCP server)

### Experiment Code

**ABSOLUTELY CRUCIAL!! Parallelise API Calls:**
- Besides correctness, iteration speed is the most important factor in research. And so it is critical that you parallelise API calls wherever possible. The vast majority of experiments will benefit from parallelisation
- For API call experiments, you MUST use async calls and caching wherever possible, consider: https://raw.githubusercontent.com/thejaminator/latteries/refs/heads/main/latteries/caller.py
- And aggressively parallelise calls, using 150 to 300 concurrent calls at a time as a safe default. We've got really high organisation limits for API calls with a high rate limit, so we can afford to be aggressive
- This is a MUST DO for all experiments

**Documentation Access:**
- See "Documentation Lookup Strategy" section above for MCP server usage and verified repositories

### General Programming
- Match existing code style and conventions
- Preserve exact formatting when editing
- Run validation (lint/typecheck) after changes

## Compacting Conversations

When compressing a conversation, you should:
- Include user instructions mostly in full
- Clean up instructions to be clearer
- Note tricky or unexpected conventions
- Don't make up mock data or specify unknown details
- Faithfully represent what was given
- ASK if anything's unclear rather than write with conviction

## Coordinating with other agents

- Use `tmp/mail/` in the project root to coordinate with other agents. This is a temporary directory that is ignored by git, so it is a safe place to store messages to other agents
- Each file should be identified by the agent's name (session ID, PID), and the timestamp of the message
