# Implementation Engineering Critique: Claude Memory System

**Reviewing:** typed-shimmying-hearth.md
**Date:** 2026-02-03 UTC
**Focus:** Implementation risks, edge cases, practical concerns

---

## 1. Implementation Risks

### Critical Race Conditions

**session_end.sh - Multiple Sessions Ending Simultaneously:**
```bash
# CURRENT (lines 374-389): Race condition on file write
STAGING_FILE="$MEMORY_DIR/staging/${TIMESTAMP}_${MODE}.md"
echo "$INSIGHTS" >> "$STAGING_FILE"  # Multiple processes can corrupt
```

**Problems:**
- Two sessions ending at same time → concurrent appends to same daily file → interleaved lines
- `>>` is NOT atomic on all filesystems (especially NFS, network mounts)
- `jq` on `history.jsonl` while Claude is writing → reads partial JSON → parse errors

**Fix:**
```bash
# Use file locking (requires flock on Linux, lockfile on macOS)
LOCK_FILE="$MEMORY_DIR/staging/.lock"
STAGING_FILE="$MEMORY_DIR/staging/${TIMESTAMP}_${MODE}.md"

(
  flock -x 200 || exit 1  # Exclusive lock

  # Check history.jsonl is not being written
  while lsof "$HOME/.claude/history.jsonl" >/dev/null 2>&1; do
    sleep 0.1
  done

  echo "$INSIGHTS" >> "$STAGING_FILE"
) 200>"$LOCK_FILE"
```

**Alternative (atomic writes):**
```bash
# Write to temp, atomic rename
TEMP_FILE=$(mktemp)
SESSION_FILE="$MEMORY_DIR/staging/${TIMESTAMP}_${MODE}_$$_$(date +%s).md"
echo "$INSIGHTS" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SESSION_FILE"  # Atomic on same filesystem

# Consolidation happens later in /memory-review
```

### Hook Trigger Reliability

**Line 365:** "Triggered when session ends (exit, compact, explicit `/end`)"

**Problems:**
- What if Claude crashes? (kill -9, OOM, system crash) → hook never runs
- What if user closes terminal? (SSH disconnect, laptop sleep) → SIGHUP may not trigger hook
- Compact doesn't necessarily mean session end → might capture mid-session

**Evidence needed:**
- How are hooks actually triggered? (Need to check Claude Code source)
- Is there a `.claude/hooks/on_compact.sh` vs `.claude/hooks/on_exit.sh`?
- Does `/compact` trigger session_end hook or a different one?

**Recommendations:**
1. **Check hook documentation** - verify when hooks actually fire
2. **Add periodic checkpoint** - auto-save staging every N messages, not just on exit
3. **Recovery mechanism** - detect incomplete sessions on startup, extract from history.jsonl

### history.jsonl Corruption Risk

**Line 373-376:** Reading history.jsonl with jq during active session

**Problems:**
- `history.jsonl` is written incrementally by Claude → partial JSON at EOF
- `jq` will fail if last line is incomplete: `parse error: Invalid numeric literal at line 1234`
- No validation that file is complete before parsing

**Fix:**
```bash
# Only parse complete JSON objects (ignore incomplete last line)
INSIGHTS=$(jq -r 'select(type == "object") | .messages[]? | select(.role=="assistant") | .content' \
    "$HOME/.claude/history.jsonl" 2>/dev/null | \
    grep -iE "we decided|I'll use" | head -10)

# Or: Parse up to last complete newline
INSIGHTS=$(head -c -1 "$HOME/.claude/history.jsonl" | \  # Drop incomplete last line
    jq -r '.messages[] | select(.role=="assistant") | .content' | \
    grep -iE "...")
```

---

## 2. Shell Script Quality

### Pattern Matching Limitations

**Line 375-376:** Grep patterns for insight extraction

**Current patterns:**
```bash
grep -iE "we decided|I'll use|watch out|common mistake|batch_size|learning_rate"
```

**Problems:**

