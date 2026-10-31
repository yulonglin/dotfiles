# CLI Output

**Commands built in this repo print in colour on a terminal, for usability.** A state reads at a glance: running, on or in sync in green; differs or a warning in yellow; a failure in red; names in bold; secondary detail dimmed (Yulong, 2026-10-30).

- **Colour only for a person at a terminal.** Add it when stdout is a TTY and `NO_COLOR` is unset. Piped output (Alfred, hooks, `| jq`, tests) stays plain, and machine output such as `--json` never carries escape codes.
- **Colour adds to the words, never replaces them.** Every coloured state also says its state in text, so a plain pipe or a colour-blind reader loses nothing.
- **Python:** a small stdlib helper for scripts that otherwise need no dependencies, as `paint()` in `custom_bins/focus` does; `rich` when the tool already wants tables, panels or progress bars.
- **zsh:** `print -P '%F{green}in sync%f'`, guarded by `[[ -t 1 && -z $NO_COLOR ]]` with a plain `print` otherwise.
