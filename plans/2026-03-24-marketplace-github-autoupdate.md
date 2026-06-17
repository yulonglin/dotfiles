# Marketplace GitHub-First + Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all plugin marketplaces use GitHub repos with auto-update enabled, fully version-controlled so every machine gets the same behavior.

**Architecture:** Three layers of config work together: (1) `extraKnownMarketplaces` in `claude/settings.json` declares all marketplace sources (version-controlled, portable), (2) `profiles.yaml` declares `autoUpdate: true` per marketplace (version-controlled source of truth), (3) `claude-context --sync` applies the autoUpdate flag to Claude Code's runtime `known_marketplaces.json`. A SessionStart hook warns when no context profile is configured.

**Tech Stack:** Python (claude-context), Bash (hook), JSON/YAML (config)

---

## File Structure

| File | Responsibility | Change Type |
|------|---------------|-------------|
| `claude/settings.json:305-330` | Declares marketplace sources for Claude Code | Modify (add 2 missing marketplaces) |
| `claude/templates/contexts/profiles.yaml:1-28` | Declarative marketplace registry + autoUpdate flag | Modify (remove local:, add autoUpdate) |
| `custom_bins/claude-context:251-348` | Sync logic: register, update, apply autoUpdate | Modify (update resolve fn, add autoUpdate patch) |
| `claude/hooks/context_auto_apply.sh` | SessionStart hook | Modify (add no-context warning) |

---

### Task 1: Add missing marketplaces to settings.json

**Files:**
- Modify: `claude/settings.json:305-330`

- [ ] **Step 1: Add `claude-plugins-official` and `alignment-hive` to `extraKnownMarketplaces`**

Add these two entries to the existing `extraKnownMarketplaces` block (which already has ai-safety-plugins, productivity-tools, dev-browser-marketplace, ui-ux-pro-max-skill):

```json
"claude-plugins-official": {
  "source": {
    "source": "github",
    "repo": "anthropics/claude-plugins-official"
  }
},
"alignment-hive": {
  "source": {
    "source": "github",
    "repo": "Crazytieguy/alignment-hive"
  }
},
```

- [ ] **Step 2: Verify JSON is valid**

Run: `python3 -c "import json; json.load(open('claude/settings.json'))"`
Expected: no output (valid JSON)

- [ ] **Step 3: Commit**

```bash
git add claude/settings.json
git commit -m "feat: add all 6 marketplaces to extraKnownMarketplaces"
```

---

### Task 2: Update profiles.yaml to GitHub-only with autoUpdate

**Files:**
- Modify: `claude/templates/contexts/profiles.yaml:1-28`

- [ ] **Step 1: Remove `local:` keys, add `autoUpdate: true` to all marketplaces**

Replace the marketplaces block (lines 7-28) with:

```yaml
# Plugin marketplaces — registered + synced by `claude-context --sync`
# All use GitHub repos for portability. autoUpdate: true enables startup auto-update.
# For local dev, set CLAUDE_CONTEXT_LOCAL=1 and add local: paths.
marketplaces:
  claude-plugins-official:
    github: anthropics/claude-plugins-official
    autoUpdate: true

  ai-safety-plugins:
    github: yulonglin/ai-safety-plugins
    autoUpdate: true

  dev-browser:
    github: sawyerhood/dev-browser
    autoUpdate: true

  ui-ux-pro-max-skill:
    github: nextlevelbuilder/ui-ux-pro-max-skill
    autoUpdate: true

  alignment-hive:
    github: Crazytieguy/alignment-hive
    autoUpdate: true

  productivity-tools:
    github: yulonglin/productivity-tools
    autoUpdate: true
```

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('claude/templates/contexts/profiles.yaml'))"`
Expected: no output (valid YAML)

- [ ] **Step 3: Commit**

```bash
git add claude/templates/contexts/profiles.yaml
git commit -m "feat: remove local marketplace paths, add autoUpdate flags"
```

---

### Task 3: Update claude-context to apply autoUpdate

**Files:**
- Modify: `custom_bins/claude-context:251-348`

- [ ] **Step 1: Update `resolve_marketplace_source()` to be GitHub-first**

Replace the function (lines 251-265) so local paths are only used when `CLAUDE_CONTEXT_LOCAL=1`:

