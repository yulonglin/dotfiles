---
name: spec-interview
description: Interview-based spec development for large features. Iteratively questions user about implementation, UX, concerns, and tradeoffs before writing a complete specification.
---

# Spec Interview

Build complete specifications through in-depth interviewing before implementation.

## Usage

```
/spec-interview                     # → specs/SPEC.md
/spec-interview auth-system         # → specs/auth-system.md
/spec-interview specs/existing.md   # → uses existing file as context
```

## Core Workflow

1. **Read existing context** (if file exists or user provides description)
2. **Interview iteratively** using AskUserQuestionTool
3. **Write completed spec** to file
4. **User starts new session** to execute

## Interview Principles

- Ask **non-obvious** questions - not "what should it do?" but "what happens when X fails during Y?"
- **2-4 questions per round**, probe deeper on vague answers
- **Challenge assumptions** - "why not do X instead?"
- Continue until all major areas covered

## Reference Files

- **`references/interview-guide.md`** - Question categories, example questions, completion checklist
- **`references/spec-template.md`** - Output structure for the final spec

## When Complete

Tell user: spec written to `{path}`, suggest new session to execute, highlight open questions.
