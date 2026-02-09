# Plan: claude-context YAML redesign + drift detection

## Context

`claude-context` manages which Claude Code plugins load per-project. Currently uses 8 separate JSON templates that each enumerate all 30+ plugins with explicit true/false. Problems:

1. **Destructive merge** — replaces `enabledPlugins` entirely, silently deleting unmentioned plugins
2. **Massive duplication** — 80% of each template is `false` boilerplate; 6 always-on plugins repeated in every file
3. **No drift detection** — 3 new plugins already missing from templates, 1 stale
4. **Verbose** — adding a plugin means editing 5-8 JSON files
5. **No persistence** — running `claude-context code web` leaves no record of what a project uses

## Design

### Single `profiles.yaml` replaces 8 JSON files

**File:** `claude/templates/contexts/profiles.yaml`

```yaml
# Short name → qualified plugin ID (single source of truth)
registry:
  superpowers: superpowers@claude-plugins-official
  hookify: hookify@claude-plugins-official
  plugin-dev: plugin-dev@claude-plugins-official
  commit-commands: commit-commands@claude-plugins-official
  claude-md-management: claude-md-management@claude-plugins-official
  context7: context7@claude-plugins-official
  code-toolkit: code-toolkit@local-marketplace
  research-toolkit: research-toolkit@local-marketplace
  writing-toolkit: writing-toolkit@local-marketplace
  workflow-toolkit: workflow-toolkit@local-marketplace
  viz-toolkit: viz-toolkit@local-marketplace
  document-skills: document-skills@anthropic-agent-skills
  Notion: Notion@claude-plugins-official
  figma: figma@claude-plugins-official
  ui-ux-pro-max: ui-ux-pro-max@ui-ux-pro-max-skill
  frontend-design: frontend-design@claude-plugins-official
  huggingface-skills: huggingface-skills@claude-plugins-official
  vercel: vercel@claude-plugins-official
  coderabbit: coderabbit@claude-plugins-official
  code-simplifier: code-simplifier@claude-plugins-official
  security-guidance: security-guidance@claude-plugins-official
  code-review: code-review@claude-plugins-official
  pyright-lsp: pyright-lsp@claude-plugins-official
  typescript-lsp: typescript-lsp@claude-plugins-official
  ralph-loop: ralph-loop@claude-plugins-official
  serena: serena@claude-plugins-official
  feature-dev: feature-dev@claude-plugins-official
  stripe: stripe@claude-plugins-official
  example-plugin: example-plugin@claude-plugins-official
  claude-code-setup: claude-code-setup@claude-plugins-official
  playwright: playwright@claude-plugins-official
  supabase: supabase@claude-plugins-official
  pr-review-toolkit: pr-review-toolkit@claude-plugins-official
  playground: playground@claude-plugins-official
  linear: linear@claude-plugins-official

# Always-on in every profile (declared once, never repeated)
base:
  - superpowers
  - hookify
  - plugin-dev
  - commit-commands
  - claude-md-management
  - context7

# Profiles — only list what they ENABLE beyond base
profiles:
  code:
    comment: "Software projects"
    enable:
      - code-toolkit
      - workflow-toolkit
      - coderabbit
      - code-simplifier
      - security-guidance
      - code-review
      - feature-dev

  research:
    comment: "Experiments, evals, analysis"
    enable:
      - research-toolkit
      - writing-toolkit
      - workflow-toolkit
      - viz-toolkit
      - Notion

  writing:
    comment: "Papers, blog posts, documentation"
    enable:
      - writing-toolkit
      - viz-toolkit
      - workflow-toolkit
      - document-skills
      - Notion

  design:
    comment: "Frontend, visualizations, web"
    enable:
      - code-toolkit
      - viz-toolkit
      - document-skills
      - figma
      - ui-ux-pro-max
      - frontend-design
      - vercel
      - playwright

  full:
    comment: "Everything enabled (dotfiles, meta-work)"
    enable:
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

  # Sub-profiles (compose with domain)
  python:
    comment: "Adds pyright-lsp"
    enable: [pyright-lsp]

  web:
    comment: "Adds vercel, stripe, typescript-lsp, supabase"
    enable: [vercel, stripe, typescript-lsp, supabase]

  ml:
    comment: "Adds huggingface-skills"
    enable: [huggingface-skills]
```

**Why this eliminates drift:** Adding a new plugin = one line in `registry`. No profile updates needed — new plugins are disabled by default.

### Per-project `.claude/context.yaml`

```yaml
# .claude/context.yaml — committed, declares project's plugin needs
profiles: [code, web]
enable: [linear]       # optional: additional enables beyond profiles
disable: [playwright]  # optional: explicit disables
```

Behavior:
- `claude-context` (no args) — if `.claude/context.yaml` exists, apply it and show result
- `claude-context code web` (CLI args) — apply these profiles AND write/update `.claude/context.yaml`
- `claude-context --reset` — remove `enabledPlugins` from settings.json, delete context.yaml

This means CLI args are the primary interface but they persist automatically. No separate "save" step.

### Build algorithm (deterministic)

Every invocation builds `enabledPlugins` from scratch — no state leakage:

