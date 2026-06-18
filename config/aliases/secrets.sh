# aliases/secrets.sh — SOPS/BWS encrypted secrets management, snippet sync, Mouseless sync

# shellcheck source=/dev/null
source "$DOT_DIR/scripts/helpers/dotfiles_secrets.sh"

# SOPS-encrypted secrets management
# On macOS, sops checks ~/Library/Application Support/sops/age/keys.txt (Go's
# os.UserConfigDir), not ~/.config/. Point it to the XDG-conventional location.
export SOPS_AGE_KEY_FILE="$(dotfiles_secrets_age_key)"

# Thin wrapper: secrets are dotenv format but files end in .enc, so sops
# can't infer the format. This sets --input-type/--output-type once.
sops_dotenv() { sops --input-type dotenv --output-type dotenv "$@"; }

secrets-paths() {
    "$DOT_DIR/custom_bins/dotfiles-secrets" paths
}

secrets-fix-perms() {
    dotfiles_secrets_harden_permissions
    project_secret_harden_permissions "$PWD"
}

secrets-recipients-edit() {
    local sops_yaml
    sops_yaml=$(dotfiles_secrets_sops_config)
    mkdir -p "$(dotfiles_secrets_dir)"
    "${EDITOR:-vim}" "$sops_yaml"
    dotfiles_secrets_harden_permissions
}

secrets-updatekeys() {
    if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh"; return 1; fi
    local sops_yaml enc
    sops_yaml=$(dotfiles_secrets_sops_config)
    enc=$(dotfiles_secrets_enc)
    sops --config "$sops_yaml" updatekeys --yes "$enc"
    dotfiles_secrets_harden_permissions
}

secrets-rotate-data-key() {
    if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh"; return 1; fi
    local sops_yaml enc
    sops_yaml=$(dotfiles_secrets_sops_config)
    enc=$(dotfiles_secrets_enc)
    sops --config "$sops_yaml" rotate -i --input-type dotenv --output-type dotenv "$enc"
    dotfiles_secrets_harden_permissions
}

secrets-edit() {
    local backend
    backend=$(dotfiles_secrets_backend)
    case "$backend" in
        sops)
            if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh" >&2; return 1; fi
            local sops_yaml enc
            sops_yaml=$(dotfiles_secrets_sops_config)
            enc=$(dotfiles_secrets_enc)
            mkdir -p "$(dotfiles_secrets_dir)"
            sops_dotenv --config "$sops_yaml" "$enc"
            dotfiles_secrets_harden_permissions
            ;;
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
            "sops	Set up SOPS + age (offline, file-based)" \
            "project	Configure secrets for current repo (setup-envrc)" \
            | fzf --prompt="secrets-init> " \
                  --header="What do you want to set up?" \
                  --with-nth=1.. \
                  --delimiter=$'\t' \
            | cut -f1) || return 0
    else
        echo "Usage: secrets-init [bws|sops|project]" >&2
        return 1
    fi

    case "$choice" in
        bws)     secrets-init-bws ;;
        sops)    secrets-init-sops ;;
        project) setup-envrc ;;
        *)       echo "Unknown option: $choice. Use 'bws', 'sops', or 'project'." >&2; return 1 ;;
    esac
}

