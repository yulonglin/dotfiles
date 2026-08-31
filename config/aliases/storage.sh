# aliases/storage.sh — volume tiering: forward bulky caches to the data volume + low-root-disk warning
# shellcheck shell=bash
#
# Companion to the server-storage-tiering skill (claude/skills/server-storage-tiering).
# Silent no-op on machines without a data volume (laptop, volume-less boxes).

# -------------------------------------------------------------------
# Per-machine config — volume mount point + warning threshold
# -------------------------------------------------------------------
# config/storage.conf is gitignored and written by `storage-setup` (also run by
# ./deploy.sh --only=storage). The defaults below reproduce the pre-config
# behaviour, so a box without the file needs no setup.
STORAGE_VOLUME=/workspace
STORAGE_ROOT_WARN_GB=20
_storage_conf="${DOT_DIR:-$HOME/code/dotfiles}/config/storage.conf"
# shellcheck source=/dev/null  # per-machine file, absent on most boxes
[ -r "$_storage_conf" ] && . "$_storage_conf"
unset _storage_conf
# A non-numeric threshold would break the arithmetic below on every shell start.
case "${STORAGE_ROOT_WARN_GB:-}" in
    '' | *[!0-9]*) STORAGE_ROOT_WARN_GB=20 ;;
esac

# -------------------------------------------------------------------
# Forward env vars — future bulky downloads land on the volume
# -------------------------------------------------------------------
# Only when the default cache path is NOT already a symlink onto the volume:
# a relocated cache (~/.cache/huggingface -> $STORAGE_VOLUME/...) already
# redirects transparently, and pointing HF_HOME elsewhere would orphan it and
# trigger mass re-downloads. Respect pre-existing exports.
#
# HUGGINGFACE_HUB_CACHE derives as $HF_HOME/hub — no need to set it.
# Deliberately NOT set: UV_CACHE_DIR / PIP_CACHE_DIR (latency-sensitive,
# may host live venvs — keep on local NVMe).
if [ -n "${STORAGE_VOLUME:-}" ] && [ -d "$STORAGE_VOLUME" ]; then
    if [ -z "${HF_HOME:-}" ] && [ ! -L "$HOME/.cache/huggingface" ]; then
        export HF_HOME="$STORAGE_VOLUME/hf"
    fi
    if [ -z "${TORCH_HOME:-}" ] && [ ! -L "$HOME/.cache/torch" ]; then
        export TORCH_HOME="$STORAGE_VOLUME/torch"
    fi
fi

# -------------------------------------------------------------------
# Low-root-disk warning — one line per new shell when root is nearly full
# -------------------------------------------------------------------
# Fast (single df, no du); silent when disk is fine, on macOS, or at threshold 0.
if [ "$(uname -s)" = "Linux" ] && [ "$STORAGE_ROOT_WARN_GB" -gt 0 ]; then
    _root_free_kb=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${_root_free_kb:-}" ] && [ "$_root_free_kb" -lt "$((STORAGE_ROOT_WARN_GB * 1048576))" ]; then
        if [ -n "${STORAGE_VOLUME:-}" ] && [ -d "$STORAGE_VOLUME" ]; then
            _storage_hint="tier bulky data to $STORAGE_VOLUME"
        else
            _storage_hint="no data volume configured (run storage-setup)"
        fi
        printf '\033[1;31mWARNING: root disk has only %sG free (<%sG) — %s (server-storage-tiering skill)\033[0m\n' \
            "$((_root_free_kb / 1048576))" "$STORAGE_ROOT_WARN_GB" "$_storage_hint" >&2
        unset _storage_hint
    fi
    unset _root_free_kb
fi
