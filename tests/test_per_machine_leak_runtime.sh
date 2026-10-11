#!/usr/bin/env bash
# Pins how scripts/git-guards/per-machine-leak picks a Python for its TOML check.
#
# tomllib is 3.11+, and a system python3 can be older (Ubuntu 20.04: 3.8). Run
# under one, the check would reject every clean Codex config and block every
# sync. So the launcher runs the checker through `uv run --script` (which
# honours requires-python), else a python3 >= 3.11 on PATH, and fails closed,
# naming the missing runtime, when there is neither.
#
# Each case runs with PATH set to a scratch dir holding only what that case
# allows: bash, a stub python3 that behaves like an old interpreter without
# tomllib, and, where the case says so, uv or a real python3.1x.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/git-guards/per-machine-leak"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/per-machine-leak-runtime.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

BASH_BIN="$(command -v bash)"
UV_BIN="$(command -v uv || true)"
NEW_PY=""
for cand in python3.14 python3.13 python3.12 python3.11 python3; do
    p="$(command -v "$cand" || true)"
    [ -n "$p" ] && "$p" -c 'import sys; sys.exit(sys.version_info < (3, 11))' && { NEW_PY="$p"; break; }
done

CLEAN='model = "gpt-5"
'
TRUST='model = "gpt-5"

[projects."/home/example/p"]
trust_level = "trusted"
'

bindir() {  # $1 = name, then the binaries to expose as NAME=PATH pairs
    local d="$WORK/$1"; shift
    mkdir -p "$d"
    ln -sf "$BASH_BIN" "$d/bash"
    # An old python3: too old for the version probe, and no tomllib if run.
    cat >"$d/python3" <<'STUB'
#!/bin/sh
[ "$1" = "-c" ] && case "$2" in *print*) echo 3.8.10; exit 0 ;; *) exit 1 ;; esac
echo "ModuleNotFoundError: No module named 'tomllib'" >&2
exit 1
STUB
    chmod +x "$d/python3"
    local kv
    for kv in "$@"; do ln -sf "${kv#*=}" "$d/${kv%%=*}"; done
    printf '%s' "$d"
}

run() {  # $1 = PATH, $2 = content; prints "rc<TAB>output"
    local out rc=0
    out="$(printf '%s' "$2" | PATH="$1" "$CHECK" codex/config.toml 2>/dev/null)" || rc=$?
    printf '%s\t%s' "$rc" "$out"
}

# 1. Old python3, uv available: uv runs the checker on a 3.11+ Python.
if [ -n "$UV_BIN" ]; then
    d="$(bindir with-uv "uv=$UV_BIN")"
    r="$(run "$d" "$CLEAN")"; [ "${r%%$'\t'*}" = 0 ] || fail "with uv, a clean config was rejected: $r"
    r="$(run "$d" "$TRUST")"; [ "${r%%$'\t'*}" = 1 ] || fail "with uv, a trust table was not rejected: $r"
    pass "old python3 + uv: clean config passes, trust table is rejected"
else
    echo "skip - no uv on this machine; case 1 not run"
fi

# 2. Old python3, no uv, a python3.1x >= 3.11 on PATH: the fallback is used.
if [ -n "$NEW_PY" ]; then
    d="$(bindir with-new-py "python3.12=$NEW_PY")"
    r="$(run "$d" "$CLEAN")"; [ "${r%%$'\t'*}" = 0 ] || fail "with python >= 3.11, a clean config was rejected: $r"
    r="$(run "$d" "$TRUST")"; [ "${r%%$'\t'*}" = 1 ] || fail "with python >= 3.11, a trust table was not rejected: $r"
    pass "old python3 + python3.12, no uv: the fallback interpreter runs the check"
else
    echo "skip - no python >= 3.11 on this machine; case 2 not run"
fi

# 3. Old python3 and nothing else: fail closed, and say which runtime is missing.
d="$(bindir bare)"
r="$(run "$d" "$CLEAN")"
[ "${r%%$'\t'*}" != 0 ] || fail "with no usable runtime, a clean config passed (fail-open)"
msg="${r#*$'\t'}"
printf '%s' "$msg" | grep -q 'needs uv, or python3 >= 3.11' || fail "message does not name the missing runtime: $msg"
printf '%s' "$msg" | grep -q 'python3 3.8.10' || fail "message does not report the python3 it found: $msg"
printf '%s' "$msg" | grep -q 'failing closed' || fail "message does not say it fails closed: $msg"
pass "old python3 only: fails closed and names the missing runtime"

echo "all per-machine-leak runtime tests passed"
