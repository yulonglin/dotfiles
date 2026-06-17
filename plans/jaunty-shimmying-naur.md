# Plan: Add Worktree + Tmux Support to Dotfiles

## Context

Claude Code supports `--worktree [name]` and `--tmux` flags for isolated parallel development. Currently the dotfiles have no worktree aliases, `.claude/worktrees/` isn't gitignored, and there's no tooling for managing worktree artifacts (logs, experiment outputs). This adds first-class worktree support: aliases, lifecycle management, artifact porting, and documentation.

## Changes

### 1. Gitignore — two files

**`.gitignore`** (after L499, next to existing `.claude/tasks/`):
```gitignore
.claude/worktrees/
```

**`config/ignore_global`** (after L464, in the `# Claude Code` section):
```gitignore
.claude/worktrees/
```

Why both: `.gitignore` covers this dotfiles repo. `config/ignore_global` covers ALL repos globally (deployed to `~/.gitignore_global` via concatenation with `config/ignore_research`, and symlinked as `~/.ignore_global` for ripgrep/fd).

### 2. Make `yolo` default to worktree — `config/aliases.sh`

Change `yolo` from alias to function. Update `resume`/`cont`/`continue` to bypass worktree (they resume existing sessions, not create new ones).

**Replace lines 84-88:**
```bash
# yolo — always creates isolated worktree + tmux
yolo() { claude --worktree --tmux --dangerously-skip-permissions "$@"; }

# resume/continue bypass worktree (resuming existing sessions)
alias resume='claude --dangerously-skip-permissions --resume'
alias cont='claude --dangerously-skip-permissions --continue'
alias continue='claude --dangerously-skip-permissions --continue'
alias yn='yolo -t'  # yn <name>: yolo with task name (auto-named worktree)
```

### 3. Add worktree functions — `config/aliases.sh` (after yn)

```bash
# worktree commands
cw() {
  # Launch Claude in isolated worktree with tmux (without yolo)
  # Usage: cw [name] [extra args...]
  local wt_args=("--worktree")
  if [[ $# -gt 0 && "$1" != -* ]]; then
    wt_args+=("$1")
    shift
  fi
  claude "${wt_args[@]}" --tmux "$@"
}

cwy() {
  # cw + yolo (skip permissions), with optional name
  local wt_args=("--worktree")
  if [[ $# -gt 0 && "$1" != -* ]]; then
    wt_args+=("$1")
    shift
  fi
  claude "${wt_args[@]}" --tmux --dangerously-skip-permissions "$@"
}

alias cwl='git worktree list'

cwport() {
  # Port gitignored artifacts from a worktree to main tree
  # Usage: cwport <name> [dirs...]
  #   cwport refactor-auth              # ports default dirs
  #   cwport refactor-auth out logs     # ports specific dirs
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: cwport <worktree-name> [dirs...]"
    return 1
  fi
  shift

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local wt_path="$git_root/.claude/worktrees/$name"
  if [[ ! -d "$wt_path" ]]; then
    echo "cwport: worktree not found: $wt_path" >&2
    return 1
  fi

  local dirs=("${@:-out logs data results}")
  local dest="$git_root/out/worktree-${name}-$(date -u +%Y%m%d_%H%M%S)"
  local ported=0

  for dir in "${dirs[@]}"; do
    if [[ -d "$wt_path/$dir" ]]; then
      mkdir -p "$dest"
      echo "Porting $dir/ → $dest/$dir/"
      cp -r "$wt_path/$dir" "$dest/$dir"
      ((ported++))
    fi
  done

  if [[ $ported -eq 0 ]]; then
    echo "No artifacts found in: ${dirs[*]}"
  else
    echo "Ported $ported dir(s) to $dest"
  fi
}

cwrm() {
  # Remove a Claude-created worktree + its branch
  # Warns if gitignored artifacts exist (use cwport first or --force)
  local force=false
  if [[ "$1" == "--force" ]]; then force=true; shift; fi

  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: cwrm [--force] <worktree-name>"
    echo ""; cwl; return 1
  fi

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local wt_path="$git_root/.claude/worktrees/$name"
  if [[ ! -d "$wt_path" ]]; then
    echo "cwrm: worktree not found: $wt_path" >&2
    cwl; return 1
  fi

  # Check for gitignored artifacts
  if ! $force; then
    local artifacts=()
    for dir in out logs data results experiments; do
      [[ -d "$wt_path/$dir" ]] && artifacts+=("$dir/")
    done
    if [[ ${#artifacts[@]} -gt 0 ]]; then
      echo "Warning: worktree has artifacts: ${artifacts[*]}"
      echo "  Port first: cwport $name"
      echo "  Or force:   cwrm --force $name"
      return 1
    fi
  fi

  echo "Removing worktree: $wt_path"
  git worktree remove --force "$wt_path" && echo "Worktree removed."

  local branch="worktree-$name"
  if git rev-parse --verify "$branch" &>/dev/null; then
    echo "Deleting branch: $branch"
    git branch -D "$branch"
  fi
}

cwclean() {
  # List Claude worktrees with status, optionally prune stale ones
  # Usage: cwclean [--prune]
  local prune=false
  [[ "$1" == "--prune" ]] && prune=true

  git worktree prune  # always clean up metadata for deleted dirs

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local wt_dir="$git_root/.claude/worktrees"

  if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
    echo "No Claude worktrees found."
    return 0
  fi

  echo "Claude worktrees:"
  local stale=0
  for wt in "$wt_dir"/*/; do
    [[ ! -d "$wt" ]] && continue
    local name
    name=$(basename "$wt")
    local status="active"

    # Check if any claude process is using this worktree
    if ! pgrep -f "claude.*$wt" >/dev/null 2>&1; then
      # Check for uncommitted changes
      if git -C "$wt" diff --quiet HEAD 2>/dev/null && \
         [[ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        status="clean"
        ((stale++))
      else
        status="dirty"
      fi
    fi

    # Check for artifacts
    local has_artifacts=""
    for dir in out logs data results; do
      [[ -d "$wt/$dir" ]] && has_artifacts=" +artifacts"
    done

    printf "  %-30s [%s%s]\n" "$name" "$status" "$has_artifacts"

    if $prune && [[ "$status" == "clean" ]] && [[ -z "$has_artifacts" ]]; then
      cwrm --force "$name"
    fi
  done

  if ! $prune && [[ $stale -gt 0 ]]; then
    echo ""
    echo "Run 'cwclean --prune' to remove clean worktrees without artifacts."
  fi
}
```

