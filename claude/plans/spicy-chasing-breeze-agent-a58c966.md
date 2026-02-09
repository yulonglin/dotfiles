# Review: `claude-context` Design and Implementation

## Executive Summary

The current implementation works but is fighting against itself. You have 8 JSON template files that are 90% identical boilerplate, a bash script shelling out to inline Python for trivial JSON operations, and a target file (`settings.json`) that mixes plugin state with permissions, hooks, sandbox config, and other settings that should never be touched by a context-switching tool. The YAML-driven approach you're considering is the right direction, but the details matter.

---

## 1. YAML Config Driving JSON Generation: Yes, This Is Idiomatic

This is a well-established pattern (Helm values.yaml -> K8s manifests, Ansible vars -> config templates, Nix -> system configs). The key insight is that your current templates encode two kinds of information:

1. **Profile semantics**: "the code profile enables code-toolkit, coderabbit, feature-dev"
2. **Plugin registry**: "here is the exhaustive list of all 30+ plugins with their qualified names"

These should be separated. The profile definition should only contain (1). The full plugin registry should exist in exactly one place, and generation should combine them.

**Recommended single-file format** -- replace all 8 JSON files with one YAML file:

```yaml
# ~/.claude/templates/contexts/profiles.yaml

# Plugin registry: short name -> qualified identifier
# Single source of truth. Add new plugins here when Claude Code introduces them.
registry:
  # Always-on (every profile)
  superpowers: superpowers@claude-plugins-official
  hookify: hookify@claude-plugins-official
  plugin-dev: plugin-dev@claude-plugins-official
  commit-commands: commit-commands@claude-plugins-official
  claude-md-management: claude-md-management@claude-plugins-official
  context7: context7@claude-plugins-official
  # Local marketplace
  research-toolkit: research-toolkit@local-marketplace
  writing-toolkit: writing-toolkit@local-marketplace
  code-toolkit: code-toolkit@local-marketplace
  workflow-toolkit: workflow-toolkit@local-marketplace
  viz-toolkit: viz-toolkit@local-marketplace
  # Third-party
  document-skills: document-skills@anthropic-agent-skills
  Notion: Notion@claude-plugins-official
  coderabbit: coderabbit@claude-plugins-official
  # ... etc

# Plugins enabled in EVERY profile (no need to repeat)
always_on:
  - superpowers
  - hookify
  - plugin-dev
  - commit-commands
  - claude-md-management
  - context7

# Profile definitions: list only what they ADD beyond always_on
profiles:
  code:
    description: "Software projects"
    plugins:
      - code-toolkit
      - workflow-toolkit
      - coderabbit
      - code-simplifier
      - security-guidance
      - code-review
      - feature-dev

  writing:
    description: "Papers, blog posts, documentation"
    plugins:
      - writing-toolkit
      - viz-toolkit
      - workflow-toolkit
      - document-skills
      - Notion

  research:
    description: "Experiments, evals, analysis"
    plugins:
      - research-toolkit
      - writing-toolkit
      - workflow-toolkit
      - viz-toolkit
      - Notion

  design:
    description: "Frontend, visualizations, web"
    plugins:
      - code-toolkit
      - viz-toolkit
      - document-skills
      - figma
      - ui-ux-pro-max
      - frontend-design
      - vercel
      - playwright

  full:
    description: "Everything enabled (dotfiles, meta-work)"
    plugins:
      - research-toolkit
      - writing-toolkit
      - code-toolkit
      - workflow-toolkit
      - viz-toolkit
      - document-skills
      - Notion
      - coderabbit
      - code-simplifier
      - security-guidance
      - code-review

  # Sub-profiles (composable)
  python:
    description: "Adds pyright-lsp"
    plugins:
      - pyright-lsp

  web:
    description: "Adds web stack"
    plugins:
      - vercel
      - stripe
      - typescript-lsp
      - supabase

  ml:
    description: "Adds HuggingFace"
    plugins:
      - huggingface-skills
```

**Why this is better:**
- **1 file instead of 8**: The `code` profile definition is 7 lines, not 36.
- **No duplication**: `always_on` is declared once. Each profile lists only its deltas.
- **Registry solves drift**: When Claude Code adds a new plugin, you add one line to `registry`. The `--check`/`--sync` logic becomes trivial: compare registry keys against `settings.json` keys.
- **Readable**: A human can glance at this and understand what each profile does. The current JSON files are walls of true/false that require mental diffing.