1. **False positives:**
   - "We decided to investigate X" → not a decision, just planning
   - "I'll use this as an example of what NOT to do" → negative example captured as positive
   - "batch_size" in error messages → noise
   - Code snippets with `batch_size=...` → implementation detail, not learning

2. **False negatives:**
   - "Going with approach A because..." → missed (no trigger words)
   - "The optimal value turned out to be..." → missed
   - "After testing, N=50 works best" → missed

3. **No context extraction:**
   - Captures "batch_size=50" but not WHY or WHAT it's for
   - Missing surrounding conversation context

**Improvements:**
```bash
# Better patterns with context
PATTERNS=(
  "decided to .{0,100}"                    # Decision + context
  "works? best|optimal|prefer.{0,50}"      # Successful approaches
  "fails? if|watch out|gotcha.{0,100}"     # Pitfalls
  "[a-z_]+\s*=\s*[\d.e-]+.{0,50}"         # Params with context
  "(?:don't|avoid|never) .{0,80}"         # Anti-patterns
)

for pattern in "${PATTERNS[@]}"; do
  grep -oP "$pattern" ... >> "$STAGING_FILE"
done
```

**Better yet - extract full sentences:**
```bash
# Get full sentences containing keywords (requires GNU grep -P)
grep -P "([^.!?]*(?:decided|optimal|watch out|batch_size)[^.!?]*[.!?])" \
  <(jq -r ...) | head -20
```

### Mode Detection Logic

**Line 380:** `MODE="research"  # Default, could detect from content`

**Problem:** No mode detection implemented, everything goes to research

**Impact:**
- Writing sessions → captured as research → wrong category
- Code debugging → captured as research → hard to find later
- Mixed sessions → single mode, loses granularity

**Fix (pattern-based detection):**
```bash
detect_mode() {
  local content="$1"

  # Count keyword occurrences
  local research_score=$(echo "$content" | grep -ciE "experiment|hypothesis|data|metric|baseline")
  local writing_score=$(echo "$content" | grep -ciE "paper|draft|section|citation|review")
  local code_score=$(echo "$content" | grep -ciE "function|class|import|debug|error")

  # Return mode with highest score
  if [[ $research_score -gt $writing_score && $research_score -gt $code_score ]]; then
    echo "research"
  elif [[ $writing_score -gt $code_score ]]; then
    echo "writing"
  else
    echo "code"
  fi
}

MODE=$(detect_mode "$INSIGHTS")
```

### Error Handling Gaps

**Missing validations:**
```bash
# Line 368-370: No checks if variables are set
SESSION_ID="$1"  # What if $1 is empty?
MEMORY_DIR="$HOME/.claude/.memory"  # What if $HOME is empty (cron job)?

# Line 373: jq failure not handled
INSIGHTS=$(jq -r ... "$HOME/.claude/history.jsonl")  # Fails silently if file missing
```

**Improved version:**
```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars

# Validate environment
if [[ -z "${HOME:-}" ]]; then
  echo "ERROR: HOME not set" >&2
  exit 1
fi

MEMORY_DIR="${HOME}/.claude/.memory"
if [[ ! -d "$MEMORY_DIR" ]]; then
  echo "WARN: Memory system not initialized, skipping" >&2
  exit 0
fi

# Validate history file
HISTORY_FILE="${HOME}/.claude/history.jsonl"
if [[ ! -f "$HISTORY_FILE" || ! -r "$HISTORY_FILE" ]]; then
  echo "WARN: Cannot read history.jsonl, skipping" >&2
  exit 0
fi

# Extract with error handling
INSIGHTS=$(jq -r '.messages[] | select(.role=="assistant") | .content' \
    "$HISTORY_FILE" 2>/dev/null | \
    grep -iE "..." | head -10 || true)  # Don't fail on no matches
```

---

## 3. Git Integration Issues

### Per-Project .gitignore Conflicts

**Lines 261-265:** Per-project tracking of `.claude/`

**Problem:** Most repos already have `.claude/` in `.gitignore` (Claude Code default)

