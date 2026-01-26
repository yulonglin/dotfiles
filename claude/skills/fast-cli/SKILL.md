---
name: fast-cli
description: This skill should be used when the user asks to "list files", "show disk usage", "search files", "find files", "view file contents", "check directory size", or mentions fast CLI tools like eza, dust, rg, fd, bat, fzf, zoxide, delta, jq, duf, btop. Provides smart defaults for modern CLI replacements.
---

# Fast CLI Tools

Execute fast CLI commands with smart defaults. These modern replacements are significantly faster and more ergonomic than their traditional counterparts.

## Tool Mappings

| Traditional | Fast Alternative | Purpose |
|-------------|------------------|---------|
| `ls` | `eza` | List files with git status, icons |
| `find` | `fd` | Find files by pattern |
| `grep` | `rg` | Search file contents |
| `cat` | `bat` | View files with syntax highlighting |
| `du` | `dust` | Disk usage visualization |
| `df` | `duf` | Disk free space |
| `top` | `btop` | System monitor |
| `cd` | `z` (zoxide) | Smart directory jumping |
| `diff` | `delta` | Beautiful diffs |
| `jq` | `jq`/`jless` | JSON processing |

## Smart Defaults

### eza (file listing)

```bash
# Basic listing with git status and icons
eza -la --git --icons

# Tree view (2 levels deep)
eza --tree --level=2 --icons

# Show only directories
eza -D --icons

# Sort by modification time (newest first)
eza -la --sort=modified --reverse --icons

# Group directories first
eza -la --group-directories-first --icons
```

### fd (find files)

```bash
# Find by pattern (faster than find)
fd "pattern"

# Find specific extension
fd -e py

# Find and execute command on each
fd -e json -x jq .

# Find hidden files too
fd -H "pattern"

# Find only directories
fd -t d "pattern"

# Exclude directories
fd -E node_modules -E .git "pattern"
```

### rg (ripgrep - search contents)

```bash
# Search for pattern
rg "pattern"

# Search specific file types
rg -t py "import"

# Show context (3 lines before/after)
rg -C 3 "pattern"

# Case insensitive
rg -i "pattern"

# Fixed string (not regex)
rg -F "exact match"

# Count matches per file
rg -c "pattern"

# Files with matches only
rg -l "pattern"
```

### dust (disk usage)

```bash
# Disk usage of current directory
dust

# Limit depth
dust -d 2

# Show hidden files
dust -a

# Reverse order (smallest first)
dust -r

# Only show N items
dust -n 10

# Specific path
dust /path/to/dir
```

### bat (file viewing)

```bash
# View file with syntax highlighting
bat file.py

# Show line numbers only
bat -n file.py

# Plain output (no decorations)
bat -p file.py

# Specify language
bat -l json file.txt

# Show non-printable characters
bat -A file.txt

# Multiple files
bat file1.py file2.py
```

### fzf (fuzzy finder)

```bash
# Interactive file selection
fd | fzf

# Preview files while selecting
fd | fzf --preview 'bat --color=always {}'

# Multi-select with tab
fd | fzf -m

# Search in file contents
rg "" --files | fzf --preview 'rg --color=always {} {}'
```

### zoxide (smart cd)

```bash
# Jump to frecent directory
z project-name

# Interactive selection
zi

# Add current directory to database
z add .
```

### jq / jless (JSON)

```bash
# Pretty print JSON
jq . file.json

# Extract field
jq '.key' file.json

# Filter array
jq '.[] | select(.active == true)' file.json

# Interactive JSON exploration
jless file.json
```

### duf (disk free)

```bash
# Show disk usage
duf

# Only local filesystems
duf --only local

# Specific path
duf /home
```

### delta (diffs)

```bash
# Git diff with delta (configure in gitconfig)
git diff

# Diff two files
delta file1.txt file2.txt
```

## Custom Utilities (dotfiles)

Located in `custom_bins/`:

| Command | Purpose |
|---------|---------|
| `utc_date` | Outputs date in DD-MM-YYYY format |
| `utc_timestamp` | Outputs DD-MM-YYYY_HH-MM-SS |
| `tmux-clean` | Start tmux with minimal environment |
| `tsesh` | Tmux session management |
| `twin` | Tmux window management |
| `rcopy`/`rpaste` | Remote clipboard (SSH) |
| `machine-name` | Get machine hostname |
| `sync-secrets` | Sync secrets with GitHub gist |
| `clear-claude-code` | Clean up Claude Code sessions |
| `clear-mac-apps` | Clean up macOS application data |

## Execution Guidelines

When asked to perform file operations:

1. **Prefer fast alternatives** - Use eza over ls, fd over find, rg over grep
2. **Use smart defaults** - Include `--icons` for eza, `-C 3` for rg context
3. **Limit output** - Use `-n 10` or `head` for long listings
4. **Combine tools** - Pipe fd to fzf for interactive selection

## Common Patterns

```bash
# Find large files
dust -n 20

# Search and preview
fd -e py | fzf --preview 'bat --color=always {}'

# Recent files
eza -la --sort=modified -r | head -20

# Project overview
eza --tree --level=2 --icons -I 'node_modules|.git|__pycache__|.venv'

# Find TODO comments
rg -t py "TODO|FIXME|XXX" -C 1
```
