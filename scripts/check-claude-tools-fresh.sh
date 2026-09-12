#!/usr/bin/env bash
# Flag committed claude-tools binaries that are older than the Rust source.
#
# Why this exists: custom_bins/claude-tools-<platform> binaries are committed,
# and the statusline runs the binary, not the source. An agent (or a human)
# editing tools/claude-tools/src/ can only rebuild the platform it is sitting
# on — nobody on Linux can cross-compile darwin-arm64 — so the usual failure is
# silent: the Mac keeps rendering the old statusline and nothing errors.
# Comments in the source cannot catch that; a date comparison can.
#
# Advisory by default (always exits 0) so it is safe to call from a hook.
# --strict exits 1 when something is stale, for use in tests or CI.
#
# Usage: check-claude-tools-fresh.sh [--strict] [--quiet]

set -euo pipefail

STRICT=false
QUIET=false
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=true ;;
        --quiet)  QUIET=true ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown option: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    $QUIET || echo "not in a git repository" >&2
    exit 0
}

SRC_DIR="$REPO_ROOT/tools/claude-tools"
[[ -d "$SRC_DIR" ]] || exit 0  # not the dotfiles repo

# Last commit that touched the crate (source or manifest).
src_commit_time=$(git -C "$REPO_ROOT" log -1 --format=%ct -- \
    tools/claude-tools/src tools/claude-tools/Cargo.toml 2>/dev/null || echo 0)
[[ -n "$src_commit_time" ]] || src_commit_time=0

stale=()
while IFS= read -r binary; do
    [[ -n "$binary" ]] || continue
    bin_commit_time=$(git -C "$REPO_ROOT" log -1 --format=%ct -- "$binary" 2>/dev/null || echo 0)
    [[ -n "$bin_commit_time" ]] || bin_commit_time=0
    if (( src_commit_time > bin_commit_time )); then
        stale+=("$(basename "$binary")")
    fi
done < <(git -C "$REPO_ROOT" ls-files 'custom_bins/claude-tools-*')

# custom_bins/claude-tools must stay the platform dispatch WRAPPER — a shell
# script that execs the arch-suffixed asset. It is the path the statusline
# actually invokes, so when a rebuild is copied here instead of to
# claude-tools-<platform>, one architecture's binary becomes the runtime for
# every machine and silently freezes at whatever the source said that day.
# That has happened twice (e7c2de0 fixed it, eabeba2 reintroduced it), and
# neither the date comparison above nor SHA256SUMS catches it — the file is
# not tracked as an asset and it still exits 0. Two bytes do catch it.
WRAPPER="$REPO_ROOT/custom_bins/claude-tools"
clobbered=false
wrapper_problem=""
if [[ ! -f "$WRAPPER" ]]; then
    # Absent is not "fine". An earlier version only tested the first two bytes of
    # an existing file, so a deleted or chmod-ed dispatcher left clobbered=false
    # and --strict could report everything up to date while `claude-tools` could
    # not run at all.
    clobbered=true
    wrapper_problem="missing"
elif [[ ! -x "$WRAPPER" ]]; then
    clobbered=true
    wrapper_problem="not executable"
elif [[ "$(head -c2 "$WRAPPER" 2>/dev/null)" != '#!' ]]; then
    clobbered=true
    wrapper_problem="a raw binary, not the dispatch wrapper"
fi

# SHA256SUMS records the committed binaries; this check is now its only
# consumer (the installers' download-and-verify bootstrap was removed on
# 2026-09-04). A rebuilt-but-unrecorded asset is a binary nobody signed off on.
# Portable hashing: macOS ships `shasum`, not `sha256sum`. Without this, every
# asset hashes to the empty string on a Mac and the check cries wolf about all of
# them — a guard nobody trusts is a guard nobody reads.
# This stays standalone (no helpers.sh, which is zsh and exits unless config.sh
# was sourced first) so it is safe to call from a hook.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    else
        return 1
    fi
}

SUMS="$SRC_DIR/SHA256SUMS"
badsums=()
no_hasher=false
if [[ -f "$SUMS" ]]; then
    if ! sha256_of "$SUMS" >/dev/null; then
        # Report the absence rather than reporting every asset as mismatched.
        no_hasher=true
    else
        while read -r want name; do
            [[ -n "$name" ]] || continue
            got=$(sha256_of "$REPO_ROOT/custom_bins/$name" || true)
            [[ "$got" == "$want" ]] || badsums+=("$name")
        done < "$SUMS"
    fi
fi

# Uncommitted source edits are a softer signal: nothing is stale *yet*, but
# every binary will be the moment the edit is committed.
dirty_src=$(git -C "$REPO_ROOT" status --porcelain -- tools/claude-tools/src 2>/dev/null)

if [[ ${#stale[@]} -eq 0 && -z "$dirty_src" ]] \
    && [[ "$clobbered" == "false" && ${#badsums[@]} -eq 0 && "$no_hasher" == "false" ]]; then
    $QUIET || echo "claude-tools binaries are up to date with the source"
    exit 0
fi

if [[ "$no_hasher" == "true" ]]; then
    echo "⚠ neither sha256sum nor shasum is available — SHA256SUMS was NOT verified."
fi

if [[ "$clobbered" == "true" ]]; then
    echo "🔴 custom_bins/claude-tools is $wrapper_problem — it must be the dispatch wrapper."
    echo "  The statusline runs this path on every platform. Restore the wrapper:"
    echo "    git show e7c2de0:custom_bins/claude-tools > custom_bins/claude-tools && chmod +x custom_bins/claude-tools"
    echo "  Rebuilds belong in custom_bins/claude-tools-<platform>, never here."
fi

if [[ ${#badsums[@]} -gt 0 ]]; then
    echo "⚠ SHA256SUMS does not match the committed binaries: ${badsums[*]}"
    echo "  Refresh it:  (cd custom_bins && sha256sum claude-tools-* > ../tools/claude-tools/SHA256SUMS)"
fi

if [[ -n "$dirty_src" ]]; then
    echo "⚠ tools/claude-tools/src has uncommitted changes — every committed binary will be stale once you commit."
fi

if [[ ${#stale[@]} -gt 0 ]]; then
    echo "⚠ claude-tools binaries older than the Rust source: ${stale[*]}"
    echo "  Rebuild on each platform (they cannot be cross-compiled here):"
    echo "    cargo build --release --manifest-path tools/claude-tools/Cargo.toml"
    echo "    cp tools/claude-tools/target/release/claude-tools custom_bins/claude-tools-<platform>"
fi

$STRICT && exit 1
exit 0
