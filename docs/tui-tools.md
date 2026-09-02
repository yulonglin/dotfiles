# TUI Tools Reference

When to use which tool for interactive terminal interfaces.

## Tool Landscape

| Layer | Tool | Language | Use case | Install |
|-------|------|----------|----------|---------|
| **Pipe-through picker** | [fzf](https://github.com/junegunn/fzf) | Go | Shell scripts — pipe stdin, get selections, custom preview | `brew install fzf` |
| **Pipe-through picker** | [skim](https://github.com/lotabout/skim) | Rust | fzf-compatible API, Rust ecosystem | `cargo install skim` |
| **Standalone finder** | [television](https://github.com/alexpasmantier/television) | Rust | File/text/repo finding (like telescope.nvim for terminal) | `brew install television` |
| **Shell widgets** | [gum](https://github.com/charmbracelet/gum) | Go | Composable widgets: confirm, input, choose, spin, table | `brew install gum` |
| **Full TUI framework** | [ratatui](https://github.com/ratatui/ratatui) | Rust | Custom apps with state, layout, events | `cargo add ratatui` |
| **Full TUI framework** | [bubbletea](https://github.com/charmbracelet/bubbletea) | Go | Elm-architecture TUI apps | `go get github.com/charmbracelet/bubbletea` |
| **Full TUI framework** | [textual](https://github.com/Textualize/textual) | Python | Rich TUI apps, CSS-like styling | `uv add textual` |

## Repo Standard

This repo uses **three** tools from the landscape above. Each has a clear lane — don't cross them.

| Tool | Lane | Where used |
|------|------|-----------|
| **fzf** | Pipe-through pickers in shell scripts | `setup-envrc`, `tmux-restore`, `secrets-init`, `modern_tools.sh` (git/history/cd helpers) |
| **gum** | Guided script UI (menus, confirms, inputs, spinners) | `install.sh`/`deploy.sh` component toggle menu |
| **ratatui** | Full TUI in compiled Rust binaries | `claude-tools` (context TUI, ignore TUI) |

### Decision Tree

```
Need interactive terminal UI?
├─ Shell script filtering/selecting data? → fzf
│   (pipe stdin, get selections out, preview pane)
│
├─ Shell script guided flow? → gum
│   (confirm, choose, input, spin — no piping needed)
│
├─ Compiled Rust tool needs a TUI? → ratatui
│   (stateful panels, keyboard navigation, themes)
│
└─ Standalone workspace finder? → television (optional)
    (file/text/repo finding, like telescope.nvim)
```

### Why These Three

Both Codex and Gemini independently recommended keeping fzf + gum as complementary tools:

- **fzf** is unbeatable for pipe-through data filtering with preview panes. Replacing with gum would lose streaming input and preview.
- **gum** is purpose-built for scripted UX flows — styled prompts, spinners, confirms. Replacing with fzf would make install scripts feel raw.
- **ratatui** is already in `claude-tools` for complex stateful TUIs that exceed what shell tools can do. Standard Rust TUI choice (superseded tui-rs, most active community).
- Both fzf and gum are single binaries, already installed. Near-zero dependency cost.

**Not currently used:** skim (unnecessary alongside fzf), bubbletea (no Go TUI apps), textual (no Python TUI apps). Documented above for reference when choosing tools in other projects.

## fzf Conventions

All fzf pickers in this repo follow these conventions:

### Keybindings

- **Space to toggle** in multi-select: `--bind 'space:toggle'`
- TAB still works (fzf default) but space is the primary advertised binding
- Header must mention bindings: `--header="SPACE to toggle, ENTER to confirm."`

### Preview Panes

- **Always add preview** when the item has viewable content (file contents, secret values, descriptions)
- Use `--preview-window=right:40%:wrap` (or `right:50%:wrap` for file contents)
- For data already in memory, dump to a temp file and have preview grep from it (avoids re-fetching)

```bash
# Pattern: preview from temp file (fast, no API calls per item)
local preview_data
preview_data=$(mktemp)
trap "rm -f '$preview_data'" EXIT
printf '%s\n' "$DATA" > "$preview_data"

fzf --preview="grep '^{1}=' '$preview_data' | sed 's/^[^=]*=//'"
```

### Display

- Use `--with-nth` to control visible columns; keep raw data in hidden fields for extraction
- Use `--delimiter=$'\t'` for structured data
- Tab-separate display fields: `name\tmetadata\t[tag]`

### Template

```bash
selections=$(printf '%s\n' "${items[@]}" | fzf --multi \
    --prompt="Select items> " \
    --header="SPACE to toggle, ENTER to confirm." \
    --bind 'space:toggle' \
    --delimiter=$'\t' \
    --with-nth=1..2 \
    --preview="cat {1}" \
    --preview-window=right:40%:wrap) || return 0
```

## gum Conventions

### Keybindings

- Space to toggle is gum's default for `--no-limit` — no extra config needed
- Header pattern: `--header "Select components (space=toggle, enter=confirm):"`

### Patterns

```bash
# Confirmation
gum confirm "Delete these files?" || exit 0

# Text input with placeholder
name=$(gum input --placeholder "Enter project name")

# Choose from list (single select)
choice=$(gum choose "option1" "option2" "option3")

# Multi-select (uses space to toggle by default)
selected=$(gum choose --no-limit "item1" "item2" "item3")

# Spinner while running command
gum spin --spinner dot --title "Deploying..." -- ./deploy.sh
```

### Graceful Fallback

Always check for gum availability and fall back to defaults in non-interactive mode:

```bash
if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] || ! command -v gum &>/dev/null; then
    return 0  # proceed with defaults
fi
```

## ratatui Conventions

Used only in `tools/claude-tools/` (Rust binary). See existing TUI modules:
- `src/context/tui/` — context profile selector
- `src/ignore/tui/` — ignore pattern manager

Follow the existing theme system in `src/context/tui/theme.rs`.

## television (Optional)

Not currently installed or required. Worth considering if you want a standalone "find anything" launcher beyond what fzf shell aliases provide. Complements fzf — doesn't replace it.

| Feature | fzf | television |
|---------|-----|-----------|
| Pipe stdin | Primary use case | Not the focus |
| Built-in file search | Ctrl+T integration | Native channels |
| Custom data sources | `cmd \| fzf` | Channel config files |
| Shell script embedding | Excellent | Limited |

Install: `brew install television` / `cargo install television`
