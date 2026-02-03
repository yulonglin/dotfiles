#!/usr/bin/env bash
# Migrate plans/tasks from global ~/.claude/ to per-project locations
# Includes auto-discovery, classification, and checksum verification

set -euo pipefail

GLOBAL_CLAUDE="$HOME/.claude"
CODE_DIR="${CODE_DIR:-$HOME/code}"
WRITING_DIR="${WRITING_DIR:-$HOME/writing}"
SEARCH_DIRS=("$CODE_DIR" "$WRITING_DIR")
REPOS=()

# Use scratchpad if available, otherwise fallback to user tmp
if [[ -n "${TMPDIR:-}" ]]; then
    TEMP_DIR="$TMPDIR"
elif [[ -w "$HOME/tmp" ]]; then
    TEMP_DIR="$HOME/tmp"
else
    TEMP_DIR="/tmp"
fi

MIGRATION_LOG="$TEMP_DIR/claude_migration_$(date +%s).log"

# Track stats
PLANS_MIGRATED=0
TASKS_MIGRATED=0
PLANS_SKIPPED=0
TASKS_SKIPPED=0

echo "🔍 Discovering repositories..."

# Auto-discover all git repos (including nested repos)
for dir in "${SEARCH_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue
    while IFS= read -r repo; do
        REPOS+=("$repo")
    done < <(find "$dir" -maxdepth 4 -name ".git" -type d 2>/dev/null | sed 's|/.git||' || true)
done

echo "✓ Found ${#REPOS[@]} repositories"
echo "Sample repos: $(printf '%s\n' "${REPOS[@]}" | head -3 | tr '\n' ',' | sed 's/,$//')"
echo ""

# Initialize migration log
{
    echo "Migration started: $(date)"
    echo "Global location: $GLOBAL_CLAUDE"
    echo "Target repos: ${#REPOS[@]}"
    echo ""
} > "$MIGRATION_LOG"

# Function to classify plan by content
classify_plan() {
    local plan="$1"
    local confidence=0
    local project="UNKNOWN"

    # Extract first 100 lines for analysis
    local content
    content=$(head -100 "$plan" 2>/dev/null || echo "")

    # Filename-based matching (highest confidence)
    local filename
    filename=$(basename "$plan")

    if [[ "$filename" =~ (dotfiles|humanizer|plotting|deploy|zsh|tmux|vim) ]]; then
        project="dotfiles"
        confidence=95
    elif [[ "$filename" =~ (slack|mcp|edge) ]]; then
        project="slack-mcp-server"
        confidence=90
    elif [[ "$filename" =~ (gpqa|math|sandbagging|scheme|internals|article|learned-rules) ]]; then
        project="articulating-learned-rules"
        confidence=90
    elif [[ "$filename" =~ (voice|ink|audio|speak) ]]; then
        project="VoiceInk"
        confidence=85
    elif [[ "$filename" =~ (w2sg|salary|gender) ]]; then
        project="w2sg"
        confidence=85
    fi

    # Content-based matching (medium confidence)
    if [[ "$confidence" -lt 70 ]]; then
        if echo "$content" | grep -qi "slack-mcp\|edge\.go\|mcp.*server"; then
            project="slack-mcp-server"
            confidence=70
        elif echo "$content" | grep -qi "deploy\.sh\|install\.sh\|zshrc\|tmux\.conf\|finicky"; then
            project="dotfiles"
            confidence=70
        elif echo "$content" | grep -qi "GPQA\|MATH.*benchmark\|sandbagging\|scheming\|learned.*rules"; then
            project="articulating-learned-rules"
            confidence=70
        elif echo "$content" | grep -qi "voice.*ink\|audio\|speech"; then
            project="VoiceInk"
            confidence=70
        elif echo "$content" | grep -qi "wage.*gender\|w2sg\|salary"; then
            project="w2sg"
            confidence=70
        fi
    fi

    echo "$project:$confidence"
}

