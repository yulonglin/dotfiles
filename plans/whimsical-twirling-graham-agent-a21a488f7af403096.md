# Ghostty Terminal Mode Reset on Child Exit — Source Analysis

## Summary

Research into the Ghostty (ghostty-org/ghostty) Zig codebase to understand terminal mode management, RIS implementation, child process exit detection, and where to add auto-reset logic when a child process exits abnormally.

---

## 1. Terminal Modes: Where They're Defined and Managed

### `src/terminal/modes.zig` — Mode Definitions & State

The central mode system. Defines **41 terminal modes** as a compile-time-generated `Mode` enum backed by `u16` tags:

**Key modes for this analysis:**
| Mode | Value | Category |
|------|-------|----------|
| `mouse_event_normal` | 1000 | DEC (mouse click tracking) |
| `mouse_event_button` | 1002 | DEC (button-motion tracking) |
| `mouse_event_any` | 1003 | DEC (any-event tracking) |
| `mouse_format_sgr` | 1006 | DEC (SGR extended mouse format) |
| `bracketed_paste` | 2004 | DEC |
| `cursor_visible` | 25 | DEC (default: true) |
| `disable_keyboard` | 2 | ANSI |

**`ModeState` struct** — holds all mode state:
- `.values: ModePacked` — current mode values (packed struct of bools)
- `.default: ModePacked` — initial/default values for reset
- `.saved: ModePacked` — single-level save for XTSAVE/XTRESTORE

**Key methods:**
- `set(mode, bool)` — set a single mode
- `get(mode) -> bool` — query a mode
- `save(mode)` / `restore(mode)` — XTSAVE/XTRESTORE
- **`reset()`** — `self.values = self.default; self.saved = .{};` — restores ALL modes to defaults and clears saved state

### `src/terminal/Terminal.zig` — Terminal State Owner

The `Terminal` struct owns the `modes: ModeState` field. Initialized from `Options.default_modes`:
```zig
.modes = .{
    .values = opts.default_modes,
    .default = opts.default_modes,
},
```

Also owns `Options.default_modes: ModePacked` — the baseline for resets.

**`fullReset()`** — the RIS implementation. While I couldn't retrieve the complete body (file is ~6000+ lines, truncated by WebFetch), from the stream handler and modes.zig we can infer it calls at minimum:
- `self.modes.reset()` — restores all modes to defaults
- Likely also: clears screen, resets charset, resets cursor position, resets tabstops, resets colors, etc.

### `src/termio/stream_handler.zig` — Mode Dispatch

Bridges the VT parser to terminal state. Key functions:

**`setMode(mode, enabled)`** — handles `CSI ? <n> h/l`:
- Sets `self.terminal.modes.set(mode, enabled)`
- Then processes side effects per mode (e.g., mouse modes update `terminal.flags.mouse_event`, alt screen modes swap screen buffers, etc.)

**`fullReset()`** — handles `ESC c` (RIS):
```zig
pub fn fullReset(self: *StreamHandler) !void {
    self.terminal.fullReset();
    try self.setMouseShape(.text);
    self.messageWriter(.{ .color_scheme_report = .{ .force = false } });
    self.progressReport(.{ .state = .remove });
}
```

### `src/terminal/stream.zig` — VT Parser Dispatch

Dispatches parsed escape sequences to handler functions:

**RIS dispatch** (in `escDispatch`):
```zig
'c' => switch (action.intermediates.len) {
    0 => try self.handler.vt(.full_reset, {}),
    // ...
},
```

**Mode set/reset** (in `csiDispatch`, for `h`/`l` final chars):
- Converts `?` intermediate to DEC mode flag
- Calls `modes.modeFromInt(param, is_ansi)` to get the Mode enum
- Dispatches via `self.handler.vt(.set_mode, .{ .mode = mode })`

**DECSTR (CSI ! p)** — **NOT IMPLEMENTED**. The `p` final handler only recognizes `$` and `?$` intermediates (DECRQM), not `!` (DECSTR).

---

## 2. RIS (Reset to Initial State) Implementation

### Dispatch Path
```
ESC c  →  stream.zig:escDispatch('c')
       →  handler.vt(.full_reset, {})
       →  stream_handler.zig:fullReset()
       →  terminal.fullReset()       // resets all terminal state
       →  setMouseShape(.text)       // reset mouse cursor
       →  color_scheme_report        // re-report colors
       →  progress remove            // clear progress bar
```

### `Terminal.fullReset()` (inferred from modes.zig)
At minimum calls `self.modes.reset()` which does:
```zig
self.values = self.default;
self.saved = .{};
```
This resets ALL 41 modes to their compiled defaults (e.g., `cursor_visible=true`, `wraparound=true`, all mouse modes=false, `bracketed_paste=false`).

