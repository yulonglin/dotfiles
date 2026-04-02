# Default Editor File Associations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Single config file declares the default editor for coding files. Deploy sets both macOS Launch Services associations and shell `$EDITOR`/`$VISUAL` from it.

**Architecture:** A declarative config file (`config/file_associations.conf`) maps file extensions to app bundle IDs. A small Swift CLI (`tools/set-default-app/main.swift`, ~50 lines) reads the config and calls `LSSetDefaultRoleHandlerForContentType`. `deploy.sh` compiles and runs it. `zshrc.sh` reads the same config for `$EDITOR`/`$VISUAL`.

**Tech Stack:** Swift (macOS-native API), zsh (config parsing)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `config/file_associations.conf` | Create | Declarative config: default editor bundle ID, CLI command, extension list |
| `tools/set-default-app/main.swift` | Create | Swift CLI: reads config, calls `LSSetDefaultRoleHandlerForContentType` per UTI |
| `deploy.sh` | Modify (~920) | Add `--file-apps` deployment section: compile Swift + apply associations |
| `config.sh` | Modify (~59) | Add `DEPLOY_FILE_APPS=true` default |
| `config/zshrc.sh` | Modify (~19-24) | Read editor CLI command from config instead of hardcoding `cursor --wait` |
| `scripts/shared/helpers.sh` | Modify (~70) | Add `file-apps` to interactive component menu |

---

## Config File Format

`config/file_associations.conf`:
```bash
# Default editor for coding files
# Used by: deploy.sh (macOS file associations), zshrc.sh ($EDITOR/$VISUAL)
#
# EDITOR_BUNDLE_ID: macOS app bundle identifier (for Launch Services)
# EDITOR_CLI: shell command for $EDITOR (--wait makes it blocking)
# EDITOR_CLI_SSH: shell command for $EDITOR over SSH
# EXTENSIONS: space-separated list of file extensions to associate

EDITOR_BUNDLE_ID="com.todesktop.230313mzl4w4u92"  # Cursor
EDITOR_CLI="cursor --wait"
EDITOR_CLI_SSH="edit"

EXTENSIONS=(
  # Python
  py pyi pyw
  # Web
  js jsx ts tsx css html htm
  # Markup / data
  md txt json yaml yml toml xml csv
  # Systems
  c cpp h hpp rs go java swift
  # Shell / config
  sh bash zsh fish
  # Other
  rb r tex sql ini cfg log conf
)
```

---

### Task 1: Create the config file

**Files:**
- Create: `config/file_associations.conf`

- [ ] **Step 1: Create the config file**

```bash
# config/file_associations.conf
# ═══════════════════════════════════════════════════════════════════════════════
# Default Editor — File Type Associations
# ═══════════════════════════════════════════════════════════════════════════════
# Single source of truth for which app opens coding files.
# Used by:
#   - deploy.sh --file-apps  → sets macOS Launch Services defaults
#   - zshrc.sh               → exports $EDITOR and $VISUAL
#
# To change your default editor, update EDITOR_BUNDLE_ID and EDITOR_CLI below,
# then run: ./deploy.sh --file-apps
#
# Find an app's bundle ID:
#   osascript -e 'id of app "AppName"'
# ═══════════════════════════════════════════════════════════════════════════════

# App bundle identifier (macOS Launch Services)
EDITOR_BUNDLE_ID="com.todesktop.230313mzl4w4u92"  # Cursor

# Shell command for $EDITOR (local) and $VISUAL
EDITOR_CLI="cursor --wait"

# Shell command for $EDITOR over SSH (lightweight/terminal editor)
EDITOR_CLI_SSH="edit"

# File extensions to associate with the editor above.
# Each extension is looked up as a UTI via UniformTypeIdentifiers at deploy time.
# Extensions with no recognized UTI are skipped (with a warning).
EXTENSIONS=(
  # Python
  py pyi pyw
  # Web
  js jsx ts tsx css html htm
  # Markup / data
  md txt json yaml yml toml xml csv
  # Systems
  c cpp h hpp rs go java swift
  # Shell / config
  sh bash zsh fish
  # Other
  rb r tex sql ini cfg log conf
)
```

