#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Migrate Node to NodeSource apt + Retire mise
# ═══════════════════════════════════════════════════════════════════════════════
# One-shot sudo runbook for the mise → Homebrew/Linuxbrew migration. Ordering is
# the point: apt node must reach v24 BEFORE mise's node is removed, and every
# migrated CLI tool must exist under Linuxbrew BEFORE mise is archived.
#
# Idempotent: safe to re-run after partial completion. Archives, never deletes —
# the only removals are dangling /usr/local/bin symlinks whose superseding copy
# in ~/.bun/bin was confirmed first.
# Does NOT run deploy.sh and does NOT edit any dotfile — run deploy.sh yourself
# afterwards and open a fresh shell.
#
# Usage:
#   scripts/cleanup/migrate-node-and-retire-mise.sh            # run for real
#   scripts/cleanup/migrate-node-and-retire-mise.sh --dry-run  # print mutations
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

DRY_RUN=false
BREW_BIN_DIR="/home/linuxbrew/.linuxbrew/bin"
ARCHIVE_DIR="$HOME/archive"
MIGRATION_DATE="$(date +%F)"

# binary-name → brew-formula pairs for the migrated CLI tools (step 6)
MIGRATED_TOOLS=(
    "rg:ripgrep"
    "fd:fd"
    "eza:eza"
    "bat:bat"
    "fzf:fzf"
    "delta:git-delta"
    "dust:dust"
    "zoxide:zoxide"
    "jless:jless"
    "just:just"
    "sd:sd"
    "duf:duf"
    "gum:gum"
    "vivid:vivid"
    "hyperfine:hyperfine"
    "gitui:gitui"
    "code2prompt:code2prompt"
)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--dry-run]"
            echo ""
            echo "Migrates node from mise to NodeSource apt, removes stale root-owned"
            echo "npm globals, verifies every brew-migrated CLI tool, then archives mise."
            echo ""
            echo "Options:"
            echo "  --dry-run    Print every mutating command instead of running it"
            echo "  -h, --help   Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

step() { echo ""; echo "═══ $* ═══"; }
info() { echo "  $*"; }
die()  { echo "" >&2; echo "ABORT: $*" >&2; exit 1; }

# In dry-run a gate that would abort must not stop the walkthrough — later
# steps depend on mutations that were only printed. Warn and continue instead.
gate_fail() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  GATE WOULD FAIL (continuing under --dry-run): $*" >&2
    else
        die "$@"
    fi
}

# Every mutating command goes through run(); dry-run prints it instead.
run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] $*"
    else
        info "\$ $*"
        "$@"
    fi
}

# Archive src → $ARCHIVE_DIR/dest-name, tolerating already-moved (src gone)
# and a dest that already exists from a previous partial run.
archive_move() {
    local src="$1" dest_name="$2" dest
    dest="$ARCHIVE_DIR/$dest_name"
    if [[ ! -e "$src" && ! -L "$src" ]]; then
        info "already gone, skipping: $src"
        return 0
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
        dest="$dest-$(date +%s)"
        info "archive destination existed; using $dest"
    fi
    run mkdir -p "$ARCHIVE_DIR"
    run mv "$src" "$dest"
}

# ─── Step 1: Preflight ────────────────────────────────────────────────────────

step "Step 1: Preflight"

if grep -rqs 'deb\.nodesource\.com/node_24' /etc/apt/sources.list.d/; then
    info "OK: NodeSource node_24.x apt repo is configured in /etc/apt/sources.list.d/"
else
    die "NodeSource node_24.x apt repo not found in /etc/apt/sources.list.d/ — configure it first (https://deb.nodesource.com), then re-run."
fi

if [[ -x "$BREW_BIN_DIR/brew" ]]; then
    info "OK: Linuxbrew present at $BREW_BIN_DIR/brew"
else
    die "Linuxbrew not found at $BREW_BIN_DIR/brew — install it first, then re-run."
fi

if [[ -x "$HOME/.bun/bin/socket" ]]; then
    info "OK: socket resolves from ~/.bun/bin (bun-global copy)"
else
    die "socket not found at ~/.bun/bin/socket — migrate it to bun's global store first (bun add -g @socketsecurity/cli), because later steps remove its old home (~/.npm-global)."
fi

