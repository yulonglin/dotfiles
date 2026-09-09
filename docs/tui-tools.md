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

## Repo Standard: A Menu Is Not A Search Box

Two tools, one each for the two jobs a script actually has. A **menu** is a short, known list that fits on screen — arrow to a row, pick or toggle, no typing. A **search box** is a long list you narrow by typing. They are different products, and neither replaces the other.

| Tool | Lane | Where used |
|------|------|-----------|
| **`claude-tools select`** (ratatui, ours) | Menus: pick one row (`--single`) or toggle several | `install.sh`/`deploy.sh` component menu, `app-picker`, the bare `secrets` menu |
| **fzf** | Search: type to narrow a long list, with a preview pane | `secrets envrc`, `secrets edit`, `secrets use`, `tmux-restore`, `modern_tools.sh` (git/history/cd helpers), the `ctrl-r`/`ctrl-t` shell widgets |

`claude-tools select` is a committed binary for darwin-arm64, linux-x86_64 and linux-aarch64, so it exists before Homebrew does — on a fresh Mac, in `install.sh` before brew runs, and on a RunPod box where `scripts/cloud/setup.sh` never installs brew at all. That is why the menus use it and not a brew-installed tool. fzf is brew-only, which is acceptable because every fzf use is either a shell widget in an interactive login shell or a picker that degrades to defaults when fzf is absent.

### Decision Tree

```
Need interactive terminal UI?
├─ Short known list, arrow and pick/toggle? → claude-tools select
│   (stdin rows, works pre-brew, --single for one pick)
│
├─ Long list the user types to narrow? → fzf
│   (pipe stdin, get selections out, preview pane)
│
├─ A yes/no in a cleanup or uninstall script? → plain `read`
│   (a confirm prompt does not need a TUI)
│
└─ Compiled Rust tool needs stateful panels? → ratatui in claude-tools
```

### Retired: gum

gum (Go, brew-only) was used in two files, both only `gum choose`, which `claude-tools select` already did. It never reached a cloud box. Retired 2026-09-08; the landscape table above keeps it for reference in other projects. The earlier claim on this page that gum drove the component menu was wrong — `install.sh` always used `claude-tools select` there.

**Not used:** skim (unnecessary alongside fzf), bubbletea (no Go TUI apps), textual (no Python TUI apps), television (optional, see below).

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

## claude-tools select Conventions

Source: `tools/claude-tools/src/select/`. Contract:

- **Input** on stdin, one row per line: `group|name|description|checked`. `checked` is the literal `true` to pre-select. A new group value opens a header; sort rows by group first or headers repeat. `|` is the separator, so normalise it out of display fields.
- **Output** on stdout: the chosen *names*, one per line, nothing else. The TUI paints on stderr and reads keys from `/dev/tty`, so `result=$(rows | claude-tools select)` is safe.
- **Flags**: `--title <text>` for the header; `--single` makes Enter pick the row under the cursor (space is an alias), hides the checkboxes, and prints exactly one name.
- **Keys**: `j`/`k` or arrows, `space` toggle, `enter` confirm, `q`/`Esc` cancel (**exit 1**), `ctrl-l` repaint.
- **Binaries rebuild in CI**: `.github/workflows/build-claude-tools.yml` builds all three targets on any merge to main touching `tools/claude-tools/src/` and commits them with `SHA256SUMS`. A local `cargo build --release` copied to `custom_bins/claude-tools-<host>` covers the host until then. An old binary ignores flags it does not know — `--single` degrades to space-then-Enter — so callers take `head -n 1` and never assume the flag landed.

```bash
# One pick from a short menu
choice=$(printf '%s\n' \
    "What next?|Edit keys|fzf editor over every key|false" \
    "What next?|Wire this repo|write .envrc bindings|false" \
    | claude-tools select --single --title "secrets" | head -n 1) || return 0

# Toggle several, pre-selecting defaults
chosen=$(print -rl -- "$rows[@]" | claude-tools select --title "Select apps") || exit 0
```

### Graceful Fallback

Gate on the mode, the TTY and the binary, and fall through to defaults. A menu that dispatches into mutating commands (the bare `secrets` menu) also requires stdout to be a terminal, so `secrets | cat` stays inert:

```bash
if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] || ! command -v claude-tools &>/dev/null; then
    return 0  # proceed with defaults
fi
```

## ratatui Conventions

Used only in `tools/claude-tools/` (Rust binary). See existing TUI modules:
- `src/select/` — the menu described above
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
