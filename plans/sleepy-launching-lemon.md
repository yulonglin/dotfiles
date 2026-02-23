# Plan: Auto-resolve file paths when Read target doesn't exist

## Context

When Claude is told to read a file and it doesn't exist at the exact path, Claude reports "file not found" and gives up. It should **search for it** before giving up. This is a recurring friction pattern.

**Trigger case:** User said "look at `specs/status.md`" — Claude tried one Read, got ENOENT, and stopped. Should have searched with Glob.

## Approach: PostToolUse Hook (Rust + Shell) + Behavioral Rule

**Why PostToolUse over PreToolUse:** (Two independent critique agents converged on this)
- No `updatedInput` needed → avoids critical hook ordering conflict with `check_read_size.sh`
- Only fires on actual failures → zero false positives
- Claude uses judgment for multi-match → better than a bash script guessing

**Why Rust fast path:**
- PostToolUse fires on EVERY Read call (success or failure)
- Bash+jq: ~15ms per Read call (fork+exec overhead)
- Rust: ~0.5ms per Read call (no fork, native JSON parsing)
- Over 50-100 Read calls/session: 750ms → 25ms total overhead

## Implementation

### 1. Rust subcommand: `resolve-file-path` (~50 lines)

**File:** `tools/claude-tools/src/resolve_file_path.rs`

```rust
use serde::Deserialize;
use std::io::Read;
use std::path::Path;

#[derive(Deserialize)]
struct Input {
    tool_name: Option<String>,
    tool_input: Option<ToolInput>,
    tool_response: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct ToolInput {
    file_path: Option<String>,
}

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input_str = String::new();
    std::io::stdin().read_to_string(&mut input_str)?;
    let input: Input = serde_json::from_str(&input_str)?;

    // Only handle Read tool
    if input.tool_name.as_deref() != Some("Read") {
        return Ok(());
    }

    // Check if response indicates file-not-found
    let response_str = match &input.tool_response {
        Some(v) => v.to_string().to_lowercase(),
        None => return Ok(()),
    };

    let is_not_found = ["does not exist", "no such file", "enoent", "not found"]
        .iter()
        .any(|pattern| response_str.contains(pattern));

    if !is_not_found {
        return Ok(());
    }

    // Extract path info for search guidance
    let file_path = input.tool_input
        .as_ref()
        .and_then(|ti| ti.file_path.as_deref())
        .unwrap_or("");

    let path = Path::new(file_path);
    let basename = path.file_name()
        .and_then(|f| f.to_str())
        .unwrap_or("");

    // Preserve directory hint if present
    let parent_name = path.parent()
        .and_then(|p| p.file_name())
        .and_then(|f| f.to_str())
        .unwrap_or("");

    let search_hint = if !parent_name.is_empty() && parent_name != "/" {
        format!(
            "Glob(\"**/{}/{}\") first, then Glob(\"**/{}\") if no results",
            parent_name, basename, basename
        )
    } else {
        format!("Glob(\"**/{}\") or fd -H \"{}\"", basename, basename)
    };

    // Output systemMessage JSON
    let msg = format!(
        "File not found at {}. REQUIRED: Search before giving up.\n\
         1. {}\n\
         2. Single match → Read it. Multiple → list candidates and ask user.\n\
         3. Zero matches → ask user for correct path or repo.\n\
         Never silently skip a referenced file.",
        file_path, search_hint
    );

    println!(
        "{}",
        serde_json::json!({ "systemMessage": msg })
    );
    Ok(())
}
```