**Scenario:**
1. User's existing repo: `.gitignore` contains `.claude/` (whole directory ignored)
2. Migration creates `repo/.claude/plans/important.md`
3. File is NOT tracked (parent directory ignored)
4. User loses plans when switching machines

**Fix:**
```bash
# In migration script, update each repo's .gitignore
update_project_gitignore() {
  local repo_path="$1"
  local gitignore="$repo_path/.gitignore"

  if [[ ! -f "$gitignore" ]]; then
    return
  fi

  # Check if .claude is ignored
  if grep -q "^\.claude/?$" "$gitignore"; then
    # Change blanket ignore to selective
    sed -i.bak 's|^\.claude/?$|.claude/\n!.claude/plans/\n!.claude/tasks/\n!.claude/.memory/|' "$gitignore"
    echo "Updated .gitignore in $repo_path (backup: .gitignore.bak)"
  fi
}
```

**Alternative:** Use `.gitignore` in `.claude/` subdirectory instead:
```bash
# repo/.claude/.gitignore (more robust, doesn't conflict with repo-level ignore)
*               # Ignore everything in .claude/ by default
!plans/         # Except plans
!tasks/archive/ # And completed tasks
!.memory/       # And memory
.memory/staging/  # But not staging
```

### Global .gitignore Ambiguity

**Lines 269-280:** Updating `claude/.gitignore` in dotfiles

**Problem:** Ignoring `plans/` and `tasks/` at root level

```gitignore
plans/  # Does this mean:
        # 1. claude/plans/ (what's intended)
        # 2. dotfiles/plans/ (if it existed)
        # 3. Both?
```

**Git behavior:** `plans/` matches ANY directory named "plans" in the repo

**Risk:** If dotfiles later adds `docs/plans/` for documentation, it gets ignored unintentionally

**Fix:**
```gitignore
# Be explicit about paths
/claude/plans/        # Only claude/plans/, not other plans/
/claude/tasks/        # Only claude/tasks/
/claude/.memory/staging/
```

### Migration Data Loss Risk

**Lines 467-481:** Auto-classification with manual fallback

**Problem:** No verification before moving files

```bash
cp -p "$plan" "$CODE_DIR/$project/.claude/plans/"  # Copy
mv "$plan" "$GLOBAL_CLAUDE/plans/.migrated/"       # Move original
```

**Race condition:**
- `cp` succeeds
- System crashes / disk full / permission error BEFORE `mv`
- Result: File in both locations, script restarts, re-copies → duplicates

**Fix (atomic move with verification):**
```bash
# Copy first
if ! cp -p "$plan" "$CODE_DIR/$project/.claude/plans/"; then
  echo "ERROR: Failed to copy $plan" >&2
  exit 1
fi

# Verify copy (checksum match)
SRC_MD5=$(md5sum "$plan" | awk '{print $1}')
DST_MD5=$(md5sum "$CODE_DIR/$project/.claude/plans/$(basename "$plan")" | awk '{print $1}')

if [[ "$SRC_MD5" != "$DST_MD5" ]]; then
  echo "ERROR: Checksum mismatch for $plan" >&2
  rm "$CODE_DIR/$project/.claude/plans/$(basename "$plan")"  # Cleanup bad copy
  exit 1
fi

# Only then move original
mv "$plan" "$GLOBAL_CLAUDE/plans/.migrated/"
```

**Better: Use transaction log:**
```bash
MIGRATION_LOG="$GLOBAL_CLAUDE/.migration.log"

# Record each step
echo "COPY|$plan|$CODE_DIR/$project/.claude/plans/|$(date +%s)" >> "$MIGRATION_LOG"
cp -p ...
echo "VERIFY|$plan|$SRC_MD5|$DST_MD5|$(date +%s)" >> "$MIGRATION_LOG"
# etc.

# If script crashes, can resume from log
```

---

## 4. Migration Script Robustness

### Auto-Classification Brittleness