### 4. Update CLAUDE.md — worktree workflow docs

**File:** `CLAUDE.md` — add under "### Git Workflow" section:

```markdown
### Worktree Workflow

**`yolo` always creates a worktree** — every yolo session runs in an isolated `.claude/worktrees/<name>/` directory with its own branch. `resume`/`cont` bypass worktree (they resume existing sessions).

| Command | What it does |
|---------|-------------|
| `yolo` | Auto-named worktree + tmux + skip permissions |
| `cw [name]` | Named/auto worktree + tmux (with permission prompts) |
| `cwy [name]` | Named/auto worktree + tmux + skip permissions |
| `cwl` | List all worktrees |
| `cwport <name> [dirs...]` | Copy artifacts (out/, logs/, etc.) from worktree to main tree |
| `cwrm [--force] <name>` | Remove worktree + branch (warns about artifacts) |
| `cwclean [--prune]` | List worktree status; `--prune` removes clean ones |

**Gitignored files** (.env, out/, logs/) do NOT exist in new worktrees. Each worktree starts clean with only tracked files.

**Artifact lifecycle**: `cw auth-fix` → work → `cwport auth-fix` → `cwrm auth-fix`
```

## Files Modified

| File | Change | Lines |
|------|--------|-------|
| `.gitignore` | Add `.claude/worktrees/` | +1 (after L499) |
| `config/ignore_global` | Add `.claude/worktrees/` | +1 (after L464) |
| `config/aliases.sh` | Replace yolo/resume/cont (L84-88), add worktree functions | ~120 lines |
| `CLAUDE.md` | Add worktree workflow section | ~15 lines |

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| `yolo` defaults to worktree | Yes (user's choice) | Every yolo session is isolated; `resume`/`cont` bypass it |
| `claude` unchanged | Yes | Quick sessions don't need worktree overhead |
| `resume`/`cont` bypass worktree | Required | They resume existing sessions, not create new ones |
| `cwport` for artifact porting | Yes | Copies gitignored dirs to `out/worktree-<name>-<timestamp>/` in main tree |
| `cwrm` warns about artifacts | Yes | Prevents accidental loss; `--force` to override |
| `cwclean` for lifecycle mgmt | Yes | Lists status (active/clean/dirty/+artifacts), `--prune` removes clean stale ones |
| Functions in aliases.sh (not custom_bins) | Yes | Keeps all claude aliases together; can extract later if they grow |

## Verification

1. `source config/aliases.sh` — confirm functions load without errors
2. `type yolo cw cwy cwl cwport cwrm cwclean` — all defined as functions
3. `yolo` — should create auto-named worktree + tmux session
4. `cw test-verify` — should create `.claude/worktrees/test-verify/`
5. Create a test artifact: `mkdir -p .claude/worktrees/test-verify/out && echo test > .claude/worktrees/test-verify/out/result.txt`
6. `cwport test-verify` — should copy to `out/worktree-test-verify-<timestamp>/`
7. `cwrm test-verify` — should succeed (out/ was already ported)
8. `cwclean` — should show status of remaining worktrees
9. `git check-ignore .claude/worktrees/` — should confirm ignored
10. `resume` — should resume without creating a worktree
