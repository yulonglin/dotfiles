# Claude Memory & Organization - Practitioner-Based Approach

**Goal:** Fix immediate pain points using battle-tested solutions that practitioners actually use.

**Approach:** Based on what Simon Willison, Andrej Karpathy, and the community use (2025-2026).

**Timeline:** 4.5-5.5 hours (one afternoon)

---

## Research Findings

**What practitioners use:**
- **Simon Willison:** CLAUDE.md + auto-compact + Skills ([source](https://simonw.substack.com/p/claude-skills-are-awesome-maybe-a))
- **Andrej Karpathy:** Tab completion + multiple windows, no complex memory ([source](https://dev.to/jasonguo/karpathys-claude-code-field-notes-real-experience-and-deep-reflections-on-the-ai-programming-era-4e2f))
- **Community:** [claude-mem](https://github.com/thedotmack/claude-mem) is most popular ([source](https://levelup.gitconnected.com/someone-built-memory-for-claude-code-and-people-are-actually-using-it-9f657be0f193))

**Key insight:** Don't overthink it. Karpathy accepts LLM limitations rather than building complex systems.

---

## User Requirements

**Core pain points:**
1. Plans/tasks in global `~/.claude/` → confusion across sessions
2. Stale ground truth docs (CLAUDE.md has old hyperparams)
3. Hard to search across specs/ai_docs/CLAUDE.md
4. Want passive auto-capture (low-noise, no manual review)
5. `ai_docs/` lacks VSCode icon support (non-standard directory name)

**Preferences:**
- Lots of compute, minimize Claude API usage
- Prefer fd/grep over vector DB (transparency)
- Simple, battle-tested solutions

---

## Implementation Plan

### Step 1: Migrate Plans/Tasks to Per-Project (2 hours)

**Problem:** All plans/tasks in `~/.claude/` mix work from different projects → confusion.

**Solution:** Move to per-project `.claude/plans/` and `.claude/tasks/`.

**File:** `scripts/migrate_claude_plans_tasks.sh`

```bash
#!/usr/bin/env bash
# Migrate plans/tasks from global to per-project

set -euo pipefail

GLOBAL_CLAUDE="$HOME/.claude"
# Auto-discover all git repos (including nested repos like sandbagging-detection/dev)
SEARCH_DIRS=("$HOME/code" "$HOME/writing")
REPOS=()

for dir in "${SEARCH_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue
    while IFS= read -r repo; do
        REPOS+=("$repo")
    done < <(find "$dir" -maxdepth 4 -name ".git" -type d | sed 's|/.git||')
done

echo "Found ${#REPOS[@]} repositories to process"
echo "Sample repos: $(printf '%s\n' "${REPOS[@]}" | head -5)"
MIGRATION_LOG="/tmp/claude_migration_$(date +%s).log"

# Auto-classify plans by content
classify_plan() {
    local plan="$1"
    local confidence=0
    local project="UNKNOWN"

    # Filename matching (high confidence)
    if [[ "$plan" =~ (dotfiles|slack-mcp|VoiceInk|w2sg) ]]; then
        project="${BASH_REMATCH[1]}"
        confidence=90
    # Content analysis (medium confidence)
    elif grep -q "slack-mcp\|edge.go" "$plan"; then
        project="slack-mcp-server"
        confidence=70
    elif grep -q "deploy\.sh\|install\.sh\|zshrc" "$plan"; then
        project="dotfiles"
        confidence=70
    elif grep -q "GPQA\|MATH\|sandbagging\|scheming" "$plan"; then
        project="articulating-learned-rules"
        confidence=70
    fi

    echo "$project:$confidence"
}

# Create per-project structure
for repo in "${REPOS[@]}"; do
    mkdir -p "$CODE_DIR/$repo/.claude"/{plans,tasks/archive}
done

# Migrate plans with checksum verification
for plan in "$GLOBAL_CLAUDE/plans"/*.md; do
    [[ ! -f "$plan" ]] && continue

    result=$(classify_plan "$plan")
    project="${result%:*}"
    confidence="${result#*:}"

    # Interactive for low confidence
    if [[ "$project" == "UNKNOWN" || "$confidence" -lt 60 ]]; then
        echo "Plan: $(basename "$plan")"
        head -10 "$plan"
        echo "Which project? (1) articulating-learned-rules (2) dotfiles (3) slack-mcp-server (4) VoiceInk (5) w2sg (6) skip"
        read -r choice
        case "$choice" in
            1) project="articulating-learned-rules" ;;
            2) project="dotfiles" ;;
            3) project="slack-mcp-server" ;;
            4) project="VoiceInk" ;;
            5) project="w2sg" ;;
            6) continue ;;
        esac
    fi

    dest="$CODE_DIR/$project/.claude/plans/$(basename "$plan")"

    # Copy with checksum verification
    cp -p "$plan" "$dest"
    src_sum=$(md5 -q "$plan" 2>/dev/null || md5sum "$plan" | awk '{print $1}')
    dest_sum=$(md5 -q "$dest" 2>/dev/null || md5sum "$dest" | awk '{print $1}')

    if [[ "$src_sum" != "$dest_sum" ]]; then
        echo "ERROR: Checksum mismatch for $(basename "$plan")"
        exit 1
    fi

    echo "COPY:$plan->$dest" >> "$MIGRATION_LOG"
    mv "$plan" "$GLOBAL_CLAUDE/plans/.migrated/"
    echo "✓ Migrated $(basename "$plan") → $project"
done

echo "Migration complete. Log: $MIGRATION_LOG"
echo "Verify: find ~/code/*/.claude/plans -name '*.md' | wc -l"
```

### Step 2: Install claude-mem (30 min)

**Why:** Battle-tested, community favorite, passive auto-capture.

**Installation:**
```bash
# In Claude Code
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
# Restart Claude Code
```

**What it does:**
- Automatically captures tool usage during sessions
- SQLite + Chroma vector DB for hybrid search
- Web UI at localhost:37777 (optional viewing)
- Progressive retrieval (~10x token savings)
- No manual review required - just search when needed

**Configuration:** `~/.claude-mem/settings.json` (auto-generated)

**Verify:**
```bash
ls ~/.claude-mem/
curl -s localhost:37777 | grep -q "Claude-Mem" && echo "✓ Web UI running"
```

### Step 3: Add Stale Doc Detection (1 hour)

**Git hook to warn about outdated docs:**

**File:** `claude/hooks/pre_session_start.sh`

```bash
#!/bin/bash
# Warn about stale docs at session start

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
DOCS_DIR="$REPO_ROOT/docs"  # Renamed from ai_docs

# Check CLAUDE.md staleness
if [[ -f "$CLAUDE_MD" ]]; then
    COMMITS_SINCE=$(git log --oneline "$CLAUDE_MD".. 2>/dev/null | wc -l || echo 0)
    DAYS_SINCE=$(( ($(date +%s) - $(git log -1 --format=%ct "$CLAUDE_MD" 2>/dev/null || echo $(date +%s))) / 86400 ))

    if [[ $COMMITS_SINCE -gt 50 ]] || [[ $DAYS_SINCE -gt 90 ]]; then
        echo "⚠️  CLAUDE.md not updated in $COMMITS_SINCE commits ($DAYS_SINCE days)"
        echo "    Consider refreshing ground truth docs"
    fi
fi

# Check docs/ staleness (formerly ai_docs/)
if [[ -d "$DOCS_DIR" ]]; then
    for doc in "$DOCS_DIR"/*.md; do
        [[ ! -f "$doc" ]] && continue
        DAYS=$(( ($(date +%s) - $(git log -1 --format=%ct "$doc" 2>/dev/null || echo $(date +%s))) / 86400 ))
        if [[ $DAYS -gt 180 ]]; then
            echo "⚠️  $(basename "$doc") last updated $DAYS days ago"
        fi
    done
fi
```

**Deploy:**
```bash
# Add to claude/hooks/
cp claude/hooks/pre_session_start.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/pre_session_start.sh
```

### Step 4: Add Validation Hooks (30 min)

**Problem:** Need to enforce that plans/tasks go to project `.claude/` not global `~/.claude/`.

**Solution:** Add hooks that validate and redirect plan/task creation.

**File:** `claude/hooks/pre_plan_create.sh` (new)

```bash
#!/bin/bash
# Validate plan creation location and naming

set -euo pipefail

PLAN_PATH="$1"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Check if plan is going to global location (BAD)
if [[ "$PLAN_PATH" == "$HOME/.claude/plans/"* ]]; then
    echo "❌ ERROR: Plans must be per-project, not global"
    echo "   Expected: $REPO_ROOT/.claude/plans/"
    echo "   Got:      $PLAN_PATH"
    echo ""
    echo "Fix: Use project-local .claude/plans/ directory"
    exit 1
fi

# Check if plan has timestamp in name (GOOD)
PLAN_NAME=$(basename "$PLAN_PATH")
if [[ ! "$PLAN_NAME" =~ ^[0-9]{8}_[0-9]{6}_UTC ]]; then
    echo "⚠️  WARNING: Plan name should start with UTC timestamp"
    echo "   Example: 20260202_143022_UTC_feature_name.md"
    echo "   Got:     $PLAN_NAME"
fi

# Suggest name if in repo
if [[ -n "$REPO_ROOT" ]] && [[ "$PLAN_PATH" != "$REPO_ROOT/.claude/plans/"* ]]; then
    echo "⚠️  WARNING: Plan should be in $REPO_ROOT/.claude/plans/"
    echo "   Got: $PLAN_PATH"
fi
```

**File:** `claude/hooks/pre_task_create.sh` (new)

```bash
#!/bin/bash
# Validate task creation location

set -euo pipefail

TASK_PATH="$1"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# Check if task is going to global location (BAD)
if [[ "$TASK_PATH" == "$HOME/.claude/tasks/"* ]]; then
    echo "❌ ERROR: Tasks must be per-project, not global"
    echo "   Expected: $REPO_ROOT/.claude/tasks/"
    echo "   Got:      $TASK_PATH"
    echo ""
    echo "Fix: Use project-local .claude/tasks/ directory"
    exit 1
fi
```

### Step 5: Configure Per-Project Plans/Tasks (15 min)

**Problem:** Claude Code defaults to global `~/.claude/plans/` and `~/.claude/tasks/`.

**Solution:** Configure to use per-project locations going forward.

**Option A: Environment Variables (Recommended)**

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Claude Code: use per-project plans/tasks
export CLAUDE_CODE_PLANS_DIR=".claude/plans"
export CLAUDE_CODE_TASKS_DIR=".claude/tasks"
```

**Option B: Per-Project Settings**

Create `.claude/settings.json` in each repo:

```json
{
  "plansDirectory": ".claude/plans",
  "tasksDirectory": ".claude/tasks"
}
```

**Option C: Update CLAUDE.md (Instruction-Based)**

Add to project CLAUDE.md:

```markdown
## Task and Plan Organization

**CRITICAL**: All plans and tasks must be stored per-project, not globally.

- Plans: `<repo>/.claude/plans/` (NOT `~/.claude/plans/`)
- Tasks: `<repo>/.claude/tasks/` (NOT `~/.claude/tasks/`)

When creating plans or tasks, Claude MUST use the project-local `.claude/` directory.
```

**Verify:**
```bash
# Start new session, create a task
# Check it went to project .claude/tasks/ not ~/.claude/tasks/
```

**Update global CLAUDE.md:**

Update `claude/CLAUDE.md` to reflect per-project locations:

```diff
- Stored in: `~/.claude/tasks/<name>/`
+ Stored in: `<repo>/.claude/tasks/<name>/` (per-project)

- Location: `.claude/plans/` directory
+ Location: `<repo>/.claude/plans/` directory (per-project, NOT global)
```

### Step 6: Add /docs-search Skill (30 min - optional)

**File:** `claude/skills/docs-search.md`

```markdown
---
name: docs-search
description: Fast grep-based search across specs, docs, CLAUDE.md
---

Search project documentation using fd + grep (no vector DB).

Usage:
```
/docs-search <query>
/docs-search "batch size"
/docs-search "hyperparameters" --files="docs/*.md"
```

Implementation:
```bash
#!/bin/bash
query="$1"

# Search locations (prioritize by relevance)
fd -e md -E node_modules -E .git . | \
  xargs grep -i "$query" -H -n | \
  head -20
```

Returns file paths + line numbers + matching context.
```

**Deploy:**
```bash
cp claude/skills/docs-search.md ~/.claude/skills/
```

### Step 7: Rename ai_docs/ to Standard Directory (30 min)

**Problem:** `ai_docs/` lacks VSCode icon support (non-standard name), causing visual inconsistency.

**Solution:** Rename to standard directory name across all repos.

**Directory Options:**

Based on [VSCode Icons supported folders list](https://github.com/vscode-icons/vscode-icons/wiki/ListOfFolders):

| Option | VSCode Folder Icon Support | Pros | Cons | Recommendation |
|--------|----------------------------|------|------|----------------|
| `docs/` | ✅ YES ("docs, doc, document, documents") | Most standard, guaranteed icon | May conflict with API/user docs | ✅ **Recommended** - official support |
| `ai/` | ❌ NO (ai support is FILES only, not directories) | Short, clear | No folder icon support (defeats purpose) | ❌ Doesn't solve problem |
| `.docs/` | ❌ NO | Hidden, no conflicts | No icon support | ❌ Doesn't solve problem |
| `.memory/` | ❌ NO | Semantic | No icon support | ❌ Doesn't solve problem |

**Note:** VSCode Icons has "ai" support for FILE icons (`.ai` files), but NOT for folder/directory icons. Therefore `ai/` doesn't solve the icon visibility problem.

**Recommended: `docs/`** - Only option with official VSCode folder icon support. If conflicts with existing `docs/` directory in a specific repo, manually choose alternative for that repo (e.g., `ai-docs/`, `knowledge/`).

**Migration Script:** `scripts/rename_ai_docs.sh`

```bash
#!/usr/bin/env bash
# Rename ai_docs/ to ai/ across all repos

set -euo pipefail

NEW_NAME="${1:-docs}"  # Default to 'docs' (has VSCode icon support), allow override
SEARCH_DIRS=("$HOME/code" "$HOME/writing")
MIGRATION_LOG="/tmp/ai_docs_rename_$(date +%s).log"

echo "Renaming ai_docs/ → $NEW_NAME/ across all repos"
echo "Searching in: ${SEARCH_DIRS[*]}"

# Find all repos with ai_docs/ directory (including nested like sandbagging-detection/dev)
for dir in "${SEARCH_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue

    while IFS= read -r repo; do
        OLD_DIR="$repo/ai_docs"
        NEW_DIR="$repo/$NEW_NAME"

        [[ ! -d "$OLD_DIR" ]] && continue

        # Check if new directory already exists
        if [[ -d "$NEW_DIR" ]]; then
            echo "⚠️  $NEW_DIR already exists, skipping $repo"
            echo "SKIP:$repo (target exists)" >> "$MIGRATION_LOG"
            continue
        fi

        # Git mv for proper rename (preserves history)
        (
            cd "$repo"
            git mv ai_docs "$NEW_NAME" 2>/dev/null || mv ai_docs "$NEW_NAME"
            echo "RENAME:$OLD_DIR → $NEW_DIR" >> "$MIGRATION_LOG"
            echo "✓ Renamed in $repo"
        )
    done < <(find "$dir" -maxdepth 4 -type d -name "ai_docs" | sed 's|/ai_docs||')
done

echo ""
echo "Migration complete. Log: $MIGRATION_LOG"
echo "Next: Update references in CLAUDE.md, hooks, and scripts"
```

**Update References:**

Files to update (search and replace `ai_docs` → `docs`):

1. **Global CLAUDE.md** (`claude/CLAUDE.md`):
```bash
# Search and replace
sd 'ai_docs/' 'docs/' claude/CLAUDE.md
sd 'ai_docs' 'docs' claude/CLAUDE.md  # catch references without trailing /
```

2. **Hooks** (`claude/hooks/pre_session_start.sh`):
```bash
# Update variable name and comments
sd 'AI_DIR=".*ai_docs"' 'DOCS_DIR="$REPO_ROOT/docs"' claude/hooks/pre_session_start.sh
sd 'AI_DIR' 'DOCS_DIR' claude/hooks/pre_session_start.sh
sd 'ai/' 'docs/' claude/hooks/pre_session_start.sh
sd 'formerly ai_docs' 'formerly ai_docs, now docs' claude/hooks/pre_session_start.sh
```

3. **Project CLAUDE.md files** (each repo):
```bash
for repo in ~/code/* ~/writing/*; do
    [[ -f "$repo/CLAUDE.md" ]] && sd 'ai_docs/' 'docs/' "$repo/CLAUDE.md"
done
```

4. **README files** (if they reference the directory):
```bash
fd README.md | xargs sd 'ai_docs/' 'docs/'
```

**Verify .gitignore:**

Ensure the new directory is tracked (not ignored):

```bash
# Check if docs/ is ignored
for repo in ~/code/* ~/writing/*; do
    if [[ -f "$repo/.gitignore" ]] && grep -q "^docs/$" "$repo/.gitignore"; then
        echo "⚠️  $repo/.gitignore ignores docs/ - remove or add exception"
    fi
done
```

**Commit Changes:**

```bash
# In each repo with renamed directory
cd <repo>
git add docs/ .gitignore  # If .gitignore was updated
git commit -m "refactor: rename ai_docs/ to docs/ for VSCode icon support

- Rename ai_docs/ → docs/ for standard directory naming
- Gets VSCode icon support (ai_docs was non-standard)
- Update CLAUDE.md references
- Preserve git history with git mv

Ref: https://github.com/vscode-icons/vscode-icons/wiki/ListOfFolders"
```

**Verification:**

```bash
# Check all renames completed
fd -t d '^docs$' ~/code ~/writing | wc -l  # Should match old ai_docs count
fd -t d '^ai_docs$' ~/code ~/writing | wc -l  # Should be 0

# Verify no broken references
rg 'ai_docs' ~/code/*/CLAUDE.md ~/writing/*/CLAUDE.md ~/.claude/CLAUDE.md  # Should return nothing

# Verify VSCode icon support
code .  # Open in VSCode and check that docs/ has a folder icon
```

---

## Verification Checklist

### ✅ Plans/Tasks Migration
- [ ] 83 plans migrated to per-project locations
- [ ] Checksums verified (no data loss)
- [ ] Git tracking correct (`.claude/plans/` committed)

```bash
# Verify
find ~/code/*/.claude/plans -name "*.md" | wc -l  # ~83
find ~/.claude/plans/.migrated/ -name "*.md" | wc -l  # ~83
```

### ✅ claude-mem Installation
- [ ] Plugin installed
- [ ] Web UI accessible at localhost:37777
- [ ] Search working: `/memory-search "test"`

```bash
ls ~/.claude-mem/
curl -s localhost:37777 | grep -q "Claude-Mem"
```

### ✅ Stale Doc Detection
- [ ] Hook executes on session start
- [ ] Warnings shown for stale docs

```bash
# Start new session, should see warnings if docs stale
```

### ✅ /docs-search (Optional)
- [ ] Skill deployed
- [ ] Returns results in <2 seconds

```bash
/docs-search "test"
```

---

## Success Criteria

**Functional:**
- Plans/tasks no longer in global `~/.claude/` ✓
- Can search project context with `/docs-search` ✓
- claude-mem captures passively (no manual review) ✓
- Warned about stale docs at session start ✓

**Data Integrity:**
- No data loss in migration (checksums match) ✓
- Git tracking correct ✓

**Usability:**
- No manual curation required ✓
- Simple grep-based search (transparent) ✓
- Clear warnings when docs stale ✓

---

## Next Steps

1. **Implement** (one afternoon):
   - Run migration script
   - Install claude-mem
   - Deploy hooks

2. **Test** (1 week):
   - Use claude-mem passively
   - Monitor stale doc warnings
   - Evaluate if `/docs-search` is useful

3. **Iterate:**
   - If claude-mem is noisy: disable it
   - If /docs-search is slow: optimize
   - Update CLAUDE.md/ai_docs when warned

---

## Critical Files

**New files:**
1. `scripts/migrate_claude_plans_tasks.sh` - Migration with auto-discovery and checksum verification
2. `scripts/rename_ai_docs.sh` - Rename ai_docs/ → ai/ across all repos
3. `claude/hooks/pre_session_start.sh` - Stale doc warnings
4. `claude/hooks/pre_plan_create.sh` - Validate plan location and naming
5. `claude/hooks/pre_task_create.sh` - Validate task location
6. `claude/skills/docs-search.md` - Grep-based search (optional)

**Modified files:**
1. Per-project `.gitignore` - Allow `.claude/plans/` and `.claude/tasks/archive/`, ensure `ai/` not ignored
2. `claude/CLAUDE.md` - Update references from `ai_docs/` → `ai/`, document per-project locations
3. `~/.zshrc` - Add environment variables for per-project paths (Option A)
4. Project `CLAUDE.md` files - Update `ai_docs/` → `ai/` references
5. `README.md` files - Update `ai_docs/` → `ai/` references (if applicable)

**Directory changes:**
- `ai_docs/` → `ai/` - Renamed for VSCode icon support (git mv preserves history)

**No changes to:**
- `specs/` - keep as-is
- `CLAUDE.md` content - just warn when stale, don't auto-update

---

**Implementation Date:** TBD
**Status:** ✅ Ready to Implement
