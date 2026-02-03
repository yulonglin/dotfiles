# Plan: Add Modern CLI Tools

## Summary
Add fzf, bat, eza, zoxide, delta to core. Add hyperfine, lazygit to extras. Remove peco (redundant with fzf). Fix dangerous `find="fd"` alias. Keep `z` separate from `cd`.

## Changes

### 1. install.sh

**macOS core** (~line 155) - add fzf, bat, eza, zoxide, delta:
```bash
brew install --quiet coreutils ncdu htop rsync btop jq fzf bat eza zoxide delta
```

**macOS extras** (~line 179) - remove peco, add hyperfine, lazygit:
```bash
brew install --quiet fd ripgrep dust jless hyperfine lazygit
```

**Linux core** (~line 103) - add fzf:
```bash
apt install -y less nano htop ncdu nvtop lsof rsync jq fzf
```

**Linux extras** (~line 125) - add cargo fallback, remove peco:
```bash
if [ $extras == true ]; then
    apt install -y fd-find ripgrep

    # Homebrew for tools not in apt
    if command -v brew &> /dev/null; then
        brew install dust jless hyperfine lazygit
    fi

    # Cargo fallback for Rust tools (no sudo needed)
    if command -v cargo &> /dev/null; then
        echo "Installing Rust CLI tools via cargo..."
        cargo install bat eza zoxide delta --locked 2>/dev/null || true
    fi
fi
```

### 2. config/aliases.sh - Remove dangerous alias

**Delete line 44:**
```bash
alias find="fd"  # REMOVE THIS
```

### 3. config/zshrc.sh - Add zoxide init (~after line 32)

```bash
# zoxide (smarter cd - use 'z' command, not replacing cd)
command -v zoxide &> /dev/null && eval "$(zoxide init zsh)"
```

### 4. config/modern_tools.sh - Add zoxide and delta sections

**Add at end:**
```bash
# zoxide: Smarter directory jumping (z learns your habits)
# Usage: z <partial-path>  |  zi (interactive with fzf)
# Note: Intentionally NOT aliasing cd='z' - z is probabilistic, cd is explicit

# delta: Better diffs with syntax highlighting
# Configured in gitconfig for git operations
if command -v delta &> /dev/null; then
    alias diff='delta'
fi
```

### 5. config/gitconfig - Add delta integration

**Add after `[init]` section:**
```ini
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    line-numbers = true

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default
```

### 6. claude/CLAUDE.md - Update CLI tools list (~line 320)

```markdown
### CLI Tools Available
ripgrep (`rg`), fd, fzf, bat, eza, zoxide (`z`), delta, jq, jless, btop, dust, duf, bun
```

## Files to Modify

1. `install.sh` - Add packages, remove peco
2. `config/aliases.sh` - Remove `alias find="fd"` (line 44)
3. `config/zshrc.sh` - Add zoxide init
4. `config/modern_tools.sh` - Add delta alias, zoxide docs
5. `config/gitconfig` - Add delta pager config
6. `claude/CLAUDE.md` - Update CLI tools list

## Verification

1. `./install.sh --minimal --extras` - verify no errors
2. `source ~/.zshrc` - verify zoxide init works
3. `z --version && delta --version && fzf --version`
4. `git diff` - should show syntax-highlighted output
5. `cd /tmp && cd ~ && z tmp` - zoxide should jump back
