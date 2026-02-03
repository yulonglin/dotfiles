# Standardize Directory Environment Variables in Dotfiles

## Overview

Replace hardcoded directory paths in aliases with configurable environment variables, following the existing `${VAR:-default}` pattern used throughout the codebase. This improves user customization, maintainability, and cloud environment portability.

**Also fixes bug:** `config/aliases_speechmatics.sh` currently references undefined `$CODE_DIR` variable (lines 57-59), breaking those aliases. Our changes properly define this variable.

## Assumptions

**Environment variables we rely on:**
- `$HOME` - Standard shell variable, always defined by the system on all platforms (macOS, Linux, containers)
- `$DOT_DIR` - Already defined in `config/zshrc.sh` line 2, points to dotfiles repository root

**Environment variables we're creating:**
- `CODE_DIR`, `WRITING_DIR`, `SCRATCH_DIR`, `PROJECTS_DIR` - None currently defined in standard config
- Note: `CODE_DIR` is already used in `config/aliases_speechmatics.sh` but never defined (broken)

## Changes Required

### 1. Define Environment Variables in `config/zshrc.sh`

**Location:** After line 2 (after `DOT_DIR` definition)

**Add:**
```bash
# User-customizable directory locations (override in ~/.zshenv or config/secrets.sh)
CODE_DIR="${CODE_DIR:-$HOME/code}"           # Primary code projects
WRITING_DIR="${WRITING_DIR:-$HOME/writing}"  # Writing projects (papers, notes)
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"  # Temporary experimentation
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"  # General projects
```

**Rationale:**
- Follows existing pattern (DOT_DIR defined here, `${VAR:-default}` syntax used throughout codebase)
- Users can override in `~/.zshenv` or `config/secrets.sh`
- No automatic RunPod detection needed (cloud setup scripts already handle this via symlinks)

### 2. Update Aliases in `config/aliases.sh`

