#!/bin/bash
# Automatic cleanup of old files in Downloads and Screenshots
# Moves files older than specified retention period to trash

set -e

# Configuration
RETENTION_DAYS=${RETENTION_DAYS:-180}  # Default: 6 months (180 days)
DOWNLOADS_DIR="$HOME/Downloads"
SCREENSHOTS_DIR="$HOME/Screenshots"

# Normalize DRY_RUN to true/false (handles: true, 1, yes, y, TRUE, Yes, etc.)
case "$DRY_RUN" in
    [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]|[Yy]) DRY_RUN=true ;;
    *) DRY_RUN=false ;;
esac

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to move file to trash
move_to_trash() {
    local file="$1"

    # Check if file still exists (prevents race condition)
    if [[ ! -f "$file" ]]; then
        log_warn "File no longer exists, skipping: $file"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would trash: $file"
        return 0
    fi

    # Use macOS 'trash' command if available, otherwise use osascript
    if command -v trash &> /dev/null; then
        if ! trash "$file" 2>&1; then
            log_error "Failed to move to trash with 'trash' command: $file"
            return 1
        fi
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS fallback using osascript
        if ! osascript -e "tell application \"Finder\" to delete POSIX file \"$file\"" 2>&1; then
            log_error "Failed to move to trash with osascript: $file"
            return 1
        fi
    else
        # Linux fallback - move to XDG trash directory
        TRASH_DIR="$HOME/.local/share/Trash/files"
        if ! mkdir -p "$TRASH_DIR" 2>&1; then
            log_error "Failed to create trash directory: $TRASH_DIR"
            return 1
        fi
        if ! mv "$file" "$TRASH_DIR/" 2>&1; then
            log_error "Failed to move to trash (mv failed): $file"
            return 1
        fi
    fi
}

# Function to clean directory
clean_directory() {
    local dir="$1"
    local dir_name="$2"

    if [[ ! -d "$dir" ]]; then
        log_warn "$dir_name directory not found: $dir"
        return 0
    fi

    log_info "Cleaning $dir_name: $dir"
    log_info "Retention period: $RETENTION_DAYS days"

    # Count files before cleanup
    local total_files
    total_files=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    log_info "Total files in $dir_name: $total_files"

    # Find and process old files
    # Using -atime for access time AND -mtime for modification time
    # Files must be old by BOTH metrics to be considered for deletion
    local old_files
    old_files=$(find "$dir" -maxdepth 1 -type f -atime +${RETENTION_DAYS} -mtime +${RETENTION_DAYS} 2>/dev/null)

    if [[ -z "$old_files" ]]; then
        log_info "No files older than $RETENTION_DAYS days in $dir_name"
        return 0
    fi

    local count=0
    local total_size=0

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local size
            size=$(du -k "$file" 2>/dev/null | cut -f1)
            total_size=$((total_size + size))

            if move_to_trash "$file"; then
                count=$((count + 1))
            fi
        fi
    done <<< "$old_files"

    # Convert KB to human readable
    local size_mb=$((total_size / 1024))

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would trash $count files (~${size_mb}MB) from $dir_name"
    else
        log_info "Moved $count files (~${size_mb}MB) to trash from $dir_name"
    fi
}

# Main execution
main() {
    log_info "Starting cleanup process..."
    log_info "Date: $(date)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No files will be deleted"
    fi

    echo ""
    clean_directory "$DOWNLOADS_DIR" "Downloads"

    echo ""
    clean_directory "$SCREENSHOTS_DIR" "Screenshots"

    echo ""
    log_info "Cleanup complete!"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "To perform actual cleanup, run without DRY_RUN:"
        echo "  $0"
    fi
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Preview what would be deleted without actually deleting"
            echo "  --days DAYS        Set retention period in days (default: 180)"
            echo "  --help             Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  RETENTION_DAYS     Override default retention period (default: 180)"
            echo "  DRY_RUN           Set to 'true' for dry run mode (default: false)"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run                    # Preview cleanup"
            echo "  $0 --days 90                    # Clean files older than 90 days"
            echo "  RETENTION_DAYS=30 $0            # Clean files older than 30 days"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

main
