#!/usr/bin/env zsh
# Pins the ~/.zshenv deployment in deploy.sh. The file matters because it is the
# only startup file a non-interactive ssh shell reads, so mosh's remote
# `mosh-server` lookup depends on it — see docs/mosh-from-phone.md.
#
# The two properties worth pinning are the ones a rewrite through $OP would
# break: the line is appended exactly once however many times deploy runs, and
# content this repo does not own (rustup's cargo env) survives.
set -euo pipefail

REPO_ROOT="${0:A:h:h}"

# Extract the real block from deploy.sh rather than restating it, so the test
# fails when deploy.sh drifts instead of quietly testing a stale copy.
deploy_block="$(sed -n '/^    if cmd_exists zsh && ! grep -q "config\/zshenv.sh"/,/^    fi$/p' "$REPO_ROOT/deploy.sh")"
[[ -n "$deploy_block" ]] || {
    print -u2 "FAIL: could not find the ~/.zshenv deploy block in deploy.sh"
    exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

HOME="$work/home"
mkdir -p "$HOME"
DOT_DIR="$REPO_ROOT"
cmd_exists() { command -v "$1" &>/dev/null; }

run_deploy() { eval "$deploy_block"; }

# --- an existing ~/.zshenv carrying a line this repo does not own -------------
print '. "$HOME/.cargo/env"' > "$HOME/.zshenv"

run_deploy
run_deploy
run_deploy

sourced=$(grep -c "config/zshenv.sh" "$HOME/.zshenv" || true)
[[ "$sourced" == "1" ]] || {
    print -u2 "FAIL: expected exactly 1 zshenv.sh source line after 3 deploys, got $sourced"
    exit 1
}

cargo=$(grep -c 'cargo/env' "$HOME/.zshenv" || true)
[[ "$cargo" == "1" ]] || {
    print -u2 "FAIL: deploy dropped the unmanaged cargo line from ~/.zshenv"
    exit 1
}

# --- a machine with no ~/.zshenv at all ---------------------------------------
rm -f "$HOME/.zshenv"
run_deploy

[[ -f "$HOME/.zshenv" ]] || {
    print -u2 "FAIL: deploy did not create ~/.zshenv when absent"
    exit 1
}
grep -q "config/zshenv.sh" "$HOME/.zshenv" || {
    print -u2 "FAIL: freshly created ~/.zshenv does not source config/zshenv.sh"
    exit 1
}

# --- the sourced file puts Homebrew on a non-interactive PATH -----------------
# The whole point of the file: a non-interactive zsh must resolve mosh-server.
if [[ -d /opt/homebrew/bin ]]; then
    path_out=$(PATH=/usr/bin:/bin zsh -c "source '$REPO_ROOT/config/zshenv.sh'; print \$PATH")
    [[ "$path_out" == *"/opt/homebrew/bin"* ]] || {
        print -u2 "FAIL: config/zshenv.sh did not add /opt/homebrew/bin to PATH"
        exit 1
    }

    # Idempotent when already present, and not prepended twice.
    twice=$(PATH=/usr/bin:/bin zsh -c "source '$REPO_ROOT/config/zshenv.sh'; source '$REPO_ROOT/config/zshenv.sh'; print \$PATH")
    occurrences=${#${(@s./opt/homebrew/bin.)twice}}
    (( occurrences == 2 )) || {
        print -u2 "FAIL: config/zshenv.sh is not idempotent; /opt/homebrew/bin appears more than once"
        exit 1
    }
fi

print "PASS: ~/.zshenv deploy is append-once and preserves unmanaged lines"