**Lines 452-463:** Grep-based classification

```bash
if grep -q "slack-mcp\|edge.go" "$plan"; then
    echo "slack-mcp-server"
elif grep -q "deploy.sh\|install.sh\|zshrc" "$plan"; then
    echo "dotfiles"
```

**Problems:**

1. **False positives:**
   - Plan mentions "similar to deploy.sh in X project" → classified as dotfiles
   - Research plan quotes Slack API code → classified as slack-mcp

2. **Outdated signatures:**
   - Project renamed → grep patterns no longer match
   - New projects not in patterns → everything "UNKNOWN"

3. **No confidence scoring:**
   - Weak match (1 keyword) same as strong match (10 keywords)

**Improved approach:**
```bash
classify_plan() {
  local plan="$1"
  local content=$(cat "$plan")

  # Score each project (0-100)
  local slack_score=0
  local dotfiles_score=0
  local research_score=0

  # Slack indicators
  [[ "$content" =~ slack-mcp ]] && ((slack_score+=30))
  [[ "$content" =~ edge\.go|channel_id|conversations ]] && ((slack_score+=20))
  grep -q "MCP server" "$plan" && ((slack_score+=10))

  # Dotfiles indicators
  [[ "$content" =~ deploy\.sh|install\.sh ]] && ((dotfiles_score+=30))
  [[ "$content" =~ zshrc|tmux\.conf|p10k ]] && ((dotfiles_score+=20))

  # Research indicators
  [[ "$content" =~ GPQA|MATH|sandbagging ]] && ((research_score+=40))
  [[ "$content" =~ experiment|eval|baseline ]] && ((research_score+=15))

  # Classify by highest score
  if [[ $slack_score -gt $dotfiles_score && $slack_score -gt $research_score && $slack_score -ge 30 ]]; then
    echo "slack-mcp-server|$slack_score"
  elif [[ $dotfiles_score -gt $research_score && $dotfiles_score -ge 30 ]]; then
    echo "dotfiles|$dotfiles_score"
  elif [[ $research_score -ge 30 ]]; then
    echo "articulating-learned-rules|$research_score"
  else
    echo "UNKNOWN|0"
  fi
}

# Usage
result=$(classify_plan "$plan")
project="${result%|*}"
confidence="${result#*|}"

if [[ "$project" == "UNKNOWN" || $confidence -lt 30 ]]; then
  # Show context for manual classification
  echo "========================================"
  echo "File: $(basename "$plan")"
  echo "Confidence: $confidence (low)"
  echo "First 10 lines:"
  head -10 "$plan"
  echo "========================================"
  read -p "Project (research/dotfiles/slack/other): " manual_project
  project="$manual_project"
fi
```

### Interactive Classification UX Issues

**Lines 475-477:**
```bash
echo "Classify manually (research/dotfiles/slack/other):"
read -r project
```

**Problems:**

1. **No validation:** User types "reserch" (typo) → creates `~/code/reserch/` directory
2. **No preview:** User can't see plan content to make informed decision
3. **No undo:** Wrong classification requires manual fixing
4. **Batch fatigue:** 83 plans × manual review = tedious

**Better UX:**
```bash
# Show plan preview with fzf
classify_interactive() {
  local plan="$1"

  # Generate preview
  local preview="File: $(basename "$plan")\n"
  preview+="Size: $(wc -l < "$plan") lines\n"
  preview+="Modified: $(stat -f %Sm "$plan")\n"
  preview+="\nFirst 20 lines:\n"
  preview+="$(head -20 "$plan")\n"

  # Use fzf for selection (if available)
  if command -v fzf >/dev/null; then
    echo "articulating-learned-rules
dotfiles
slack-mcp-server
VoiceInk
w2sg
[skip - classify later]" | \
      fzf --prompt="Project for $(basename "$plan"): " \
          --preview="echo '$preview'" \
          --preview-window=right:70%
  else
    # Fallback to plain read
    echo "$preview"
    read -p "Project: " project
    echo "$project"
  fi
}
```

