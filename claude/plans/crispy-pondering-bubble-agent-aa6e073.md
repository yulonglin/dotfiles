# Debug Plan: clear-claude-code Process 39507 Classification Issue

**Problem**: Process 39507 (1d 8h old, 0.7% CPU) shows as `*ACTIVE*` instead of `idle>=24h`

**Expected**: Rule 2 should catch this (age >= 24h AND CPU < 1% → IDLE)

## Root Cause Analysis

### Logic Flow in `get_process_status()` for PID 39507

Given:
- Age: 1d 8h = ~32h (> 24h threshold)
- CPU: 0.7% (< 1% threshold)
- Expected path: lines 278-282 → return "IDLE"

### Hypothesis Testing

**H1: Age check failing**
- `is_process_old("39507", "86400")` returns false somehow?
- Possible causes:
  - Regex parsing failure in `is_process_old()`
  - Octal interpretation still happening despite `10#` prefix
  - `ps etime` format unexpected

**H2: CPU check failing**
- `cpu_int` not being computed correctly
- `0.7%` → should extract `0` → `cpu_int=0` → `(( 0 < 1 ))` should be true

**H3: Early return before Rule 2**
- Process caught by tmux check (line 236)?
- Process caught by stopped check (line 242)?
- Process caught by zombie check (line 245)?
- Process caught by orphaned check (line 248-251)?
- Process caught by Rule 1 (lines 260-275)?

**H4: Logic after Rule 2**
- Process has TTY and is in foreground (`stat` contains `+`) → lines 300-316
- This would explain ACTIVE status

## Investigation Steps

1. **Check actual process state**:
   ```bash
   ps -p 39507 -o pid,etime,stat,tty,%cpu,ppid,comm
   ```

2. **Test age parsing**:
   ```bash
   etime=$(ps -p 39507 -o etime= | tr -d ' ')
   echo "etime: '$etime'"
   # Test regex matching manually
   ```

3. **Test CPU extraction**:
   ```bash
   cpu=$(ps -p 39507 -o %cpu=)
   echo "cpu: '$cpu'"
   cpu_int="10#${cpu%.*}"
   echo "cpu_int: $cpu_int"
   (( cpu_int < 1 )) && echo "PASS: cpu < 1%" || echo "FAIL: cpu >= 1%"
   ```

4. **Test orphan detection**:
   ```bash
   # Check parent chain
   ps -p 39507 -o pid,ppid,stat
   ppid=$(ps -p 39507 -o ppid= | tr -d ' ')
   ps -p $ppid -o pid,ppid,stat,comm
   ```

5. **Test tmux ancestry**:
   ```bash
   # Check parent chain for tmux
   pstree -p 39507  # or manual walk up ppid chain
   ```

6. **Add debug output**:
   - Insert `echo` statements in `get_process_status()` to trace execution
   - Show which branch is taken

## Most Likely Root Cause

**Prediction**: Process has `stat` containing `+` (foreground marker)

Looking at lines 300-316:
```bash
if [[ "$stat" == *"+"* ]]; then
    # Recent process (<1h) = likely actively in use
    if ! is_process_old "$pid" $((60*60)); then
        echo "ACTIVE"
        return
    fi

    # Old process (>=1h) with low CPU (<1%) = abandoned
    if (( cpu_int < 1 )); then
        echo "IDLE"
        return
    fi

    # Old process with meaningful CPU (>=1%) = still working
    echo "ACTIVE"
    return
fi
```

**Issue**: Lines 312-315 are UNREACHABLE if `cpu_int < 1`
- Line 302-305: Age < 1h → ACTIVE (early return)
- Line 307-310: Age >= 1h AND CPU < 1% → IDLE (early return)
- Line 313-315: Age >= 1h AND CPU >= 1% → ACTIVE

But wait... if age is 32h and CPU is 0.7%, we should hit line 307-310.

**Alternative prediction**: The `cpu_int` variable is not being set to 0 as expected.

### CPU Parsing Bug?

Lines 253-258:
```bash
local cpu=$(ps_field "$pid" "%cpu")
local cpu_int=0
if [[ -n "$cpu" && "${cpu%.*}" != "" ]]; then
    cpu_int="10#${cpu%.*}"  # Extract integer part
fi
```

If `cpu="0.7"`, then:
- `${cpu%.*}` = `"0"`
- Check: `"0" != ""` → TRUE
- Set: `cpu_int="10#0"` = `0`

This should work correctly.

**Wait... there's an issue with the condition!**