---

## 2. Current Code Quality Issues

### 2a. Inline Python is the wrong tool

The script uses `python3 -c "..."` with bash variable interpolation (`$TEMPLATES_DIR`, `$TARGET_FILE`) embedded inside Python strings. This is fragile:

- **Injection risk**: If `$TEMPLATES_DIR` contains a quote or backslash, the Python code breaks. Not exploitable in practice (you control the path), but it's sloppy.
- **Quoting hell**: The `list_profiles` function does `python3 -c "import json; d=json.load(open('$f'))"` -- if any filename has a single quote, this crashes.
- **Debugging pain**: Syntax errors in inline Python produce inscrutable error messages with no line numbers.

**Recommendation**: Either write the whole thing in Python (it's a 50-line script that does JSON/YAML manipulation -- bash adds nothing), or use `jq` for the JSON operations. Given the YAML migration, Python is the clear choice.

A standalone `claude-context` Python script with `#!/usr/bin/env python3` would be:
- Shorter (no bash boilerplate for colors, argument parsing)
- Testable
- Able to use `yaml.safe_load` directly
- Free of quoting issues

If you want to keep the bash wrapper for PATH/env reasons, have it call a Python script rather than embedding Python inline.

### 2b. Error handling gaps

- `python3 -c` failures in `list_profiles` are silently swallowed (`2>/dev/null || echo ""`)
- `apply_profiles` has no error handling if `python3` itself is missing
- The `mkdir -p .claude` could succeed but the Python write could fail, leaving a half-created directory
- No validation that the current directory is actually a git repo or has a `.claude/` that makes sense

### 2c. Missing `settings.local.json` vs `settings.json` confusion

The CLAUDE.md documentation says the tool writes to `settings.local.json` (gitignored), but the actual code writes to `settings.json` (committed). There's an existing plan (`spicy-chasing-breeze.md`) that notes this discrepancy. The code and docs disagree -- the code is doing the right thing (writing to `settings.json` so it's committed per-project), but the docs are wrong.

---

## 3. `settings.json` as Target: Real Risks

### 3a. Destructive merge (already identified in your plan)

The current code does `existing['enabledPlugins'] = merged`, which **replaces** the entire `enabledPlugins` dict. If your `settings.json` has plugins not mentioned in any template (like `linear`, `playground`, `pr-review-toolkit` which are in the global settings.json but missing from templates), they get silently deleted. The fix in `spicy-chasing-breeze.md` (overlay instead of replace) is correct.

### 3b. The real design problem: scope contamination

`settings.json` contains **permissions**, **hooks**, **sandbox config**, **env vars**, and **plugin state** all in one file. The `claude-context` tool should only touch `enabledPlugins`, but it reads/writes the entire file. The current code handles this correctly (reads existing, modifies only `enabledPlugins`, writes back), but it's one bug away from nuking your permissions config.

**Risk scenario**: If the Python inline code crashes mid-write (power loss, disk full), you get a truncated `settings.json` and lose your permissions, hooks, everything. This is unlikely but the blast radius is unnecessarily large.

**Mitigation**: Write to a temp file first, then `mv` atomically:
```python
import tempfile, os
with tempfile.NamedTemporaryFile('w', dir='.claude', suffix='.json', delete=False) as tmp:
    json.dump(existing, tmp, indent=2)
    tmp.write('\n')
os.rename(tmp.name, TARGET_FILE)
```

### 3c. Claude Code reading during write

Claude Code reads `settings.json` at startup and likely watches it for changes. A non-atomic write (the current `open('w')` approach) could theoretically be read mid-write. In practice, the file is small enough that this is vanishingly unlikely, but atomic writes via temp+rename cost nothing and eliminate the risk entirely.

### 3d. Merge conflicts in git

