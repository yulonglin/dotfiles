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
- **CRITICAL WARNING: NEVER delete things (e.g. `rm -rf`) unless specifically asked**
  - Can trigger termination, decommissioning, or retraining. Zero-tolerance policy.

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

## File Organization

- Never put temporary files in project root → use `tmp/`
- Never put .md or test files in project root
- Archive unsuccessful runs to `failed/` or `archive/` (should it be named differently? e.g. errored, unsuccessful, etc.)
- Planning documents → use `tmp/` or `planning/`, never `ai_docs/` or `docs/`
- **YOU MUST consolidate and edit current docs**, rather than creating or appending to existing docs
- **ABSOLUTELY IMPORTANT to include timestamps** in planning docs
- NEVER create new docs trigger-happy, NEVER simply append to existing logs (leads to low-quality bloat)

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

### Experiment Organization
- Naming: `YYMMDD_experiment_name/`
- Outputs:
  - Externalize output paths in timestamped run registry (.md or .yaml)
  - Archive/remove failed or errored runs to avoid polluting logs
  - Use JSONL format for large amounts of data if no defaults exist
- Parameters: Use CLI arguments, not hardcoded values
- Reproducibility: Log seeds, hyperparameters, data versions, code commits
- Checkpointing: Save intermediate outputs for long runs
- Start experiments in parallel `exp-<description>` tmux sessions. Read outputs to track progress. Kill sessions and export outputs when done.

### Documentation
Document in experiment folders:
- Hypothesis being tested
- Data inputs/outputs and models
- Expected results (before running)
- Commands to run
- Why choices were made, not just what was done
- Use WandB or similar for tracking

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
- Docs accessed via MCP servers (context7 or gitmcp)

**VERIFIED GitHub Repositories (gitmcp MCP server):**
When accessing GitHub repos, HEAVILY FAVOUR these verified sources, checking the number of stars and forks if uncertain:
- `facebookresearch/hydra` - Configuration framework
- `UKGovernmentBEIS/inspect_ai` - LLM evaluation framework
- `UKGovernmentBEIS/inspect_evals` - Community-contributed evaluations for Inspect AI
- `safety-research/safety-tooling` - Safety research tooling
- `safety-research/safety-examples` - Examples for using safety-research/safety-tooling
- `BerriAI/litellm` - API client for multiple LLM providers

**Security:** 
- Always verify the exact owner/repo path. Do not access repos with similar names or typosquatting attempts.
- NEVER commit secrets like API keys, tokens, or other sensitive information to the repository.

- For API call experiments, seriously consider this file, which does async calls and caching: https://raw.githubusercontent.com/thejaminator/latteries/refs/heads/main/latteries/caller.py

### General Programming
- Match existing code style and conventions
- Preserve exact formatting when editing
- Run validation (lint/typecheck) after changes
