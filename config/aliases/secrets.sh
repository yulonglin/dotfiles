# aliases/secrets.sh — BWS encrypted secrets management, snippet sync, Mouseless sync
# shellcheck shell=bash

alias snippets-sync='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync'
alias snippets-export='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" export'
alias snippets-diff='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" diff'
alias snippets-prune='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync --prune'

# Sync Mouseless UI config changes back to dotfiles (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
    sync-mouseless() {
        local src="$HOME/Library/Containers/net.sonuscape.mouseless/Data/.mouseless/configs/config.yaml"
        local dst="$DOT_DIR/config/mouseless/config.yaml"
        if [[ ! -f "$src" ]]; then
            echo "Mouseless config not found at $src"
            return 1
        fi
        if ! python3 -c "import yaml" 2>/dev/null; then
            echo "PyYAML not installed. Run: pip3 install pyyaml" >&2
            return 1
        fi
        python3 - "$src" "$dst" <<'PYEOF'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = yaml.safe_load(f)
cfg.pop('keyboard_layout', None)
cfg.pop('app_version', None)
with open(dst, 'w') as f:
    yaml.dump(cfg, f, allow_unicode=True, sort_keys=False, default_flow_style=False)
PYEOF
        echo "Synced Mouseless config → $dst (stripped keyboard_layout, app_version)"
    }
fi
