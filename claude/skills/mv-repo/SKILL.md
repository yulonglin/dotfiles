---
name: mv-repo
description: "Move a repo to a new directory. Handles venv, Claude Code project state, path references, and tmux sessions."
---

# Move Repo

Move one or more repos to a new parent directory, updating all path-dependent state.

**Usage:** `/mv-repo <source>... <dest-dir>`

Examples:
- `/mv-repo nudge bots/` — move `nudge` into `bots/`
- `/mv-repo nudge ambassador swordsmith bots/` — move multiple repos

## Steps

### 1. Validate

- Confirm source repo(s) exist and dest directory exists (or create it)
- Confirm no name collisions in dest

### 2. Move

```bash
mv <source>... <dest>/
```

### 3. Recreate venvs

For each moved repo that has a `.venv/`:
- Delete `.venv`
- Run `uv sync` in the new location
- If no `pyproject.toml`, skip (venv was manual — warn user)

### 4. Update Claude Code project state

Rename directories in `~/.claude/projects/` that match the old path encoding.

Path encoding: absolute path with `/` replaced by `-`, leading `-`. Example:
- `/home/yulong/code/nudge` → `-home-yulong-code-nudge`
- `/home/yulong/code/bots/nudge` → `-home-yulong-code-bots-nudge`

Include worktree variants (dirs matching `${old_encoded}--*`).

```bash
# For each repo, rename matching project dirs
# Strip trailing slash to avoid encoding artifacts
old_abs_path="${old_abs_path%/}"
new_abs_path="${new_abs_path%/}"
old_encoded="$(echo "$old_abs_path" | tr '/' '-')"
new_encoded="$(echo "$new_abs_path" | tr '/' '-')"
# Match exact dir and worktree variants (--*), not unrelated repos
for dir in ~/.claude/projects/${old_encoded} ~/.claude/projects/${old_encoded}--*; do
  [ -d "$dir" ] || continue
  new_dir="${dir/$old_encoded/$new_encoded}"
  mv "$dir" "$new_dir"
done
```

### 5. Handle git worktrees

Moving a repo breaks git worktree references in two places:

**A. Main repo's worktree registry** (`.git/worktrees/*/gitdir`):

```bash
git -C <new-path> worktree list
```

For each worktree:
- **Path doesn't exist** (stale) → `git worktree prune` removes it
- **Path exists, has changes** → update paths (see below)
- **Path exists, only `.claude/settings.json` changes** → safe to prune

**B. Claude Code worktrees** (`.claude/worktrees/*/`):

These moved with the repo but contain `.git` **files** (not directories) with absolute `gitdir:` paths pointing to the old location:

```
# .claude/worktrees/auto-heal/.git contains:
gitdir: /old/path/.git/worktrees/auto-heal
```

Fix both directions (use `-F` for fixed-string matching — paths contain `.` which is regex):
```bash
old_path="/old/path"
new_path="/new/path"

# Fix .claude/worktrees/*/.git → points to main repo's .git/worktrees/
for gitfile in <new-path>/.claude/worktrees/*/.git; do
  [ -f "$gitfile" ] || continue
  sd -F "$old_path" "$new_path" "$gitfile"
done

# Fix .git/worktrees/*/gitdir → points back to .claude/worktrees/
for gitdir_file in <new-path>/.git/worktrees/*/gitdir; do
  [ -f "$gitdir_file" ] || continue
  sd -F "$old_path" "$new_path" "$gitdir_file"
done

# Check for absolute commondir paths (should be relative, but verify)
for f in <new-path>/.git/worktrees/*/commondir; do
  [ -f "$f" ] || continue
  grep -q "^/" "$f" && echo "WARNING: absolute commondir in $f — fix manually"
done
```

If worktrees have no meaningful changes (just `settings.json`), it's simpler to `mv .claude/worktrees .claude/worktrees.bak` and let them be recreated. `*.bak` is globally gitignored.

**C. `hooksPath` in `.git/config`** (and worktree configs):

Use `git config` to scope the fix to `hooksPath` only (avoid corrupting remote URLs or other config):
```bash
# Main repo
hooks_path=$(git -C <new-path> config core.hooksPath 2>/dev/null)
if [[ "$hooks_path" == *"$old_path"* ]]; then
  git -C <new-path> config core.hooksPath "${hooks_path/$old_path/$new_path}"
fi

# Worktree-level configs may also override hooksPath
for wt_config in <new-path>/.git/worktrees/*/config; do
  [ -f "$wt_config" ] || continue
  grep -qF "$old_path" "$wt_config" && sd -F "$old_path" "$new_path" "$wt_config"
done
```

### 6. Grep for stale path references

Search for old paths across common locations:
- `~/code/` (all repos — CLAUDE.md, specs, scripts, configs)
- `~/.claude/` (rules, docs, settings)
- Dotfiles config dir if it exists

```bash
rg --no-ignore -l "$old_path_pattern" ~/code/ ~/.claude/ 2>/dev/null
```

For each match:
- Show the file and matching lines
- Offer to fix (replace old path with new path)
- Skip `tmp/`, `archive/`, `.git/`, `node_modules/` matches — these are throwaway

### 7. Update tmux sessions

Check for tmux sessions named after the repo:

```bash
tmux ls 2>/dev/null | grep -i "<repo-name>"
```

If found, send `cd` to the new path:

```bash
tmux send-keys -t <session> "cd <new-path>" Enter
```

### 8. Remind about manual steps

After completing all automated steps, remind the user about:
- **Crontab entries**: `crontab -l | grep <old-path>` — update manually with `crontab -e`
- **Systemd units/launchd plists**: check for hardcoded paths
- **Git commits**: each moved repo has uncommitted changes (updated refs) — commit them
- **Remote CI/CD**: any pipelines referencing the old path
