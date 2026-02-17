# Plan: claude-context v2 — Auto-discover + Better UX

## Context

`claude-context` is a 550-line Python CLI that manages per-project Claude Code plugin sets via composable profiles. The tool works but has poor UX: a manually-maintained registry that duplicates `installed_plugins.json`, `--check/--sync` commands that never catch real drift, no visibility into active plugins, and no session integration.

**Goal:** Eliminate the manual registry, add plugin visibility (statusline + list + session-start), and simplify the codebase from ~550 to ~350 lines.

## Changes

### 1. Auto-discover registry from `installed_plugins.json`

**File:** `custom_bins/claude-context`

Replace manual registry loading with auto-discovery:

```python
INSTALLED_PLUGINS = os.path.expanduser("~/.claude/plugins/installed_plugins.json")

def load_registry():
    """Build registry from installed_plugins.json (source of truth)."""
    if not os.path.exists(INSTALLED_PLUGINS):
        sys.exit(f"{RED}installed_plugins.json not found{NC}")
    with open(INSTALLED_PLUGINS) as f:
        data = json.load(f)
    registry = {}
    for qid in data.get("plugins", {}):
        short = qid.split("@")[0]
        if short in registry:
            # Collision: keep both with full qualified IDs
            old_qid = registry.pop(short)
            registry[old_qid] = old_qid
            registry[qid] = qid
        else:
            registry[short] = qid
    return registry
```

Update `load_profiles()` to no longer read `registry:` from profiles.yaml — call `load_registry()` separately.

### 2. Simplify `profiles.yaml` — remove registry section

**File:** `~/.claude/templates/contexts/profiles.yaml`

Delete the entire `registry:` block (lines 7-46). Keep only `base:` and `profiles:`.

```yaml
# profiles.yaml — composable plugin profiles
base:
  - superpowers
  - hookify
  - plugin-dev
  - commit-commands
  - claude-md-management
  - context7
  - core-toolkit

profiles:
  code:
    comment: "Software projects"
    enable: [code-toolkit, workflow-toolkit, coderabbit, code-simplifier, security-guidance, code-review, feature-dev]
  # ... (rest unchanged)
```

### 3. Delete dead code (~220 lines removed)

**File:** `custom_bins/claude-context`

Remove entirely:
- `resolve_name()` — no longer needed (registry has qualified IDs)
- `check_drift()` — no registry to compare
- `sync_registry()` — no registry to sync
- `prompt_profile_assignment()` — sync UI gone
- `_find_enable_insert_point()` — YAML manipulation gone
- `_insert_into_flow_enable()` — YAML manipulation gone
- `--check` and `--sync` arg parsing + dispatch

### 4. Improve no-args default: show active context clearly

**File:** `custom_bins/claude-context`

When run with no args, show a clear view of what's active. Replace `show_status()`:

```python
def show_status():
    """Show current active context and available profiles."""
    # --- Active context ---
    # Read project settings if present, else global
    settings_path = TARGET_FILE if os.path.exists(TARGET_FILE) else GLOBAL_SETTINGS
    with open(settings_path) as f:
        data = json.load(f)
    plugins = data.get("enabledPlugins", {})

    on = sorted(k.split("@")[0] for k, v in plugins.items() if v)
    off = sorted(k.split("@")[0] for k, v in plugins.items() if not v)

    # Context header
    ctx = load_context_yaml()
    if ctx:
        pnames, enable, disable = ctx
        print(f"{BOLD}Active context:{NC} {BLUE}{', '.join(pnames)}{NC}")
        if enable:
            print(f"  + {', '.join(enable)}")
        if disable:
            print(f"  - {', '.join(disable)}")
    elif os.path.exists(TARGET_FILE):
        print(f"{BOLD}Active context:{NC} {YELLOW}manual{NC} (no context.yaml)")
    else:
        print(f"{BOLD}Active context:{NC} {YELLOW}global defaults{NC}")

    # Plugin status
    print(f"\n{GREEN}ON  ({len(on)}):{NC} {', '.join(on)}")
    if off:
        print(f"{YELLOW}OFF ({len(off)}):{NC} {', '.join(off)}")

    # --- Available profiles ---
    _, _, profiles = load_profiles()
    print(f"\n{BOLD}Profiles:{NC}")
    for name, pdata in profiles.items():
        comment = pdata.get("comment", "")
        print(f"  {GREEN}{name:<12}{NC} {comment}")
```

Also add `--list` as an alias for this (for discoverability):
```python
parser.add_argument("--list", action="store_true", help="Show active plugins")
# In dispatch: if args.list -> show_status()
```

