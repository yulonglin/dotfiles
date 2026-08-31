# aliases/storage.sh — volume tiering: forward bulky caches to /workspace + low-root-disk warning
# shellcheck shell=bash
#
# Companion to the server-storage-tiering skill (claude/skills/server-storage-tiering).
# Silent no-op on machines without /workspace (laptop, volume-less boxes).

# -------------------------------------------------------------------
# Forward env vars — future bulky downloads land on the volume
# -------------------------------------------------------------------
# Only when the default cache path is NOT already a symlink onto the volume:
# a relocated cache (~/.cache/huggingface -> /workspace/...) already redirects
# transparently, and pointing HF_HOME elsewhere would orphan it and trigger
# mass re-downloads. Respect pre-existing exports.
#
# HUGGINGFACE_HUB_CACHE derives as $HF_HOME/hub — no need to set it.
# Deliberately NOT set: UV_CACHE_DIR / PIP_CACHE_DIR (latency-sensitive,
# may host live venvs — keep on local NVMe).
if [ -d /workspace ]; then
    if [ -z "${HF_HOME:-}" ] && [ ! -L "$HOME/.cache/huggingface" ]; then
        export HF_HOME=/workspace/hf
    fi
    if [ -z "${TORCH_HOME:-}" ] && [ ! -L "$HOME/.cache/torch" ]; then
        export TORCH_HOME=/workspace/torch
    fi
fi

# -------------------------------------------------------------------
# Low-root-disk warning — one line per new shell when root is nearly full
# -------------------------------------------------------------------
# Fast (single df, no du); silent when disk is fine or on macOS.
if [ "$(uname -s)" = "Linux" ]; then
    _root_free_kb=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "${_root_free_kb:-}" ] && [ "$_root_free_kb" -lt 20971520 ]; then
        printf '\033[1;31mWARNING: root disk has only %sG free (<20G) — tier bulky data to /workspace (server-storage-tiering skill)\033[0m\n' \
            "$((_root_free_kb / 1048576))" >&2
    fi
    unset _root_free_kb
fi
