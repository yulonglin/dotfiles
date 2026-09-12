#!/usr/bin/env bash
# shellcheck shell=bash
# End-to-end install.sh + deploy.sh on a clean Ubuntu, in a disposable container.
#
#   bash tests/test_installers_container.sh            # full run (~10 min cold)
#   bash tests/test_installers_container.sh --quick    # contract legs only (~1 min)
#   bash tests/test_installers_container.sh --keep     # leave the image behind
#   bash tests/test_installers_container.sh --mutate   # the suite must go RED
#
# Opt-in when the output is captured (tests/run-all.sh, CI, an agent):
#   DOTFILES_CONTAINER_TESTS=1 bash tests/test_installers_container.sh
#
# Why a container and not the runner's own filesystem: install.sh installs
# packages, rewrites the shell, and creates a user. `no-stall.yml`'s unattended
# job runs the installers on the GitHub runner itself and can only ask "did it
# finish in time"; this asks "did it resolve and deploy the right components",
# which needs a machine you are allowed to break.
#
# The container CANNOT cover: macOS (every platform branch is a different code
# path), the component menu drawing and being keyed (that needs a pty nobody
# types at — the harness in PR #134), and anything needing real credentials, a
# GUI, or an App Store session. Those stay a manual pass. See the PR body.
set -uo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=dotfiles-installer-contract
declare -a RUN_ARGS=()
KEEP=false
MUTATE=false
for arg in "$@"; do
    case "$arg" in
        --quick) RUN_ARGS+=(--quick) ;;
        --keep)  KEEP=true ;;
        --mutate) MUTATE=true; RUN_ARGS+=(--quick) ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# tests/run-all.sh discovers every tests/test_*.sh and caps each at 600 s. A
# full run here is about nine minutes of live apt, nodejs.org, GitHub Releases
# and Homebrew, so inside the runner it would be a coin flip between a slow
# pass and a timeout reported as a failure. It is therefore opt-in: a human at
# a terminal gets the real run, anything capturing the output gets a skip
# unless DOTFILES_CONTAINER_TESTS=1 asks for it by name.
if [[ "${DOTFILES_CONTAINER_TESTS:-0}" != "1" && ! -t 1 ]]; then
    echo "SKIP: the container suite is opt-in — set DOTFILES_CONTAINER_TESTS=1."
    echo "      It needs a container runtime, the live network, and about nine minutes."
    exit 77
fi

# Exit 77 is the runner's skip code: no container runtime is an absent
# environment, not a failed contract, and reporting it as a failure is how a
# suite gets ignored.
RUNTIME=""
for candidate in docker podman; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" info >/dev/null 2>&1; then
        RUNTIME="$candidate"; break
    fi
done
if [[ -z "$RUNTIME" ]]; then
    echo "SKIP: no usable container runtime (tried docker, podman)." >&2
    echo "      Install one, or run the manual checklist in the PR body instead." >&2
    exit 77
fi

CTX="$(mktemp -d)"
# shellcheck disable=SC2317  # invoked by trap
cleanup() {
    rm -rf "$CTX"
    [[ "$KEEP" == "true" ]] || "$RUNTIME" image rm -f "$IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The COMMITTED tree, never the working copy: a green run against uncommitted
# edits is a green run nobody else can reproduce.
if ! git -C "$DOT_DIR" diff --quiet HEAD -- install.sh deploy.sh config.sh scripts/shared/helpers.sh; then
    echo "WARNING: install.sh/deploy.sh/config.sh/helpers.sh have uncommitted changes." >&2
    echo "         This suite builds from 'git archive HEAD' and will not see them." >&2
fi
git -C "$DOT_DIR" archive --format=tar HEAD -o "$CTX/repo.tar" || exit 1
cp "$DOT_DIR/tests/container/Dockerfile" "$CTX/Dockerfile"

# A suite that cannot fail proves nothing. --mutate removes the empty-set guard
# in the image only — the checkout is never touched — and requires the contract
# legs to notice. It is the same shape as no-stall.yml's canary mutation step.
if [[ "$MUTATE" == "true" ]]; then
    mkdir -p "$CTX/src"
    tar -xf "$CTX/repo.tar" -C "$CTX/src"
    sed -i 's|^guard_nonempty_components() {|guard_nonempty_components() { return 0|' \
        "$CTX/src/scripts/shared/helpers.sh"
    grep -q 'guard_nonempty_components() { return 0' "$CTX/src/scripts/shared/helpers.sh" || {
        echo "mutation did not apply — the guard has been renamed" >&2; exit 1; }
    ( cd "$CTX/src" && tar -cf ../repo.tar . ) || exit 1
    rm -rf "$CTX/src"
    echo "MUTATION: guard_nonempty_components neutered in the image."
fi

echo "Building $IMAGE with $RUNTIME (context $(du -h "$CTX/repo.tar" | cut -f1))..."
"$RUNTIME" build --quiet -t "$IMAGE" "$CTX" || { echo "image build failed" >&2; exit 1; }

echo ""
# --network is left at the default: install.sh fetches packages, and a run with
# no network would pass by skipping everything it could not reach.
"$RUNTIME" run --rm --init "$IMAGE" "${RUN_ARGS[@]}"
rc=$?
echo ""
if [[ "$MUTATE" == "true" ]]; then
    if [[ $rc -eq 0 ]]; then
        echo "Container contract: VACUOUS — the suite passed against a removed guard."
        exit 1
    fi
    echo "Container contract: mutation correctly caught (suite exited $rc)."
    exit 0
fi
if [[ $rc -eq 0 ]]; then
    echo "Container contract: PASS ($RUNTIME, ubuntu:24.04)"
else
    echo "Container contract: FAIL (exit $rc)"
fi
exit $rc
