# Plan: Git Alias Cleanup

## Context

The git aliases in `config/aliases.sh` have accumulated issues: `gl=git pull` is non-obvious, there's no short git log alias, `gg` points to `git gui` but `gitui` is preferred, two aliases hardcode `master`, `grhard` is broken (resets to nothing), and several common workflows have no short alias. This plan cleans those up and fills coverage gaps.

This plan was critiqued by Codex (correctness) and Gemini (conventions). The updated version incorporates their findings.

## File to Modify

`config/aliases.sh` — git section (lines 493–537)

---

## Changes

### 1. `gl` → last-20 log; `gpl` → git pull

```bash
# Before
alias gl="git pull"

# After
alias gl='git log --oneline -20'    # quick recent history: "what did I just do?"
alias gpl="git pull"
```

`glog` (with `--all --graph`) stays as the topology view. `gl` vs `glog` are now complementary:
- `gl` — last 20 commits, no graph noise, fast scan
- `glog` — full branch graph, all refs

---

### 2. `gg` → gitui

```bash
# Before
alias gg='git gui'

# After
alias gg='gitui'
```

---

### 3. `gcm`/`grbm` → dynamic main branch

```bash
# Before
alias gcm="git checkout master"
alias grbm="git rebase master"

# After
alias gcm='git checkout $(git_main_branch)'
alias grbm='git rebase $(git_main_branch)'
```

`git_main_branch` is provided by oh-my-zsh's `lib/git.zsh` (auto-loaded). It detects `main`, `master`, or `trunk` dynamically — works across all repos.

---

### 4. Fix `grhard` — was resetting to nothing; now resets to origin branch

```bash
# Before
alias grhard="git fetch origin && git reset --hard"
# ^ git reset --hard with no ref = resets working tree to HEAD (no-op for committed files)
# ^ Also: was going to be changed to @{u} but that hard-errors if no upstream is set

# After
alias grhard='git fetch origin && git reset --hard "origin/$(git_current_branch)"'
# ^ Explicit: always resets to the origin version of the current branch
# ^ Works even if local tracking isn't configured; fails clearly if branch doesn't exist on origin
```

---

### 5. Fix `gpf` — use `--force-with-lease` instead of `-f`

```bash
# Before
alias gpf="git push -f"

# After
alias gpf="git push --force-with-lease"
```

`--force-with-lease` refuses to overwrite remote commits you haven't fetched — prevents silently destroying teammates' work.

---

### 6. Remove duplicate push alias

`gpp` and `gpsup` are identical:

```bash
alias gpp='git push --set-upstream origin $(git_current_branch)'   # ← REMOVE
alias gpsup='git push --set-upstream origin $(git_current_branch)'  # ← KEEP
```

---

### 7. Add `gm` — git merge (currently missing)

```bash
alias gm="git merge"
```

---

### 8. Add `gds` — diff staged (high-frequency, currently missing)

```bash
alias gds="git diff --staged"
```

---

### 9. Add branch management aliases (currently none)

```bash
alias gb="git branch"
alias gba="git branch -a"
alias gbd="git branch -d"
alias gbD="git branch -D"
```

---

### 10. Add `gstl` — stash list (currently missing from stash series)

```bash
alias gstl="git stash list"
```

---

### 11. Add interactive rebase

```bash
alias grbi="git rebase -i"
```

---

### 12. Add cherry-pick series

```bash
alias gcp="git cherry-pick"
alias gcpa="git cherry-pick --abort"
alias gcpc="git cherry-pick --continue"
```

---

### 13. Add `gsw`/`gswc` — modern git switch (keep `gco`/`gcb` too)

```bash
alias gsw="git switch"
alias gswc="git switch -c"
```

`git switch` (git 2.23+) is the preferred modern branch command. Keep `gco`/`gcb` as aliases — no removal, just add the modern equivalents.

---

### 14. Add `grv` — remote -v (quick remote check)

```bash
alias grv="git remote -v"
```

---

## Pre-existing conventions (no change)

These were flagged by agents but are intentional divergences from oh-my-zsh defaults:

| Alias | Value | oh-my-zsh default | Decision |
|-------|-------|-------------------|----------|
| `gst` | `git stash` | `git status` | Keep — `gs` covers status; `gst` for stash is consistent with stash series |
| `gc` | `git commit -m` | `git commit --verbose` | Keep — faster for quick commits; use `git commit` bare when editor needed |

---

## Summary Table

| Alias | Before | After | Reason |
|-------|--------|-------|--------|
| `gl` | `git pull` | `git log --oneline -20` | User chose; pull → `gpl` |
| `gpl` | (none) | `git pull` | New alias for pull |
| `gg` | `git gui` | `gitui` | User prefers gitui |
| `gcm` | `git checkout master` | `git checkout $(git_main_branch)` | Dynamic; works across repos |
| `grbm` | `git rebase master` | `git rebase $(git_main_branch)` | Same |
| `grhard` | `git fetch && git reset --hard` | `git fetch && git reset --hard "origin/$(git_current_branch)"` | Fix broken reset |
| `gpf` | `git push -f` | `git push --force-with-lease` | Safety |
| `gpp` | `git push --set-upstream...` | (removed) | Duplicate of `gpsup` |
| `gm` | (none) | `git merge` | Add missing |
| `gds` | (none) | `git diff --staged` | Add missing |
| `gb` | (none) | `git branch` | Add missing |
| `gba` | (none) | `git branch -a` | Add missing |
| `gbd` | (none) | `git branch -d` | Add missing |
| `gbD` | (none) | `git branch -D` | Add missing |
| `gstl` | (none) | `git stash list` | Add to stash series |
| `grbi` | (none) | `git rebase -i` | Add missing |
| `gcp` | (none) | `git cherry-pick` | Add missing |
| `gcpa` | (none) | `git cherry-pick --abort` | Add missing |
| `gcpc` | (none) | `git cherry-pick --continue` | Add missing |
| `gsw` | (none) | `git switch` | Modern alternative to gco |
| `gswc` | (none) | `git switch -c` | Modern alternative to gcb |
| `grv` | (none) | `git remote -v` | Add missing |

---

## Placement in aliases.sh

All new aliases go in the git section (after line 537). Changes to existing aliases are in-place. The new additions group naturally:

```
# existing block (modified in-place)
...
# new additions after existing stash aliases:
alias gstl="git stash list"
alias grbi="git rebase -i"
alias gcp="git cherry-pick"
alias gcpa="git cherry-pick --abort"
alias gcpc="git cherry-pick --continue"
alias gsw="git switch"
alias gswc="git switch -c"
alias gds="git diff --staged"
alias gb="git branch"
alias gba="git branch -a"
alias gbd="git branch -d"
alias gbD="git branch -D"
alias grv="git remote -v"
```

---

## Verification

After sourcing (`source config/aliases.sh`):

```bash
alias gl      # → git log --oneline -20
alias gpl     # → git pull
alias gg      # → gitui
alias gcm     # → git checkout $(git_main_branch)
alias grbm    # → git rebase $(git_main_branch)
alias grhard  # → git fetch origin && git reset --hard "origin/$(git_current_branch)"
alias gpf     # → git push --force-with-lease
alias gpp     # → error: not found
alias gm      # → git merge
alias gds     # → git diff --staged
alias gb      # → git branch
alias gstl    # → git stash list
alias grbi    # → git rebase -i
alias gcp     # → git cherry-pick
alias gsw     # → git switch
alias grv     # → git remote -v
```