secrets-init-sops() {
    local age_key
    local age_dir
    local secrets_dir
    local sops_yaml
    local enc

    age_key=$(dotfiles_secrets_age_key)
    age_dir=$(dirname "$age_key")
    secrets_dir=$(dotfiles_secrets_dir)
    sops_yaml=$(dotfiles_secrets_sops_config)
    enc=$(dotfiles_secrets_enc)

    mkdir -p "$secrets_dir"

    echo "Config: age_key=$age_key"
    echo "Config: secrets_dir=$secrets_dir"
    echo "Config: sops_yaml=$sops_yaml"
    echo "Config: enc=$enc"

    if [[ ! -f "$age_key" ]]; then
        mkdir -p "$age_dir"
        age-keygen -o "$age_key" 2>&1
        echo "Generated age key at $age_key"
    else
        echo "Age key already exists at $age_key"
    fi

    local pub_key
    pub_key=$(grep -o 'age1[a-z0-9]*' "$age_key" | head -1)
    echo "Public key: ${pub_key:0:20}..."

    if [[ ! -f "$sops_yaml" ]] || grep -q 'age1\.\.\.' "$sops_yaml"; then
        cat > "$sops_yaml" <<YAML
creation_rules:
  - path_regex: \\.enc$
    age: "$pub_key"
YAML
        echo "Created $sops_yaml with public key"
    else
        # Warn if local key doesn't match the key in .sops.yaml
        local config_key
        config_key=$(grep -o 'age1[a-z0-9]*' "$sops_yaml" | head -1)
        if [[ -n "$config_key" && "$config_key" != "$pub_key" ]]; then
            echo "⚠️  Key mismatch! Local age key does not match $sops_yaml"
            echo "  Local key:      ${pub_key:0:30}..."
            echo "  .sops.yaml key: ${config_key:0:30}..."
            echo "  You won't be able to decrypt existing secrets with this key"
            echo "  To fix: paste the original age key from Bitwarden into $age_key"
        else
            echo "$sops_yaml already exists, skipping"
        fi
    fi

    if [[ ! -s "$enc" ]]; then
        local tmpfile="${TMPDIR:-/tmp}/secrets_template.env"
        printf '%s\n' \
            "# Encrypted API keys (edit with: secrets-edit)" \
            "PLACEHOLDER=replace_me" \
            "# ANTHROPIC_API_KEY=" \
            "# OPENAI_API_KEY=" \
            "# HF_TOKEN=" \
            "# GITHUB_TOKEN=" \
            > "$tmpfile"
        echo "Running: sops -e --config /dev/null --age <key> $tmpfile > $enc"
        if sops -e --config /dev/null --age "$pub_key" "$tmpfile" > "${enc}.tmp"; then
            mv "${enc}.tmp" "$enc"
            echo "Created $enc — edit with: secrets-edit"
        else
            rm -f "${enc}.tmp"
            echo "Failed to encrypt (sops -e --config /dev/null --age ... $tmpfile)" >&2
        fi
        rm -f "$tmpfile"
    else
        echo "Encrypted secrets already exist at $enc"
    fi

    dotfiles_secrets_harden_permissions

    echo ""
    echo "Next steps:"
    echo "  1. secrets-edit          # Add your API keys"
    echo "  2. sync-gist             # Sync SSH config + git identity"
    echo "  3. setup-envrc           # Export selected keys in the current repo"
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
secrets-init-project() {
    local sops_yaml=".sops.yaml"
    local enc="secrets.env.enc"
    local envrc=".envrc"
    local age_key="$HOME/.config/sops/age/keys.txt"

    if [[ ! -f "$age_key" ]]; then
        echo "No age key found at $age_key — run secrets-init sops first"
        return 1
    fi

    local pub_key
    pub_key=$(grep -o 'age1[a-z0-9]*' "$age_key" | head -1)
    if [[ -z "$pub_key" ]]; then
        echo "Could not extract public key from $age_key" >&2; return 1
    fi
    echo "Public key: ${pub_key:0:20}..."

    if [[ ! -f "$sops_yaml" ]]; then
        cat > "$sops_yaml" <<YAML
creation_rules:
  - path_regex: \\.enc$
    age: "$pub_key"
YAML
        echo "Created $sops_yaml in $(pwd)"
    fi

    if [[ ! -s "$enc" ]]; then
        local tmpfile="${TMPDIR:-/tmp}/proj_secrets.env"
        printf '%s\n' "# Project secrets (edit with: sops --input-type dotenv --output-type dotenv --config $sops_yaml $enc)" "PLACEHOLDER=replace_me" > "$tmpfile"
        echo "Running: sops -e --config /dev/null --age <key> $tmpfile > $enc"
        if sops -e --config /dev/null --age "$pub_key" "$tmpfile" > "${enc}.tmp"; then
            mv "${enc}.tmp" "$enc"
            echo "Created $enc"
        else
            rm -f "${enc}.tmp"
            echo "Failed to encrypt (sops -e --config /dev/null --age ... $tmpfile)" >&2
        fi
        rm -f "$tmpfile"
    fi

    if [[ ! -f "$envrc" ]]; then
        if [[ -f "$DOT_DIR/config/envrc_sops_template" ]]; then
            cp "$DOT_DIR/config/envrc_sops_template" "$envrc"
        else
            printf '%s\n' '# Auto-decrypt SOPS secrets on cd' \
                'if command -v sops &>/dev/null && [ -f secrets.env.enc ]; then' \
                '    dotenv <(sops -d --input-type dotenv --output-type dotenv --config .sops.yaml secrets.env.enc 2>/dev/null)' \
                'fi' > "$envrc"
        fi
        echo "Created $envrc — run: direnv allow"
    fi

    project_secret_harden_permissions "$PWD"

    echo "Done. Edit secrets: sops --input-type dotenv --output-type dotenv --config $sops_yaml $enc"
}
alias snippets-sync='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync'
alias snippets-export='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" export'
alias snippets-diff='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" diff'
# back-compat shims for renamed aliases
alias sync-snippets='snippets-sync'
alias export-snippets='snippets-export'

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
