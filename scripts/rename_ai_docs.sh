#!/usr/bin/env bash
# Rename ai_docs/ → ai/ (or other name) across all repos
# Preserves git history with git mv when possible
# Handles nested repos like sandbagging-detection/dev

set -euo pipefail

# Configuration
NEW_NAME="${1:-docs}"  # Default to 'docs' (has VSCode icon support)
SEARCH_DIRS=("$HOME/code" "$HOME/writing")

# Use scratchpad if available, otherwise fallback to user tmp
if [[ -n "${TMPDIR:-}" ]]; then
    TEMP_DIR="$TMPDIR"
elif [[ -w "$HOME/tmp" ]]; then
    TEMP_DIR="$HOME/tmp"
else
    TEMP_DIR="/tmp"
fi

MIGRATION_LOG="$TEMP_DIR/ai_docs_rename_$(date +%s).log"

# Track stats
RENAMED=0
SKIPPED=0
ERRORS=0

echo "🔄 Renaming ai_docs/ → $NEW_NAME/ across all repos"
echo "Searching in: ${SEARCH_DIRS[*]}"
echo ""

# Initialize log
{
    echo "Rename started: $(date)"
    echo "New name: $NEW_NAME"
    echo "Search dirs: ${SEARCH_DIRS[*]}"
    echo ""
} > "$MIGRATION_LOG"

# Find and process each ai_docs directory
for dir in "${SEARCH_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue

    while IFS= read -r old_dir; do
        [[ ! -d "$old_dir" ]] && continue

        repo_root=$(dirname "$old_dir")
        new_dir="$repo_root/$NEW_NAME"

        # Check if in a git repo
        is_git_repo=false
        if [[ -d "$repo_root/.git" ]]; then
            is_git_repo=true
        fi

        # Check if new directory already exists
        if [[ -d "$new_dir" ]]; then
            echo "⚠️  $NEW_NAME already exists in $(basename "$repo_root")"
            echo "   (keeping existing $NEW_NAME, skipping ai_docs)"
            ((SKIPPED++))
            echo "SKIP:$old_dir -> TARGET_EXISTS" >> "$MIGRATION_LOG"
            continue
        fi

        # Handle merge: if both ai_docs and $NEW_NAME exist, merge content
        if [[ -d "$new_dir" ]] && [[ -d "$old_dir" ]]; then
            echo "📋 Merging $old_dir → $new_dir..."
            cp -r "$old_dir"/* "$new_dir/" 2>/dev/null || true
            if [[ "$is_git_repo" == "true" ]]; then
                (
                    cd "$repo_root"
                    git add "$NEW_NAME" 2>/dev/null || true
                    git rm -r ai_docs 2>/dev/null || true
                ) || true
            else
                rm -rf "$old_dir"
            fi
            ((RENAMED++))
            echo "MERGE:$old_dir -> $new_dir" >> "$MIGRATION_LOG"
            continue
        fi

        # Standard rename
        if [[ "$is_git_repo" == "true" ]]; then
            # Use git mv to preserve history
            (
                cd "$repo_root"
                if git mv ai_docs "$NEW_NAME" 2>/dev/null; then
                    echo "✓ Git renamed: $(basename "$repo_root")/ai_docs → $NEW_NAME"
                    ((RENAMED++))
                    echo "GIT_MV:$old_dir -> $new_dir" >> "$MIGRATION_LOG"
                else
                    echo "❌ Git mv failed in $(basename "$repo_root"), trying mv instead"
                    mv "$old_dir" "$new_dir"
                    git add "$NEW_NAME" ai_docs 2>/dev/null || true
                    echo "FALLBACK_MV:$old_dir -> $new_dir" >> "$MIGRATION_LOG"
                    ((RENAMED++))
                fi
            ) || {
                ((ERRORS++))
                echo "ERROR:$old_dir -> RENAME_FAILED" >> "$MIGRATION_LOG"
            }
        else
            # Not a git repo, just use mv
            echo "✓ Moved (non-git): $(basename "$repo_root")/ai_docs → $NEW_NAME"
            mv "$old_dir" "$new_dir"
            ((RENAMED++))
            echo "MV:$old_dir -> $new_dir" >> "$MIGRATION_LOG"
        fi

    done < <(find "$dir" -maxdepth 4 -type d -name "ai_docs" 2>/dev/null)
done

echo ""
echo "✅ Rename operations complete!"
echo ""
echo "📊 Summary:"
echo "   Renamed: $RENAMED"
echo "   Skipped: $SKIPPED"
echo "   Errors: $ERRORS"
echo ""
echo "📝 Log: $MIGRATION_LOG"
echo ""

# Verify
echo "🔍 Verification:"
echo "   Remaining ai_docs dirs: $(find ~/code ~/writing -maxdepth 4 -type d -name "ai_docs" 2>/dev/null | wc -l)"
echo "   New $NEW_NAME dirs: $(find ~/code ~/writing -maxdepth 4 -type d -name "$NEW_NAME" 2>/dev/null | wc -l)"
echo ""

# Check for references that need updating
echo "📌 Files to update (containing 'ai_docs'):"
echo "   CLAUDE.md files: $(rg -l 'ai_docs' ~/code/*/CLAUDE.md ~/writing/*/CLAUDE.md ~/.claude/CLAUDE.md 2>/dev/null | wc -l)"
echo "   Other files: $(rg -l 'ai_docs' ~/code ~/writing --max-depth 4 --type md 2>/dev/null | wc -l)"
echo ""

echo "✨ Next steps:"
echo "   1. Run: sd 'ai_docs' '$NEW_NAME' <CLAUDE.md files>"
echo "   2. Run: git add . && git commit -m 'refactor: rename ai_docs/ → $NEW_NAME/'"
echo "   3. Update hook references (pre_session_start.sh)"
echo "   4. Verify no broken references: rg 'ai_docs' ~/code ~/writing"
echo ""

# Final log entry
{
    echo ""
    echo "Rename completed: $(date)"
    echo "Final stats:"
    echo "   Renamed: $RENAMED"
    echo "   Skipped: $SKIPPED"
    echo "   Errors: $ERRORS"
} >> "$MIGRATION_LOG"