---

## 3. Child Process Exit Detection

### Architecture: 3-Layer Message Flow

```
Exec.zig (PTY/process)  →  Surface.zig (UI)  →  Terminal state
     ↓                          ↓
  xev event loop            message handler
  detects exit              updates display
```

### `src/termio/Exec.zig` — Process Layer

**Process watching** — uses `xev.Process` (async event loop, NOT SIGCHLD signals):
```zig
process.wait(loop, &process_wait_c, ThreadData, td, processExit);
```

**Exit callback chain:**
```
processExit()  →  processExitCommon(td, exit_code)
```

**`processExitCommon()`:**
```zig
fn processExitCommon(td: *termio.Termio.ThreadData, exit_code: u32) void {
    td.backend.exec.exited = true;
    // calculate runtime_ms from start time
    td.surface_mailbox.push(.{
        .child_exited = .{ .exit_code = exit_code, .runtime_ms = runtime_ms }
    }, .{ .forever = {} });
}
```

Sends `child_exited` message to the **surface mailbox** (not to termio — this goes directly to the UI layer).

### `src/apprt/surface.zig` — Message Definition
```zig
pub const ChildExited = extern struct {
    exit_code: u32,
    runtime_ms: u64,
};
```

### `src/Surface.zig` — Exit Handler (UI Layer)

**`childExited(info: ChildExited)`** — main handler:

1. Sets `self.child_exited = true`
2. **Abnormal exit detection**: `info.runtime_ms <= config.abnormal_command_exit_runtime_ms`
   - On non-macOS: also checks `exit_code == 0` (good exit skips abnormal path)
   - Abnormal: tries native GUI notification, falls back to `childExitedAbnormally()`
3. **Normal exit path**: displays "Process exited. Press any key to close."
4. **Limited mode resets (current state):**
   ```zig
   t.modes.set(.cursor_visible, false);    // hide cursor
   t.modes.set(.disable_keyboard, false);  // re-enable keyboard
   t.screens.active.kitty_keyboard.set(.set, .disabled);  // disable kitty protocol
   ```
5. If `wait_after_command` is false, calls `self.close()`

**`childExitedAbnormally(info)`** — error display:
- Resets styles, draws horizontal rule, shows red error with command/exit code/runtime
- Sets `cursor_visible = false`
- Does NOT reset keyboard modes (bug? or intentional since it also waits for keypress?)

---

## 4. DECSTR (Soft Reset) — Current State

**DECSTR is NOT implemented in Ghostty.** Specifically:
- `stream.zig` dispatches CSI `p` only for `$` intermediate (DECRQM), not `!` intermediate (DECSTR)
- No `softReset` function exists in `Terminal.zig` or `stream_handler.zig`
- No soft reset handler is registered

This means there's no existing soft reset to "reuse" — it would need to be implemented from scratch.

---

## 5. Where to Insert Auto-Reset Logic

### Option A: Extend `Surface.childExited()` (Simplest, Recommended)

**File:** `src/Surface.zig`, function `childExited()`

Currently it only resets 3 things. Expand to reset the critical modes that cause terminal corruption:

```zig
// After acquiring renderer_state.mutex and getting terminal t:

// Reset modes that commonly cause terminal corruption after abnormal exit
t.modes.set(.mouse_event_normal, false);   // 1000
t.modes.set(.mouse_event_button, false);   // 1002
t.modes.set(.mouse_event_any, false);      // 1003
t.modes.set(.mouse_format_sgr, false);     // 1006
t.modes.set(.bracketed_paste, false);      // 2004
t.modes.set(.cursor_visible, true);        // 25 — show cursor (currently sets false!)
t.modes.set(.disable_keyboard, false);     // 2 (already done)

// Also reset kitty keyboard (already done)
t.screens.active.kitty_keyboard.set(.set, .disabled);
```

**Pros:** Minimal change, targeted, no new API surface.
**Cons:** Manual list of modes to reset — could miss new modes added later.

### Option B: Use `modes.reset()` in `childExited()` (More Thorough)

```zig
t.modes.reset();  // Restore ALL modes to defaults
```

**Pros:** Comprehensive, future-proof (new modes automatically included).
**Cons:** Resets modes like `wraparound` and `autorepeat` that should stay on — but since `reset()` restores *defaults* (which have these enabled), this is actually correct.

### Option C: Implement DECSTR + Use It

**Three files to modify:**

1. **`src/terminal/stream.zig`** — Add DECSTR dispatch:
   ```zig
   // In csiDispatch, 'p' case:
   'p' => switch (action.intermediates) {
       "!" => try self.handler.vt(.soft_reset, {}),  // DECSTR
       "$" => // existing DECRQM...
   }
   ```