- [ ] **Step 2: Commit**

```bash
git add config/file_associations.conf
git commit -m "feat: add file_associations.conf — single source for default editor"
```

---

### Task 2: Create the Swift CLI tool

**Files:**
- Create: `tools/set-default-app/main.swift`

The tool accepts a bundle ID and list of file extensions. For each extension, it resolves the UTI via `UniformTypeIdentifiers` and calls the (deprecated but functional) `LSSetDefaultRoleHandlerForContentType`.

- [ ] **Step 1: Create the Swift source**

```swift
// tools/set-default-app/main.swift
// Sets macOS default app for file extensions via Launch Services.
// Usage: set-default-app <bundle-id> <ext> [ext...]
// Example: set-default-app com.todesktop.230313mzl4w4u92 py md json

import Foundation
import UniformTypeIdentifiers

// Suppress deprecation warning — Apple deprecated LSSetDefaultRoleHandlerForContentType
// in macOS 12 with no replacement. All tools (duti, utiluti, dutix) use this same API.
// It still works on macOS 15 (Sequoia).
@_silgen_name("LSSetDefaultRoleHandlerForContentType")
func LSSetDefaultRoleHandlerForContentType(
    _ inContentType: CFString,
    _ inRole: Int,
    _ inHandlerBundleID: CFString
) -> Int32

// LSRolesMask.all = 0xFFFFFFFF (viewer + editor + shell + none)
let kLSRolesAll: Int = -1  // 0xFFFFFFFF as signed

func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        fputs("Usage: set-default-app <bundle-id> <ext> [ext...]\n", stderr)
        exit(1)
    }

    let bundleID = args[1]
    let extensions = Array(args[2...])
    var failures = 0

    for ext in extensions {
        guard let utType = UTType(filenameExtension: ext) else {
            fputs("⚠️  skip: .\(ext) — no UTI found\n", stderr)
            continue
        }

        let uti = utType.identifier
        let result = LSSetDefaultRoleHandlerForContentType(
            uti as CFString,
            kLSRolesAll,
            bundleID as CFString
        )

        if result == 0 {
            print("✓ .\(ext) → \(uti) → \(bundleID)")
        } else {
            fputs("✗ .\(ext) → \(uti) — error \(result)\n", stderr)
            failures += 1
        }
    }

    if failures > 0 {
        exit(1)
    }
}

main()
```

- [ ] **Step 2: Verify it compiles**

```bash
cd tools/set-default-app
swiftc -O -o set-default-app main.swift
```

Expected: compiles with no errors (deprecation warnings are suppressed via `@_silgen_name`).

- [ ] **Step 3: Quick smoke test**

```bash
./tools/set-default-app/set-default-app com.todesktop.230313mzl4w4u92 py md json
```

Expected output:
```
✓ .py → public.python-script → com.todesktop.230313mzl4w4u92
✓ .md → net.daringfireball.markdown → com.todesktop.230313mzl4w4u92
✓ .json → public.json → com.todesktop.230313mzl4w4u92
```

- [ ] **Step 4: Add to .gitignore**

The compiled binary should not be committed. Add to the repo's `.gitignore`:

```
tools/set-default-app/set-default-app
```

- [ ] **Step 5: Commit**

```bash
git add tools/set-default-app/main.swift .gitignore
git commit -m "feat: add set-default-app Swift CLI for macOS file associations"
```

---

### Task 3: Add deploy.sh integration

**Files:**
- Modify: `config.sh` (~line 59, after `DEPLOY_FINICKY`)
- Modify: `deploy.sh` (~line 912, before "Wait for background builds")
- Modify: `deploy.sh` (~line 75, help text)
- Modify: `scripts/shared/helpers.sh` (~line 70, component menu)

