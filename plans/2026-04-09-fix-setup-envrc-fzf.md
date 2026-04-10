# Fix setup-envrc Picker + Silent Error Anti-Pattern

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken interactive picker in `setup-envrc` by replacing fzf with gum, show rich metadata (key, masked value, project, description), preserve user-added `.envrc` sections across regeneration, and add global lint to prevent silent error suppression

**Architecture:** Replace all fzf calls with `gum choose` (native `--selected`, `--label-delimiter`). Extend existing `dotfiles-secrets keys-meta` to include masked value and project name. Add section markers to `.envrc` so `write_envrc` preserves user content below the managed block. Add lint script for the `2>/dev/null || exit` anti-pattern.

**Tech Stack:** Bash, gum 0.17+, bws CLI, python3, shellcheck

---

### Root Cause

Two broken fzf calls use `--select` (not a valid fzf flag in 0.71.0):
1. **Main picker** (line 723): `select_args+=(--select "$item")`
2. **Telegram secret picker** (line 583): `select_args=(--select "$current_secret")`

Both hidden by `2>/dev/null` + `|| exit 0` / `|| { return }` — the silent error anti-pattern.

```
$ echo -e "foo\nbar" | fzf --select bar --multi 2>&1
unknown option: --select    ← exits code 2
```

---

### Task 1: Extend `keys-meta` with masked value and project name

**Files:**
- Modify: `custom_bins/dotfiles-secrets` (around `load_secrets_cache_bws` and `keys-meta` case)

`keys-meta` already returns `env_name\tbws_key\tnote`. Extend it to return `env_name\tbws_key\tnote\tmasked_value\tproject_name` by enriching the bws metadata cache.

- [ ] **Step 1: Update `load_secrets_cache_bws` to capture project IDs and values**

In `load_secrets_cache_bws()` (line 92), the Python script currently only extracts `key` and `value` for dotenv. Add a second cache variable `BWS_META_CACHE` that includes all metadata. Find where `BWS_META_CACHE` is populated and update the Python to include masked values and resolve project names.

Check current `BWS_META_CACHE` population:
```bash
grep -n 'BWS_META_CACHE' custom_bins/dotfiles-secrets
```

Update the Python code that builds `BWS_META_CACHE` to output 5 columns:
```python
# Output: env_name\tbws_key\tnote\tmasked_value\tproject_name
masked = value[:4] + "..." if len(value) > 8 else ("****" if value else "(empty)")
# Sanitize: replace tabs in notes/descriptions with spaces
note_clean = (note or "").replace("\t", " ").replace("\n", " ")
project_name_clean = projects.get(project_id, "").replace("\t", " ")
meta_lines.append(f"{env_name}\t{raw_key}\t{note_clean}\t{masked}\t{project_name_clean}")
```

If `BWS_META_CACHE` is not already built from a separate `bws project list` call, add one:
```bash
projects_json=$(bws project list 2>>"$bws_stderr") || projects_json="[]"
```
And pass it into the Python script alongside secrets.

- [ ] **Step 2: Update `keys-meta` case to output all 5 columns**

```bash
    keys-meta)
        load_secrets
        if [[ "$BACKEND" == "bws" && -n "$BWS_META_CACHE" ]]; then
            printf '%s\n' "$BWS_META_CACHE"
        else
            # SOPS fallback: env_name, bws_key=same, no note/project, masked value
            load_secrets_cache
            printf '%s\n' "$SECRETS_CACHE" | while IFS='=' read -r key value; do
                [[ -n "$key" ]] || continue
                if [[ ${#value} -gt 8 ]]; then masked="${value:0:4}..."
                elif [[ -n "$value" ]]; then masked="****"
                else masked="(empty)"; fi
                printf '%s\t%s\t\t%s\t\n' "$key" "$key" "$masked"
            done
        fi
        ;;
```

- [ ] **Step 3: Run shellcheck and test**

Run: `shellcheck custom_bins/dotfiles-secrets && dotfiles-secrets keys-meta | head -3`
Expected: 5 tab-separated columns, e.g.:
```
ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - Claude key	Claude key	sk-a...	MyProject
```

- [ ] **Step 4: Commit**