# ─── Step 2: Swap Ubuntu npm/node for NodeSource 24.x ────────────────────────

step "Step 2: Replace Ubuntu npm/nodejs with NodeSource 24.x"

# `apt-get -y` here cascade-removes a large web of distro node-* packages
# (eslint, webpack, terser, node-gyp, libnode-dev, ...). Printing the command
# string hides that, so --dry-run runs the unprivileged read-only simulations
# instead — `apt-get -s` needs no root and mutates nothing.
simulate_apt() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] simulating: apt-get -s $*"
        apt-get -s "$@" 2>&1 | sed 's/^/      /' || echo "      (simulation failed — apt-get -s $* returned non-zero)"
    fi
}

# dpkg -s matches only the real Ubuntu npm deb, never a virtual Provides: npm
# from NodeSource's nodejs — so a re-run cannot rip out the migrated node.
if dpkg -s npm &>/dev/null; then
    info "Ubuntu npm deb is installed — removing it (anchors old nodejs 18)"
    simulate_apt remove npm
    run sudo apt-get remove -y npm
else
    info "Ubuntu npm deb already removed, skipping"
fi

# Non-fatal: apt-get update exits non-zero if ANY configured repo fails (docker,
# chrome, tailscale, ... all live in sources.list.d here). Under `set -e` that
# would abort with npm already removed and nodejs still at 18. The NodeSource
# candidate is normally already in the cached index, and step 3's v24 gate is
# the real enforcement, so a stale index is a warning, not a stop.
run sudo apt-get update || info "WARNING: apt-get update failed (a third-party repo is likely broken) — continuing on the cached index; step 3 will catch a failed upgrade."
simulate_apt install nodejs
run sudo apt-get install -y nodejs
run sudo apt-get autoremove -y

# ─── Step 3: GATE — /usr/bin/node must be v24 ─────────────────────────────────

step "Step 3: GATE — /usr/bin/node reports v24.x"

if [[ -x /usr/bin/node ]]; then
    apt_node_version="$(/usr/bin/node --version 2>/dev/null || echo "unreadable")"
    info "/usr/bin/node --version → $apt_node_version"
    if [[ "$apt_node_version" == v24.* ]]; then
        info "OK: apt node is v24"
    else
        gate_fail "/usr/bin/node reports $apt_node_version, not v24.x — do not proceed to mise removal. Check step 2 output."
    fi
else
    gate_fail "/usr/bin/node does not exist — NodeSource install did not land."
fi

# ─── Step 4: Remove node from mise ────────────────────────────────────────────

step "Step 4: Remove node from mise (tolerating mise already gone)"

if command -v mise &>/dev/null; then
    run bash -c "mise unuse -g node 2>/dev/null || true"
    run bash -c "mise uninstall node 2>/dev/null || true"
else
    info "mise not on PATH, skipping unuse/uninstall"
fi

info "GATE: node must still resolve, via /usr/bin/node, at v24"
hash -r
node_path="$(command -v node || true)"
if [[ -z "$node_path" ]]; then
    gate_fail "'command -v node' resolves nothing — node is gone from PATH."
else
    node_version="$("$node_path" --version 2>/dev/null || echo "unreadable")"
    info "node → $node_path ($node_version)"
    if [[ "$node_path" != "/usr/bin/node" ]]; then
        # Naming the remedy matters: step 7 (which archives ~/.local/share/mise
        # and would clear a surviving shim) is DOWNSTREAM of this gate, so
        # without a way out every re-run dies on this same line.
        gate_fail "node resolves to $node_path, not /usr/bin/node — a mise shim or another PATH entry is still ahead of /usr/bin.
    Remedy: remove the offending entry, then re-run. Usually that is a mise shim —
      rm -f ~/.local/share/mise/shims/node ~/.local/share/mise/shims/npm ~/.local/share/mise/shims/npx
    or archive the whole shims dir:
      mkdir -p $ARCHIVE_DIR && mv ~/.local/share/mise/shims $ARCHIVE_DIR/mise-shims-$MIGRATION_DATE
    If $node_path is something else entirely, remove or rename it by hand.
    /usr/bin/node itself already passed the v24 gate in step 3, so the apt side is fine."
    elif [[ "$node_version" != v24.* ]]; then
        gate_fail "node reports $node_version, not v24.x."
    else
        info "OK: node resolves to /usr/bin/node at v24"
    fi
