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

## Stale VIRTUAL_ENV After Repo Move

**Root cause**: `.venv/bin/activate` hardcodes the absolute path when the venv is created. Moving the repo makes that path stale. Every `source .venv/bin/activate` (by you, your IDE, or a tool) then sets `VIRTUAL_ENV` to the old location. This causes `ty`, `ruff`, `uv`, and other tools to fail:
```
Invalid `VIRTUAL_ENV` environment variable `/old/path/.venv`: does not point to a directory on disk
```

**Fix** (after moving a repo):
```bash
uv venv    # recreates .venv with correct paths (~1s)
uv sync    # reinstalls deps (~2s with cache)
```

**Prevention**: Use `uv run <cmd>` instead of activating venvs. `uv run` resolves `.venv` by project location, ignoring `VIRTUAL_ENV` entirely:
```bash
uv run ruff check .     # not: ruff check .
uv run ty check .       # not: ty check .
uv run pytest           # not: pytest
```

**Inside Claude Code** (can't `deactivate`): `unset VIRTUAL_ENV` as a workaround, but the real fix is `uv venv && uv sync`.

A `PreToolUse` hook auto-detects this — see `hooks/check-venv.sh`.

## Machine-Specific Setup

On new machines, set `SERVER_NAME` in `~/.zshenv` for identification in prompts and statusline.

```bash
echo 'export SERVER_NAME="<short-name>"' >> ~/.zshenv
source ~/.zshenv
```

**Naming conventions**: `rp` (RunPod), `mats` (MATS cluster), `hz-1` (Hetzner server 1)

**Why zshenv**: Loaded for ALL shells (interactive, non-interactive, scripts), ensuring `SERVER_NAME` is always available. Used by `machine-name` script for p10k prompt and Claude statusline.
