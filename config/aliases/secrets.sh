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

    # Sync OBS Studio profile and scene collection back to dotfiles (macOS only)
    sync-obs() {
        local src="$HOME/Library/Application Support/obs-studio/basic"
        local dst="$DOT_DIR/config/obs/basic"
        if [[ ! -d "$src" ]]; then
            echo "OBS config not found at $src"
            return 1
        fi
        mkdir -p "$dst/profiles/Untitled" "$dst/scenes"
        python3 - "$src" "$dst" "$HOME" <<'PYEOF'
import json, pathlib, sys
src, dst, home = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

ini_src = src / "profiles/Untitled/basic.ini"
if ini_src.is_file():
    lines = [
        line.replace(home, "__HOME__")
        for line in ini_src.read_text(encoding="utf-8-sig").splitlines()
        if not line.startswith("CookieId=")
    ]
    (dst / "profiles/Untitled/basic.ini").write_text("\n".join(lines) + "\n", encoding="utf-8")

scene_src = src / "scenes/Untitled.json"
if scene_src.is_file():
    data = json.loads(scene_src.read_text(encoding="utf-8"))
    (dst / "scenes/Untitled.json").write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
PYEOF
        echo "Synced OBS config → $dst (stripped CookieId, templated \$HOME)"
    }
fi