```bash
git add custom_bins/dotfiles-secrets
git commit -m "feat: extend keys-meta with masked value and project name

Now returns 5 columns: env_name, bws_key, note, masked_value, project.
Tabs in notes/descriptions sanitized to spaces."
```

---

### Task 2: Replace ALL fzf calls with gum in setup-envrc

**Files:**
- Modify: `custom_bins/setup-envrc:560-601` (`prompt_for_telegram_secret`)
- Modify: `custom_bins/setup-envrc:683-753` (main picker)

There are TWO fzf calls — both must be migrated. Both use the broken `--select` flag.

#### Part A: Replace main picker (lines 683-753)

- [ ] **Step 1: Verify gum `--selected` matching behavior with `--label-delimiter`**

Run this test interactively (MUST be run in a real terminal, not piped):
```bash
printf 'Label A (tag)\tvalA\nLabel B\tvalB\nLabel C (tag)\tvalC\n' | \
  gum choose --no-limit --label-delimiter=$'\t' --selected "Label A (tag)" --selected "Label C (tag)"
```

Check:
- Does it pre-select "Label A (tag)" and "Label C (tag)"? → `--selected` matches on **label** text
- Does it return `valA` and `valC` on Enter? → `--label-delimiter` returns the **value** portion

If `--selected` matches on the full input line instead, use:
```bash
--selected "Label A (tag)\tvalA"
```

Document which behavior is observed and adjust the code accordingly.

- [ ] **Step 2: Replace lines 683-753 with gum picker**

```bash
if [[ ${#selected_export_bindings[@]} -eq 0 && "$include_all" == false && -z "$telegram_secret" ]]; then
    command -v gum >/dev/null 2>&1 || die "gum required (brew install gum). Or use: setup-envrc KEY1 KEY2"

    load_secrets_cache
    mapfile -t current_export_bindings < <(current_envrc_export_bindings)
    mapfile -t current_export_bindings < <(normalize_export_bindings "${current_export_bindings[@]}")
    current_telegram_secret=$(current_envrc_telegram_secret)
    preselected=()
    menu_items=()

    # Load rich metadata: env_name\tbws_key\tnote\tmasked_value\tproject
    declare -A meta_note meta_masked meta_project
    while IFS=$'\t' read -r m_env m_bws m_note m_masked m_proj; do
        [[ -n "$m_env" ]] || continue
        meta_note["$m_env"]="$m_note"
        meta_masked["$m_env"]="$m_masked"
        meta_project["$m_env"]="$m_proj"
    done < <("$SECRETS_HELPER" keys-meta)

    while IFS= read -r key; do
        [[ -n "$key" ]] || continue

        # Build display label with available metadata
        label="$key"
        masked="${meta_masked[$key]:-}"
        project="${meta_project[$key]:-}"
        note="${meta_note[$key]:-}"
        [[ -n "$masked" ]] && label+="  ${masked}"
        [[ -n "$project" ]] && label+="  [${project}]"
        [[ -n "$note" ]] && label+="  ${note}"

        existing_binding=$(binding_for_secret "$key" "${current_export_bindings[@]}" || true)
        if [[ -n "$existing_binding" ]]; then
            if [[ "$(binding_env_key "$existing_binding")" != "$key" ]]; then
                label+="  (envrc->$(binding_env_key "$existing_binding"))"
            else
                label+="  ✓"
            fi
            preselected+=("$label")
        fi

        # gum displays label, returns value (env_name) via label-delimiter
        menu_items+=("${label}"$'\t'"${key}")
    done < <(list_sensitive_keys)

    if [[ ${#menu_items[@]} -eq 0 ]]; then
        die "No secrets found in $(dotfiles_secrets_backend) backend. Add secrets first."
    fi

    gum_args=(
        --no-limit
        --header="Select secrets for $(basename "$REPO_ROOT") — space to toggle, enter to confirm"
        --label-delimiter=$'\t'
    )
    for item in "${preselected[@]}"; do
        gum_args+=(--selected "$item")
    done

    selected=$(printf '%s\n' "${menu_items[@]}" | gum choose "${gum_args[@]}") || exit 0

    while IFS= read -r secret_name; do
        [[ -n "$secret_name" ]] || continue
        existing_binding=$(binding_for_secret "$secret_name" "${current_export_bindings[@]}" || true)
        if [[ -n "$existing_binding" ]]; then
            selected_export_bindings+=("$existing_binding")
        else
            selected_export_bindings+=("$secret_name")
        fi
    done <<< "$selected"

    if repo_uses_telegram_plugin || [[ -n "$current_telegram_secret" ]]; then
        telegram_secret=$(prompt_for_telegram_secret "$current_telegram_secret")
    fi
fi
```