**No-args behavior changes:**
- **Before:** If context.yaml exists → silently apply it. If not → show profiles.
- **After:** Always show current status first (what's ON/OFF). If context.yaml exists → also apply it. Then show available profiles.

### 5. Add warnings for missing context and stale settings

**File:** `custom_bins/claude-context`

**A. No context in current repo:**

In `show_status()`, after checking for context.yaml:

```python
# Warn if project has .claude/ but no context.yaml
if not ctx and os.path.isdir(".claude") and not os.path.exists(CONTEXT_FILE):
    print(f"{YELLOW}Warning: this project has .claude/ but no context.yaml{NC}")
    print(f"  Run: claude-context <profile> to set up context")
```

**B. Marketplace/qualified-ID drift detection:**

When applying or showing status, compare project settings.json qualified IDs against what's actually installed:

```python
def check_stale_settings():
    """Warn if project settings.json references plugins with changed qualified IDs."""
    if not os.path.exists(TARGET_FILE):
        return
    with open(TARGET_FILE) as f:
        project_plugins = json.load(f).get("enabledPlugins", {})

    registry = load_registry()  # from installed_plugins.json
    installed_qids = set(registry.values())

    stale = []
    for qid in project_plugins:
        if qid not in installed_qids:
            short = qid.split("@")[0]
            # Check if same short name exists under different marketplace
            new_qid = registry.get(short)
            if new_qid and new_qid != qid:
                stale.append((qid, new_qid))
            elif not new_qid:
                stale.append((qid, None))  # plugin no longer installed

    if stale:
        print(f"\n{YELLOW}Stale settings detected:{NC}")
        for old, new in stale:
            if new:
                print(f"  {old} → {new}")
            else:
                print(f"  {old} (no longer installed)")
        print(f"{BLUE}Run: claude-context <profile> to refresh{NC}")
```

Call `check_stale_settings()` from `show_status()` and from the SessionStart hook (via exit code or stderr output).

### 6. Add SessionStart hook — auto-apply context.yaml

**File (new):** `claude/hooks/context_auto_apply.sh`

```bash
#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml if present
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-context 2>/dev/null
fi
```

**File:** core-toolkit `plugin.json` (lines 52-61) — add the new hook to SessionStart array.

Note: The hook runs `claude-context` (no args), which auto-applies context.yaml if present (existing behavior at line 540 of current code). This ensures settings.json stays fresh on every session start.

### 6. Add context info to statusline

**File:** `claude/statusline.sh`

Add a new section between machine info and directory path:

```bash
# CONTEXT PROFILES (from context.yaml if present)
context_profiles=""
if [ -f "$cwd/.claude/context.yaml" ]; then
    # Extract profile names from YAML (simple grep, no pyyaml dependency)
    profiles_line=$(grep -A1 '^profiles:' "$cwd/.claude/context.yaml" 2>/dev/null | tail -1)
    if [ -n "$profiles_line" ]; then
        # Parse YAML list: "- code" -> "code", or flow style "[code, python]"
        profiles=$(echo "$profiles_line" | sed 's/.*\[//;s/\].*//;s/- //g' | tr -d ' ' | tr ',' ' ')
        if [ -n "$profiles" ]; then
            # Cyan color for context profiles
            context_profiles="[$(printf "\033[36m")${profiles}$(printf "\033[0m")] "
        fi
    fi
fi
```

Then prepend `$context_profiles` to the output line (before `$dir`):
```bash
printf "%s%s\033[2m\033[36m%s\033[0m%s%s%s" "$machine_info" "$context_profiles" "$dir" "$git_info" "$context_info" "$cost_info"
```

Display example: `[code python] ~/code/myproject (main*) +5,-3 📊 42% $1.23`

### 7. Update `build_plugins()` — graceful handling of uninstalled plugins

**File:** `custom_bins/claude-context`

Change hard `sys.exit()` for unknown plugins in profiles to a warning:

```python
# In build_plugins(), step 3 (profiles):
for plugin in profiles[pname].get("enable", []):
    if plugin not in state:
        print(f"{YELLOW}Warning: profile '{pname}' references uninstalled plugin: {plugin} (skipped){NC}",
              file=sys.stderr)
        continue
    state[plugin] = True
```

This handles the case where a profile references a plugin you haven't installed — common when sharing profiles across machines.

### 8. Update docs

**Files:**
- `CLAUDE.md` — Update "Plugin Organization & Context Profiles" section:
  - Remove mention of registry, `--check`, `--sync`
  - Add `--list` command
  - Note auto-discovery from installed_plugins.json
  - Mention SessionStart auto-apply and statusline
- `custom_bins/claude-context` docstring — Update usage/help text

## Files Modified

| File | Action |
|------|--------|
| `custom_bins/claude-context` | Rewrite: auto-discover, delete sync/check, add --list |
| `~/.claude/templates/contexts/profiles.yaml` | Simplify: remove registry section |
| `claude/statusline.sh` | Add: context profiles display |
| `claude/hooks/context_auto_apply.sh` | New: SessionStart hook |
| core-toolkit `plugin.json` (in cache + source) | Add: SessionStart hook entry |
| `CLAUDE.md` | Update: context profiles documentation |

## Verification

1. **Auto-discovery works:**
   ```bash
   cd /Users/yulong/code/dotfiles
   claude-context code  # Should resolve all plugin names via installed_plugins.json
   ```

2. **List command works:**
   ```bash
   claude-context --list  # Shows ON/OFF plugins for current project
   ```

3. **Profile with uninstalled plugin warns gracefully:**
   - Temporarily add a fake plugin name to a profile in profiles.yaml
   - Run `claude-context <profile>` — should warn and skip, not crash

4. **Statusline shows context:**
   - In a project with context.yaml, statusline should show `[code python]` etc.
   - In a project without context.yaml, no context shown

5. **SessionStart hook auto-applies:**
   - Start new Claude Code session in project with context.yaml
   - Settings.json should be up-to-date without manual `claude-context` run

6. **Regression: existing context.yaml projects still work:**
   - Check one existing project with context.yaml (e.g., llm-council)
   - Run `claude-context` — should apply same plugins as before
