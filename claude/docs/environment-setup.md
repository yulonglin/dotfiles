# Environment Setup

## Agent Spawning Fix

**Issue**: On some systems, `/tmp/claude` is owned by root, blocking agent spawning.

**Solution**: Set `CLAUDE_CODE_TMPDIR` environment variable to writable location.

```bash
mkdir -p ~/tmp/claude-code
echo 'export CLAUDE_CODE_TMPDIR=~/tmp/claude-code' >> ~/.bashrc
echo 'export CLAUDE_CODE_TMPDIR=~/tmp/claude-code' >> ~/.zshrc 2>/dev/null
export CLAUDE_CODE_TMPDIR=~/tmp/claude-code
```

Alternatives: `export CLAUDE_CODE_TMPDIR=/run/user/$(id -u)` or `$HOME/tmp/claude`

**Note**: The error message is misleading. Processes often start anyway despite the EACCES error.

## Machine-Specific Setup

On new machines, set `SERVER_NAME` in `~/.zshenv` for identification in prompts and statusline.

```bash
echo 'export SERVER_NAME="<short-name>"' >> ~/.zshenv
source ~/.zshenv
```

**Naming conventions**: `rp` (RunPod), `mats` (MATS cluster), `hz-1` (Hetzner server 1)

**Why zshenv**: Loaded for ALL shells (interactive, non-interactive, scripts), ensuring `SERVER_NAME` is always available. Used by `machine-name` script for p10k prompt and Claude statusline.
