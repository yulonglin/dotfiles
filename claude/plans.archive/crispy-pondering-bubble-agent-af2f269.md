# Plan: Simplify clear-claude-code Script

## Overview
Simplify `custom_bins/clear-claude-code` for improved clarity and maintainability while preserving all functionality.

## Current Complexity Analysis

### 1. `is_orphaned()` Function (Lines 162-202)
**Current state:** 5 checks with overlapping logic and redundant comments

**Issues:**
- Check 4 (grandparent=1) and Check 5 (login shell + grandparent=1) are redundant
- Check 5 is impossible to trigger because Check 4 already returns when grandparent=1
- Comments explain WHAT each check does, but not WHY we need all these checks

**Simplification:**
1. Remove Check 5 (unreachable code - Check 4 covers this)
2. Consolidate to 4 clear checks with better comments explaining the orphan detection strategy
3. Add a header comment explaining the progressive fallback approach

### 2. `get_process_status()` Function (Lines 232-334)
**Current state:** Complex branching with CPU/age thresholds, 3 different activity classifications

**Issues:**
- CPU thresholds change based on age (5% vs 20%, <1% vs ≥1%)
- "Active" determination spans 4 separate code paths (Rules 1, 3a, 3c, and default)
- TTY-based classification mixed with age-based classification
- Hard to see the decision tree at a glance

**Simplification:**
1. Extract CPU activity check to helper: `is_cpu_active(pid, age_hours)` - encapsulates the age-dependent thresholds
2. Extract foreground check logic to helper: `classify_foreground_process(pid, cpu_int)` - handles Rule 3's 3 branches
3. Reorder checks to match conceptual flow: fast exits first (tmux, stopped, zombie, orphaned) → activity checks → TTY checks
4. Add section comments marking each phase of classification

### 3. Diagnostic Output Section (Lines 428-458)
**Current state:** Orphaned process diagnostic loop with inline reason detection

**Issues:**
- Duplicates orphan detection logic from `is_orphaned()` (lines 445-454)
- Rebuilds information that was already computed
- Tightly couples display logic with detection logic

**Simplification:**
1. Extract reason detection to helper: `get_orphan_reason(pid, ppid)` - returns human-readable string
2. This can use `is_orphaned()` internally but adds the "why" explanation
3. Reduces duplication and makes diagnostic section focus on display

### 4. Child Process Killing (Lines 607-633)
**Current state:** Two-pass approach with tracking arrays

**Issues:**
- Logic is clear but could benefit from extracted helper
- Good structure, minimal changes needed

**Minor improvement:**
1. Extract to `kill_process_tree(pid)` helper - improves testability and reuse
2. Returns status (graceful/forceful/failed) for cleaner reporting

## Proposed Helper Functions

### New Helpers
```bash
# Determine if CPU usage indicates active work (age-dependent thresholds)
is_cpu_active() {
    local pid="$1" cpu_int="$2"
    # Recent (<12h): 5% threshold - likely user-initiated
    # Old (≥12h): 20% threshold - must be intentional work
    if ! is_process_old "$pid" $((12*60*60)); then
        (( cpu_int >= 5 ))
    else
        (( cpu_int >= 20 ))
    fi
}

# Classify foreground process based on age and CPU
classify_foreground_process() {
    local pid="$1" cpu_int="$2"
    # Recent (<1h) = actively in use regardless of CPU
    if ! is_process_old "$pid" $((60*60)); then
        echo "ACTIVE"
        return
    fi
    # Old (≥1h) with low CPU = abandoned
    if (( cpu_int < 1 )); then
        echo "IDLE"
        return
    fi
    # Old with meaningful CPU = still working
    echo "ACTIVE"
}

# Explain why a process is considered orphaned
get_orphan_reason() {
    local pid="$1"
    local ppid=$(ps_field "$pid" "ppid")
    [[ -z "$ppid" ]] && { echo "no parent found"; return; }

    if [[ "$ppid" == "1" ]]; then
        echo "parent reparented to init"
    elif ! ps -p "$ppid" >/dev/null 2>&1; then
        echo "parent no longer exists"
    elif [[ "$(ps_field "$ppid" "stat")" == *"Z"* ]]; then
        echo "parent is zombie"
    elif [[ "$(ps_field "$ppid" "ppid")" == "1" ]]; then
        echo "grandparent is init (indirect orphan)"
    else
        echo "unknown"
    fi
}

# Kill process and its children with graceful → forceful escalation
kill_process_tree() {
    local pid="$1"
    local result="graceful"

    # Kill children first, then parent (SIGTERM)
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    sleep 0.1

    # Check if survived, escalate to SIGKILL
    if ps -p "$pid" >/dev/null 2>&1; then
        pkill -9 -P "$pid" 2>/dev/null || true
        if kill -9 "$pid" 2>/dev/null; then
            result="forceful"
        else
            result="failed"
        fi
    fi

    echo "$result"
}
```

## Detailed Changes

### Phase 1: Simplify `is_orphaned()`
- Remove Check 5 (lines 192-198) - unreachable code
- Update Check 4 comment to explain it catches indirect orphans
- Add function header explaining the progressive detection strategy

### Phase 2: Refactor `get_process_status()`
- Extract `is_cpu_active()` helper (replaces lines 260-275)
- Extract `classify_foreground_process()` helper (replaces lines 300-316)
- Add phase comments: "Fast exits", "Activity checks", "TTY classification"
- Reorder: keep fast exits first, then activity, then TTY

### Phase 3: Simplify Diagnostic Output
- Replace inline reason detection (lines 445-454) with `get_orphan_reason()` call
- Keep display formatting, remove detection duplication

### Phase 4: Extract Process Killing Logic
- Replace two-pass killing (lines 607-633) with `kill_process_tree()` calls
- Simplified result aggregation using helper's return values

## Variable Naming Improvements

| Current | Improved | Why |
|---------|----------|-----|
| `proc_status` | `status` | Context makes "process" obvious |
| `cpu_int` | `cpu_pct` | Clearer it's percentage (integer part) |
| `IDLE_THRESHOLD_HOURS` | Keep | Clear as-is |
| `STALE_UNKNOWN_DAYS` | Keep | Clear as-is |

## Expected Benefits

1. **Reduced duplication**: Orphan reason detection in one place
2. **Clearer decision flow**: Activity checks isolated, TTY checks separate
3. **Better testability**: Helpers can be unit tested independently
4. **Easier maintenance**: Change CPU thresholds in one function
5. **No behavior changes**: All logic preserved, just reorganized

## Implementation Notes

- Maintain all existing flags and command-line interface
- Keep all safety checks (confirmation prompts, dry-run mode)
- Preserve error handling patterns
- No changes to output format or messages
- Verify with: test on processes in each state (active, orphaned, tmux, etc.)

## Success Criteria

- [ ] Script passes shellcheck with no new warnings
- [ ] All existing test cases work identically (status display, kill behavior)
- [ ] Functions are ≤30 lines each (target for readability)
- [ ] No duplicated orphan detection logic
- [ ] CPU activity threshold logic in single location
- [ ] Comments explain WHY not WHAT