```
1. Load profiles.yaml
2. Start: all registry plugins → false
3. Enable base plugins
4. For each profile: enable its plugins
5. Apply enable/disable overrides from context.yaml
6. Resolve short names → qualified IDs via registry
7. Read existing .claude/settings.json
8. Replace only enabledPlugins key (preserve hooks, permissions, env, etc.)
9. Append any plugins in existing settings.json NOT in registry (future-proofing)
10. Atomic write: temp file in same dir → os.rename()
```

### Python rewrite

**File:** `custom_bins/claude-context` (shebang: `#!/usr/bin/env python3`)

**Dependency:** `pyyaml` — checked at import time with clear install instructions if missing.

Structure (~200 lines):
```python
#!/usr/bin/env python3
"""claude-context — YAML-driven plugin profiles for Claude Code."""

import argparse, json, os, sys, tempfile
try:
    import yaml
except ImportError:
    sys.exit("pyyaml required: pip install pyyaml")

# Constants
PROFILES_PATH = os.path.expanduser("~/.claude/templates/contexts/profiles.yaml")
GLOBAL_SETTINGS = os.path.expanduser("~/.claude/settings.json")
CONTEXT_FILE = ".claude/context.yaml"
TARGET_FILE = ".claude/settings.json"

# Colors (ANSI)
RED, GREEN, YELLOW, BLUE, NC = ...

def load_profiles(): ...       # Parse profiles.yaml → registry, base, profiles
def build_plugins(): ...       # Algorithm steps 2-6
def apply_to_settings(): ...   # Steps 7-10, atomic write
def show_status(): ...         # No-arg display
def check_drift(): ...         # --check
def sync_registry(): ...       # --sync
def reset(): ...               # --reset
def main(): ...                # argparse dispatch
```

## Subcommands

| Command | Behavior |
|---------|----------|
| `claude-context` | Show current state. If context.yaml exists, apply it. |
| `claude-context code [web] [python]` | Apply profiles, write settings.json + context.yaml |
| `claude-context --check` | Compare registry against global settings.json. Exit 0 if in sync, 1 if drift. |
| `claude-context --sync` | Add new plugins from global settings.json to registry in profiles.yaml. |
| `claude-context --reset` | Remove enabledPlugins from project settings.json, delete context.yaml. |
| `claude-context --help` | Help text |

## Implementation Steps

### Step 0: Update `claude/CLAUDE.md` (document convention first)

Replace lines 126-138 of `claude/CLAUDE.md` (the "Context profiles" section):

```markdown
**Context profiles** control which plugins load per-project via `claude-context`:
```bash
claude-context                    # Show current / apply context.yaml
claude-context code               # Software projects
claude-context code web python    # Compose multiple profiles
claude-context --check            # Detect registry drift
claude-context --sync             # Fix drift in profiles.yaml
claude-context --reset            # Clear project plugin config
```

**Architecture:**
- Profile definitions: `~/.claude/templates/contexts/profiles.yaml` (registry + base + per-profile enables)
- Per-project config: `.claude/context.yaml` (profiles + optional enable/disable overrides, committed)
- Output: `.claude/settings.json` `enabledPlugins` section (deterministic rebuild from profiles)
- CLI args persist to `context.yaml` automatically; no-arg invocation re-applies it

Adding a new plugin: one line in `profiles.yaml` registry. Restart Claude Code after applying.
```

### Step 1: Create `profiles.yaml`
- Build from current JSON templates (extract registry, base, per-profile enables)
- Verify round-trip: for each old JSON template, the new YAML produces identical `enabledPlugins`

### Step 2: Rewrite `claude-context` in Python
- Replace bash script in-place (`custom_bins/claude-context`)
- Implement all subcommands
- Implement per-project context.yaml read/write

### Step 3: Delete old JSON templates
- Remove `claude/templates/contexts/{code,research,writing,design,full,python,web,ml}.json`

### Step 4: Update docs
- `claude/CLAUDE.md` — context profiles section: mention YAML, settings.json (not settings.local.json)
- `CLAUDE.md` — project CLAUDE.md: update context profile references
- Help text in the script itself

### Step 5: Verify
1. `claude-context --check` → exit 0 (registry matches global settings.json)
2. `claude-context code` in a test dir → correct settings.json, context.yaml created
3. `claude-context code web` → composition works, both profiles in context.yaml
4. `claude-context research` after `code` → no code plugins leak (deterministic rebuild)
5. Manual plugin in settings.json → preserved after `claude-context code` (step 9)
6. `claude-context` no args with existing context.yaml → auto-applies
7. `claude-context --reset` → clean slate
8. Remove a plugin from global settings.json, `claude-context --check` → reports registry has extra

## Files (in order)

| Step | File | Action |
|------|------|--------|
| 0 | `claude/CLAUDE.md` | **Edit** context profiles section (document convention first) |
| 1 | `claude/templates/contexts/profiles.yaml` | **Create** single YAML definitions |
| 2 | `custom_bins/claude-context` | **Rewrite** bash → Python |
| 3 | `claude/templates/contexts/*.json` (8 files) | **Delete** old JSON templates |
| 4 | `CLAUDE.md` | **Edit** project CLAUDE.md references |