### Rollback Plan Incompleteness

**Lines 602-620:** Rollback instructions

**Missing scenarios:**

1. **Partial migration:** Script crashes halfway → some plans moved, some not → how to resume?
2. **Modified files:** User edits migrated plan before discovering issue → `mv .migrated/* back` loses changes
3. **Concurrent work:** User creates new plan during migration → gets clobbered by restore
4. **Timestamp conflicts:** `.migrated/` preserves mtime, but restore clobbers newer files

**Robust rollback:**
```bash
# Include rollback capability in migration script itself
MIGRATION_STATE="$GLOBAL_CLAUDE/.migration_state.json"

rollback() {
  if [[ ! -f "$MIGRATION_STATE" ]]; then
    echo "No migration to rollback"
    exit 1
  fi

  # Parse state file for operations to reverse
  jq -r '.operations[] | select(.status=="completed") |
    "\(.src_path)|\(.dst_path)"' "$MIGRATION_STATE" | \
  while IFS='|' read -r src dst; do
    # Check if destination was modified since migration
    if [[ -f "$dst" ]]; then
      DST_MTIME=$(stat -f %m "$dst")
      MIGRATION_TIME=$(jq -r '.timestamp' "$MIGRATION_STATE")

      if [[ $DST_MTIME -gt $MIGRATION_TIME ]]; then
        echo "WARN: $dst was modified after migration, keeping both"
        mv "$dst" "${dst}.post-migration"
      else
        rm "$dst"  # Safe to remove unchanged copy
      fi
    fi

    # Restore original
    if [[ -f "${src}.migrated" ]]; then
      mv "${src}.migrated" "$src"
    fi
  done

  rm "$MIGRATION_STATE"
  echo "Rollback complete"
}

# Add trap to handle Ctrl+C
trap rollback EXIT
```

---

## 5. Cost Optimization

### Gemini Pricing Assumptions

**Line 193:** "~$0.01 per session (Gemini pricing)"

**Needs verification:**

1. **Which Gemini model?** (Pricing varies 10x: Flash vs Pro)
2. **Input context size?** Staging files could be 1K-50K tokens
3. **Batch vs streaming?** Affects throughput pricing
4. **Rate limits?** Free tier has tight quotas

**Actual Gemini pricing (as of Jan 2025):**
- Gemini 1.5 Flash: $0.075 / 1M input tokens, $0.30 / 1M output
- Gemini 1.5 Pro: $1.25 / 1M input tokens, $5 / 1M output

**Cost calculation:**
```
Assume: 50 staging entries × 200 tokens each = 10K input tokens
Output: ~2K tokens (summaries)

Flash: (10K × $0.075 / 1M) + (2K × $0.30 / 1M) = $0.00075 + $0.0006 = $0.00135 (~$0.001)
Pro:   (10K × $1.25 / 1M) + (2K × $5 / 1M) = $0.0125 + $0.01 = $0.0225 (~$0.02)
```

**Reality:** $0.001-$0.02 per session, not $0.01

**Hidden costs not accounted for:**

1. **Embedding costs** (if `/memory-search` uses semantic search):
   - Embedding API calls for each staging entry
   - Flash embedding: $0.037 / 1M tokens
   - 100 entries × 200 tokens × $0.037/1M = $0.00074 each time

2. **Re-embedding on updates:**
   - Adding to curated memory → need to re-embed that file
   - If done per-session instead of batched → multiplies cost

3. **Search query costs:**
   - Every `/memory-search` → embed query + fetch results
   - Heavy users could do 10+ searches/session

**Recommendation:**
```bash
# In /memory-summarize skill, show cost estimate
estimate_cost() {
  local input_tokens=$(wc -w staging/*.md | awk '{sum+=$1} END {print sum*1.3}')  # words → tokens
  local estimated_cost=$(echo "$input_tokens * 0.075 / 1000000 * 1.5" | bc -l)  # Flash + buffer

  printf "Estimated cost: \$%.4f (%d input tokens)\n" "$estimated_cost" "$input_tokens"
  read -p "Proceed? (y/n): " confirm
}
```