# Function to verify checksum
verify_checksum() {
    local src="$1"
    local dest="$2"

    local src_sum dest_sum
    if command -v md5 >/dev/null 2>&1; then
        src_sum=$(md5 -q "$src" 2>/dev/null || echo "")
        dest_sum=$(md5 -q "$dest" 2>/dev/null || echo "")
    elif command -v md5sum >/dev/null 2>&1; then
        src_sum=$(md5sum "$src" 2>/dev/null | awk '{print $1}' || echo "")
        dest_sum=$(md5sum "$dest" 2>/dev/null | awk '{print $1}' || echo "")
    else
        # Fallback: compare file sizes and first 100 bytes
        src_sum=$(wc -c < "$src")
        dest_sum=$(wc -c < "$dest")
    fi

    if [[ "$src_sum" != "$dest_sum" ]]; then
        return 1
    fi
    return 0
}

# Create per-project structure
echo "📁 Creating per-project .claude directories..."
CREATED_DIRS=0
for repo in "${REPOS[@]}"; do
    if mkdir -p "$repo/.claude"/{plans,tasks/archive} 2>/dev/null && \
       mkdir -p "$repo/.claude/tasks" 2>/dev/null; then
        ((CREATED_DIRS++))
    else
        echo "   ⚠️  Skipped (permission denied): $repo"
    fi
done
echo "✓ Directory structure created for $CREATED_DIRS repos"
echo ""

# Migrate plans
echo "📦 Migrating plans from $GLOBAL_CLAUDE/plans/..."
[[ -d "$GLOBAL_CLAUDE/plans" ]] && mkdir -p "$GLOBAL_CLAUDE/plans/.migrated"

for plan in "$GLOBAL_CLAUDE/plans"/*.md; do
    [[ ! -f "$plan" ]] && continue

    result=$(classify_plan "$plan")
    project="${result%:*}"
    confidence="${result#*:}"
    plan_name=$(basename "$plan")

    # Interactive prompt for low confidence or UNKNOWN
    if [[ "$project" == "UNKNOWN" ]] || [[ "$confidence" -lt 60 ]]; then
        echo "❓ Plan: $plan_name (confidence: $confidence%)"
        head -5 "$plan" | sed 's/^/   /'
        echo ""
        echo "   Select project:"
        echo "   (1) articulating-learned-rules"
        echo "   (2) dotfiles"
        echo "   (3) slack-mcp-server"
        echo "   (4) VoiceInk"
        echo "   (5) w2sg"
        echo "   (6) skip this plan"
        read -p "   Choice [1-6]: " choice
        case "$choice" in
            1) project="articulating-learned-rules" ;;
            2) project="dotfiles" ;;
            3) project="slack-mcp-server" ;;
            4) project="VoiceInk" ;;
            5) project="w2sg" ;;
            6)
                echo "   ⏭️  Skipped"
                ((PLANS_SKIPPED++))
                echo "SKIP:$plan -> UNKNOWN" >> "$MIGRATION_LOG"
                continue
                ;;
            *)
                echo "   Invalid choice, skipping"
                ((PLANS_SKIPPED++))
                echo "SKIP:$plan -> INVALID_CHOICE" >> "$MIGRATION_LOG"
                continue
                ;;
        esac
    fi

    # Verify project exists
    if [[ ! -d "$CODE_DIR/$project" ]] && [[ ! -d "$WRITING_DIR/$project" ]]; then
        echo "   ⚠️  Project directory not found: $project"
        ((PLANS_SKIPPED++))
        echo "SKIP:$plan -> PROJECT_NOT_FOUND" >> "$MIGRATION_LOG"
        continue
    fi

    # Determine actual project path
    local proj_path
    if [[ -d "$CODE_DIR/$project" ]]; then
        proj_path="$CODE_DIR/$project"
    elif [[ -d "$WRITING_DIR/$project" ]]; then
        proj_path="$WRITING_DIR/$project"
    fi

    dest="$proj_path/.claude/plans/$plan_name"

    # Copy with verification
    cp -p "$plan" "$dest"

    if verify_checksum "$plan" "$dest"; then
        echo "   ✓ $plan_name → $project"
        ((PLANS_MIGRATED++))
        echo "COPY:$plan -> $dest" >> "$MIGRATION_LOG"
        mv "$plan" "$GLOBAL_CLAUDE/plans/.migrated/"
    else
        echo "   ❌ Checksum mismatch for $plan_name (rolling back)"
        ((PLANS_SKIPPED++))
        rm "$dest"
        echo "FAIL:$plan -> CHECKSUM_MISMATCH" >> "$MIGRATION_LOG"
    fi
done

echo "   Plans: $PLANS_MIGRATED migrated, $PLANS_SKIPPED skipped"
echo ""

# Migrate tasks (basic structure - no detailed classification needed)
echo "📦 Migrating tasks from $GLOBAL_CLAUDE/tasks/..."
[[ -d "$GLOBAL_CLAUDE/tasks" ]] && mkdir -p "$GLOBAL_CLAUDE/tasks/.migrated"

for task_dir in "$GLOBAL_CLAUDE/tasks"/*/; do
    [[ ! -d "$task_dir" ]] && continue

    task_name=$(basename "$task_dir")

    # Try to classify based on directory name
    project="dotfiles"  # Default
    for proj in "${REPOS[@]}"; do
        proj_basename=$(basename "$proj")
        if [[ "$task_name" =~ $proj_basename ]]; then
            project="$proj_basename"
            break
        fi
    done

    # Verify project exists
    local proj_path
    if [[ -d "$CODE_DIR/$project" ]]; then
        proj_path="$CODE_DIR/$project"
    elif [[ -d "$WRITING_DIR/$project" ]]; then
        proj_path="$WRITING_DIR/$project"
    else
        echo "   ⏭️  $task_name (project not found: $project)"
        ((TASKS_SKIPPED++))
        continue
    fi

    dest="$proj_path/.claude/tasks/$task_name"

    # Copy entire task directory
    cp -r "$task_dir" "$dest"
    echo "   ✓ $task_name → $project"
    ((TASKS_MIGRATED++))
    echo "COPY_DIR:$task_dir -> $dest" >> "$MIGRATION_LOG"
    mv "$task_dir" "$GLOBAL_CLAUDE/tasks/.migrated/"
