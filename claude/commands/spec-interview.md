---
argument-hint: [spec-name or path/to/spec.md]
description: Interview-based spec development for large features
---

# Spec Interview

Read the skill at `~/.claude/skills/spec-interview/SKILL.md` and its references, then execute the interview workflow.

**Arguments**: `$ARGUMENTS`

Parse as:
- Empty → `specs/SPEC.md`
- Ends with `.md` → use path as-is
- Otherwise → `specs/{arg}.md`

Interview the user in-depth using AskUserQuestionTool until the spec is complete, then write to the determined path.
