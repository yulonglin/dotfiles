# aliases/secrets.sh — BWS encrypted secrets management, snippet sync, Mouseless sync

# shellcheck source=/dev/null
source "$DOT_DIR/scripts/helpers/dotfiles_secrets.sh"

secrets-paths() {
    "$DOT_DIR/custom_bins/dotfiles-secrets" paths
}

secrets-fix-perms() {
    dotfiles_secrets_harden_permissions
    project_secret_harden_permissions "$PWD"
}

secrets-edit() {
    local backend
    backend=$(dotfiles_secrets_backend)
    case "$backend" in
        bws)
            if [[ $# -ge 1 ]]; then
                # Direct mode: secrets-edit KEY [VALUE] [--note DESC]
                dotfiles-secrets set "$@"
                return
            fi
            command -v fzf >/dev/null 2>&1 || { echo "fzf required for interactive mode. Use: secrets-edit KEY [VALUE]" >&2; return 1; }
            _secrets_edit_bws_fzf
            ;;
        none)
            echo "No secrets backend. Run: secrets-init" >&2; return 1
            ;;
    esac
}
_secrets_edit_bws_fzf() {
    local mutated=false
    while true; do
        local listing items=()
        listing=$(dotfiles-secrets list-full 2>/dev/null) || { echo "Failed to list secrets" >&2; return 1; }

        while IFS=$'\t' read -r _id env_name bws_key preview note; do
            [[ -n "$_id" ]] || continue
            local line="$env_name"
            if [[ "$bws_key" != "$env_name" ]]; then
                line+=$'\t'"(bws: $bws_key)"
            else
                line+=$'\t'
            fi
            line+=$'\t'"$preview"
            [[ -n "$note" ]] && line+=$'\t'"# $note"
            items+=("$line")
        done <<< "$listing"

        if [[ ${#items[@]} -eq 0 ]]; then
            echo "No secrets found. Use Ctrl-A to add one."
        fi

        local selection action chosen chosen_env
        selection=$(printf '%s\n' "${items[@]}" | fzf \
            --prompt="secrets> " \
            --header="Enter: edit value | Ctrl-A: add | Ctrl-X: delete | Esc: done" \
            --expect=ctrl-a,ctrl-x \
            --delimiter=$'\t' \
            --no-multi \
            --ansi) || break

        action=$(head -1 <<< "$selection")
        chosen=$(sed -n '2p' <<< "$selection")
        chosen_env="${chosen%%$'\t'*}"

        case "$action" in
            ctrl-a)
                printf 'Key (ENV_VAR_NAME): ' >/dev/tty
                read -r new_key </dev/tty
                [[ -n "$new_key" ]] || continue
                printf 'Description (optional, appended as "KEY - desc"): ' >/dev/tty
                read -r new_desc </dev/tty
                printf 'Value: ' >/dev/tty
                read -rs new_value </dev/tty
                echo "" >/dev/tty
                [[ -n "$new_value" ]] || { echo "Empty value, skipping."; continue; }
                if [[ -n "$new_desc" ]]; then
                    dotfiles-secrets set "$new_key" "$new_value" --note "$new_desc"
                else
                    dotfiles-secrets set "$new_key" "$new_value"
                fi
                mutated=true
                ;;
            ctrl-x)
                [[ -n "$chosen_env" ]] || continue
                printf 'Delete %s? (y/N) ' "$chosen_env" >/dev/tty
                read -r confirm </dev/tty
                if [[ "$confirm" == [yY]* ]]; then
                    dotfiles-secrets rm --yes "$chosen_env"
                    mutated=true
                fi
                ;;
            *)  # Enter: edit value
                [[ -n "$chosen_env" ]] || continue
                printf 'New value for %s: ' "$chosen_env" >/dev/tty
                read -rs new_value </dev/tty
                echo "" >/dev/tty
                [[ -n "$new_value" ]] || { echo "Empty value, skipping."; continue; }
                dotfiles-secrets set "$chosen_env" "$new_value"
                mutated=true
                ;;
        esac
    done

    if $mutated; then
        dotfiles-secrets cache-clear >/dev/null 2>&1
        echo "Cache cleared. Run 'direnv reload' in projects to pick up changes."
    fi
}
secrets-init() {
    local choice
    if [[ $# -gt 0 ]]; then
        choice="$1"
    elif command -v fzf >/dev/null 2>&1; then
        choice=$(printf '%s\n' \
            "bws	Set up Bitwarden Secrets Manager (recommended, multi-machine)" \
            "project	Configure secrets for current repo (setup-envrc)" \
            | fzf --prompt="secrets-init> " \
                  --header="What do you want to set up?" \
                  --with-nth=1.. \
                  --delimiter=$'\t' \
            | cut -f1) || return 0
    else
        echo "Usage: secrets-init [bws|project]" >&2
        return 1
    fi

    case "$choice" in
        bws)     secrets-init-bws ;;
        project) setup-envrc ;;
        *)       echo "Unknown option: $choice. Use 'bws' or 'project'." >&2; return 1 ;;
    esac
}

secrets-init-bws() {
    if ! command -v bws &>/dev/null; then
        echo "Error: bws CLI not found — install it first:" >&2
        echo "  ./install.sh --minimal --core     # includes bws" >&2
        return 1
    fi

    local token_file token_dir
    token_file=$(dotfiles_secrets_bws_token_file)
    token_dir=$(dirname "$token_file")

    echo "BWS token file: $token_file"

    if [[ -f "$token_file" ]]; then
        echo "BWS token already exists."
        echo -n "Overwrite? [y/N] "
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 0
    fi

    echo ""
    echo "Paste your BWS access token (from Bitwarden Secrets Manager):"
    echo "(machine account token, starts with 0., leave empty to skip)"
    read -rs bws_token
    echo ""

    if [[ -z "$bws_token" ]]; then
        echo "Skipped"
        return 0
    fi

    mkdir -p "$token_dir"
    chmod 700 "$token_dir"

    echo "Testing bws connectivity..."
    local bws_output
    if bws_output=$(BWS_ACCESS_TOKEN="$bws_token" bws secret list 2>/dev/null); then
        local count
        count=$(printf '%s' "$bws_output" | \
            python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?")
        echo "Success — $count secret(s) accessible"
        printf '%s\n' "$bws_token" > "$token_file"
        chmod 600 "$token_file"
        echo "Token saved to $token_file"
    else
        echo "Error: bws secret list failed — token NOT saved" >&2
        echo "Check your token and try again" >&2
        unset bws_token
        return 1
    fi

    unset bws_token

    dotfiles_secrets_harden_permissions

    echo ""
    echo "Backend: $(dotfiles_secrets_backend)"
    echo "Next: dotfiles-secrets keys / setup-envrc"
}
alias snippets-sync='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync'
alias snippets-export='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" export'
alias snippets-diff='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" diff'
alias snippets-prune='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync --prune'
# back-compat shims for renamed aliases
alias sync-snippets='snippets-sync'
alias export-snippets='snippets-export'
alias trsync='snippets-prune'

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
