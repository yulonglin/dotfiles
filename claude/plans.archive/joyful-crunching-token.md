# Plan: Cache Sync Script Between Machines

## Goal
Create a script to sync API response caches between machines using rsync over SSH, with progress tracking and ETA.

## Cache Locations to Sync

| Cache | Location | Size | Purpose |
|-------|----------|------|---------|
| Inspect AI API | `~/.cache/inspect_ai/` | 1.8GB | LLM API responses |
| Inspect Evals | `~/.cache/inspect_evals/` | 5.3GB | Evaluation datasets |
| Paraphrases | `{repo}/.cache/paraphrases/` | 10MB | Paraphrased prompts |
| Prompt Selection | `{repo}/data/prompt_selection/` | varies | Measurement cache |

## Script Design

**Location**: `scripts/sync_cache.sh`

**Usage**:
```bash
# Sync to remote machine (push)
./scripts/sync_cache.sh push mats /path/to/repo/on/remote

# Sync from remote machine (pull)
./scripts/sync_cache.sh pull mats /path/to/repo/on/remote

# Dry run (show what would sync)
./scripts/sync_cache.sh push mats /path/to/repo/on/remote --dry-run
```

**Arguments**:
1. `direction`: `push` (local→remote) or `pull` (remote→local)
2. `host`: SSH host name from `~/.ssh/config` (e.g., `mats`, `hetzner-8`)
3. `remote_repo`: Path to repo on remote machine
4. `--dry-run`: Optional flag to preview without syncing

## Implementation

```bash
#!/usr/bin/env bash
# scripts/sync_cache.sh - Sync API caches between machines

set -euo pipefail

DIRECTION="${1:-}"
HOST="${2:-}"
REMOTE_REPO="${3:-}"
DRY_RUN=""

# Parse flags
shift 3 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN="--dry-run" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Validate
if [[ -z "$DIRECTION" || -z "$HOST" || -z "$REMOTE_REPO" ]]; then
    echo "Usage: $0 <push|pull> <ssh-host> <remote-repo-path> [--dry-run]"
    echo ""
    echo "Examples:"
    echo "  $0 push mats /home/user/sandbagging-detection"
    echo "  $0 pull hetzner-8 /root/sandbagging-detection --dry-run"
    exit 1
fi

LOCAL_REPO="$(cd "$(dirname "$0")/.." && pwd)"

# rsync options:
#   -a: archive mode (preserves permissions, times, etc.)
#   -v: verbose
#   -z: compress during transfer
#   --info=progress2: show overall progress with ETA
#   --ignore-existing: never overwrite (additive merge)
#   --human-readable: human-readable sizes
RSYNC_OPTS="-avz --info=progress2 --ignore-existing --human-readable $DRY_RUN"

# Calculate and display cache sizes
echo "=== Cache Sizes ==="
get_local_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "N/A"
}

get_remote_size() {
    ssh "$HOST" "du -sh '$1' 2>/dev/null | cut -f1" || echo "N/A"
}

echo "Local:"
echo "  Inspect AI API:    $(get_local_size "$HOME/.cache/inspect_ai")"
echo "  Inspect Evals:     $(get_local_size "$HOME/.cache/inspect_evals")"
echo "  Paraphrases:       $(get_local_size "$LOCAL_REPO/.cache/paraphrases")"
echo "  Prompt Selection:  $(get_local_size "$LOCAL_REPO/data/prompt_selection")"
echo ""
echo "Remote ($HOST):"
echo "  Inspect AI API:    $(get_remote_size "$HOME/.cache/inspect_ai")"
echo "  Inspect Evals:     $(get_remote_size "$HOME/.cache/inspect_evals")"
echo "  Paraphrases:       $(get_remote_size "$REMOTE_REPO/.cache/paraphrases")"
echo "  Prompt Selection:  $(get_remote_size "$REMOTE_REPO/data/prompt_selection")"
echo ""

if [[ -n "$DRY_RUN" ]]; then
    echo "[DRY RUN - no files will be transferred]"
    echo ""
fi

sync_cache() {
    local name="$1" local_path="$2" remote_path="$3"

    # Skip if source doesn't exist
    if [[ "$DIRECTION" == "push" && ! -d "$local_path" ]]; then
        echo "=== Skipping $name (local path doesn't exist) ==="
        return
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Syncing: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$DIRECTION" == "push" ]]; then
        # Ensure remote directory exists
        ssh "$HOST" "mkdir -p '$(dirname "$remote_path")'"
        rsync $RSYNC_OPTS "$local_path" "${HOST}:${remote_path}"
    else
        # Ensure local directory exists
        mkdir -p "$(dirname "$local_path")"
        rsync $RSYNC_OPTS "${HOST}:${remote_path}" "$local_path"
    fi
}

START_TIME=$(date +%s)

# Sync each cache (home-relative caches use $HOME on both sides)
sync_cache "Inspect AI API cache" \
    "$HOME/.cache/inspect_ai/" \
    "$HOME/.cache/inspect_ai/"

sync_cache "Inspect Evals cache" \
    "$HOME/.cache/inspect_evals/" \
    "$HOME/.cache/inspect_evals/"

sync_cache "Paraphrases cache" \
    "$LOCAL_REPO/.cache/paraphrases/" \
    "$REMOTE_REPO/.cache/paraphrases/"

sync_cache "Prompt Selection cache" \
    "$LOCAL_REPO/data/prompt_selection/" \
    "$REMOTE_REPO/data/prompt_selection/"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Complete! (${ELAPSED}s elapsed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

## Key Features

1. **Overall progress with ETA**: Uses `--info=progress2` which shows:
   ```
   1.23G  45%  12.5MB/s    0:01:32 (xfr#1234, to-chk=567/8901)
   ```
2. **Pre-sync size comparison**: Shows local vs remote sizes before starting
3. **Additive sync**: Uses `--ignore-existing` to never overwrite
4. **Elapsed time**: Reports total sync duration
5. **Bidirectional**: Push to or pull from remote
6. **Dry-run**: Preview changes before syncing

## Files to Create

| File | Action |
|------|--------|
| `scripts/sync_cache.sh` | Create new |

## Verification

```bash
# Test dry-run (shows sizes + what would transfer)
./scripts/sync_cache.sh push mats /home/user/sandbagging-detection --dry-run

# Actual sync
./scripts/sync_cache.sh push mats /home/user/sandbagging-detection
```