fi

# ─── Step 5: Remove stale root-owned npm globals ──────────────────────────────

step "Step 5: Remove stale root-owned /usr/local npm globals (verified first)"

# Expected stale versions: codex 0.88.0, gemini 0.25.0. The /usr/local/bin
# symlinks may be dangling, so read versions from package.json, not --version.
print_pkg_version() {
    local pkg_json="$1"
    if [[ -f "$pkg_json" ]]; then
        grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg_json" | head -1 || echo "(version not found in $pkg_json)"
    else
        echo "(no package.json at $pkg_json)"
    fi
}

remove_stale_symlink() {
    local link="$1" tool="$2"
    if [[ ! -L "$link" && ! -e "$link" ]]; then
        info "already gone, skipping: $link"
        return 0
    fi
    local target
    target="$(readlink -f "$link" 2>/dev/null || readlink "$link" 2>/dev/null || echo "")"
    info "$link → ${target:-"(unreadable)"}"
    if [[ "$(readlink "$link" 2>/dev/null || echo "")" != *"/usr/local/lib/node_modules/"* && "$target" != /usr/local/lib/node_modules/* ]]; then
        echo "  WARNING: $link does not point into /usr/local/lib/node_modules — skipping removal, inspect manually." >&2
        return 0
    fi
    if [[ ! -x "$HOME/.bun/bin/$tool" ]]; then
        echo "  WARNING: no working copy at ~/.bun/bin/$tool — skipping removal of $link." >&2
        return 0
    fi
    # Do not invoke a third-party binary under --dry-run: a first run can write
    # config or block on a TTY prompt, and a dry-run must not do either.
    if [[ "$DRY_RUN" == "true" ]]; then
        info "working copy: ~/.bun/bin/$tool (present and executable; version not queried under --dry-run)"
    else
        info "working copy: ~/.bun/bin/$tool ($("$HOME/.bun/bin/$tool" --version 2>/dev/null | head -1 || echo "version unreadable"))"
    fi
    run sudo rm -f "$link"
}

# Archive the whole tree rather than rm -rf it. The per-tool guards above are
# advisory (they warn and return 0), so a delete here would destroy the last
# copy of a package whose supersession was NOT confirmed — and the tree holds
# more than the two packages enumerated below. Archiving keeps this step inside
# the file header's archive-never-delete contract.
archive_usr_local_node_modules() {
    local src=/usr/local/lib/node_modules dest
    dest="$ARCHIVE_DIR/usr-local-node_modules-$MIGRATION_DATE"
    if [[ -e "$dest" || -L "$dest" ]]; then
        dest="$dest-$(date +%s)"
        info "archive destination existed; using $dest"
    fi
    info "packages in $src:"
    find "$src" -mindepth 1 -maxdepth 1 -printf '      %f\n' 2>/dev/null || info "      (unreadable)"
    run mkdir -p "$ARCHIVE_DIR"
    # sudo: the tree is root-owned, so archive_move's plain mv cannot take it.
    run sudo mv "$src" "$dest"
}

if [[ -d /usr/local/lib/node_modules ]]; then
    info "stale codex version: $(print_pkg_version /usr/local/lib/node_modules/@openai/codex/package.json)"
    info "stale gemini version: $(print_pkg_version /usr/local/lib/node_modules/@google/gemini-cli/package.json)"
    remove_stale_symlink /usr/local/bin/codex codex
    remove_stale_symlink /usr/local/bin/gemini gemini
    archive_usr_local_node_modules
else
    info "/usr/local/lib/node_modules already gone, skipping"
    remove_stale_symlink /usr/local/bin/codex codex
    remove_stale_symlink /usr/local/bin/gemini gemini
fi

# ─── Step 6: GATE — every migrated tool exists under Linuxbrew ────────────────

step "Step 6: GATE — all migrated CLI tools present in $BREW_BIN_DIR"

missing_formulas=()
for pair in "${MIGRATED_TOOLS[@]}"; do
    tool="${pair%%:*}"
    formula="${pair##*:}"
    if [[ -x "$BREW_BIN_DIR/$tool" ]]; then
        info "OK: $tool"
    else
        echo "  MISSING: $tool (formula: $formula)" >&2
        missing_formulas+=("$formula")
    fi
done

if [[ ${#missing_formulas[@]} -gt 0 ]]; then
    gate_fail "${#missing_formulas[@]} tool(s) missing from $BREW_BIN_DIR — mise stays in place. Fix with: brew install ${missing_formulas[*]}"
else
    info "All ${#MIGRATED_TOOLS[@]} migrated tools present — safe to retire mise"
fi

# ─── Step 7: Retire mise (archive, never delete) ──────────────────────────────

step "Step 7: Retire mise — archive to $ARCHIVE_DIR (never delete)"

archive_move "$HOME/.local/share/mise" "mise-data-$MIGRATION_DATE"
archive_move "$HOME/.config/mise"      "mise-config-$MIGRATION_DATE"
archive_move "$HOME/.local/bin/mise"   "mise-bin-$MIGRATION_DATE"

# ─── Step 8: Cleanup stragglers ───────────────────────────────────────────────

step "Step 8: Archive stragglers (zerobrew remnants, ~/.npm-global)"

archive_move "$HOME/.local/bin/zb"           "zb-$MIGRATION_DATE"
archive_move "$HOME/.local/bin/zbx"          "zbx-$MIGRATION_DATE"
archive_move "$HOME/.local/share/zerobrew"   "zerobrew-$MIGRATION_DATE"

# ~/.npm-global/bin outranks ~/.bun/bin on PATH, so anything resolving from
# there stops resolving once the dir moves. The preflight only checked socket;
# enumerate the rest rather than trusting that socket was the only occupant.
if [[ -d "$HOME/.npm-global/bin" ]]; then
    unmatched=()
    for _entry in "$HOME/.npm-global/bin"/*; do
        [[ -e "$_entry" || -L "$_entry" ]] || continue
        _name="$(basename "$_entry")"
        if [[ -x "$HOME/.bun/bin/$_name" ]]; then
            info "OK: $_name has a bun-global counterpart"
        else
            echo "  WARNING: ~/.npm-global/bin/$_name has no counterpart at ~/.bun/bin/$_name" >&2
            unmatched+=("$_name")
        fi
    done
    unset _entry _name
    if [[ ${#unmatched[@]} -gt 0 ]]; then
        gate_fail "${#unmatched[@]} npm-global binary/ies are not superseded in bun's global store: ${unmatched[*]}
    Archiving ~/.npm-global would take them off PATH. Migrate each first (bun add -g <package>), then re-run.
    Everything above this point in step 8 is idempotent, so a re-run is safe."
    else
        info "All ~/.npm-global/bin entries are superseded by ~/.bun/bin — safe to archive"
    fi
fi

archive_move "$HOME/.npm-global"             "npm-global-$MIGRATION_DATE"

# ─── Step 9: Final report ─────────────────────────────────────────────────────

step "Step 9: Final report"

hash -r
info "node --version: $(node --version 2>/dev/null || echo "NOT FOUND")"
info "which -a node:"
which -a node 2>/dev/null | sed 's/^/    /' || info "    (none)"
info "which -a npm:"
which -a npm 2>/dev/null | sed 's/^/    /' || info "    (none)"
info "brew --version: $("$BREW_BIN_DIR/brew" --version 2>/dev/null | head -1 || echo "NOT FOUND")"

# Step 6 verified the migrated tools by absolute path, which is the right gate —
# but $BREW_BIN_DIR is not on the PATH of a shell that predates the new zshrc.
# Step 7 has just taken mise's installs dirs away, so this shell can be left
# with none of the 17. Say so rather than letting the operator discover it.
unresolved=()
for _probe in rg gum; do
    command -v "$_probe" &>/dev/null || unresolved+=("$_probe")
done
unset _probe
if [[ ${#unresolved[@]} -gt 0 ]]; then
    info "PATH check: ${unresolved[*]} do(es) not resolve in THIS shell — expected."
    info "  The migrated tools live in $BREW_BIN_DIR, which this shell's PATH predates."
    info "  They come back after the two steps below; nothing is missing on disk."
else
    info "PATH check: rg and gum resolve in this shell"
fi

echo ""
echo "Done. Now do these two things yourself (this script will not):"
echo "  1. Run deploy.sh — rolls out the new zshrc without mise activation."
echo "  2. Open a fresh shell so the new PATH takes effect."