### Free Tier Rate Limit Risks

**Not mentioned in plan:** Gemini Flash free tier limits

**Actual limits (Google AI Studio free tier):**
- 15 requests/minute
- 1M tokens/minute
- 1500 requests/day

**Failure scenario:**
1. User runs `/memory-summarize` on month of staging (1000 entries)
2. Script sends all to Gemini in one request (50K tokens)
3. Exceeds rate limit → request fails
4. No retry logic → user gets error, tries again → hits daily limit
5. System unusable for rest of day

**Fix (chunking + retry):**
```bash
summarize_with_gemini() {
  local staging_files=("$@")
  local chunk_size=10  # Process 10 entries at a time

  for ((i=0; i<${#staging_files[@]}; i+=chunk_size)); do
    local chunk=("${staging_files[@]:i:chunk_size}")
    local attempt=0
    local max_attempts=3

    while [[ $attempt -lt $max_attempts ]]; do
      if gemini-cli summarize "${chunk[@]}" --model=flash; then
        break
      else
        ((attempt++))
        echo "Rate limit hit, waiting 60s (attempt $attempt/$max_attempts)..."
        sleep 60
      fi
    done

    # Rate limit: 15 req/min → sleep 4s between chunks
    sleep 4
  done
}
```

---

## 6. Verification Steps

### Insufficient Negative Testing

**Lines 546-596:** Verification steps only test happy path

**Missing:**

1. **Concurrent session testing:**
   - Start 2 Claude sessions simultaneously
   - End both at same time
   - Check staging for corruption/duplicates

2. **Partial file testing:**
   - Corrupt history.jsonl (truncate last line)
   - Run session_end.sh
   - Verify graceful failure, not crash

3. **Permission testing:**
   - Make `.memory/staging/` read-only
   - End session
   - Verify error message, not silent failure

4. **Large file testing:**
   - Session with 10K messages (huge history.jsonl)
   - Check if jq/grep timeout
   - Verify memory usage doesn't explode

5. **Migration edge cases:**
   - Plan with same name in 2 projects
   - Plan with special characters in filename
   - Empty plans (0 bytes)
   - Symlinks in plans/ directory

**Recommended test suite:**
```bash
# tests/test_memory_system.sh

test_concurrent_capture() {
  # Simulate 2 sessions ending at once
  session_end.sh session1 &
  session_end.sh session2 &
  wait

  # Check for corruption
  local staging_file="$(date -u +%Y-%m-%d)_research.md"
  if grep -q "Session.*Session" "$staging_file"; then
    echo "FAIL: Interleaved writes detected"
    return 1
  fi
}

test_corrupted_history() {
  # Truncate history.jsonl mid-line
  head -c -50 "$HOME/.claude/history.jsonl" > /tmp/bad_history.jsonl
  mv /tmp/bad_history.jsonl "$HOME/.claude/history.jsonl"

  # Should not crash
  if session_end.sh test_session 2>&1 | grep -q "ERROR"; then
    echo "PASS: Graceful error handling"
  else
    echo "FAIL: Should report error on corrupt file"
    return 1
  fi
}

test_disk_full() {
  # Fill disk (use small loop device for testing)
  # ... setup ...

  session_end.sh test_session

  # Should alert user, not silently fail
  if [[ -f "$HOME/.claude/.memory/.errors" ]]; then
    echo "PASS: Error logged"
  else
    echo "FAIL: No error notification"
    return 1
  fi
}
```

### No Performance Benchmarks

**Missing:** What's acceptable performance?

- `/memory-search` on 100 files: 2s? 10s? 30s?
- `session_end.sh` with 1K message history: 5s? 20s? 60s?
- `/memory-summarize` on month of staging: 1min? 5min?

