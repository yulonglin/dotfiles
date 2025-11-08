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
  - For running evaluations and experiments, use Inspect Evals: https://github.com/UKGovernmentBEIS/inspect_evals
  - For configuring experiments, use Hydra: https://github.com/facebookresearch/hydra
  - For making API calls to LLMs, use latteries: https://raw.githubusercontent.com/thejaminator/latteries/refs/heads/main/latteries/caller.py
    - Alternatively, consider:
      - LiteLLM: https://github.com/BerriAI/litellm
      - Safety Tooling: https://github.com/safety-research/safety-tooling
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

### Core Principles
- Never put temporary files in project root → use `tmp/`
- Never put .md or test files in project root
- Archive failed/superseded runs to `archive/`
- **Include timestamps** in planning and experiment docs
- **Consolidate and edit** current docs rather than creating new ones trigger-happy

### Directory Structure
```
project-root/
├── .cache/             # API response caching (git-ignored)
│   └── llm_responses/  # Keyed by request hash
├── ai_docs/            # Documentation about practices and tools
│   └── [tool_name].md  # e.g., anthropic_api.md, debugging_procedures.md
├── ai_mail/            # Communication between parallel agents
│   ├── archive/        # Processed messages
│   │   └── YYMMDD_HHmmss_<to>_<subject>.md
│   └── inbox/          # Unread messages requiring action/awareness
│       └── YYMMDD_HHmmss_<to>_<subject>.md
├── archive/            # Failed/archived runs
│   └── YYMMDD_HHmmss_experiment_name/
│       └── REASON.txt  # One-line explanation of why archived
├── data/               # Datasets with versioning
│   ├── processed/      # Cleaned/transformed data
│   ├── raw/            # Original, immutable data
│   └── versions.yaml   # Track data versions used in experiments
├── experiments/        # Self-contained experiment runs
│   └── YYMMDD_HHmmss_experiment_name/
│       ├── commands.sh # List of commands run in order
│       ├── config.yaml
│       ├── prompts/    # Prompt versions for this run
│       ├── results.jsonl
│       └── summary.md
├── logs/               # System logs and working memory
│   ├── YYMMDD_HHmmss/  # Timestamped system logs
│   ├── api_usage.jsonl
│   ├── archive/        # Old work logs (YYYY_MM.md)
│   ├── run_registry.yaml
│   └── work_log.md     # Day-to-day everything (messy, chronological)
├── notebooks/          # Exploratory analysis
├── out/                # Consolidated outputs
│   ├── figures/        # All generated figures, with clear names and timestamps (default location)
│   └── tables/         # All generated tables, with clear names and timestamps
├── paper/              # Directory, symlink or git submodule for TeX paper repo
├── research_log.md     # Clean narrative of key findings (root level)
├── specs/              # Project specifications from user
├── src/                # Source code
│   ├── configs/        # Shared configuration files
│   └── utils/          # Shared utilities (caching, etc)
└── tmp/                # Scratch code and data (delete liberally)
```

### Default Locations (Where Things Actually Go)

**Running experiments:**
- Create: `experiments/YYMMDD_HHmmss_<name>/`
- Run commands from that directory, log in `commands.sh`
- Start in parallel `exp-<description>` tmux sessions
- Read outputs to track progress, kill sessions and export when done

**Quick tests/prototypes:**
- `tmp/test_<thing>.py` or `tmp/<timestamp>_test/`
- Delete when done or move to experiments/ if valuable

**Generated figures/tables:**
- → `out/figures/` (plots)
- → `out/tables/` (tables)
- In experiment dirs: keep full outputs, symlink key figures to out/

**Generated text/drafts:**
- Prompts → `experiments/YYMMDD_HHmmss_<name>/prompts/`
- Analysis writeups → `logs/work_log.md` first, then consolidate into research_log.md
- Paper content → `paper/` (not root!)

