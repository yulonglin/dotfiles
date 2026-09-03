#!/bin/bash
# shellcheck shell=bash
# Shared path helpers for the private dotfiles secrets store.
# Safe to source from bash or zsh.

dotfiles_secrets_dir() {
    printf '%s\n' "${DOTFILES_SECRETS_DIR:-$HOME/.config/dotfiles-secrets}"
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
    # Auto-detect: bws if BOTH token exists AND bws CLI is installed
    if { [[ -n "${BWS_ACCESS_TOKEN:-}" ]] || [[ -f "$(dotfiles_secrets_bws_token_file)" ]]; } && \
       command -v bws >/dev/null 2>&1; then
        printf 'bws\n'
    else
        printf 'none\n'
    fi
}

dotfiles_secrets_harden_permissions() {
    local secrets_dir

    secrets_dir=$(dotfiles_secrets_dir)

    if [[ -d "$secrets_dir" ]]; then chmod 700 "$secrets_dir" 2>/dev/null || true; fi

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

# ─── check-only permission queries ───────────────────────────────────────────
# The *_harden_permissions functions above chmod as a side effect. A status
# readout must not: typing `secrets` should never silently change a file mode.
# These two report what the hardening pair WOULD change, one path per line,
# and touch nothing. `secrets doctor` remains the one command that applies.

_dotfiles_secrets_mode_is() {
    local path="$1" want="$2" mode
    mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null) || return 1
    [[ "$mode" == "$want" ]]
}

dotfiles_secrets_permission_issues() {
    local secrets_dir token_path token_dir

    secrets_dir=$(dotfiles_secrets_dir)
    if [[ -d "$secrets_dir" ]] && ! _dotfiles_secrets_mode_is "$secrets_dir" 700; then
        printf '%s (want 700)\n' "$secrets_dir"
    fi

    token_path=$(dotfiles_secrets_bws_token_file)
    token_dir=$(dirname "$token_path")
    if [[ -f "$token_path" ]] && ! _dotfiles_secrets_mode_is "$token_path" 600; then
        printf '%s (want 600)\n' "$token_path"
    fi
    if [[ -d "$token_dir" ]] && ! _dotfiles_secrets_mode_is "$token_dir" 700; then
        printf '%s (want 700)\n' "$token_dir"
    fi
}

project_secret_permission_issues() {
    local project_root="${1:-.}"
    local envrc="$project_root/.envrc"
    local env_file telegram_dir

    if [[ -f "$envrc" ]] && ! _dotfiles_secrets_mode_is "$envrc" 600; then
        printf '%s (want 600)\n' "$envrc"
    fi

    while IFS= read -r env_file; do
        [[ -n "$env_file" ]] || continue
        _dotfiles_secrets_mode_is "$env_file" 600 || printf '%s (want 600)\n' "$env_file"
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
            -type f -name '.env' -print 2>/dev/null
    )

    telegram_dir="$project_root/.claude/channels/telegram"
    if [[ -d "$telegram_dir" ]]; then
        _dotfiles_secrets_mode_is "$telegram_dir" 700 || printf '%s (want 700)\n' "$telegram_dir"
        for env_file in "$telegram_dir/.env" "$telegram_dir/access.json"; do
            [[ -f "$env_file" ]] || continue
            _dotfiles_secrets_mode_is "$env_file" 600 || printf '%s (want 600)\n' "$env_file"
        done
        if [[ -d "$telegram_dir/approved" ]]; then
            _dotfiles_secrets_mode_is "$telegram_dir/approved" 700 \
                || printf '%s (want 700)\n' "$telegram_dir/approved"
            while IFS= read -r env_file; do
                [[ -n "$env_file" ]] || continue
                _dotfiles_secrets_mode_is "$env_file" 600 || printf '%s (want 600)\n' "$env_file"
            done < <(find "$telegram_dir/approved" -type f -print 2>/dev/null)
        fi
    fi
}
