# Context

The dotfiles repo uses **vscode-icons**. It has built-in mappings for `.claude` and `.gemini` (dot-prefixed hidden dirs), but not for the plain `claude/`, `gemini/`, `codex/` directories in the repo root. File icons (CLAUDE.md, GEMINI.md, AGENTS.md) work fine via built-in mappings — macOS case-insensitivity means `CLAUDE.md` matches the `claude.md` built-in rule.

The fix: add 3 folder associations to `config/vscode_settings.json`, then re-run deploy.

---

# What's Already Working (no changes needed)

| Name | Reason |
|------|--------|
| `plans/` | Already in `vsicons.associations.folders` → `blueprint` |
| `CLAUDE.md`, `GEMINI.md`, `AGENTS.md` | File icons work via built-in vscode-icons mappings + macOS case-insensitivity |
| `specs/`, `docs/`, `scripts/`, `config/`, `tools/`, `lib/` | Built-in vscode-icons folder mappings |

---

# Change Required

## File: `config/vscode_settings.json`

Add 3 entries to `vsicons.associations.folders` (currently lines 91–99):

```json
{ "icon": "claude", "extensions": ["claude"], "format": "svg" },
{ "icon": "gemini", "extensions": ["gemini"], "format": "svg" },
{ "icon": "cli",    "extensions": ["codex"],  "format": "svg" }
```

Icon rationale (all SVGs verified present in vscode-icons 12.17.0):
- `claude` → `folder_type_claude.svg` ✓ — same icon as the built-in `.claude/` mapping
- `gemini` → `folder_type_gemini.svg` ✓ — same icon as the built-in `.gemini/` mapping
- `cli` → `folder_type_cli.svg` ✓ — Codex is a CLI tool; no `codex`-specific folder icon exists

---

# Verification

1. Run `./deploy.sh --editor` from the dotfiles root (merges into Cursor/VS Code settings)
2. In Cursor: Command Palette → "vsicons: Apply Icons Customization" (or accept the auto-prompt)
3. Reload window (`Cmd+Shift+P` → "Developer: Reload Window")
4. Explorer panel: `claude/`, `gemini/`, `codex/` should show distinct icons