**Recommendation:**
```bash
# Verification step 6: Performance benchmarks
benchmark_memory_system() {
  echo "Testing memory search performance..."

  # Generate 100 dummy memory files
  for i in {1..100}; do
    echo "Sample content $i batch_size=50 experiment gotcha" > \
      ~/.claude/.memory/research/test_$i.md
  done

  # Time search
  start=$(date +%s)
  /memory-search "batch size" > /dev/null
  end=$(date +%s)
  duration=$((end - start))

  if [[ $duration -gt 5 ]]; then
    echo "WARN: Search took ${duration}s (expected <5s)"
  else
    echo "PASS: Search completed in ${duration}s"
  fi

  # Cleanup
  rm ~/.claude/.memory/research/test_*.md
}
```

---

## Summary of Critical Issues

### Must Fix Before Implementation:

1. **Race condition in session_end.sh** → Add file locking
2. **history.jsonl parsing** → Handle incomplete JSON gracefully
3. **Git tracking conflicts** → Update per-project .gitignore properly
4. **Migration data loss risk** → Add checksum verification
5. **Cost estimation** → Clarify Gemini model and actual pricing
6. **Rollback plan** → Add transaction log and resume capability

### Should Fix for Robustness:

7. **Pattern matching quality** → Extract full sentences, not fragments
8. **Mode detection** → Implement scoring-based classification
9. **Auto-classification** → Add confidence scoring and better UX
10. **Rate limiting** → Handle Gemini quotas with chunking + retry
11. **Error handling** → Add validation and meaningful error messages
12. **Performance benchmarks** → Set and verify acceptable latency

### Nice to Have:

13. **Negative testing** → Test failure modes, not just happy path
14. **Monitoring** → Track memory system health (capture rate, review frequency)
15. **Gradual rollout** → Feature flag for alpha testing before full deployment

---

## Specific Code Recommendations

### 1. Robust session_end.sh

```bash
#!/bin/bash
set -euo pipefail

# Validate environment
[[ -z "${HOME:-}" ]] && exit 1
[[ "$CLAUDE_MEMORY_DISABLE" == "1" ]] && exit 0
[[ "$CLAUDE_MEMORY_AUTO_CAPTURE" == "0" ]] && exit 0

MEMORY_DIR="$HOME/.claude/.memory"
[[ ! -d "$MEMORY_DIR" ]] && exit 0

HISTORY_FILE="$HOME/.claude/history.jsonl"
[[ ! -f "$HISTORY_FILE" ]] && exit 0

# Wait for history.jsonl to be released (max 5s)
for i in {1..50}; do
  lsof "$HISTORY_FILE" >/dev/null 2>&1 || break
  sleep 0.1
done

# Extract with error handling (ignore incomplete last line)
INSIGHTS=$(
  head -c -1 "$HISTORY_FILE" 2>/dev/null | \
  jq -r 'select(type == "object") | .messages[]? | select(.role=="assistant") | .content' 2>/dev/null | \
  grep -P "([^.!?]*(?:decided|optimal|watch out|batch_size)[^.!?]*[.!?])" | \
  head -10 || true
)

if [[ -z "$INSIGHTS" ]]; then
  exit 0  # No insights, nothing to do
fi

# Detect mode (basic implementation)
MODE="research"  # Default
if echo "$INSIGHTS" | grep -qiE "paper|draft|section|citation"; then
  MODE="writing"
elif echo "$INSIGHTS" | grep -qiE "function|class|import|debug|error"; then
  MODE="code"
fi

# Atomic write with locking
LOCK_FILE="$MEMORY_DIR/staging/.lock"
TIMESTAMP=$(date -u +%Y-%m-%d)
SESSION_TIME=$(date -u +%H:%M:%S)

(
  flock -x -w 5 200 || exit 1  # 5s timeout on lock

  STAGING_FILE="$MEMORY_DIR/staging/${TIMESTAMP}_${MODE}.md"

  {
    echo "## Session $SESSION_TIME UTC - Auto-captured"
    echo ""
    echo "$INSIGHTS"
    echo ""
  } >> "$STAGING_FILE"

) 200>"$LOCK_FILE"

# Success notification (only if insights captured)
echo "Memory captured: staging/${TIMESTAMP}_${MODE}.md"
```

