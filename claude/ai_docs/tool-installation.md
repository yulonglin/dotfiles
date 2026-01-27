# Tool Installation Reference

Quick setup guides for CLI tools used across projects.

## aichat-search (Session Search)

Full-text search across Claude Code and Codex sessions.

**Install** (Linux x86_64):
```bash
mkdir -p ~/.local/bin
curl -L https://github.com/pchalasani/claude-code-tools/releases/download/rust-v0.3.0/aichat-search-linux-x86_64.tar.gz | tar -xz -C ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Other platforms**:
- macOS: `brew install pchalasani/tap/aichat-search`
- Cargo: `cargo install aichat-search`
- ARM64: Replace `x86_64` with `arm64` in URL

**Initialize**: Run `aichat search --help` to auto-index sessions.

**Usage**:
```bash
aichat search "query"           # Interactive TUI
aichat search "query" --json    # JSON output for scripts/agents
aichat search -g "query"        # Search all projects (global)
```

**Note**: Use `aichat` commands (Python frontend), not `aichat-search` directly. The binary can't bootstrap itself without the Python wrapper.

## tmux-cli

See global CLAUDE.md for usage. Install via uv:
```bash
uv tool install aichat  # Includes tmux-cli
```

Or with pipx:
```bash
pipx install aichat
```
