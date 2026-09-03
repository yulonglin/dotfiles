# aliases/storage.sh — volume tiering: forward bulky caches to the data volume + low-root-disk warning
# shellcheck shell=bash
#
# Companion to the server-storage-tiering skill (claude/skills/server-storage-tiering).
# Silent no-op on machines without a data volume (laptop, volume-less boxes).

# -------------------------------------------------------------------
# Per-machine config — volume mount point + warning threshold
# -------------------------------------------------------------------
# config/storage.conf is gitignored and written by `storage-setup` (also run by
# ./deploy.sh --only storage). The defaults below reproduce the pre-config
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
# Is the volume actually MOUNTED, not merely a directory?
# -------------------------------------------------------------------
# The failure this guards: cloud volumes are mounted with `nofail`, so a failed
# mount leaves the mountpoint as an empty directory ON THE ROOT DISK, and a
# /workspace symlink still resolves to it. Every "tiered" write would then land
# silently back on root and refill the disk this config exists to protect.
#
# The test compares the filesystem the volume sits on against root's. That is
# stricter than `mountpoint`, which only asks "is this a mount point" and so is
# fooled by a bind mount that still lives on the root disk; it also stays correct
# when STORAGE_VOLUME is a subdirectory of the mount rather than the mount itself.
# df resolves the symlink itself, so no readlink is needed for the test.
_storage_mounted=0
if [ -n "${STORAGE_VOLUME:-}" ] && [ -d "$STORAGE_VOLUME" ]; then
    _storage_mounted=$(df -P "$STORAGE_VOLUME" / 2>/dev/null | awk '
        NR == 2 { vol = $1 }
        NR == 3 { root = $1 }
        END { print (vol != "" && root != "" && vol != root) ? 1 : 0 }')
    : "${_storage_mounted:=0}"
fi

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
if [ "$_storage_mounted" = "1" ]; then
    if [ -z "${HF_HOME:-}" ] && [ ! -L "$HOME/.cache/huggingface" ]; then
        export HF_HOME="$STORAGE_VOLUME/hf"
    fi
    if [ -z "${TORCH_HOME:-}" ] && [ ! -L "$HOME/.cache/torch" ]; then
        export TORCH_HOME="$STORAGE_VOLUME/torch"
    fi
elif [ -n "${STORAGE_VOLUME:-}" ] && [ -d "$STORAGE_VOLUME" ]; then
    # Directory present, nothing mounted on it — the nofail case above. Loud,
    # because anything written there is silently consuming the root disk.
    _storage_real=$(readlink -f "$STORAGE_VOLUME" 2>/dev/null || printf '%s' "$STORAGE_VOLUME")
    printf '\033[1;31mWARNING: %s is NOT mounted (resolves to %s, on the root disk) — caches not forwarded; fix the mount before writing bulky data\033[0m\n' \
        "$STORAGE_VOLUME" "$_storage_real" >&2
    unset _storage_real
fi

# -------------------------------------------------------------------
# Low-root-disk warning — one line per new shell when root is nearly full
# -------------------------------------------------------------------
# Fast (single df, no du); silent when disk is fine, on macOS, or at threshold 0.
if [ "$(uname -s)" = "Linux" ] && [ "$STORAGE_ROOT_WARN_GB" -gt 0 ]; then
    _root_free_kb=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${_root_free_kb:-}" ] && [ "$_root_free_kb" -lt "$((STORAGE_ROOT_WARN_GB * 1048576))" ]; then
        if [ "$_storage_mounted" = "1" ]; then
            _storage_hint="tier bulky data to $STORAGE_VOLUME"
        elif [ -n "${STORAGE_VOLUME:-}" ] && [ -d "$STORAGE_VOLUME" ]; then
            _storage_hint="fix the $STORAGE_VOLUME mount first (see above)"
        else
            _storage_hint="no data volume configured (run storage-setup)"
        fi
        printf '\033[1;31mWARNING: root disk has only %sG free (<%sG) — %s (server-storage-tiering skill)\033[0m\n' \
            "$((_root_free_kb / 1048576))" "$STORAGE_ROOT_WARN_GB" "$_storage_hint" >&2
        unset _storage_hint
    fi
    unset _root_free_kb
fi
unset _storage_mounted
