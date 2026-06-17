# Normalize plugin scopes: local → project

## Agent Critiques Summary

Codex, Gemini, and plan-critic reviewed against 7 criteria. Key findings incorporated below:

- **Scope semantics safe for our workflow**: `local` → `settings.local.json`, `project` → `settings.json`. Since `claude-context` deterministically rebuilds `settings.json`, this is fine. We never toggle plugins via Claude Code's UI.
- **Atomic write required**: Match `apply_to_settings()` pattern (tempfile + `os.rename`)
- **Trailing newline required**: Add `f.write("\n")` after `json.dump` for consistency
- **Marketplace update resets scope**: `claude plugin marketplace update` may reset scope to `local` each time, so `normalize_scopes()` at end of `sync_marketplaces()` is the correct placement
- **Verbose logging**: Pass `verbose` flag to log affected plugin names

## Context

`installed_plugins.json` has 28 entries with `"scope": "local"`, 10 with `"scope": "project"`, and 1 with `"scope": "user"`. For personal repos, `local` (private per-project, stored in `.claude/settings.local.json`) and `project` (shared per-project, stored in `.claude/settings.json`) are functionally identical. Since `claude-context` already manages `settings.json` deterministically, normalizing to `project`+`user` only simplifies the mental model.

## Changes

### 1. Bulk replace `local` → `project` in installed_plugins.json

**File:** `~/.claude/plugins/installed_plugins.json`

Use `jq` to replace all `"scope": "local"` with `"scope": "project"`:

```bash
jq '(.plugins[][] | select(.scope == "local")).scope = "project"' \
  ~/.claude/plugins/installed_plugins.json > "$TMPDIR/installed_plugins.json" \
  && mv "$TMPDIR/installed_plugins.json" ~/.claude/plugins/installed_plugins.json
```

### 2. Add post-sync scope normalization to `claude-context`

**File:** `custom_bins/claude-context`

`claude plugin marketplace update` has no `--scope` flag, so newly added plugins from a marketplace default to `local`. Add a normalization step after sync completes to prevent drift.

Insert `normalize_scopes()` after `sync_marketplaces()` (around line 346), before the `# --- Subcommands ---` section:

```python
def normalize_scopes(verbose=False):
    """Replace 'local' scope with 'project' in installed_plugins.json.

    Marketplace updates default new plugins to 'local' scope. For personal
    repos, 'project' scope is functionally identical and simplifies the
    mental model (project + user only).
    """
    if not os.path.exists(INSTALLED_PLUGINS):
        return
    with open(INSTALLED_PLUGINS) as f:
        data = json.load(f)
    changed = []
    for qid, entries in data.get("plugins", {}).items():
        for entry in entries:
            if entry.get("scope") == "local":
                entry["scope"] = "project"
                changed.append(qid.split("@")[0])
    if changed:
        # Atomic write (matches apply_to_settings pattern)
        dir_name = os.path.dirname(os.path.abspath(INSTALLED_PLUGINS))
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".json")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.write("\n")
            os.rename(tmp_path, INSTALLED_PLUGINS)
        except Exception:
            os.unlink(tmp_path)
            raise
        print(f"{GREEN}Normalized {len(changed)} plugin scope(s): local → project{NC}")
        if verbose:
            for name in changed:
                print(f"  {name}")
```

Call `normalize_scopes(verbose=verbose)` at the end of `sync_marketplaces()`, after the update loop (after line 344, before `return errors == 0`).

### Not changed

- `install.sh` — doesn't touch plugin scopes
- `deploy.sh` — calls `claude-context --sync` which will now auto-normalize
- `claude plugin install` defaults to `user` scope, which is fine

## Verification

1. `grep -c '"scope": "local"' ~/.claude/plugins/installed_plugins.json` → should be `0`
2. `grep -c '"scope": "project"' ~/.claude/plugins/installed_plugins.json` → should be `38` (28 former local + 10 existing project)
3. `grep -c '"scope": "user"' ~/.claude/plugins/installed_plugins.json` → should be `1` (unchanged)
4. Run `claude-context --list` to confirm plugins still resolve correctly
5. Start a new Claude Code session to confirm plugins load normally
