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

Moving a repo breaks git worktree references. Check and handle:

```bash
git -C <new-path> worktree list
```

For each worktree:
- **Path doesn't exist** (stale) → `git worktree prune` removes it
- **Path exists, has changes** → warn user; they may want to update the worktree's `.git` file to point to the new main repo location
- **Path exists, only `.claude/settings.json` changes** → safe to prune (just Claude Code runtime state)

For most moves, `git worktree prune` is sufficient — worktrees under the old repo's `.claude/worktrees/` moved with the repo and their internal `.git` pointers auto-resolve. Worktrees outside the repo tree (e.g., in `/tmp/`) need manual `.git` file updates.

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