### 2. Migration with transaction log

```bash
#!/usr/bin/env bash
set -euo pipefail

GLOBAL_CLAUDE="$HOME/.claude"
MIGRATION_LOG="$GLOBAL_CLAUDE/.migration.log"
MIGRATION_STATE="$GLOBAL_CLAUDE/.migration_state.json"

# Initialize state
cat > "$MIGRATION_STATE" <<EOF
{
  "timestamp": $(date +%s),
  "operations": []
}
EOF

migrate_plan() {
  local plan="$1"
  local project="$2"
  local dst_path="$HOME/code/$project/.claude/plans/$(basename "$plan")"

  # Log intent
  jq ".operations += [{
    \"type\": \"migrate_plan\",
    \"src\": \"$plan\",
    \"dst\": \"$dst_path\",
    \"status\": \"pending\"
  }]" "$MIGRATION_STATE" > "$MIGRATION_STATE.tmp"
  mv "$MIGRATION_STATE.tmp" "$MIGRATION_STATE"

  # Execute migration
  mkdir -p "$(dirname "$dst_path")"
  cp -p "$plan" "$dst_path"

  # Verify checksum
  local src_md5=$(md5sum "$plan" | awk '{print $1}')
  local dst_md5=$(md5sum "$dst_path" | awk '{print $1}')

  if [[ "$src_md5" != "$dst_md5" ]]; then
    echo "ERROR: Checksum mismatch for $plan" >&2
    jq "(.operations[] | select(.src == \"$plan\")).status = \"failed\"" \
      "$MIGRATION_STATE" > "$MIGRATION_STATE.tmp"
    mv "$MIGRATION_STATE.tmp" "$MIGRATION_STATE"
    exit 1
  fi

  # Move original to .migrated
  mv "$plan" "${plan}.migrated"

  # Update state
  jq "(.operations[] | select(.src == \"$plan\")).status = \"completed\"" \
    "$MIGRATION_STATE" > "$MIGRATION_STATE.tmp"
  mv "$MIGRATION_STATE.tmp" "$MIGRATION_STATE"

  echo "Migrated: $(basename "$plan") → $project"
}

# ... rest of migration logic ...
```

### 3. Cost estimation in /memory-summarize

```bash
#!/bin/bash
# In memory-summarize skill implementation

estimate_gemini_cost() {
  local staging_files=("$@")

  # Count tokens (rough: 1 word ≈ 1.3 tokens)
  local total_words=$(cat "${staging_files[@]}" | wc -w)
  local input_tokens=$((total_words * 13 / 10))

  # Gemini Flash pricing (per 1M tokens)
  local input_price=0.000075  # $0.075 / 1M
  local output_price=0.0003   # $0.30 / 1M (assume 20% output ratio)

  local cost=$(echo "scale=6; $input_tokens * $input_price + $input_tokens * 0.2 * $output_price" | bc)

  printf "Estimated cost: \$%.4f (%d tokens)\n" "$cost" "$input_tokens"

  if (( $(echo "$cost > 0.05" | bc -l) )); then
    echo "⚠️  High cost detected. Consider chunking or using Flash model."
    read -p "Continue? (y/n): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
  fi
}
```

---

## Questions for User

Before implementing, clarify:

1. **Hook trigger mechanism:** How are `session_end.sh` hooks actually invoked? (Check Claude Code docs/source)
2. **Gemini model choice:** Flash or Pro for `/memory-summarize`? (10x cost difference)
3. **Migration dry run:** Should migration script have `--dry-run` flag to preview classification?
4. **Active task lists:** Any `CLAUDE_CODE_TASK_LIST_ID` currently set that needs special handling?
5. **Cross-project plans:** Any plans that legitimately span multiple projects? How to handle?
6. **Performance targets:** What's acceptable latency for `/memory-search` on 100+ files?

