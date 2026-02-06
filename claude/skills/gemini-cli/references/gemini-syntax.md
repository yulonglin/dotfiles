# Gemini CLI Syntax Reference

## Basic Commands

```bash
# Single file analysis
gemini -p "@path/to/file.py Explain this file's purpose"

# Multiple files
gemini -p "@package.json @src/index.js Analyze the dependencies used"

# Entire directory (recursive)
gemini -p "@src/ Summarize the architecture"

# All files in project
gemini --all_files -p "Analyze the project structure"
```

## Key Options

| Option | Purpose |
|--------|---------|
| `-p "prompt"` | Inline prompt (required) |
| `@path` | Include file or directory |
| `--all_files` | Include all project files |
| `--yolo` | Not needed for read-only analysis |

## Path Rules

- Paths are **relative to current working directory**
- Directory paths include all contents recursively
- Multiple `@` references can be combined
- Wildcards work: `@src/*.py`, `@**/*.ts`

## Reading PDFs and Documents

```bash
# Research paper
gemini -p "@paper.pdf Summarize the key contributions and methodology"

# Conference manuscript review
gemini -p "@manuscript.pdf Review for clarity, identify weak arguments, suggest improvements"

# Multiple papers comparison
gemini -p "@paper1.pdf @paper2.pdf Compare the approaches and findings"

# Extract specific information
gemini -p "@thesis.pdf Extract all equations and explain their purpose"
```

## Experiment Logs and Outputs

```bash
# Training logs
gemini -p "@logs/training.log Identify when loss stopped improving, any anomalies or errors"

# JSONL experiment results
gemini -p "@out/results.jsonl Summarize the experiment results with statistics"

# Multiple log analysis
gemini -p "@logs/*.log Find common error patterns across all runs"

# Hydra experiment output
gemini -p "@out/2026-01-28_experiment/ Analyze the config, logs, and outputs. What worked?"
```

---

# Workflow

## Step 1: Understand the Request

Parse what the user wants:
- **Codebase**: Architecture, patterns, implementations, security?
- **Documents**: Summarize, extract, transform, compare papers?
- **Logs/Data**: Analyze experiment results, find errors, compute stats?
- **Comparison**: Multiple files, configs, papers?
- **Transformation**: Convert format, extract structure, generate content?

## Step 2: Formulate the Gemini Command

Construct a precise prompt that:
1. Specifies exactly what files/directories to include
2. Asks a clear, specific question
3. Requests structured output when appropriate

**Good prompts:**
```bash
# Architecture analysis
gemini -p "@src/ Analyze the architecture. Identify: 1) Entry points 2) Core modules 3) Data flow 4) External dependencies"

# Pattern verification
gemini -p "@src/ Check if all database queries use parameterized statements. List any raw SQL string concatenation."

# Implementation search
gemini -p "@src/ @tests/ Find all implementations of rate limiting. Show file paths and brief descriptions."

# Consistency check
gemini -p "@packages/*/webpack.config.js Compare these configs. List inconsistencies in: loaders, plugins, output settings."
```

**Avoid vague prompts:**
```bash
# Too vague
gemini -p "@src/ Tell me about this code"  # What aspect?

# Better
gemini -p "@src/ Explain the authentication flow from login to session management"
```

## Step 3: Execute and Capture Output

```bash
# Run the command and capture output
gemini -p "@relevant/paths Query here"
```

- Gemini may produce verbose output; that's expected
- Output goes directly to Claude's context for synthesis

## Step 4: Synthesize and Report

After receiving Gemini's analysis:
1. Extract key findings relevant to the user's question
2. Organize into clear sections
3. Include specific file references and line numbers when provided
4. Note any limitations or areas needing follow-up

---

# Output Format

Return findings as:

```markdown
## Summary
[2-3 sentence answer to the user's question]

## Key Findings

### [Finding 1]
- **Location**: `path/to/relevant/files`
- **Details**: [What Gemini found]

### [Finding 2]
...

## Files Analyzed
- [List of directories/files included in analysis]

## Recommendations
- [Any suggested next steps or areas needing attention]
```

---

# Common Query Patterns

**Architecture Overview:**
```bash
gemini -p "@src/ Provide an architecture overview:
1. Directory structure and purpose of each major folder
2. Entry points (main files, CLI commands)
3. Core abstractions and patterns used
4. External dependencies and their roles
5. Data flow between components"
```

**Security Audit:**
```bash
gemini -p "@src/ Security audit:
1. Check for hardcoded secrets or credentials
2. Identify SQL injection vulnerabilities
3. Check authentication/authorization patterns
4. Review input validation
5. List any insecure dependencies"
```

**Implementation Search:**
```bash
gemini -p "@src/ Find all implementations of [FEATURE]:
- File paths where it's implemented
- How it's configured
- Any variations or inconsistencies
- Test coverage"
```

**Dependency Analysis:**
```bash
gemini -p "@package.json @src/ Analyze dependencies:
1. Which dependencies are actually used?
2. Which are imported but never used?
3. Any duplicate functionality?
4. Security concerns with any packages?"
```

**Paper Analysis:**
```bash
gemini -p "@paper.pdf Analyze this paper:
1. What is the main contribution?
2. What methodology do they use?
3. What are the key results and metrics?
4. What limitations do they acknowledge?
5. How does this relate to [specific topic]?"
```

**Experiment Log Analysis:**
```bash
gemini -p "@out/experiment/ Analyze this experiment run:
1. What were the hyperparameters used?
2. When did training converge (if at all)?
3. Were there any errors or warnings?
4. What were the final metrics?
5. Any anomalies or unexpected behavior?"
```

**Document Transformation:**
```bash
# Paper to blog post
gemini -p "@paper.pdf Convert this into a blog post outline.
Focus on: practical implications, key insights for practitioners,
skip: mathematical details, proofs"

# Logs to report
gemini -p "@logs/*.log Create a summary report of these experiment runs.
Include: success rate, common errors, performance trends"

# Extract structured data
gemini -p "@manuscript.pdf Extract all:
1. Hypotheses stated
2. Datasets used
3. Baseline methods compared
4. Statistical tests performed
Return as structured markdown tables"
```

**Plan Review (Second Opinion):**
```bash
gemini -p "@.claude/plans/plan.md @src/ Review this implementation plan. Identify:
1) Missed edge cases
2) Simpler alternatives
3) Files needing changes not mentioned in the plan
4) Potential breaking changes"
```

---

# Query Optimization Tips

1. **Be specific about scope**: `@src/api/` not `@src/` if you only need API code
2. **Ask for structured output**: Request lists, tables, or categories
3. **Break complex queries**: Multiple focused queries > one vague query
4. **Request file references**: Ask Gemini to cite specific files/lines

---

# Limitations

- Gemini CLI must be installed and authenticated (`gemini --version` to check)
- Network latency for API calls (larger content = longer processing)
- Results depend on Gemini's knowledge cutoff for factual claims
- Very large codebases/documents may still need focused queries
- Read-only: cannot execute code or modify files
- PDF parsing quality varies; scanned images may not extract well

# Error Handling

If `gemini` command fails:
1. Check if Gemini CLI is installed: `which gemini`
2. Verify authentication: `gemini --version`
3. Check path exists: `ls path/to/target`
4. Try smaller scope if timeout occurs

Report errors clearly to user with suggested fixes.