#### Part B: Replace telegram secret picker (lines 560-601)

- [ ] **Step 3: Replace `prompt_for_telegram_secret` fzf call**

Replace lines 582-594 in `prompt_for_telegram_secret()`:

```bash
    # Old: fzf with broken --select
    # New: gum choose (single select, not --no-limit)
    gum_args=(
        --header="Select Telegram bot secret for $(basename "$REPO_ROOT")"
    )
    if [[ -n "$current_secret" ]]; then
        gum_args+=(--selected "$current_secret")
    else
        gum_args+=(--selected "<none>")
    fi

    selected=$(printf '%s\n' "${items[@]}" | gum choose "${gum_args[@]}") || {
        printf '%s\n' "$current_secret"
        return 0
    }
```

- [ ] **Step 4: Run shellcheck**

Run: `shellcheck custom_bins/setup-envrc`
Expected: No new errors

- [ ] **Step 5: Manual test — interactive mode with rich metadata**

Run: `cd ~/code/bots/ambassador && setup-envrc`
Expected:
- gum picker appears showing: key name, masked value, project, description
- Items already in `.envrc` show ✓ and are pre-selected
- Space toggles, Enter confirms
- `.envrc` is updated correctly

- [ ] **Step 6: Manual test — non-interactive mode**

Run: `setup-envrc TELEGRAM_API_ID TELEGRAM_API_HASH`
Expected: `.envrc` updated (no picker shown)

- [ ] **Step 7: Commit**

```bash
git add custom_bins/setup-envrc
git commit -m "feat: replace all fzf with gum, show rich secret metadata

Both the main picker and telegram secret picker migrated from fzf
(broken --select) to gum choose (native --selected).

Picker shows: env name, masked value, bws project, description.
Existing envrc items shown with ✓ and pre-selected."
```

---

### Task 3: Preserve user sections in .envrc across regeneration

**Files:**
- Modify: `custom_bins/setup-envrc` (`write_envrc` function, lines 297-377; `--clean` handler, line 651)

Currently `write_envrc` does `} > "$ENVRC"` which overwrites the entire file.

**Design:** Section markers delimit the managed block. Everything after the end marker is preserved.

```
# === setup-envrc managed section (do not edit) ===
# setup-envrc exports: ANTHROPIC_API_KEY OPENAI_API_KEY
watch_file ...
eval "$(..."
# === end setup-envrc managed section ===

# Your custom additions below this line are preserved across setup-envrc runs.
export MY_CUSTOM_VAR="foo"
layout python
```

- [ ] **Step 1: Add section marker constants and extraction helpers**

Add before `write_envrc()`:

```bash
MANAGED_BEGIN="# === setup-envrc managed section (do not edit) ==="
MANAGED_END="# === end setup-envrc managed section ==="

extract_user_section() {
    [[ -f "$ENVRC" ]] || return 0
    local found_end=false
    while IFS= read -r line; do
        if [[ "$found_end" == true ]]; then
            printf '%s\n' "$line"
        elif [[ "$line" == "$MANAGED_END" ]]; then
            found_end=true
        fi
    done < "$ENVRC"
}

extract_legacy_user_content() {
    # One-time migration for .envrc files created before section markers.
    # Heuristic: skip lines that match known managed patterns.
    # NOTE: This is imperfect — may misclassify edge cases. On first run
    # with markers, the detected user content is shown for confirmation.
    [[ -f "$ENVRC" ]] || return 0
    grep -qF "$MANAGED_END" "$ENVRC" && return 0

    while IFS= read -r line; do
        [[ "$line" == "# Auto-generated by setup-envrc"* ]] && continue
        [[ "$line" == "# setup-envrc exports:"* ]] && continue
        [[ "$line" == "# setup-envrc telegram-secret:"* ]] && continue
        [[ "$line" == "watch_file "* ]] && continue
        [[ "$line" == "DOTFILES_SECRETS_BIN="* ]] && continue
        [[ "$line" == 'eval "$('"*" ]] && continue
        [[ "$line" == "export DOTFILES_SECRETS_BACKEND="* ]] && continue
        [[ "$line" == "export TELEGRAM_STATE_DIR="* ]] && continue
        [[ "$line" == "export DOTFILES_TELEGRAM_BOT_SECRET="* ]] && continue
        [[ "$line" == "unset "* ]] && continue
        [[ -z "$line" ]] && continue
        printf '%s\n' "$line"
    done < "$ENVRC"
}
```