Line 256: `if [[ -n "$cpu" && "${cpu%.*}" != "" ]]; then`

If `cpu="0.7"`:
- `${cpu%.*}` = `"0"` (string)
- `"0" != ""` → TRUE ✓
- Sets `cpu_int=0` ✓

But if `cpu=" 0.7"` (with leading space):
- `${cpu%.*}` = `" 0"`
- `" 0" != ""` → TRUE
- `cpu_int="10# 0"` → **SYNTAX ERROR or unexpected behavior**

**Root cause found!**

The `ps_field()` function (line 87) uses `tr -d ' '` to strip spaces, so this shouldn't happen... but let's verify.

Actually, looking more carefully:

Line 87: `ps -p "$1" -o "$2=" 2>/dev/null | tr -d ' ' || echo ""`

This strips ALL spaces, so `" 0.7 "` becomes `"0.7"`. So that's not the issue.

## Real Issue: Foreground Status Check

**Most likely**: Process 39507 has `stat` containing `+`, triggering lines 300-316.

If the process is in foreground (`+` in stat), but:
- Age is > 1h (32h)
- CPU is 0.7% (< 1%)

Then lines 307-310 should trigger:
```bash
if (( cpu_int < 1 )); then
    echo "IDLE"
    return
fi
```

**BUT**: This requires `cpu_int` to be correctly computed as `0`.

Let me re-examine the integer extraction:
- `cpu="0.7"`
- `${cpu%.*}` removes everything after the last `.` → `"0"`
- `cpu_int="10#0"` → evaluates to `0` in arithmetic context

This should work!

**Alternative bug**: What if `cpu="0.7"` but `%cpu` field from `ps` shows more precision like `"0.70"` or `.7`?

If `cpu=".7"`:
- `${cpu%.*}` = `""` (empty string!)
- Check `"" != ""` → FALSE
- `cpu_int` remains `0` (initialized on line 255)
- Should still work!

## Actual Bug Found!

Looking at line 263:
```bash
if ! is_process_old "$pid" $((12*60*60)); then
```

**What if `is_process_old()` is returning the wrong value?**

Let me check the octal parsing fix in `is_process_old()`:

Lines 216-221 show proper `10#` prefixes for all arithmetic. That looks correct.

## Debug Strategy

Since this is plan mode, I'll document the exact debugging steps to take:

1. **Check actual stat flags**:
   ```bash
   ps -p 39507 -o stat=
   ```
   If it contains `+`, that's the smoking gun.

2. **Trace through logic manually**:
   ```bash
   # Extract all values
   pid=39507
   stat=$(ps -p $pid -o stat= | tr -d ' ')
   etime=$(ps -p $pid -o etime= | tr -d ' ')
   cpu=$(ps -p $pid -o %cpu= | tr -d ' ')

   echo "stat: $stat"
   echo "etime: $etime"
   echo "cpu: $cpu"

   # Check foreground
   [[ "$stat" == *"+"* ]] && echo "IS FOREGROUND" || echo "NOT FOREGROUND"
   ```

3. **Test cpu_int extraction**:
   ```bash
   cpu="0.7"
   cpu_int_part="${cpu%.*}"
   echo "cpu_int_part: '$cpu_int_part'"
   cpu_int="10#${cpu_int_part}"
   echo "cpu_int: $cpu_int"
   (( cpu_int < 1 )) && echo "< 1%" || echo ">= 1%"
   ```

4. **Verify Rule 2 is reached**:
   Add debug output before Rule 2:
   ```bash
   # Before line 278, add:
   echo "DEBUG: Checking Rule 2 for PID $pid" >&2
   echo "  Age check: is_process_old returns $?" >&2
   echo "  CPU check: cpu_int=$cpu_int" >&2
   ```

## Recommended Fix

Once we identify the exact branch being taken, we can fix it. Most likely scenarios:

**Scenario A**: Foreground process path (lines 300-316)
- Lines 307-310 should already handle this correctly
- But maybe there's an arithmetic expansion bug with `(( cpu_int < 1 ))`

**Scenario B**: Rule 2 not being reached
- Early return from tmux/orphaned/Rule 1
- Fix: investigate why early return happens

**Scenario C**: Bug in `is_process_old()` for 1d+ ages
- Regex not matching `1-08:23:45` format (DD-HH:MM:SS)
- Fix: verify regex on line 216

## Next Steps

1. Run diagnostic commands on PID 39507
2. Add debug output to script (trace execution)
3. Identify which branch returns "ACTIVE"
4. Fix the logic bug
5. Test on PID 39507 to verify fix