- [ ] **Step 1: Add config default**

In `config.sh`, after `DEPLOY_FINICKY=true` (line 60):

```bash
DEPLOY_FILE_APPS=true           # Set default editor for coding file types (macOS only)
```

- [ ] **Step 2: Add help text**

In `deploy.sh`, in the `show_help()` COMPONENTS section (after the `--keyboard` line, ~line 76):

```bash
    --file-apps       Set default editor for coding file types (macOS only)
```

- [ ] **Step 3: Add deployment section**

In `deploy.sh`, before `# ─── Wait for background builds` (~line 918), add:

```bash
# ─── File Type Associations (macOS only) ─────────────────────────────────────

if [[ "$DEPLOY_FILE_APPS" == "true" ]] && is_macos; then
    log_section "SETTING DEFAULT FILE ASSOCIATIONS"

    ASSOC_CONF="$DOT_DIR/config/file_associations.conf"
    if [[ ! -f "$ASSOC_CONF" ]]; then
        log_warning "config/file_associations.conf not found, skipping"
    else
        source "$ASSOC_CONF"

        # Compile Swift tool if needed (binary missing or source newer)
        local tool_dir="$DOT_DIR/tools/set-default-app"
        local tool_bin="$tool_dir/set-default-app"
        if [[ ! -x "$tool_bin" ]] || [[ "$tool_dir/main.swift" -nt "$tool_bin" ]]; then
            log_info "Compiling set-default-app..."
            if swiftc -O -o "$tool_bin" "$tool_dir/main.swift" 2>/dev/null; then
                log_success "Compiled set-default-app"
            else
                log_warning "Swift compilation failed — skipping file associations"
                DEPLOY_FILE_APPS=false
            fi
        fi

        if [[ "$DEPLOY_FILE_APPS" == "true" ]]; then
            "$tool_bin" "$EDITOR_BUNDLE_ID" "${EXTENSIONS[@]}"
            log_success "File associations set to $EDITOR_BUNDLE_ID"
        fi
    fi
fi
```

- [ ] **Step 4: Add to interactive component menu**

In `scripts/shared/helpers.sh`, in the `is_macos` deploy component section (~line 70), add:

```bash
                "file-apps|Default editor for coding file types|$DEPLOY_FILE_APPS"
```

- [ ] **Step 5: Add to server/minimal profile overrides**

In `config.sh`, in the `apply_profile()` function, ensure `DEPLOY_FILE_APPS=false` is set for server and minimal profiles (alongside other macOS-only components like `DEPLOY_FINICKY`). Find the lines where `DEPLOY_FINICKY=false` is set in each profile and add `DEPLOY_FILE_APPS=false` next to them.

- [ ] **Step 6: Test deploy**

```bash
./deploy.sh --minimal --file-apps
```

Expected: compiles Swift tool, applies associations, prints success for each extension.

- [ ] **Step 7: Commit**

```bash
git add config.sh deploy.sh scripts/shared/helpers.sh
git commit -m "feat: deploy.sh --file-apps sets macOS default editor for coding files"
```

---

### Task 4: Wire zshrc.sh to read from config

**Files:**
- Modify: `config/zshrc.sh` (lines 19-24)

Currently hardcoded:
```bash
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='edit'
else
  export EDITOR='cursor --wait'
fi
```

Replace with config-driven:
```bash
# Editor — reads from file_associations.conf (single source of truth)
_fa_conf="$DOT_DIR/config/file_associations.conf"
if [[ -f "$_fa_conf" ]]; then
  # Source only the EDITOR_CLI* variables (fast, no array eval)
  EDITOR_CLI=$(sed -n 's/^EDITOR_CLI="\(.*\)"/\1/p' "$_fa_conf" | head -1)
  EDITOR_CLI_SSH=$(sed -n 's/^EDITOR_CLI_SSH="\(.*\)"/\1/p' "$_fa_conf" | head -1)
fi
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR="${EDITOR_CLI_SSH:-edit}"
else
  export EDITOR="${EDITOR_CLI:-cursor --wait}"
fi
export VISUAL="$EDITOR"
unset _fa_conf EDITOR_CLI EDITOR_CLI_SSH
```