- [ ] **Step 2: Modify `write_envrc` to use markers and preserve user content**

At the start of `write_envrc()`, capture the user section:

```bash
    # Capture user section before overwriting
    local user_section=""
    user_section=$(extract_user_section)
    if [[ -z "$user_section" ]]; then
        local legacy_content
        legacy_content=$(extract_legacy_user_content)
        if [[ -n "$legacy_content" ]]; then
            echo "Detected custom content in existing .envrc (migrating to preserved section):"
            printf '%s\n' "$legacy_content" | head -5
            [[ $(printf '%s\n' "$legacy_content" | wc -l) -gt 5 ]] && echo "  ..."
            user_section="$legacy_content"
        fi
    fi
```

Change the generation block: wrap output in markers, append user section at the end.

Replace `} > "$ENVRC"` (line 377) with:

```bash
        echo "$MANAGED_END"
        echo ""
        echo "# Your custom additions below this line are preserved across setup-envrc runs."
        if [[ -n "$user_section" ]]; then
            printf '%s\n' "$user_section"
        fi
    } > "${ENVRC}.tmp" && mv "${ENVRC}.tmp" "$ENVRC"
```

Note: write to temp file + `mv` for atomicity (addresses TOCTOU concern from review).

And add `echo "$MANAGED_BEGIN"` as the first line of the generation block (replacing the first `echo "# Auto-generated..."` — keep the auto-generated comment but inside the markers).

- [ ] **Step 3: Update `--clean` handler to preserve user content**

Replace lines 651-657:

```bash
            --clean)
                if [[ -f "$ENVRC" ]]; then
                    user_content=$(extract_user_section)
                    if [[ -n "$user_content" ]]; then
                        echo "Warning: .envrc has user-added content:"
                        printf '%s\n' "$user_content" | head -5
                        echo ""
                        read -rp "Remove managed section only, keeping custom content? [Y/n/all] " confirm
                        case "$confirm" in
                            [Nn])
                                echo "Aborted."
                                exit 0
                                ;;
                            all|ALL)
                                safe_remove "$ENVRC"
                                echo "Removed entire $ENVRC"
                                ;;
                            *)
                                # Keep only user content
                                printf '%s\n' "# Custom .envrc (managed section removed by setup-envrc --clean)" \
                                              "$user_content" > "${ENVRC}.tmp" && mv "${ENVRC}.tmp" "$ENVRC"
                                echo "Removed managed section, preserved custom content in $ENVRC"
                                ;;
                        esac
                    else
                        safe_remove "$ENVRC"
                        echo "Removed $ENVRC"
                    fi
                else
                    echo "No .envrc to remove in $REPO_ROOT"
                fi
                exit 0
                ;;
```

- [ ] **Step 4: Test — regenerate preserves user content**

```bash
cd ~/code/bots/ambassador
echo -e "\n# My custom stuff\nexport FOO=bar" >> .envrc
setup-envrc ANTHROPIC_API_KEY
grep "FOO=bar" .envrc && echo "PASS: user content preserved"
```

- [ ] **Step 5: Test — `--clean` offers choices**

```bash
setup-envrc --clean
# Should show "Warning: .envrc has user-added content" and prompt
# Choose default (Y) — should keep user content, remove managed section
```

- [ ] **Step 6: Run shellcheck and commit**

```bash
shellcheck custom_bins/setup-envrc
git add custom_bins/setup-envrc
git commit -m "feat: preserve user .envrc sections across setup-envrc runs

Adds section markers. Everything after end marker is preserved on
regeneration. Legacy .envrc files auto-migrate unrecognized lines.
--clean offers to keep user content or remove everything.
Atomic write via temp file + mv."
```

