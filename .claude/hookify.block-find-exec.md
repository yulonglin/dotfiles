---
name: block-find-exec
enabled: true
event: bash
pattern: find\s+.*\s+-(exec|delete|ok)\b
action: block
---

**Use Glob + Grep tools instead of `find -exec`.**

`find -exec` executes arbitrary code and triggers permission prompts. Safer alternatives:

- **Find files by pattern:** `Glob("**/*.json")` or `Glob("**/plugin.json")`
- **Search file contents:** `Grep` with `pattern` + `glob` filter
- **Find + filter:** `Glob` first, then `Grep` on matched files

These dedicated tools are faster, sandboxed, and don't require permission escalation.
