#!/usr/bin/env bash
# Pins the two uv supply-chain guards in install.sh / helpers.sh:
#
# 1. UV_EXCLUDE_NEWER defaults to P7D before any `uv tool install` runs, so a
#    fresh bootstrap (which never sources config/aliases/misc.sh) still gets
#    the 7-day release quarantine. UV_MALWARE_CHECK does NOT cover
#    `uv tool install`, so this default is the only guard on that path.
# 2. is_installed_global ignores executables inside an active Python
#    virtualenv, so a venv-local ruff/ty cannot suppress the persistent
#    `uv tool install`. Also pins the zsh regression where a `local path`
#    variable clobbered $PATH inside the helper.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

# ── 1a. The quarantine default exists and preserves an explicit value ────────
grep -qE 'export UV_EXCLUDE_NEWER="\$\{UV_EXCLUDE_NEWER:-P7D\}"' "$INSTALL_SH" \
    || fail "install.sh lacks the UV_EXCLUDE_NEWER P7D default"

# ── 1b. …and appears before the first uv tool install ────────────────────────
default_line=$(grep -nE 'export UV_EXCLUDE_NEWER=' "$INSTALL_SH" | head -1 | cut -d: -f1)
first_install_line=$(grep -nE '^[[:space:]]*uv tool install' "$INSTALL_SH" | head -1 | cut -d: -f1)
[[ -n "$default_line" && -n "$first_install_line" && "$default_line" -lt "$first_install_line" ]] \
    || fail "UV_EXCLUDE_NEWER default (line $default_line) does not precede first uv tool install (line $first_install_line)"

# ── 1c. The default resolves correctly in both directions ────────────────────
# shellcheck disable=SC2016  # literal on purpose: expansion happens in the child zsh
got=$(env -u UV_EXCLUDE_NEWER zsh -c 'export UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER:-P7D}"; echo "$UV_EXCLUDE_NEWER"')
[[ "$got" == "P7D" ]] || fail "clean env: expected P7D, got '$got'"
# shellcheck disable=SC2016  # literal on purpose: expansion happens in the child zsh
got=$(env UV_EXCLUDE_NEWER=2026-01-01T00:00:00Z zsh -c 'export UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER:-P7D}"; echo "$UV_EXCLUDE_NEWER"')
[[ "$got" == "2026-01-01T00:00:00Z" ]] || fail "explicit value not preserved, got '$got'"

# ── 2. is_installed_global: venv-local binary ignored, global one counted ────
# Run under zsh because install.sh is zsh — this is what caught the tied-$path
# regression that bash would not reproduce.
# Repo-local tmp first: the Claude Code sandbox mounts $TMPDIR read-only.
mkdir -p "$REPO_ROOT/tmp"
workdir=$(mktemp -d "$REPO_ROOT/tmp/uv-guards.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/venv/bin" "$workdir/global/bin"
for d in venv global; do
    printf '#!/bin/sh\necho faketool 1.0\n' > "$workdir/$d/bin/faketool"
    chmod +x "$workdir/$d/bin/faketool"
done

run_guard() { # $1=env var name ("" for none), $2=env root, $3=PATH prefix
    ENV_NAME="$1" ENV_ROOT="$2" PATH_PREFIX="$3" zsh -c '
        export DOT_DIR="'"$REPO_ROOT"'"
        source "$DOT_DIR/config.sh"
        source "$DOT_DIR/scripts/shared/helpers.sh"
        [[ -n "$ENV_NAME" ]] && export "$ENV_NAME"="$ENV_ROOT"
        export PATH="$PATH_PREFIX:$PATH"
        if is_installed_global faketool >/dev/null 2>&1; then echo counted; else echo ignored; fi
    '
}

got=$(run_guard VIRTUAL_ENV "$workdir/venv" "$workdir/venv/bin")
[[ "$got" == "ignored" ]] || fail "venv-local faketool was counted as installed"
got=$(run_guard CONDA_PREFIX "$workdir/venv" "$workdir/venv/bin")
[[ "$got" == "ignored" ]] || fail "conda-local faketool was counted as installed"
got=$(run_guard "" "" "$workdir/global/bin")
[[ "$got" == "counted" ]] || fail "global faketool was not counted (tied-\$path regression?)"

echo "PASS: all uv guard assertions hold"