**Key design:**
- No new dependencies (uses existing `serde`, `serde_json`)
- `tool_response` parsed as `serde_json::Value` (schema isn't fully documented — defensive)
- Preserves directory hints from original path (two-pass search guidance)
- Fast path: 3 early returns before any string allocation

### 2. Register in `main.rs`

```rust
mod resolve_file_path;
// ...
"resolve-file-path" => resolve_file_path::run(),
```

### 3. Shell fallback: `resolve_file_path.sh`

**File:** `claude/ai-safety-plugins/plugins/core/hooks/resolve_file_path.sh`

```bash
#!/bin/bash
# PostToolUse hook: Guide Claude to search when Read fails with file-not-found
#
# Config:
#   CLAUDE_RESOLVE_PATH=0  — disable entirely

[[ "${CLAUDE_RESOLVE_PATH:-1}" == "0" ]] && exit 0

# Fast path: Rust binary
if command -v claude-tools >/dev/null 2>&1; then
    claude-tools resolve-file-path
    exit $?
fi

# Shell fallback
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
[[ "$TOOL_NAME" != "Read" ]] && exit 0

RESPONSE=$(printf '%s' "$INPUT" | jq -r '
  (.tool_response | if type == "object" then (.error // "") else (. // "") end)
')
if ! printf '%s' "$RESPONSE" | grep -qiE 'does not exist|no such file|ENOENT|not found'; then
    exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
DIRNAME=$(dirname "$FILE_PATH" 2>/dev/null | xargs basename 2>/dev/null)

if [[ -n "$DIRNAME" && "$DIRNAME" != "." && "$DIRNAME" != "/" ]]; then
    HINT="Glob(\"**/$DIRNAME/$BASENAME\") first, then Glob(\"**/$BASENAME\") if no results"
else
    HINT="Glob(\"**/$BASENAME\") or fd -H \"$BASENAME\""
fi

jq -n --arg path "$FILE_PATH" --arg hint "$HINT" '{
    systemMessage: ("File not found at " + $path + ". REQUIRED: Search before giving up.\n1. " + $hint + "\n2. Single match → Read it. Multiple → list candidates and ask user.\n3. Zero matches → ask user for correct path or repo.\nNever silently skip a referenced file.")
}'
```

**Pattern:** Same as `check_git_root.sh` — Rust fast path first, shell fallback if binary unavailable.

Note: The shell script pipes stdin to `claude-tools` by not consuming it before the Rust call. Since `claude-tools resolve-file-path` reads from stdin, the shell script simply invokes it and exits with its exit code.

### 4. Plugin registration: `plugin.json`

Add to PostToolUse section (alongside existing `Bash:truncate_output.sh`):

```json
{
    "matcher": "Read",
    "hooks": [
        {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/resolve_file_path.sh"
        }
    ]
}
```

### 5. Rule addition: `refusal-alternatives.md`

Add row to "Tool Failure Alternatives" table (after line 46):

```markdown
| Read/Glob file not found | **Search before giving up**: `Glob("**/<basename>")` from git root. Preserve directory hints (if path had `specs/foo.md`, try `**/specs/foo.md` first). Single match → use it. Multiple → list candidates and ask. Zero → ask user for correct path/repo. **Never silently skip a referenced file.** |
```

## Files to Modify

| File | Change |
|------|--------|
| `tools/claude-tools/src/resolve_file_path.rs` | **New** — Rust PostToolUse handler (~60 lines) |
| `tools/claude-tools/src/main.rs` | Add `mod` + match arm (2 lines) |
| `claude/ai-safety-plugins/plugins/core/hooks/resolve_file_path.sh` | **New** — Shell hook with Rust fast path (~35 lines) |
| `claude/ai-safety-plugins/plugins/core/.claude-plugin/plugin.json` | Register PostToolUse > Read matcher |
| `claude/rules/refusal-alternatives.md` | Add "file not found" row (line ~46) |

## Verification

1. **Build Rust binary:**
   ```bash
   cd tools/claude-tools && cargo build --release
   cp target/release/claude-tools ../../custom_bins/
   ```

2. **Unit test Rust (file not found):**
   ```bash
   echo '{"tool_name":"Read","tool_input":{"file_path":"/foo/specs/status.md"},"tool_response":"File does not exist."}' | claude-tools resolve-file-path
   # Expected: {"systemMessage":"File not found at /foo/specs/status.md..."}
   ```

3. **Unit test Rust (success — no output):**
   ```bash
   echo '{"tool_name":"Read","tool_input":{"file_path":"/foo/README.md"},"tool_response":{"content":"hello"}}' | claude-tools resolve-file-path
   # Expected: no output, exit 0
   ```

4. **Unit test shell fallback** (rename claude-tools temporarily):
   ```bash
   echo '{"tool_name":"Read","tool_input":{"file_path":"/foo/specs/status.md"},"tool_response":"File does not exist."}' | bash claude/ai-safety-plugins/plugins/core/hooks/resolve_file_path.sh
   ```

5. **Plugin cache sync** — copy hook to `~/.claude/plugins/cache/ai-safety-plugins/core/*/hooks/`

6. **Live test** — new Claude Code session, Read a nonexistent file, verify Claude gets the search guidance and acts on it
