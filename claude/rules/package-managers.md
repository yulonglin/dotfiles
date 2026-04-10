# Package Manager Preferences

## User's Stack

Primary languages: Python, shell, TypeScript, Rust. Rarely uses Go or Node directly.

## macOS (in order of preference)

1. **Zerobrew** — same Homebrew UX, faster; use if available
2. **Homebrew** — dominant default
3. **DMG** — fine for GUI apps
4. **App Store** — sandboxed, slower updates, but handles auto-updates
5. **Ecosystem-specific:**
   - `uv tool install` — Python CLI tools. `uv python install` for Python versions.
   - `cargo install` — Rust tools
   - `bun` / `bunx` — TS/JS tools
6. **Source** — last resort

## Linux (in order of preference)

1. **System package manager** (`apt`/`dnf`/`pacman`) — always prefer; lower overhead, better security patching
2. **Source** — preferred for freshness/control
3. **Ecosystem-specific** (same as macOS)
4. **Nope:** nix, Flatpak, Snap (avoid unless no alternative)

## Rules

- **uv is the Python everything.** Package manager, tool installer, Python version manager. Replaces pip, poetry, pipx, pyenv, mise-for-python.
- **Prefer ecosystem-native installers** for dev tools: `cargo` for Rust, `bun` for JS/TS, `uv` for Python.
- **Check what's already installed** before adding a new install method.
- **mise is not needed** — the only thing versioned is Python, and `uv` handles that.
