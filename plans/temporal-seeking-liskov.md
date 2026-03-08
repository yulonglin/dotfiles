# Add dev-browser + replace `full` with dynamic `all`

## Context
User installed `dev-browser` plugin from `sawyerhood/dev-browser` marketplace. It replaces `playwright` for browser automation. Design profile should be purely visual (Figma → code), while web gets deployment + browser automation.

Three parallel reviewers (code-reviewer, codex-reviewer, gemini-cli) identified that the hardcoded `full` profile drifts — it was missing 11 plugins from other profiles. User wants a dynamic `all` profile that enables everything from the registry without hardcoding.

## Already Done (this session)

### `profiles.yaml` — marketplace + design + web changes
- ✅ Added `dev-browser` marketplace entry
- ✅ `design`: removed `playwright` and `vercel`, updated comment
- ✅ `web`: added `dev-browser`, updated comment

## Remaining Changes

### 1. `profiles.yaml` — replace `full` with `all`

Remove the hardcoded `full` profile. Replace with:
```yaml
  all:
    comment: "Everything enabled (dotfiles, meta-work)"
    all: true
```

The `all: true` flag signals to `claude-context` that this profile enables every plugin in the registry (no hardcoded enable list needed).

### 2. `custom_bins/claude-context` — handle `all: true` in `build_plugins()`

In `build_plugins()` (line 87), after Step 2 (base), add handling for `all: true` profiles:

```python
# Step 3: profiles
for pname in profile_names:
    if pname not in profiles:
        sys.exit(...)
    profile = profiles[pname]
    if profile.get("all"):
        # Enable everything in registry
        for name in state:
            state[name] = True
    else:
        for plugin in profile.get("enable", []):
            ...
```

This is ~4 lines of logic. When `all: true` is set, every plugin in the registry gets enabled. The `disable` override still works after (Step 4), so `claude-context all --disable=slack-mcp` is possible.

### 3. Update CLAUDE.md profile table

Update the `full` entry in the profiles table to `all`:
```
  all           Everything enabled (dotfiles, meta-work)
```

Also update any other references to `full` → `all` in CLAUDE.md (the `claude-context` usage examples section).

### 4. Update `context.yaml` references

Check if any `.claude/context.yaml` files reference `full` and update to `all`.

## Files to modify
- `claude/templates/contexts/profiles.yaml` (line 85-96)
- `custom_bins/claude-context` (line 106-115 in `build_plugins()`)
- `CLAUDE.md` (profiles table + any `full` references)
- Any `.claude/context.yaml` files referencing `full`

## Verification
- `claude-context all` — confirm ALL plugins enabled (count should match total registry)
- `claude-context design` — confirm `playwright` and `vercel` absent
- `claude-context web` — confirm `dev-browser` present
- `grep playwright profiles.yaml` — confirm no remaining references
- `grep 'full' profiles.yaml` — confirm no remaining `full` profile
- `python3 -c "import yaml; ..."` — validate YAML still parses