Since `settings.json` is committed and contains the full plugin list with true/false values, two branches with different profiles will conflict on every line of `enabledPlugins`. This is manageable for a personal repo (you're the only committer), but worth noting. The YAML approach actually helps here: if you commit the per-project YAML config instead of the generated JSON, the YAML is tiny and conflicts are trivial.

**Possible future enhancement**: Have `claude-context` generate `settings.json` from the YAML at Claude Code startup (via a hook or shell init), and gitignore the generated `settings.json`. Commit only the YAML. But this adds complexity and isn't necessary today.

---

## 4. Profile Definitions: Consolidate into One File

**Strong recommendation: one YAML file, delete all 8 JSON templates.**

The current state:
- 8 files, 5 of which are 36-line walls of JSON
- Every file repeats the same 6 always-on plugins as `true` and the same ~15 never-on plugins as `false`
- Adding a new plugin to Claude Code requires editing all 8 files (or using `--sync`, which is a band-aid)
- The sub-profiles (`python.json`, `web.json`, `ml.json`) are already concise because they only list their additions -- this proves the approach works

The YAML format I proposed above reduces the 5 domain profiles from ~180 lines of JSON to ~35 lines of YAML, and the sub-profiles from 3 files to 3 stanzas. The registry provides the single source of truth for plugin qualified names.

**The `--check`/`--sync` commands become unnecessary** with this approach. Drift detection is: "is every plugin in `settings.json` also in `registry`?" One comparison, no template fan-out.

---

## 5. Recommended Implementation Plan

### Phase 1: Create `profiles.yaml`, rewrite `claude-context` in Python

1. Create `~/.claude/templates/contexts/profiles.yaml` with the format above
2. Rewrite `claude-context` as a Python script (~80 lines):
   - Parse profiles.yaml with `yaml.safe_load` (stdlib `yaml` not available; use `pip install pyyaml` or parse the simple YAML manually -- but `pyyaml` is better)
   - Generate `enabledPlugins` dict: always_on + profile plugins = true, everything else in registry = false
   - Read existing `settings.json`, overlay `enabledPlugins`, atomic-write back
   - Subcommands: `show` (default), `apply <profiles...>`, `check` (registry vs settings.json)
3. Delete the 8 JSON template files
4. Fix CLAUDE.md docs (settings.local.json -> settings.json)

### Phase 2 (optional): Per-project YAML config

Support a `.claude/context.yaml` in each repo:
```yaml
profiles: [code, python]
overrides:
  linear: true
```

This would let `claude-context` (or a hook) generate `settings.json` from the project-level YAML automatically. The YAML is tiny, readable, and merge-conflict-friendly. But this is a future enhancement -- the Phase 1 CLI approach is already a big improvement.

### Dependency concern: PyYAML

`pyyaml` is not in Python's stdlib. Options:
1. **Require it**: `pip install pyyaml` or `uv pip install pyyaml`. Reasonable for a dotfiles repo.
2. **Use a simpler format**: The profiles.yaml structure is simple enough to parse with regex (all values are strings or lists of strings). But this is fragile and defeats the purpose.
3. **Use TOML instead**: Python 3.11+ has `tomllib` in stdlib. TOML is slightly less readable for this use case but eliminates the dependency.

**Recommendation**: Use TOML if you want zero dependencies (Python 3.11+ is safe to assume on your machines). Use YAML if you prefer the readability and are fine with the `pyyaml` dependency.

```toml
# profiles.toml alternative

[registry]
superpowers = "superpowers@claude-plugins-official"
hookify = "hookify@claude-plugins-official"
# ...

[always_on]
plugins = ["superpowers", "hookify", "plugin-dev", "commit-commands", "claude-md-management", "context7"]

[profiles.code]
description = "Software projects"
plugins = ["code-toolkit", "workflow-toolkit", "coderabbit", "code-simplifier", "security-guidance", "code-review", "feature-dev"]
```

TOML is slightly noisier but the stdlib advantage is real.

---

## Summary of Recommendations

| Question | Recommendation |
|----------|---------------|
| YAML driving JSON generation? | Yes, idiomatic. Do it. |
| Keep 8 JSON templates? | No. One YAML (or TOML) file. Delete all 8. |
| Bash + inline Python? | No. Rewrite as pure Python (~80 lines). |
| Target `settings.json`? | Fine, but use atomic writes (temp + rename). |
| `settings.local.json` vs `settings.json`? | Fix the docs. `settings.json` (committed) is correct. |
| Drift detection (`--check`/`--sync`)? | Becomes trivial with registry approach. Keep but simplify. |
| YAML vs TOML? | TOML if zero-dep matters (stdlib in 3.11+). YAML if readability matters more. |
| Per-project YAML config? | Good future enhancement, not needed for Phase 1. |
