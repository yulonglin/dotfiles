# Fix: deploy.sh glob error + clarify cleanup messages + migrate check_git_root hook

## Context

Running `deploy.sh --claude` produces an error on line 463:
```
./deploy.sh:463: no matches found: /Users/yulong/code/dotfiles/claude/templates/contexts/*.json
```

The `claude/templates/contexts/` directory only contains `profiles.yaml` — no JSON files. In zsh, unmatched globs are a fatal error (unlike bash which passes the literal glob string). The `[[ -f "$tmpl" ]] || continue` guard never executes because zsh aborts before entering the loop.

## Fix

**File:** `deploy.sh` (line 463)

Two changes needed in the context templates block (lines 460-468):

1. **Line 463**: Wrap the glob in a null-glob guard so zsh doesn't error on no matches
2. **Line 467**: The `ls *.json` in the log message has the same problem — already has `2>/dev/null` but zsh still errors before `ls` runs

Replace the block with:
```bash
# Deploy context templates
if [[ -d "$DOT_DIR/claude/templates/contexts" ]]; then
    mkdir -p "$HOME/.claude/templates/contexts"
    for tmpl in "$DOT_DIR/claude/templates/contexts"/*.json(N) "$DOT_DIR/claude/templates/contexts"/*.yaml(N); do
        [[ -f "$tmpl" ]] || continue
        ln -sf "$tmpl" "$HOME/.claude/templates/contexts/$(basename "$tmpl")"
    done
    local tmpl_count=$(ls "$DOT_DIR/claude/templates/contexts"/*.{json,yaml} 2>/dev/null | wc -l | tr -d ' ')
    log_success "Context templates deployed ($tmpl_count files)"
fi
```

Key changes:
- `(N)` — zsh null_glob qualifier: returns empty list instead of erroring when no matches
- Added `*.yaml` to also deploy `profiles.yaml` (currently not symlinked since it only looks for JSON)
- Fixed log message to count both file types

## Fix 2: Clarify cleanup script output

**File:** `scripts/cleanup/clean_plugin_symlinks.sh` (line 56)

Current message when no symlinks are found:
```
No plugin symlinks found in /Users/yulong/.claude/skills
```

This reads like a warning ("something's missing") when it actually means "everything is clean." Change to a positive confirmation:

```bash
# Line 55-56: replace
if [[ $count -eq 0 ]]; then
  echo "No plugin symlinks found in $SKILLS_DIR"
# with
if [[ $count -eq 0 ]]; then
  echo "Skills directory clean (no stale plugin symlinks)"
```

## Fix 3: Migrate check_git_root.sh to core-toolkit plugin

**New hook file:** `claude/hooks/check_git_root.sh` was added after the plugin extraction. It's a SessionStart hook that warns when CWD isn't the git root (catches IDE integrations and direct `command claude` that bypass the wrapper).

Currently registered in `claude/settings.json` as a global hook (lines 160-165). Should be moved to core-toolkit plugin like all other hooks.

### Steps

1. **Copy hook to ai-safety-plugins repo:**
   ```
   cp claude/hooks/check_git_root.sh ~/code/ai-safety-plugins/plugins/core-toolkit/hooks/
   ```

2. **Add SessionStart hook config to core-toolkit plugin.json:**
   ```json
   "SessionStart": [
     {
       "type": "command",
       "command": "${CLAUDE_PLUGIN_ROOT}/hooks/check_git_root.sh"
     }
   ]
   ```
   Add after the `PostToolUse` block (line 71).

3. **Remove global hook from settings.json:**
   Delete the `SessionStart` block (lines 160-165) and the enclosing `"hooks"` object if it becomes empty. Check current state — previous migration may have left a residual hooks section.

4. **Commit in ai-safety-plugins repo**, then commit dotfiles changes.

## Verification

```bash
./deploy.sh --claude
# Should see: "Context templates deployed (1 files)" with no glob error
# Should see: "Skills directory clean (no stale plugin symlinks)"
# SessionStart hook should still fire (now from plugin)
```
