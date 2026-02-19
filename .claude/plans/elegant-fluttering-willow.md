# Plan: claude-tools Iteration — Fix Context%, Add Duration, Update Bash Fallback

## Current Bug (confirmed)

Context% is **not displaying** in the statusline. Tested both the Rust binary and bash script — neither shows context% because both read from `transcript_path` JSONL (which may not exist or have data early in sessions). Meanwhile, `context_window.used_percentage` is already provided in the JSON input but **neither version uses it**. Cost works fine when > 0.

## Context

The initial Rust `claude-tools` binary is built and working (1ms vs 55ms statusline, 4ms vs 50ms context-apply). Steps 1-4 of the original plan are complete. Three issues to fix:

1. **Context% not showing** — code reads transcript JSONL file backwards, but `context_window.used_percentage` is provided directly in the statusline JSON input ([official docs](https://code.claude.com/docs/en/statusline)). The transcript approach was unnecessary complexity with bugs (UTF-8 seek issues, timing races).
2. **Duration not shown** — `cost.total_duration_ms` is available and useful for tracking session time.
3. **Bash fallback out of sync** — `claude/statusline.sh` still uses transcript reading; should use the same direct fields.

## Changes

### 1. Simplify statusline: use `context_window.used_percentage` directly

**In `tools/claude-tools/src/statusline.rs`:**

**Add structs:**
```rust
#[derive(Deserialize)]
struct ContextWindow {
    used_percentage: Option<f64>,  // serde deserializes JSON int to f64 fine
}
```

**Update `Input`:**
```rust
struct Input {
    workspace: Option<Workspace>,
    model: Option<Model>,
    cost: Option<Cost>,
    context_window: Option<ContextWindow>,  // replaces transcript_path
}
```

**Replace `format_context_usage`:**
```rust
fn format_context_usage(output: &mut String, context_window: Option<&ContextWindow>) {
    let pct = match context_window.and_then(|cw| cw.used_percentage) {
        Some(p) => p.round() as u64,  // .round() not truncate — 99.7 → 100, not 99
        None => return,               // null early in session — show nothing
    };
    if pct == 0 { return; }
    let color = if pct >= 90 { "\x1b[31m" }      // red
                else if pct >= 70 { "\x1b[33m" }  // yellow
                else { "\x1b[32m" };               // green
    let _ = write!(output, " · 📊 {}{}%\x1b[0m", color, pct);
}
```

**Update call site:**
```rust
format_context_usage(&mut output, input.context_window.as_ref());
```

**Remove dead code (~80 lines):**
- `TranscriptEntry`, `TranscriptMessage`, `Usage` structs
- `read_tail()` function
- `use std::io::Read` import (only used by `read_tail`)

### 2. Add session duration

**Update `Cost` struct:**
```rust
struct Cost {
    total_cost_usd: Option<f64>,
    total_duration_ms: Option<u64>,
}
```

**New `format_duration()` function:**
```rust
fn format_duration(output: &mut String, cost: &Option<Cost>) {
    let ms = match cost.as_ref().and_then(|c| c.total_duration_ms) {
        Some(ms) if ms > 0 => ms,
        _ => return,
    };
    let total_mins = ms / 60_000;
    if total_mins == 0 { return; }  // <1 min — don't show
    let display = if total_mins >= 60 {
        format!("{}h {}m", total_mins / 60, total_mins % 60)
    } else {
        format!("{}m", total_mins)
    };
    let _ = write!(output, " · \x1b[2m{}\x1b[0m", display);  // dim
}
```

**Insert after `format_cost` call in `run()`:**
```rust
format_duration(&mut output, &input.cost);
```

**New format:** `[profiles] ~/path (branch*) · 📊 25% · $1.23 · 12m`

### 3. Update bash fallback to match

**In `claude/statusline.sh`:**

Replace transcript-reading section (lines 119-165) with:
```bash
context_info=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "0" ]; then
  if [ "$used_pct" -ge 90 ]; then
    context_info=" · 📊 $(printf "\033[31m")${used_pct}%$(printf "\033[0m")"
  elif [ "$used_pct" -ge 70 ]; then
    context_info=" · 📊 $(printf "\033[33m")${used_pct}%$(printf "\033[0m")"
  else
    context_info=" · 📊 $(printf "\033[32m")${used_pct}%$(printf "\033[0m")"
  fi
fi
```

Add duration after cost section:
```bash
duration_info=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
if [ "$duration_ms" -gt 60000 ] 2>/dev/null; then
  total_mins=$((duration_ms / 60000))
  if [ "$total_mins" -ge 60 ]; then
    duration_info=" · $(printf "\033[2m")$((total_mins / 60))h $((total_mins % 60))m$(printf "\033[0m")"
  else
    duration_info=" · $(printf "\033[2m")${total_mins}m$(printf "\033[0m")"
  fi
fi
```

Update final printf to include `$duration_info`.

Update header comments to remove transcript references.

### 4. Deploy binary + cleanup

```bash
cd tools/claude-tools && cargo clippy && cargo build --release
cp target/release/claude-tools ../../custom_bins/claude-tools
chmod +x ../../custom_bins/claude-tools
```

Remove debug wrapper: `custom_bins/claude-tools-debug`

## Files

| File | Action |
|------|--------|
| `tools/claude-tools/src/statusline.rs` | Replace context% with `used_percentage`, add duration, remove dead code |
| `claude/statusline.sh` | Replace transcript reading with `jq .context_window.used_percentage`, add duration |
| `custom_bins/claude-tools` | Rebuild and copy |
| `custom_bins/claude-tools-debug` | Remove (debug artifact) |

## Critique Notes Addressed

| Question | Resolution |
|----------|-----------|
| `Option<f64>` vs integer in schema? | serde deserializes JSON `8` into `f64` as `8.0` — no issue |
| `p as u64` truncation (99.7→99)? | Use `.round()` before cast: `p.round() as u64` |
| Keep transcript_path as fallback? | No — personal dotfiles tool, not a library. Older CC versions still work (just no context%) |
| Hardcoded 200k window? | No longer relevant — `used_percentage` is pre-computed by CC |
| Other useful schema fields? | `total_duration_ms` added. `agent.name` and `output_style.name` not useful in statusline |
| Remove transcript_path from Input? | Yes — dead code cleanup. serde ignores unknown fields by default |
| Update statusline.sh too? | Yes — section 3 of this plan |

## Verification

1. `cargo clippy && cargo build --release` — no warnings
2. Test with full JSON including new fields:
   ```bash
   echo '{"workspace":{"current_dir":"/Users/yulong/code/dotfiles"},"model":{"id":"claude-opus-4-6"},"cost":{"total_cost_usd":1.23,"total_duration_ms":720000},"context_window":{"used_percentage":42}}' | ./target/release/claude-tools statusline
   # Expected: [code...] ~/code/dotfiles (main*) · 📊 42% · $1.23 · 12m
   ```
3. Test edge cases:
   ```bash
   # null context_window (early session)
   echo '{"workspace":{"current_dir":"."}}' | ./target/release/claude-tools statusline
   # $0 cost (Claude Max)
   echo '{"workspace":{"current_dir":"."},"cost":{"total_cost_usd":0,"total_duration_ms":300000},"context_window":{"used_percentage":15}}' | ./target/release/claude-tools statusline
   # Expected: . · 📊 15% · 5m  (no cost shown)
   # <1 minute duration
   echo '{"workspace":{"current_dir":"."},"cost":{"total_duration_ms":30000},"context_window":{"used_percentage":3}}' | ./target/release/claude-tools statusline
   # Expected: . · 📊 3%  (no duration shown)
   ```
4. Visual diff Rust vs Bash with same input
5. `hyperfine` benchmark to confirm still ~1ms
6. Start new Claude Code session — verify context%, cost, and duration all show correctly
