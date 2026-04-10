#!/bin/bash
# shellcheck shell=bash
# Shared path helpers for the private dotfiles secrets store.
# Safe to source from bash or zsh.

dotfiles_secrets_dir() {
    printf '%s\n' "${DOTFILES_SECRETS_DIR:-$HOME/.config/dotfiles-secrets}"
}

dotfiles_secrets_enc() {
    printf '%s/secrets.env.enc\n' "$(dotfiles_secrets_dir)"
}

dotfiles_secrets_sops_config() {
    printf '%s/.sops.yaml\n' "$(dotfiles_secrets_dir)"
}

dotfiles_secrets_age_key() {
    printf '%s\n' "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
}

dotfiles_secrets_bws_token_file() {
    printf '%s\n' "${BWS_TOKEN_FILE:-$HOME/.config/bws/token}"
}

dotfiles_secrets_backend() {
    local explicit="${DOTFILES_SECRETS_BACKEND:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s\n' "$explicit"
        return
    fi
    # Auto-detect: prefer bws if BOTH token exists AND bws CLI is installed
    if { [[ -n "${BWS_ACCESS_TOKEN:-}" ]] || [[ -f "$(dotfiles_secrets_bws_token_file)" ]]; } && \
       command -v bws >/dev/null 2>&1; then
        printf 'bws\n'
    elif command -v sops >/dev/null 2>&1 && [[ -f "$(dotfiles_secrets_enc)" ]]; then
        printf 'sops\n'
    else
        printf 'none\n'
    fi
}

dotfiles_secrets_harden_permissions() {
    local secrets_dir sops_yaml enc age_key

    secrets_dir=$(dotfiles_secrets_dir)
    sops_yaml=$(dotfiles_secrets_sops_config)
    enc=$(dotfiles_secrets_enc)
    age_key=$(dotfiles_secrets_age_key)

    if [[ -d "$secrets_dir" ]]; then chmod 700 "$secrets_dir" 2>/dev/null || true; fi
    if [[ -f "$sops_yaml" ]]; then chmod 600 "$sops_yaml" 2>/dev/null || true; fi
    if [[ -f "$enc" ]]; then chmod 600 "$enc" 2>/dev/null || true; fi
    if [[ -f "$age_key" ]]; then chmod 600 "$age_key" 2>/dev/null || true; fi

    local bws_token
    bws_token=$(dotfiles_secrets_bws_token_file)
    if [[ -f "$bws_token" ]]; then chmod 600 "$bws_token" 2>/dev/null || true; fi
    if [[ -d "$(dirname "$bws_token")" ]]; then chmod 700 "$(dirname "$bws_token")" 2>/dev/null || true; fi
}

telegram_state_harden_permissions() {
    local state_dir="$1"

    [[ -n "$state_dir" ]] || return 0
    if [[ -d "$state_dir" ]]; then chmod 700 "$state_dir" 2>/dev/null || true; fi
    if [[ -f "$state_dir/.env" ]]; then chmod 600 "$state_dir/.env" 2>/dev/null || true; fi
    if [[ -f "$state_dir/access.json" ]]; then chmod 600 "$state_dir/access.json" 2>/dev/null || true; fi

    if [[ -d "$state_dir/approved" ]]; then
        chmod 700 "$state_dir/approved" 2>/dev/null || true
        find "$state_dir/approved" -type f -exec chmod 600 {} + 2>/dev/null || true
    fi
}

project_secret_harden_permissions() {
    local project_root="${1:-.}"
    local envrc="$project_root/.envrc"
    local env_file

    if [[ -f "$project_root/.sops.yaml" ]]; then chmod 600 "$project_root/.sops.yaml" 2>/dev/null || true; fi
    if [[ -f "$project_root/secrets.env.enc" ]]; then chmod 600 "$project_root/secrets.env.enc" 2>/dev/null || true; fi
    if [[ -f "$envrc" ]]; then chmod 600 "$envrc" 2>/dev/null || true; fi

    while IFS= read -r env_file; do
        [[ -n "$env_file" ]] || continue
        chmod 600 "$env_file" 2>/dev/null || true
    done < <(
        find "$project_root" \
            \( \
                -path "$project_root/.git" -o \
                -path "$project_root/.direnv" -o \
                -path "$project_root/node_modules" -o \
                -path "$project_root/.venv" -o \
                -path "$project_root/venv" -o \
                -path "$project_root/build" -o \
                -path "$project_root/dist" -o \
                -path "$project_root/claude/plugins/cache" -o \
                -path "$project_root/claude/plugins/plugins.bak" -o \
                -path "$project_root/codex/.tmp" \
            \) -prune -o \
            -type f -name '.env' -print
    )

    if [[ -d "$project_root/.claude/channels/telegram" ]]; then
        telegram_state_harden_permissions "$project_root/.claude/channels/telegram"
    fi
}