2. **`src/terminal/Terminal.zig`** — Add `softReset()`:
   Per VT220 spec, DECSTR resets: insert mode, origin mode, wraparound, cursor visibility, keyboard action mode, character sets, SGR, DECSCA, DECCKM, and more — but NOT alt screen, NOT scrollback, NOT screen content.
   ```zig
   pub fn softReset(self: *Terminal) void {
       self.modes.set(.insert, false);
       self.modes.set(.origin, false);
       // ... targeted mode resets per DECSTR spec
       // Reset mouse modes, bracketed paste
       self.modes.set(.mouse_event_normal, false);
       self.modes.set(.mouse_event_button, false);
       self.modes.set(.mouse_event_any, false);
       self.modes.set(.mouse_format_sgr, false);
       self.modes.set(.bracketed_paste, false);
       self.modes.set(.cursor_visible, true);
       // Reset SGR attributes
       self.setAttribute(.{ .unset = {} });
       // Reset charset
       // Reset saved cursor
   }
   ```

3. **`src/termio/stream_handler.zig`** — Add handler:
   ```zig
   pub fn softReset(self: *StreamHandler) !void {
       self.terminal.softReset();
       try self.setMouseShape(.text);
   }
   ```

4. **`src/Surface.zig`** — Call on child exit:
   ```zig
   // In childExited, after abnormal exit detection:
   t.softReset();
   ```

**Pros:** Standards-compliant, reusable for applications sending DECSTR.
**Cons:** More code, need to get DECSTR spec exactly right, may have unintended side effects.

### Recommendation

**Option A for immediate fix, Option C for the proper long-term solution.**

Option A can be done in `Surface.childExited()` with ~10 lines of additional mode resets. This fixes the immediate problem (mouse tracking, bracketed paste persisting after crash).

Option C (DECSTR implementation) is the right architecture long-term but requires careful spec compliance and testing.

For both options, the reset should happen:
- **On ALL exits** (not just abnormal) when a new shell will be spawned
- **Before displaying the exit message** (so the terminal is in a clean state)
- **Under the renderer mutex** (already the case in `childExited`)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    src/terminal/                         │
│  modes.zig ── ModeState { values, default, saved }      │
│       │        .set() .get() .reset() .save() .restore()│
│       │                                                 │
│  Terminal.zig ── owns modes: ModeState                  │
│       │          fullReset() calls modes.reset()        │
│       │          (softReset() — NOT YET IMPLEMENTED)    │
│       │                                                 │
│  stream.zig ── VT parser dispatch                       │
│       │        ESC c → .full_reset                      │
│       │        CSI ? N h/l → .set_mode / .reset_mode    │
│       │        CSI ! p → (NOT HANDLED — DECSTR gap)     │
└───────┼─────────────────────────────────────────────────┘
        │
┌───────┼─────────────────────────────────────────────────┐
│       │           src/termio/                            │
│  stream_handler.zig ── fullReset() { t.fullReset() }    │
│       │                setMode() { t.modes.set() + fx } │
│       │                                                 │
│  Exec.zig ── PTY management, process lifecycle          │
│       │      xev.Process.wait() → processExit()         │
│       │      processExitCommon() → surface_mailbox.push │
│       │        .child_exited { exit_code, runtime_ms }  │
└───────┼─────────────────────────────────────────────────┘
        │
┌───────┼─────────────────────────────────────────────────┐
│       ▼           src/Surface.zig                       │
│  childExited(info) ←── surface mailbox                  │
│    ├─ abnormal? → childExitedAbnormally() → error msg   │
│    └─ normal → "Press any key to close"                 │
│    Both paths: cursor_visible=false, disable_keyboard=  │
│    false, kitty_keyboard=disabled                       │
│    *** MISSING: mouse mode reset, bracketed paste ***   │
│    *** MISSING: modes.reset() or softReset() call ***   │
└─────────────────────────────────────────────────────────┘
```

## Key Files Summary

| File | Role | Key Functions |
|------|------|--------------|
| `src/terminal/modes.zig` | Mode definitions + state machine | `ModeState.reset()`, `set()`, `get()` |
| `src/terminal/Terminal.zig` | Terminal state owner | `fullReset()` (RIS), modes field |
| `src/terminal/stream.zig` | VT escape sequence parser/dispatch | `escDispatch()` (RIS), `csiDispatch()` (modes) |
| `src/termio/stream_handler.zig` | Parser-to-terminal bridge | `fullReset()`, `setMode()` |
| `src/termio/Exec.zig` | PTY + process lifecycle | `processExitCommon()` → sends child_exited |
| `src/apprt/surface.zig` | Message type definitions | `ChildExited { exit_code, runtime_ms }` |
| `src/Surface.zig` | UI layer, exit handling | `childExited()`, `childExitedAbnormally()` |
