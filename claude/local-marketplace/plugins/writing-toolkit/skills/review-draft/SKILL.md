---
name: review-draft
description: Comprehensive writing review using specialized critics (clarity, narrative, facts, red-team).
---

# Review Draft

Comprehensive writing review using specialized critics.

## Arguments

Parse from provided arguments:
- **File path**: First non-flag argument (required)
- **--critics=**: Comma-separated list of critics to run (default: all five)
  - `clarity` - Sentence-level readability
  - `humanizer` - LLM cliche and chatbot artifact detection
  - `narrative` - Structure and argument flow
  - `facts` - Claim verification and citations
  - `redteam` - Counterexamples and objections
- **--sensitivity=**: `conservative|balanced|aggressive` (default: balanced)

## Workflow

1. **Parse arguments** from above
2. **Validate file exists** - error if not found
3. **Ask for target audience** using AskUserQuestion (required for all critics)
4. **Create feedback directory** - ensure `feedback/` exists in draft's directory
5. **Dispatch selected critics in parallel** using Task tool
6. **Summarize** - report completion and highlight top issue from each

## Agent Dispatch

Launch agents **in parallel** using Task tool with these prompts:

| Critic | subagent_type | Output File |
|--------|---------------|-------------|
| clarity | `clarity-critic` | `feedback/{name}_clarity.md` |
| humanizer | `humanizer` | `feedback/{name}_humanizer.md` |
| narrative | `narrative-critic` | `feedback/{name}_narrative.md` |
| facts | `fact-checker` | `feedback/{name}_facts.md` |
| redteam | `red-team` | `feedback/{name}_redteam.md` |

Where `{name}` is the draft filename without extension.

**Agent prompt template**:
```
Review the draft at {file_path} for {audience}.
Sensitivity: {sensitivity}
Write feedback to feedback/{name}_{type}.md
```

## Post-Review Summary

```
## Review Complete

Feedback written to `feedback/`:
{list files created}

**Start with**: {most impactful issue from any critic}
```

## Error Handling

| Scenario | Response |
|----------|----------|
| File not found | Error with clear message |
| Empty file | "Nothing to review" |
| >5000 words | Proceed with truncation warning |
| `feedback/` missing | Create it |
| Agent fails | Report failure, continue with others |

## Examples

```
/review-draft paper.md                              # All 4 critics
/review-draft paper.md --critics=clarity            # Just clarity
/review-draft paper.md --critics=clarity,facts      # Clarity + facts
/review-draft paper.md --sensitivity=aggressive     # Stricter review
```