done

echo "   Tasks: $TASKS_MIGRATED migrated, $TASKS_SKIPPED skipped"
echo ""

# Summary
echo "✅ Migration complete!"
echo ""
echo "📊 Summary:"
echo "   Plans: $PLANS_MIGRATED migrated, $PLANS_SKIPPED skipped (Total: $(($PLANS_MIGRATED + $PLANS_SKIPPED)))"
echo "   Tasks: $TASKS_MIGRATED migrated, $TASKS_SKIPPED skipped (Total: $(($TASKS_MIGRATED + $TASKS_SKIPPED)))"
echo ""
echo "📝 Log: $MIGRATION_LOG"
echo ""
echo "🔍 Verify migration:"
echo "   Plans in project dirs: $(find ~/code/*/.claude/plans -name "*.md" 2>/dev/null | wc -l) files"
echo "   Plans in migrated: $(find ~/.claude/plans/.migrated -name "*.md" 2>/dev/null | wc -l) files"
echo "   Original plans: $(find ~/.claude/plans -name "*.md" 2>/dev/null | wc -l) files (should be 0)"
echo ""
echo "   Tasks in project dirs: $(find ~/code/*/.claude/tasks -type d 2>/dev/null | wc -l) dirs"
echo "   Tasks in migrated: $(find ~/.claude/tasks/.migrated -type d 2>/dev/null | wc -l) dirs"
echo "   Original tasks: $(find ~/.claude/tasks -maxdepth 1 -type d 2>/dev/null | wc -l) dirs (should be 1 for . itself)"
echo ""

# Final verification
{
    echo ""
    echo "Migration completed: $(date)"
    echo "Final stats:"
    echo "   Plans migrated: $PLANS_MIGRATED"
    echo "   Plans skipped: $PLANS_SKIPPED"
    echo "   Tasks migrated: $TASKS_MIGRATED"
    echo "   Tasks skipped: $TASKS_SKIPPED"
} >> "$MIGRATION_LOG"

echo "✨ Next steps:"
echo "   1. Commit: git add . && git commit -m 'feat: migrate plans/tasks to per-project locations'"
echo "   2. Configure environment: export CLAUDE_CODE_PLANS_DIR='.claude/plans'"
echo "   3. Configure environment: export CLAUDE_CODE_TASKS_DIR='.claude/tasks'"
echo "   4. Test: Create new plan/task, verify it goes to .claude/ not ~/.claude/"