```python
def resolve_marketplace_source(name, config):
    """Return (source_string, source_type) for a marketplace.

    Uses GitHub by default. Set CLAUDE_CONTEXT_LOCAL=1 to prefer local paths.
    """
    if os.environ.get("CLAUDE_CONTEXT_LOCAL") == "1":
        local = config.get("local")
        if local:
            expanded = expand_env(local)
            if os.path.isdir(os.path.join(expanded, ".claude-plugin")):
                return expanded, "local"
    github = config.get("github")
    if github:
        return github, "github"
    return None, None
```

- [ ] **Step 2: Add `apply_auto_update()` function after `sync_marketplaces()`**

Add this function right after `sync_marketplaces()` returns (before `normalize_scopes`):

```python
KNOWN_MARKETPLACES = os.path.expanduser("~/.claude/plugins/known_marketplaces.json")

def apply_auto_update(verbose=False):
    """Patch known_marketplaces.json with autoUpdate flags from profiles.yaml."""
    marketplaces = load_marketplaces()
    if not marketplaces:
        return

    if not os.path.isfile(KNOWN_MARKETPLACES):
        if verbose:
            print(f"  {YELLOW}known_marketplaces.json not found — skipping autoUpdate{NC}")
        return

    try:
        with open(KNOWN_MARKETPLACES) as f:
            known = json.load(f)
    except (json.JSONDecodeError, OSError):
        return

    changed = 0
    for name, config in marketplaces.items():
        auto_update = config.get("autoUpdate", False)
        if name in known:
            current = known[name].get("autoUpdate")
            if current != auto_update:
                known[name]["autoUpdate"] = auto_update
                changed += 1
                if verbose:
                    print(f"  {name}: autoUpdate → {auto_update}")

    if changed:
        with open(KNOWN_MARKETPLACES, "w") as f:
            json.dump(known, f, indent=4)
            f.write("\n")
        print(f"{GREEN}Applied autoUpdate to {changed} marketplace(s){NC}")
    elif verbose:
        print(f"  autoUpdate: all up to date")
```

- [ ] **Step 3: Call `apply_auto_update()` from `sync_marketplaces()` before `normalize_scopes()`**

In `sync_marketplaces()`, add the call at line 346 (before `normalize_scopes`):

```python
    # Apply autoUpdate flags from profiles.yaml
    apply_auto_update(verbose=verbose)

    normalize_scopes(verbose=verbose)
```

- [ ] **Step 4: Verify syntax**

Run: `python3 -c "import py_compile; py_compile.compile('custom_bins/claude-context', doraise=True)"`
Expected: no output (valid Python)

- [ ] **Step 5: Commit**

```bash
git add custom_bins/claude-context
git commit -m "feat: claude-context applies autoUpdate from profiles.yaml to runtime config"
```

---

### Task 4: Add no-context warning to SessionStart hook

**Files:**
- Modify: `claude/hooks/context_auto_apply.sh`

- [ ] **Step 1: Add warning when no context.yaml exists**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml if present, warn if missing
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-context 2>/dev/null
else
    # Only warn if we're in a git repo (not a random directory)
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "\033[0;33mNo context profile configured.\033[0m Run \`claude-context <profile>\` to set one." >&2
    fi
fi
exit 0  # Don't block session start
```

- [ ] **Step 2: Commit**

```bash
git add claude/hooks/context_auto_apply.sh
git commit -m "feat: warn on session start when no context profile configured"
```

---

### Task 5: Update CLAUDE.md documentation

**Files:**
- Modify: `CLAUDE.md` (Learnings section)

- [ ] **Step 1: Add learning about marketplace config**

Append to the Learnings section:

```markdown
- Marketplace auto-update: `extraKnownMarketplaces` in settings.json declares sources (portable), `autoUpdate: true` in profiles.yaml is source of truth, `claude-context --sync` patches runtime `known_marketplaces.json`. Local paths opt-in via `CLAUDE_CONTEXT_LOCAL=1` (2026-03-24)
```

- [ ] **Step 2: Commit and push**

```bash
git add CLAUDE.md
git commit -m "docs: add marketplace auto-update learning"
git push
```