- [ ] **Step 1: Update the EDITOR block in zshrc.sh**

Replace lines 19-24 with the config-driven version above.

- [ ] **Step 2: Verify in a new shell**

```bash
zsh -ic 'echo "EDITOR=$EDITOR VISUAL=$VISUAL"'
```

Expected: `EDITOR=cursor --wait VISUAL=cursor --wait`

- [ ] **Step 3: Verify SSH fallback**

```bash
SSH_CONNECTION=fake zsh -ic 'echo "EDITOR=$EDITOR"'
```

Expected: `EDITOR=edit`

- [ ] **Step 4: Verify fallback when config missing**

```bash
mv config/file_associations.conf config/file_associations.conf.bak
zsh -ic 'echo "EDITOR=$EDITOR"'
mv config/file_associations.conf.bak config/file_associations.conf
```

Expected: `EDITOR=cursor --wait` (hardcoded fallback)

- [ ] **Step 5: Commit**

```bash
git add config/zshrc.sh
git commit -m "feat: derive EDITOR/VISUAL from file_associations.conf"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `CLAUDE.md` (deployment components list, architecture section)
- Modify: `README.md` (if it has a deploy flags table)

- [ ] **Step 1: Update CLAUDE.md deployment components**

Add to the deployment components list in CLAUDE.md:
```
- File associations - Set default editor for coding file types (macOS only, reads `config/file_associations.conf`)
```

- [ ] **Step 2: Update CLAUDE.md architecture section**

Add to the `config/` tree:
```
├── file_associations.conf    # Default editor + file type associations (single source of truth)
```

Add to the `tools/` description or create entry:
```
tools/
├── claude-tools/             # Rust binary (statusline, usage)
└── set-default-app/          # Swift binary (macOS file type associations)
```

- [ ] **Step 3: Update CLAUDE.md Important Behaviors**

Add a new subsection:
```
**File Associations (`deploy --file-apps`)**:
- Reads `config/file_associations.conf` for editor bundle ID and extension list
- Compiles `tools/set-default-app/main.swift` (cached, rebuilds only when source changes)
- Calls `LSSetDefaultRoleHandlerForContentType` per extension (deprecated macOS API, no replacement, works on Sequoia)
- Same config drives `$EDITOR` and `$VISUAL` in zshrc.sh
- macOS only (Linux uses `xdg-mime`, not implemented)
```

- [ ] **Step 4: Update deploy.sh defaults comment in CLAUDE.md**

The line listing deploy defaults should include `--file-apps`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document file associations config and deploy component"
```

---

## Notes

- **TypeScript `.ts` caveat:** macOS maps `.ts` to `public.mpeg-2-transport-stream` (video). The Swift tool will set Cursor as default for `.ts` files, which means MPEG-2 transport streams would also open in Cursor. This is almost certainly fine for a developer machine. If it causes issues, remove `ts` from the extensions list.
- **`.tsx`/`.jsx`/`.pyi`/`.pyw`:** These may not have system UTIs. The Swift tool will print a warning and skip them. This is expected — macOS only knows about extensions registered by installed apps.
- **Deprecation risk:** `LSSetDefaultRoleHandlerForContentType` has been deprecated since macOS 12 with no replacement. Every tool in the ecosystem uses it. If Apple removes it, the Swift tool will need updating — but so will every alternative.
- **Linux:** Not in scope. Linux uses `xdg-mime default` which is a completely different mechanism. Could be added later with a parallel code path.
