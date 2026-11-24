#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# SYNC CLAUDE CODE TO ANTIGRAVITY (one-way projection)
# Purpose: Project portable Claude Code config into Antigravity's shared global
#          customization root (~/.gemini/config/), used by agy CLI, Antigravity
#          2.0 App, and Antigravity IDE.
#
# Single source of truth stays in dotfiles/claude/ and dotfiles/antigravity/:
#   1. skills.json -> symlink to antigravity/skills.json (points at ~/.claude/skills
#                     with exclude list for Claude-runtime-only skills)
#   2. GEMINI.md   -> symlink to claude/CLAUDE.md (always-on, live updates)
#   3. AGENTS.md   -> symlink to antigravity/AGENTS.md (tool-compatibility shim)
#   4. rules/*.md  -> projected from portable claude/rules/*.md with required
#                     `trigger: always_on` frontmatter; stale managed files are
#                     pruned while user-authored rules are preserved
#   5. mcp_config.json -> shared MCPs via sync_mcp_servers.py plus baseline
#                         portable servers (context7, macOS bear, slack-mcp-stdio)
#                         if absent
#   6. antigravity-cli/settings.json -> defaults (agentMode="auto",
#                         enableTerminalSandbox=true), curated Antigravity
#                         permissions (antigravity/permissions.json), and
#                         portable Claude Bash token-prefix rules from
#                         claude/settings.json (non-destructive merge)
#
# Claude hooks are intentionally NOT auto-imported (incompatible JSON contracts
# and synchronous-only execution). Curate native Antigravity hooks separately.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$HOME/.gemini/config"
SETTINGS_PATH=""
CLAUDE_DIR="$DOTFILES_DIR/claude"
EXCLUDE_RULES=("background-jobs.md")

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Project portable Claude Code config one-way into Antigravity (~/.gemini/config)
and sync managed permissions/defaults into ~/.gemini/antigravity-cli/settings.json.

Options:
  --target-dir PATH     Target Antigravity config dir (default: ~/.gemini/config)
  --settings-path PATH  Target Antigravity CLI settings.json
                        (default: ~/.gemini/antigravity-cli/settings.json when
                        using the default target dir, else <target-dir>/antigravity-cli/settings.json)
  --dotfiles-dir PATH   Dotfiles repo root (default: repo containing this script)
  --claude-dir PATH     Source Claude config dir (default: <dotfiles-dir>/claude)
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        --settings-path)
            SETTINGS_PATH="$2"
            shift 2
            ;;
        --dotfiles-dir)
            DOTFILES_DIR="$2"
            shift 2
            ;;
        --claude-dir)
            CLAUDE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$SETTINGS_PATH" ]]; then
    if [[ "$TARGET_DIR" == "$HOME/.gemini/config" ]]; then
        SETTINGS_PATH="$HOME/.gemini/antigravity-cli/settings.json"
    else
        SETTINGS_PATH="$TARGET_DIR/antigravity-cli/settings.json"
    fi
fi

ANTIGRAVITY_SRC="$DOTFILES_DIR/antigravity"
RULES_SRC="$CLAUDE_DIR/rules"
RULES_DST="$TARGET_DIR/rules"
MCP_SOURCE="$DOTFILES_DIR/config/mcp-servers.json"
MCP_SYNC_SCRIPT="$DOTFILES_DIR/scripts/helpers/sync_mcp_servers.py"
SETTINGS_SYNC_SCRIPT="$DOTFILES_DIR/scripts/helpers/sync_antigravity_settings.py"
MCP_TARGET="$TARGET_DIR/mcp_config.json"

if [[ ! -d "$ANTIGRAVITY_SRC" ]]; then
    echo "Error: antigravity source directory not found at $ANTIGRAVITY_SRC" >&2
    exit 1
fi

mkdir -p "$TARGET_DIR" "$RULES_DST"

link_managed() {
    local src="$1" dst="$2"
    if [[ ! -e "$src" ]]; then
        echo "  Warning: missing source $src — skipping $dst" >&2
        return 0
    fi
    if [[ -L "$dst" ]]; then
        if [[ "$(readlink "$dst")" == "$src" ]]; then
            return 0
        fi
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local backup
        backup="${dst}.backup.$(date -u +%Y-%m-%d_%H-%M-%S)"
        mv "$dst" "$backup"
        echo "  Backed up existing $dst -> $backup"
    fi
    ln -s "$src" "$dst"
    echo "  Linked $dst -> $src"
}

echo ">>> Syncing Claude Code config to Antigravity ($TARGET_DIR)..."

# 1. Skills manifest + global instruction files
link_managed "$ANTIGRAVITY_SRC/skills.json" "$TARGET_DIR/skills.json"
link_managed "$ANTIGRAVITY_SRC/AGENTS.md" "$TARGET_DIR/AGENTS.md"
link_managed "$CLAUDE_DIR/CLAUDE.md" "$TARGET_DIR/GEMINI.md"

if [[ ! -d "$HOME/.claude/skills" && "$TARGET_DIR" == "$HOME/.gemini/config" ]]; then
    echo "  Note: ~/.claude/skills not found yet — run ./deploy.sh --only claude so skills.json resolves"
fi

# 2. Project portable claude/rules/*.md with Antigravity always_on frontmatter
if [[ -d "$RULES_SRC" ]]; then
    python3 - "$RULES_SRC" "$RULES_DST" "${EXCLUDE_RULES[@]}" <<'PY'
import os
import sys
import tempfile
from pathlib import Path

src_dir = Path(sys.argv[1])
dst_dir = Path(sys.argv[2])
excluded = set(sys.argv[3:])