**Remove broken/unused aliases:**
- Line 12: `alias cdg="cd ~/git"` - unused, inherited from previous maintainer
- Line 13: `alias zrc="cd $DOT_DIR/zsh"` - broken (directory doesn't exist)

**Update existing alias:**
- Line 148: Change `alias dotfiles='cd ~/code/dotfiles'` to `alias dotfiles='cd $CODE_DIR/dotfiles'`

**Add new alias for consistency:**
- After line 151: Add `alias projects='cd $PROJECTS_DIR'`

**Already correct (no changes needed):**
- Line 14: `alias dot="cd $DOT_DIR"` - already uses variable
- Lines 149-151: `code`, `writing`, `scratch` aliases already reference variables (will work after Step 1)

### 3. Update Migration Script `scripts/migrate_claude_plans_tasks.sh`

**Lines 23-24:** Change from hardcoded to environment-aware:

```bash
# Before:
CODE_DIR="$HOME/code"
WRITING_DIR="$HOME/writing"

# After:
CODE_DIR="${CODE_DIR:-$HOME/code}"
WRITING_DIR="${WRITING_DIR:-$HOME/writing}"
```

**Benefit:** Script respects user customization when run interactively, uses sensible defaults when standalone.

### 4. Update Documentation in `CLAUDE.md`

Add new section under "Architecture" or create "Environment Variables" section:

```markdown
### Directory Environment Variables

Standard directory locations can be customized via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `CODE_DIR` | `~/code` | Primary code projects and repositories |
| `WRITING_DIR` | `~/writing` | Writing projects (papers, drafts, notes) |
| `SCRATCH_DIR` | `~/scratch` | Temporary experimentation and testing |
| `PROJECTS_DIR` | `~/projects` | General projects |
| `DOT_DIR` | (auto-detected) | Dotfiles repository location |

**Customization:**
```bash
# In ~/.zshenv (loaded before zshrc, recommended)
export CODE_DIR="$HOME/work/projects"
export WRITING_DIR="$HOME/Documents/writing"
```

**Cloud environments:** The standard directory structure works transparently on RunPod/cloud via symlinks created by `scripts/cloud/setup.sh`.

**Related aliases:** `code`, `writing`, `scratch`, `projects`, `dotfiles`
```

## Files Modified

- `config/zshrc.sh` - Define directory variables
- `config/aliases.sh` - Remove broken aliases, update dotfiles alias, add projects alias
- `scripts/migrate_claude_plans_tasks.sh` - Use environment-aware defaults
- `CLAUDE.md` - Document new variables

## Verification Steps

### 1. Variable Definitions
```bash
# Source updated config
source config/zshrc.sh

# Verify variables set correctly (should use $HOME/<dirname>)
echo $CODE_DIR      # Should: $HOME/code
echo $WRITING_DIR   # Should: $HOME/writing
echo $SCRATCH_DIR   # Should: $HOME/scratch
echo $PROJECTS_DIR  # Should: $HOME/projects
```

### 2. Alias Functionality
```bash
# Check aliases resolve correctly (should use $HOME/<dirname>)
alias code          # Should: cd $HOME/code
alias writing       # Should: cd $HOME/writing
alias scratch       # Should: cd $HOME/scratch
alias projects      # Should: cd $HOME/projects
alias dotfiles      # Should: cd $HOME/code/dotfiles

# Verify removed aliases are gone
alias cdg 2>/dev/null  # Should fail (not found)
alias zrc 2>/dev/null  # Should fail (not found)
```

### 3. Custom Override Test
```bash
# Test user customization works
CODE_DIR="/custom/path" zsh -c 'source config/zshrc.sh && echo $CODE_DIR'
# Should output: /custom/path
```

### 4. Migration Script Test
```bash
# Test with default environment
./scripts/migrate_claude_plans_tasks.sh --dry-run

# Test with custom CODE_DIR
CODE_DIR="/alternate" ./scripts/migrate_claude_plans_tasks.sh --dry-run
```

### 5. No Regressions
```bash
# Verify speechmatics aliases still work (uses $CODE_DIR)
source config/aliases_speechmatics.sh
alias pcat  # Should reference $CODE_DIR/aladdin/utils/...
```

## Design Decisions

**Why not automatic RunPod detection?**
- Cloud setup scripts already create symlinks (`/workspace/yulong` → `$HOME`)
- Standard paths (`~/code`, `~/writing`) work transparently via symlinks
- No special shell config needed - environment already normalized
- Manual override available via `~/.zshenv` if needed

**Why not separate `config/env_dirs.sh` file?**
- `zshrc.sh` is primary config entry point (where DOT_DIR lives)
- Keeps directory variables together for easy discovery
- KISS principle - no unnecessary indirection

**Why add PROJECTS_DIR if no current usage?**
- Common directory name, low cost to add
- Maintains consistent pattern (4 variables, 4 aliases)
- Future-proofing for user customization

**Why not use DOTFILES_DIR variable?**
- `DOT_DIR` already exists and works perfectly
- `dotfiles` alias assumes common case (`$CODE_DIR/dotfiles`)
- Users with non-standard location can override alias directly
- Avoids unnecessary complexity for rare edge case

## Edge Cases Handled

- **Missing directories:** Aliases fail gracefully with "no such file" (no silent directory creation)
- **Dotfiles location:** `dot` alias uses auto-detected `$DOT_DIR` (always correct), `dotfiles` alias assumes common location
- **Shell compatibility:** `${VAR:-default}` is POSIX-compliant (works in bash, zsh, sh)
- **Variable conflicts:** No known conflicts with standard env vars or common tools
- **Platform differences:** Paths work correctly on macOS, Linux, and cloud environments

## Success Criteria

- ✅ All hardcoded paths replaced with variables
- ✅ Broken/unused aliases removed
- ✅ User customization works via `~/.zshenv` or `config/secrets.sh`
- ✅ Backward compatible (existing paths still work)
- ✅ Documentation updated and clear
- ✅ No shell errors or warnings
- ✅ Speechmatics aliases still functional