---

### Task 4: Add silent-error lint rule

**Files:**
- Create: `scripts/lint/check_silent_errors.sh`

The anti-pattern: `command 2>/dev/null || exit 0` hides errors AND silently exits.

- [ ] **Step 1: Create the lint script**

```bash
#!/usr/bin/env bash
# scripts/lint/check_silent_errors.sh
# Detect: stderr suppressed AND exit code swallowed on the same line.
#   BAD:  cmd 2>/dev/null || exit 0
#   BAD:  cmd 2>/dev/null || true
#   BAD:  cmd 2>/dev/null) || exit 0
#   OK:   cmd 2>/dev/null              (exit code preserved)
#   OK:   cmd || exit 0                (error visible)
#   OK:   command -v foo >/dev/null    (intentional existence check)
#   OK:   chmod ... 2>/dev/null || true (permission hardening, non-critical)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SEARCH_DIR="${1:-$SCRIPT_DIR}"
exit_code=0

check_file() {
    local file="$1"
    [[ "$file" == *"/vendor/"* || "$file" == *"/node_modules/"* || "$file" == *"/archive/"* ]] && return

    local matches
    matches=$(grep -nE '2>/dev/null.*\|\|\s*(exit|true|:|return)' "$file" 2>/dev/null || true)
    [[ -n "$matches" ]] || return

    while IFS= read -r match; do
        echo "$match" | grep -qE '(command -v|hash |type )\S+' && continue
        echo "$match" | grep -qE 'chmod.*2>/dev/null \|\| true' && continue
        echo "WARN: $file:$match"
        echo "  ↳ stderr suppressed AND error swallowed — failures invisible"
        echo ""
        exit_code=1
    done <<< "$matches"
}

while IFS= read -r -d '' file; do
    check_file "$file"
done < <(find "$SEARCH_DIR" -type f -name '*.sh' -print0 2>/dev/null)

if [[ -d "$SEARCH_DIR/custom_bins" ]]; then
    while IFS= read -r -d '' file; do
        head -1 "$file" 2>/dev/null | grep -qE '^#!.*(bash|sh)' || continue
        check_file "$file"
    done < <(find "$SEARCH_DIR/custom_bins" -type f -print0)
fi

if [[ $exit_code -eq 0 ]]; then
    echo "✓ No silent error suppression patterns found"
fi
exit $exit_code
```

- [ ] **Step 2: Test — should catch current bugs before fix**

```bash
chmod +x scripts/lint/check_silent_errors.sh
bash scripts/lint/check_silent_errors.sh
```
Expected: Flags the fzf lines in `setup-envrc` and any other instances

- [ ] **Step 3: Run after Task 2 to verify clean**

```bash
bash scripts/lint/check_silent_errors.sh
```

- [ ] **Step 4: Commit**

```bash
git add scripts/lint/check_silent_errors.sh
git commit -m "lint: detect silent error suppression (2>/dev/null || exit)"
```

---

### Task 5: Add CLAUDE.md rule and gum to package list

**Files:**
- Modify: `CLAUDE.md`
- Modify: package list file (check which exists)

- [ ] **Step 1: Add silent-error rule to CLAUDE.md**

```markdown
### Silent Error Anti-Pattern (NEVER)

Never combine stderr suppression with error swallowing:
- `cmd 2>/dev/null || exit 0` — NEVER (error hidden AND script exits silently)
- `cmd 2>/dev/null || true` — NEVER (error hidden AND swallowed)
- `cmd 2>/dev/null` — OK (stderr suppressed but exit code preserved)
- `cmd || exit 0` — OK (error visible, script chooses to exit)
- `command -v foo >/dev/null 2>&1 || die "missing"` — OK (intentional check with real error)

Lint: `scripts/lint/check_silent_errors.sh`
```

- [ ] **Step 2: Add gum to package list**

```bash
ls ~/code/dotfiles/Brewfile ~/code/dotfiles/packages* 2>/dev/null
```

Add `gum` (Brewfile: `brew "gum"`, etc.)

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md <package-file>
git commit -m "docs: add silent-error rule, add gum to package list"
```