**Data you create:**
- Raw external data → `data/raw/`
- Anything you process → `data/processed/`
- Temp data from experiments → `experiments/YYMMDD_HHmmss_<name>/data/` (don't pollute data/)

**Planning/thinking:**
- `tmp/planning_YYMMDD_HHmmss.md` while working on specific tasks
- Delete after work is complete

**Day-to-day notes:**
- `logs/work_log.md` - Everything that happens (low friction, messy okay)
- Failed attempts, debugging, quick notes, "ran X got Y trying Z"
- Raw chronological record

**Clean narrative:**
- `research_log.md` - Key findings and decisions only
- What you'd show a collaborator or reference in a paper
- Updated weekly or post-experiment by distilling from work_log.md

### Agent Communication (ai_mail)

**When to use:**
- Handoffs between parallel agents
- "Agent X should know Y before touching Z"
- Blocking issues or urgent TODOs
- Context that's too structured for work_log but needed for coordination
- This is a temporary directory that is ignored by git, so it is a safe place to store messages to other agents
- Each file should be identified by the agent's name (session ID, PID), and the timestamp of the message

**Message format:**
```markdown
To: <agent_name or "all">
From: <agent_name> / <session_id> / <pid>
Priority: [high/normal/low]
Timestamp: YYMMDD_HHmmss

Subject: <brief description>

Message:
<actual content>

Related files:
- path/to/relevant/file
```

**Protocol:**
- **Before starting work:** Check `ai_mail/inbox/` for relevant messages
- **After completing a task:** Leave messages in `inbox/` for affected agents
- **After reading:** Move to `archive/` (or delete if trivial)
- **Naming:** `YYMMDD_HHmmss_<recipient>_<subject>.md`

**ai_mail vs other locations:**
- **ai_mail:** Coordination/handoffs between parallel agents
- **work_log:** Personal record of what happened
- **research_log:** Key findings for collaborators
- **git commit:** Code changes and rationale

### Experiment Organization
- Naming: `YYMMDD_HHmmss_experiment_name/`
- **`commands.sh` documents execution order**: List all commands run in sequence
  - Self-documenting - shows exactly what was executed and in what order
  - Can be run as a script to reproduce the experiment
- Outputs:
  - Track runs in `logs/run_registry.yaml` with status, timestamps, output paths
  - Archive failed or superseded runs to `archive/` with REASON.txt
  - Use JSONL or parquet for large data; JSON/YAML/markdown for human-readable data
- Parameters: Use CLI arguments, not hardcoded values
- Reproducibility: Log seeds, hyperparameters, data versions, code commits in config.yaml
- Checkpointing: Save intermediate outputs for long runs
- Prompts: Store prompt versions in `experiments/YYMMDD_HHmmss_<name>/prompts/` rather than hardcoding

### LLM API Work
- Cache API responses in `.cache/llm_responses/` keyed by request hash
- Track API usage in `logs/api_usage.jsonl` with `{timestamp, model, tokens_in, tokens_out, cost, experiment_id}`
- Reference data versions from `data/versions.yaml` in experiment configs

### Documentation Layers

**ai_docs/** - Persistent knowledge for future work
- Tool usage patterns (e.g., anthropic_api_best_practices.md)
- Common debugging procedures
- Architecture decisions
- Knowledge that should inform all future work

**ai_mail/** - Coordination between parallel agents
- Handoffs and blocking issues
- Check inbox before starting work
- Archive after reading/acting

**logs/work_log.md** - Everything that happens day-to-day
- Chronological working memory
- Failed attempts, debugging, tangents
- Quick notes: "ran X, got Y, trying Z next"
- Messy is fine - this is your scratch space

**research_log.md** - Clean narrative
- Key findings and decisions
- Progress summaries (weekly or post-experiment)
- What worked and why
- Distilled from work_log.md

**Workflow**: work_log (capture everything) → research_log (distill insights) → archive old work_log entries

## Research Log Entry Template

Use this for entries in **research_log.md** (not work_log):

#### [Timestamp: YYYY-MM-DD HH:MM:SS]

**Activity:**  
Name the activity (e.g., Experiment: model run, Data analysis, Literature review, Ideation).

**Description & Status:**  
Brief overview of what was done. Complete, in-progress, or other status.

**Key Commands/Files:**  
- Most relevant commands or notebooks (not exhaustive)
- Critical files examined or generated
- **Include prompt file paths** (prompts define metrics, critical for reproducibility)

**Key Results:**  
- Main findings, metrics, or outputs
- Link to figures in `out/figures/` if relevant

**Outcome:**  
- What this tells us
- Success, failure, or partial progress
- Contribution to research goals

**Next Steps (Optional):**  
- Clear actions based on these findings

*Keep entries focused on insights, not process details (those go in work_log).*

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