MARKER = "<!-- Generated by scripts/sync_claude_to_antigravity.sh"
PER_FILE_LIMIT = 24_000


def atomic_write(path: Path, text: str) -> None:
    fd, tmp = tempfile.mkstemp(prefix=".ag-rule-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


expected: set[str] = set()
written = 0
unchanged = 0
for src in sorted(src_dir.glob("*.md")):
    if src.name in excluded:
        continue
    expected.add(src.name)
    body = src.read_text(encoding="utf-8")
    # Respect existing frontmatter if a source rule ever adopts it; otherwise
    # prepend Antigravity's required always_on trigger block.
    if body.startswith("---\n"):
        rendered = (
            f"{MARKER} from claude/rules/{src.name}; edit the source, not this file. -->\n"
            + body
        )
    else:
        rendered = (
            "---\n"
            "trigger: always_on\n"
            "---\n"
            f"{MARKER} from claude/rules/{src.name}; edit the source, not this file. -->\n\n"
            + body
        )

    size = len(rendered.encode("utf-8"))
    if size > PER_FILE_LIMIT:
        print(
            f"  Warning: {src.name} is {size} bytes (> Antigravity {PER_FILE_LIMIT}-byte per-file cap)",
            file=sys.stderr,
        )

    dst = dst_dir / src.name
    if dst.exists() and not dst.is_symlink() and dst.read_text(encoding="utf-8") == rendered:
        unchanged += 1
        continue
    if dst.is_symlink():
        dst.unlink()
    atomic_write(dst, rendered)
    written += 1

pruned = 0
for existing in sorted(dst_dir.glob("*.md")):
    if existing.name in expected or existing.is_symlink():
        continue
    try:
        head = existing.read_text(encoding="utf-8")[:512]
    except OSError:
        continue
    if MARKER in head:
        existing.unlink()
        pruned += 1

print(f"  Rules: {len(expected)} active ({written} updated, {unchanged} current, {pruned} pruned)")
PY
else
    echo "  Warning: Claude rules directory not found at $RULES_SRC" >&2
fi

# 3. Shared MCP servers -> mcp_config.json (plus baseline portable servers if absent)
if [[ -f "$MCP_SOURCE" && -f "$MCP_SYNC_SCRIPT" ]]; then
    python3 "$MCP_SYNC_SCRIPT" \
        --source "$MCP_SOURCE" \
        --claude-settings "$DOTFILES_DIR/claude/settings.json" \
        --codex-config "$DOTFILES_DIR/codex/config.toml" \
        --antigravity-config "$MCP_TARGET" \
        --apply >/dev/null
fi

python3 - "$MCP_TARGET" "$DOTFILES_DIR" <<'PY'
import json
import os
import platform
import sys
import tempfile
from pathlib import Path

target = Path(sys.argv[1])
dotfiles_dir = Path(sys.argv[2])
data = {"mcpServers": {}}
if target.exists():
    try:
        raw = target.read_text(encoding="utf-8").strip()
        if raw:
            loaded = json.loads(raw)
            if isinstance(loaded, dict):
                data = loaded
    except (OSError, json.JSONDecodeError) as exc:
        print(f"  Warning: {target} is not valid JSON ({exc}); leaving untouched", file=sys.stderr)
        sys.exit(0)

servers = data.setdefault("mcpServers", {})
if not isinstance(servers, dict):
    print(f"  Warning: {target} mcpServers is not an object; leaving untouched", file=sys.stderr)
    sys.exit(0)

added = []
defaults = {
    "context7": {"url": "https://mcp.context7.com/mcp"},
}
bearcli = "/Applications/Bear.app/Contents/MacOS/bearcli"
if platform.system() == "Darwin" and os.access(bearcli, os.X_OK):
    defaults["bear"] = {"command": bearcli, "args": ["mcp-server"]}
slack_stdio = dotfiles_dir / "custom_bins" / "slack-mcp-stdio"
if slack_stdio.exists() and os.access(slack_stdio, os.X_OK):
    defaults["slack"] = {"command": str(slack_stdio)}

for name, cfg in defaults.items():
    if name not in servers:
        servers[name] = cfg
        added.append(name)

if added or not target.exists():
    target.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(prefix=".ag-mcp-", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(rendered)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    if added:
        print(f"  MCP: seeded {', '.join(added)} in {target}")
    else:
        print(f"  MCP: initialized {target}")
else:
    print(f"  MCP: {target} already up to date ({len(servers)} server(s))")
PY

# 4. Antigravity CLI settings.json (defaults + curated permissions + Claude Bash rules)
if [[ -f "$SETTINGS_SYNC_SCRIPT" ]]; then
    python3 "$SETTINGS_SYNC_SCRIPT" \
        --claude-settings "$CLAUDE_DIR/settings.json" \
        --antigravity-perms "$ANTIGRAVITY_SRC/permissions.json" \
        --target-settings "$SETTINGS_PATH" \
        --apply
fi

# Flag legacy skill-symlink directory from the pre-2026-11 script if present
if [[ "$TARGET_DIR" == "$HOME/.gemini/config" && -d "$HOME/.gemini/antigravity-cli/skills" ]]; then
    legacy_links=$(find "$HOME/.gemini/antigravity-cli/skills" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$legacy_links" -gt 0 ]]; then
        echo "  Note: $legacy_links legacy symlink(s) remain in ~/.gemini/antigravity-cli/skills (superseded by ~/.gemini/config/skills.json)"
    fi
fi

echo ">>> Done! Antigravity global config synchronized."
