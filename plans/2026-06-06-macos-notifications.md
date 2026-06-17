# macOS Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reusable macOS notification policy and helper, then use it to make `clear-mac-apps` visibly report apps that refuse to quit without force-killing browsers.

**Architecture:** Add a small `notify-mac` command as the one shell-facing notification interface. Keep simple fire-and-forget notifications on built-in `osascript`, keep `terminal-notifier` available for richer grouped notifications, and reserve `alerter` for interactive prompt-style alerts. Refactor `clear-mac-apps` so non-focus quit work runs concurrently in subprocesses, focus-sensitive window closing remains sequential, Chrome/Safari/Safari web apps are not force-killed, and `notify-mac` reports apps that remain running.

**Tech Stack:** Bash, zsh, AppleScript via `osascript`, optional `terminal-notifier`, optional `alerter`, Python `pytest` for shell-level regression tests, Codex/Claude skill files under `claude/skills/`.

---

## File Structure

- Create `custom_bins/notify-mac`: a reusable Bash helper for macOS notifications.
- Create `tests/test_notify_mac.py`: Python tests for backend selection, escaping, and dry-run behavior.
- Modify `custom_bins/clear-mac-apps`: use bundle IDs for quit targeting, run non-focus quit workers concurrently, collect result files, track failed apps, and notify on failures.
- Modify `config/clear_mac_apps.conf`: document browser force-quit safety and add an empty `[force-quit-ok]` section.
- Create `tests/test_clear_mac_apps_static.py`: static regression tests for browser safety and notification integration.
- Create `claude/skills/macos-notifications/SKILL.md`: global skill explaining notification backend policy.
- Create `claude/skills/macos-notifications/agents/openai.yaml`: UI metadata for the global skill.
- Modify `CLAUDE.md`: add a short Learnings entry if implementation reveals a durable project convention.

## Task 1: Add `notify-mac` With Dry-Run Tests

**Files:**
- Create: `custom_bins/notify-mac`
- Create: `tests/test_notify_mac.py`

- [ ] **Step 1: Write failing tests for simple notifications**

Create `tests/test_notify_mac.py` with:

```python
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTIFY = ROOT / "custom_bins" / "notify-mac"


def run_notify(*args, env=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        [str(NOTIFY), *args],
        cwd=ROOT,
        env=merged_env,
        text=True,
        capture_output=True,
        check=False,
    )


def test_simple_mode_defaults_to_osascript_in_dry_run():
    result = run_notify(
        "--dry-run",
        "--title",
        "Clear Mac Apps",
        "--message",
        "Still running: Google Chrome",
    )

    assert result.returncode == 0
    assert "backend=osascript" in result.stdout
    assert "title=Clear Mac Apps" in result.stdout
    assert "message=Still running: Google Chrome" in result.stdout


def test_backend_can_be_disabled_for_scripts_that_only_want_logs():
    result = run_notify(
        "--dry-run",
        "--backend",
        "none",
        "--title",
        "No UI",
        "--message",
        "Only print this",
    )

    assert result.returncode == 0
    assert "backend=none" in result.stdout
    assert result.stderr == ""


def test_missing_message_is_an_error():
    result = run_notify("--dry-run", "--title", "No message")

    assert result.returncode == 2
    assert "Missing required --message" in result.stderr
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
pytest tests/test_notify_mac.py -v
```

Expected: tests fail because `custom_bins/notify-mac` does not exist.

- [ ] **Step 3: Implement `notify-mac`**

Create `custom_bins/notify-mac`:

```bash
#!/bin/bash
# Send macOS notifications through one repo-local policy.

set -euo pipefail

TITLE="Notification"
SUBTITLE=""
MESSAGE=""
GROUP=""
SOUND=""
MODE="simple"
BACKEND="${NOTIFY_MAC_BACKEND:-auto}"
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: notify-mac --message TEXT [options]

Options:
  --title TEXT          Notification title (default: Notification)
  --subtitle TEXT       Notification subtitle
  --message TEXT        Notification body (required)
  --group ID            Notification group/replacement ID
  --sound NAME          macOS sound name, or default
  --mode MODE           simple, rich, or prompt (default: simple)
  --backend BACKEND     auto, osascript, terminal-notifier, alerter, none
  --dry-run             Print selected backend and payload without notifying
  -h, --help            Show this help
EOF
}

die_usage() {
    echo "$1" >&2
    usage >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)
            [[ $# -ge 2 ]] || die_usage "Missing value for --title"
            TITLE="$2"
            shift 2
            ;;
        --subtitle)
            [[ $# -ge 2 ]] || die_usage "Missing value for --subtitle"
            SUBTITLE="$2"
            shift 2
            ;;
        --message)
            [[ $# -ge 2 ]] || die_usage "Missing value for --message"
            MESSAGE="$2"
            shift 2
            ;;
        --group)
            [[ $# -ge 2 ]] || die_usage "Missing value for --group"
            GROUP="$2"
            shift 2
            ;;
        --sound)
            [[ $# -ge 2 ]] || die_usage "Missing value for --sound"
            SOUND="$2"
            shift 2
            ;;
        --mode)
            [[ $# -ge 2 ]] || die_usage "Missing value for --mode"
            MODE="$2"
            shift 2
            ;;
        --backend)
            [[ $# -ge 2 ]] || die_usage "Missing value for --backend"
            BACKEND="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die_usage "Unknown option: $1"
            ;;
    esac
done

[[ -n "$MESSAGE" ]] || die_usage "Missing required --message"

case "$MODE" in
    simple|rich|prompt) ;;
    *) die_usage "Invalid --mode: $MODE" ;;
esac

case "$BACKEND" in
    auto|osascript|terminal-notifier|alerter|none) ;;
    *) die_usage "Invalid --backend: $BACKEND" ;;
esac

select_backend() {
    if [[ "$BACKEND" != "auto" ]]; then
        printf '%s\n' "$BACKEND"
        return
    fi

    case "$MODE" in
        simple)
            printf 'osascript\n'
            ;;
        rich)
            if command -v terminal-notifier >/dev/null 2>&1; then
                printf 'terminal-notifier\n'
            else
                printf 'osascript\n'
            fi
            ;;
        prompt)
            if command -v alerter >/dev/null 2>&1; then
                printf 'alerter\n'
            else
                printf 'osascript\n'
            fi
            ;;
    esac
}

notify_with_osascript() {
    /usr/bin/osascript - "$TITLE" "$SUBTITLE" "$MESSAGE" "$SOUND" <<'APPLESCRIPT'
on run argv
    set titleText to item 1 of argv
    set subtitleText to item 2 of argv
    set messageText to item 3 of argv
    set soundText to item 4 of argv

    if subtitleText is "" and soundText is "" then
        display notification messageText with title titleText
    else if subtitleText is "" then
        display notification messageText with title titleText sound name soundText
    else if soundText is "" then
        display notification messageText with title titleText subtitle subtitleText
    else
        display notification messageText with title titleText subtitle subtitleText sound name soundText
    end if
end run
APPLESCRIPT
}

notify_with_terminal_notifier() {
    local -a args=(-title "$TITLE" -message "$MESSAGE")
    [[ -n "$SUBTITLE" ]] && args+=(-subtitle "$SUBTITLE")
    [[ -n "$GROUP" ]] && args+=(-group "$GROUP")
    [[ -n "$SOUND" ]] && args+=(-sound "$SOUND")
    terminal-notifier "${args[@]}"
}

notify_with_alerter() {
    local -a args=(--title "$TITLE" --message "$MESSAGE" --timeout 8)
    [[ -n "$SUBTITLE" ]] && args+=(--subtitle "$SUBTITLE")
    [[ -n "$GROUP" ]] && args+=(--group "$GROUP")
    [[ -n "$SOUND" ]] && args+=(--sound "$SOUND")
    alerter "${args[@]}" >/dev/null
}

SELECTED_BACKEND="$(select_backend)"

if "$DRY_RUN"; then
    printf 'backend=%s\n' "$SELECTED_BACKEND"
    printf 'mode=%s\n' "$MODE"
    printf 'title=%s\n' "$TITLE"
    printf 'subtitle=%s\n' "$SUBTITLE"
    printf 'message=%s\n' "$MESSAGE"
    printf 'group=%s\n' "$GROUP"
    printf 'sound=%s\n' "$SOUND"
    exit 0
fi

case "$SELECTED_BACKEND" in
    none)
        exit 0
        ;;
    osascript)
        notify_with_osascript
        ;;
    terminal-notifier)
        notify_with_terminal_notifier
        ;;
    alerter)
        notify_with_alerter
        ;;
esac
```

- [ ] **Step 4: Make the helper executable**

Run:

```bash
chmod +x custom_bins/notify-mac
```

Expected: command succeeds with no output.

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
pytest tests/test_notify_mac.py -v
```

Expected: all tests in `tests/test_notify_mac.py` pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add custom_bins/notify-mac tests/test_notify_mac.py
git commit -m "feat(macos): add notification helper"
```

Expected: commit succeeds.

## Task 2: Add Backend Selection Tests for Optional Notifiers

**Files:**
- Modify: `tests/test_notify_mac.py`

- [ ] **Step 1: Add tests with fake notifier binaries**

Append to `tests/test_notify_mac.py`:

```python
def make_fake_bin(tmp_path, name):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    fake = bin_dir / name
    fake.write_text("#!/bin/bash\nprintf '%s\\n' \"$0\" \"$@\"\n", encoding="utf-8")
    fake.chmod(0o755)
    return bin_dir


def test_rich_mode_prefers_terminal_notifier_when_available(tmp_path):
    bin_dir = make_fake_bin(tmp_path, "terminal-notifier")
    env = {"PATH": f"{bin_dir}:{os.environ['PATH']}"}

    result = run_notify(
        "--dry-run",
        "--mode",
        "rich",
        "--title",
        "Build",
        "--message",
        "Done",
        env=env,
    )

    assert result.returncode == 0
    assert "backend=terminal-notifier" in result.stdout


def test_prompt_mode_prefers_alerter_when_available(tmp_path):
    bin_dir = make_fake_bin(tmp_path, "alerter")
    env = {"PATH": f"{bin_dir}:{os.environ['PATH']}"}

    result = run_notify(
        "--dry-run",
        "--mode",
        "prompt",
        "--title",
        "Decision",
        "--message",
        "Continue?",
        env=env,
    )

    assert result.returncode == 0
    assert "backend=alerter" in result.stdout
```

- [ ] **Step 2: Run tests to verify they pass**

Run:

```bash
pytest tests/test_notify_mac.py -v
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

Run:

```bash
git add tests/test_notify_mac.py
git commit -m "test(macos): cover notification backend policy"
```

Expected: commit succeeds.

## Task 3: Add Static Safety Tests for `clear-mac-apps`

**Files:**
- Create: `tests/test_clear_mac_apps_static.py`

- [ ] **Step 1: Write failing static tests**

Create `tests/test_clear_mac_apps_static.py` with:

```python
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "custom_bins" / "clear-mac-apps"
CONFIG = ROOT / "config" / "clear_mac_apps.conf"


def read_script():
    return SCRIPT.read_text(encoding="utf-8")


def test_clear_mac_apps_uses_notify_mac_for_failed_quits():
    text = read_script()

    assert "notify_failed_quits()" in text
    assert "notify-mac" in text
    assert "failed_to_quit" in text
    assert "collect_failed_quits" in text


def test_clear_mac_apps_has_browser_force_quit_guard():
    text = read_script()

    assert "is_browser_like_app()" in text
    assert "com.google.Chrome" in text
    assert "com.apple.Safari" in text
    assert "com.apple.Safari.WebApp." in text


def test_clear_mac_apps_quits_by_bundle_id_when_available():
    text = read_script()

    assert "tell application id bidText to quit" in text
    assert "quit_app_gracefully" in text


def test_clear_mac_apps_runs_non_focus_quits_as_workers():
    text = read_script()

    assert "RESULT_DIR=" in text
    assert "run_quit_worker" in text
    assert "wait_for_quit_workers" in text
    assert "close_app_windows" in text


def test_config_documents_force_quit_allowlist():
    text = CONFIG.read_text(encoding="utf-8")

    assert "[force-quit-ok]" in text
    assert "Chrome, Safari, and Safari web apps are never force-killed" in text
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
pytest tests/test_clear_mac_apps_static.py -v
```

Expected: tests fail because `clear-mac-apps` does not have the new helper functions or config section.

- [ ] **Step 3: Commit tests**

Run:

```bash
git add tests/test_clear_mac_apps_static.py
git commit -m "test(macos): specify app clearing notification safety"
```

Expected: commit succeeds.

## Task 4: Refactor `clear-mac-apps` Quit Handling

**Files:**
- Modify: `custom_bins/clear-mac-apps`

- [ ] **Step 1: Add force-quit config parsing**

In `main()`, after loading `slow_quit_set`, add:

```zsh
    typeset -A force_quit_ok_set

    while IFS= read -r app; do
        [[ -n "$app" ]] && force_quit_ok_set[${(L)app}]=1
    done < <(get_entries_in_section "force-quit-ok")
```

After `typeset -A slow_quit_bids`, add:

```zsh
    typeset -A force_quit_ok_bids
```

After building `slow_quit_bids`, add:

```zsh
    for name in ${(k)force_quit_ok_set}; do
        [[ -n "${registry[$name]:-}" ]] && force_quit_ok_bids[${registry[$name]}]=1
    done
```

- [ ] **Step 2: Add browser and process helpers**

Add these functions after `quit_app()`:

```zsh
# Browser-like apps can have unsaved forms, downloads, or confirmation dialogs.
# Never force-kill them from this cleanup shortcut.
is_browser_like_app() {
    local app="$1"
    local bid="$2"
    local app_lower="${(L)app}"

    [[ "$bid" == "com.google.Chrome" ]] && return 0
    [[ "$bid" == "com.apple.Safari" ]] && return 0
    [[ "$bid" == com.apple.Safari.WebApp.* ]] && return 0
    [[ "$app_lower" == "google chrome" ]] && return 0
    [[ "$app_lower" == "safari" ]] && return 0
    return 1
}

# Quit by bundle ID when available; app names are not unique for Safari web apps.
quit_app_gracefully() {
    local app="$1"
    local bid="$2"

    if [[ -n "$bid" ]]; then
        osascript - "$bid" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    set bidText to item 1 of argv
    tell application id bidText to quit
end run
APPLESCRIPT
    else
        quit_app "$app"
    fi
}

is_app_running() {
    local app="$1"
    local bid="$2"

    if [[ -n "$bid" ]]; then
        osascript - "$bid" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    set bidText to item 1 of argv
    tell application "System Events"
        return exists (first process whose bundle identifier is bidText)
    end tell
end run
APPLESCRIPT
    else
        osascript - "$app" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    set appName to item 1 of argv
    tell application "System Events"
        return exists (first process whose name is appName)
    end tell
end run
APPLESCRIPT
    fi
}

wait_for_app_exit() {
    local app="$1"
    local bid="$2"
    local timeout="${3:-8}"
    local elapsed=0

    while (( elapsed < timeout )); do
        sleep 1
        elapsed=$((elapsed + 1))
        [[ "$(is_app_running "$app" "$bid")" != "true" ]] && return 0
    done

    return 1
}

force_kill_app() {
    local app="$1"
    local bid="$2"

    if [[ -n "$bid" ]]; then
        osascript - "$bid" <<'APPLESCRIPT' 2>/dev/null | while IFS= read -r pid; do
on run argv
    set bidText to item 1 of argv
    tell application "System Events"
        set pidList to unix id of every process whose bundle identifier is bidText
    end tell
    set output to ""
    repeat with pidValue in pidList
        set output to output & pidValue & linefeed
    end repeat
    return output
end run
APPLESCRIPT
            [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
        done
    else
        pkill -KILL -x "$app" 2>/dev/null || true
    fi
}
```

- [ ] **Step 3: Preserve bundle IDs in quit arrays**

Change the array declarations from app-name-only lists:

```zsh
    local -a apps_to_quit=()
    local -a apps_close_windows=()
    local -a apps_slow_quit=()
    local -a apps_selective_close=()
    local -a apps_skipped=()
```

to record entries:

```zsh
    local -a apps_to_quit=()
    local -a apps_close_windows=()
    local -a apps_slow_quit=()
    local -a apps_selective_close=()
    local -a apps_force_quit_ok=()
    local -a apps_skipped=()
    local -a failed_to_quit=()
    local -a quit_worker_pids=()
```

Inside the classification loop, set:

```zsh
        local record="${app}${SEP}${bid}"
```

Then replace app-name array appends with record appends:

```zsh
            apps_skipped+=("$record")
```

```zsh
            apps_slow_quit+=("$record")
```

```zsh
            apps_close_windows+=("$record")
```

For default quit classification, add force-quit allowlist handling:

```zsh
        elif (( ${+force_quit_ok_set[$app_lower]} )) || { [[ -n "$bid" ]] && (( ${+force_quit_ok_bids[$bid]} )) }; then
            apps_force_quit_ok+=("$record")
```

Use `apps_to_quit+=("$record")` and `apps_selective_close+=("$record")` in the remaining branches.

- [ ] **Step 4: Add record formatting helpers**

Add before the dry-run block:

```zsh
    app_from_record() {
        local record="$1"
        printf '%s\n' "${record%%${SEP}*}"
    }

    bid_from_record() {
        local record="$1"
        printf '%s\n' "${record#*${SEP}}"
    }
```

- [ ] **Step 5: Update dry-run output to print names**

For every dry-run loop, change:

```zsh
        for app in "${apps_to_quit[@]}"; do
            echo "  - $app"
        done
```

to:

```zsh
        for record in "${apps_to_quit[@]}"; do
            echo "  - $(app_from_record "$record")"
        done
```

Do the same for `apps_close_windows`, `apps_slow_quit`, `apps_selective_close`, and `apps_skipped`.

Add a force-eligible section after slow-quit:

```zsh
        echo "Would FORCE-QUIT IF NEEDED (${#apps_force_quit_ok}):"
        for record in "${apps_force_quit_ok[@]}"; do
            echo "  - $(app_from_record "$record")"
        done
        echo ""
```

- [ ] **Step 6: Add concurrent quit-worker helpers**

Add these functions before `main()`:

```zsh
write_quit_result() {
    local result_dir="$1"
    local status="$2"
    local app="$3"
    local message="$4"
    local result_file

    result_file="${result_dir}/result-$$-${RANDOM}"
    printf '%s\t%s\t%s\n' "$status" "$app" "$message" > "$result_file"
}

run_quit_worker() {
    local result_dir="$1"
    local mode="$2"
    local app="$3"
    local bid="$4"
    local graceful_timeout="$5"
    local force_timeout="$6"

    echo "Quitting: $app"
    quit_app_gracefully "$app" "$bid"
    if wait_for_app_exit "$app" "$bid" "$graceful_timeout"; then
        write_quit_result "$result_dir" "ok" "$app" "exited"
        return 0
    fi

    if [[ "$mode" != "force-ok" ]]; then
        write_quit_result "$result_dir" "failed" "$app" "still running after graceful quit"
        return 0
    fi

    if is_browser_like_app "$app" "$bid"; then
        write_quit_result "$result_dir" "failed" "$app" "browser-like app not force-killed"
        return 0
    fi

    echo "  Force-killing: $app"
    force_kill_app "$app" "$bid"
    if wait_for_app_exit "$app" "$bid" "$force_timeout"; then
        write_quit_result "$result_dir" "ok" "$app" "force-killed"
    else
        write_quit_result "$result_dir" "failed" "$app" "still running after force-kill"
    fi
}

start_quit_worker() {
    local result_dir="$1"
    local mode="$2"
    local record="$3"
    local graceful_timeout="$4"
    local force_timeout="${5:-3}"
    local app="$(app_from_record "$record")"
    local bid="$(bid_from_record "$record")"

    run_quit_worker "$result_dir" "$mode" "$app" "$bid" "$graceful_timeout" "$force_timeout" &
    quit_worker_pids+=("$!")
}

wait_for_quit_workers() {
    local -a pids=("$@")
    local pid

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

collect_failed_quits() {
    local result_dir="$1"
    local result_file status app message

    for result_file in "$result_dir"/result-*; do
        [[ -f "$result_file" ]] || continue
        IFS=$'\t' read -r status app message < "$result_file"
        if [[ "$status" == "failed" ]]; then
            echo "  Warning: $app $message"
            failed_to_quit+=("$app")
        fi
    done
}
```

- [ ] **Step 7: Add result directory lifecycle**

Before `main()`, add:

```zsh
RESULT_DIR=""

cleanup_result_dir() {
    [[ -n "$RESULT_DIR" && -d "$RESULT_DIR" ]] && rm -rf "$RESULT_DIR"
}
```

At the start of `main()`, after `main() {`, add:

```zsh
    trap cleanup_result_dir EXIT
```

After the dry-run block and before any real quit/close execution, add:

```zsh
    RESULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clear-mac-apps.XXXXXX")"
```

- [ ] **Step 8: Start non-focus quit workers concurrently**

Replace the existing default quit execution with:

```zsh
    # Phase A: non-focus quit work can run concurrently.
    for record in "${apps_to_quit[@]}"; do
        start_quit_worker "$RESULT_DIR" "graceful-only" "$record" 8 3
    done

    for record in "${apps_slow_quit[@]}"; do
        start_quit_worker "$RESULT_DIR" "graceful-only" "$record" 30 3
    done

    for record in "${apps_force_quit_ok[@]}"; do
        start_quit_worker "$RESULT_DIR" "force-ok" "$record" 8 3
    done

    # Chrome selective close does not use keyboard focus, but keep it separate
    # from any Chrome quit operation.
    local chrome_is_quitting=false
    for record in "${apps_to_quit[@]}" "${apps_slow_quit[@]}" "${apps_force_quit_ok[@]}"; do
        [[ "$(app_from_record "$record")" == "Google Chrome" ]] && chrome_is_quitting=true
    done

    if ! $chrome_is_quitting; then
        for record in "${apps_selective_close[@]}"; do
            local app="$(app_from_record "$record")"
            echo "Selective-close: $app"
            close_app_selectively "$app" "${protected_patterns[@]}" &
            quit_worker_pids+=("$!")
        done
    fi

    wait_for_quit_workers "${quit_worker_pids[@]}"
    collect_failed_quits "$RESULT_DIR"
```

- [ ] **Step 9: Keep focus-sensitive close-window work sequential**

Replace the existing close-window loop with:

```zsh
    # Phase B: Cmd+W requires global keyboard focus, so keep this sequential.
    for record in "${apps_close_windows[@]}"; do
        local app="$(app_from_record "$record")"
        echo "Closing windows: $app"
        close_app_windows "$app" 3
    done
```

If Chrome was also in a quit bucket, skip selective-close because the quit worker already handled it. If Chrome was not quitting, selective-close already ran in Phase A. Add this explicit skipped case after Phase B:

```zsh
    if $chrome_is_quitting && (( ${#apps_selective_close} > 0 )); then
        echo "Skipping selective-close because Chrome is already quitting"
    fi
```

- [ ] **Step 10: Add failure notification**

Add this function before `main()`:

```zsh
notify_failed_quits() {
    local -a failed_apps=("$@")
    (( ${#failed_apps} == 0 )) && return 0

    local message="Still running: ${(j:, :)failed_apps}"
    echo "Warning: $message" >&2

    local notify_bin="${SCRIPT_DIR}/notify-mac"
    if [[ -x "$notify_bin" ]]; then
        "$notify_bin" \
            --mode simple \
            --title "Clear Mac Apps" \
            --message "$message" \
            --group "clear-mac-apps-failed" \
            2>/dev/null || true
    else
        osascript - "$message" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    display notification (item 1 of argv) with title "Clear Mac Apps"
end run
APPLESCRIPT
    fi
}
```

Before final `echo "Done."`, add:

```zsh
    notify_failed_quits "${failed_to_quit[@]}"
```

- [ ] **Step 11: Run static tests**

Run:

```bash
pytest tests/test_clear_mac_apps_static.py -v
```

Expected: all tests pass.

- [ ] **Step 12: Run zsh syntax check**

Run:

```bash
zsh -n custom_bins/clear-mac-apps
```

Expected: command exits 0 with no output.

- [ ] **Step 13: Run dry-run smoke test**

Run:

```bash
custom_bins/clear-mac-apps --dry-run
```

Expected: output lists running apps by category or shows a real macOS Automation/System Events error. If System Events returns `-10827`, note it in the final report and do not treat dry-run classification as verified.

- [ ] **Step 14: Commit**

Run:

```bash
git add custom_bins/clear-mac-apps
git commit -m "fix(macos): report apps that refuse to quit"
```

Expected: commit succeeds.

## Task 5: Document Force-Quit Policy in Config

**Files:**
- Modify: `config/clear_mac_apps.conf`

- [ ] **Step 1: Add force-quit section**

Append this section before `[protected-windows]`:

```conf
###

# [force-quit-ok] - Apps that may be force-killed if graceful quit fails
# Chrome, Safari, and Safari web apps are never force-killed even if listed here.
# Keep this list short; force-kill can lose unsaved state.
[force-quit-ok]

```

- [ ] **Step 2: Run config/static tests**

Run:

```bash
pytest tests/test_clear_mac_apps_static.py -v
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

Run:

```bash
git add config/clear_mac_apps.conf tests/test_clear_mac_apps_static.py
git commit -m "docs(macos): document app force-quit policy"
```

Expected: commit succeeds.

## Task 6: Add Global `macos-notifications` Skill

**Files:**
- Create: `claude/skills/macos-notifications/SKILL.md`
- Create: `claude/skills/macos-notifications/agents/openai.yaml`

- [ ] **Step 1: Create skill directory**

Run:

```bash
mkdir -p claude/skills/macos-notifications/agents
```

Expected: command succeeds.

- [ ] **Step 2: Write `SKILL.md`**

Create `claude/skills/macos-notifications/SKILL.md`:

```markdown
---
name: macos-notifications
description: Use when adding, changing, debugging, or choosing notification behavior for macOS scripts, launchd jobs, Shortcuts, hooks, watchdogs, cleanup tools, or shell automations. Guides when to use osascript, terminal-notifier, alerter, or the repo-local notify-mac helper.
---

# macOS Notifications

Use this skill when work touches macOS notifications from shell scripts, launchd jobs, Shortcuts, hooks, watchdogs, or cleanup automation.

## Default Policy

- Prefer `custom_bins/notify-mac` in this repo instead of calling notification tools directly.
- Use `osascript display notification` for simple fire-and-forget messages.
- Use `terminal-notifier` for richer fire-and-forget notifications that need grouping, sender attribution, click behavior, or sounds.
- Use `alerter` only for prompt-like alerts that need buttons, replies, persistence, JSON results, or a timeout-controlled interaction.
- Always print the same important message to stdout or stderr so terminal runs remain auditable.

## Why

`osascript` is built into macOS and has the smallest dependency surface. `terminal-notifier` is repo-managed through the `extras` install set and is suitable for non-blocking notifications. `alerter` is newer and more interactive, but it can block until the user interacts or a timeout fires, so it should not be the default for background scripts.

## Implementation Checklist

1. Decide notification class:
   - `simple`: failure/status message only.
   - `rich`: grouped or app-attributed status message.
   - `prompt`: user decision is required.
2. Call `notify-mac --mode simple|rich|prompt --title ... --message ...`.
3. For failure notifications, include the actionable object names in the message.
4. Add tests or dry-run coverage for backend selection when changing shared notification behavior.
5. Do not add a direct dependency on `alerter` unless the workflow needs interactivity.

## Examples

Simple failure:

```bash
custom_bins/notify-mac \
  --mode simple \
  --title "Clear Mac Apps" \
  --message "Still running: Google Chrome, Safari"
```

Grouped rich notification:

```bash
custom_bins/notify-mac \
  --mode rich \
  --title "Claude Watchdog" \
  --subtitle "$project" \
  --message "$msg" \
  --group "claude-watchdog-$session_id" \
  --sound "Submarine"
```

Prompt-like notification:

```bash
custom_bins/notify-mac \
  --mode prompt \
  --title "Cleanup" \
  --message "Force quit remaining app?"
```
```

- [ ] **Step 3: Write `agents/openai.yaml`**

Create `claude/skills/macos-notifications/agents/openai.yaml`:

```yaml
interface:
  display_name: "macOS Notifications"
  short_description: "Choose safe macOS notification backends"
  default_prompt: "Use $macos-notifications to add reliable macOS notification behavior to this script."

policy:
  allow_implicit_invocation: true
```

- [ ] **Step 4: Validate skill shape**

Run:

```bash
test -f claude/skills/macos-notifications/SKILL.md
test -f claude/skills/macos-notifications/agents/openai.yaml
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
git add claude/skills/macos-notifications
git commit -m "feat(skills): add macOS notifications guidance"
```

Expected: commit succeeds.

## Task 7: Optionally Migrate Existing Direct Notification Calls

**Files:**
- Modify: `claude/hooks/watchdog.sh`
- Modify: `scripts/security/audit_dependencies.sh`

- [ ] **Step 1: Inspect direct notification calls**

Run:

```bash
rg -n "terminal-notifier|display notification|alerter|notify-send" claude scripts custom_bins config
```

Expected: output includes `claude/hooks/watchdog.sh` and `scripts/security/audit_dependencies.sh`.

- [ ] **Step 2: Update watchdog to use `notify-mac --mode rich`**

In `claude/hooks/watchdog.sh`, replace `send_notification()` with:

```bash
send_notification() {
  local msg="$1" project="$2" session="$3"
  local notify_bin="$HOME/code/dotfiles/custom_bins/notify-mac"

  if [[ -x "$notify_bin" ]]; then
    "$notify_bin" \
      --mode rich \
      --title "Claude Watchdog" \
      --subtitle "$project" \
      --message "$msg" \
      --sound "Submarine" \
      --group "claude-watchdog-${session}" \
      2>/dev/null || true
  elif [[ "$(uname)" == "Darwin" ]]; then
    osascript -e "display notification \"$msg\" with title \"Claude Watchdog\" subtitle \"$project\" sound name \"Submarine\"" 2>/dev/null || true
  fi

  printf '\a' 2>/dev/null || true
}
```

- [ ] **Step 3: Update dependency audit to use `notify-mac --mode simple`**

In `scripts/security/audit_dependencies.sh`, replace the macOS notification line with:

```bash
        notify_bin="$HOME/code/dotfiles/custom_bins/notify-mac"
        if [[ -x "$notify_bin" ]]; then
            "$notify_bin" --mode simple --title "Dependency Audit" --message "$issues_found supply chain issue(s) found" 2>/dev/null || true
        else
            osascript -e "display notification \"$issues_found supply chain issue(s) found\" with title \"Dependency Audit\"" 2>/dev/null || true
        fi
```

- [ ] **Step 4: Run syntax checks**

Run:

```bash
bash -n claude/hooks/watchdog.sh
bash -n scripts/security/audit_dependencies.sh
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
git add claude/hooks/watchdog.sh scripts/security/audit_dependencies.sh
git commit -m "refactor(macos): route notifications through helper"
```

Expected: commit succeeds.

## Task 8: Final Verification

**Files:**
- Test only.

- [ ] **Step 1: Run all focused tests**

Run:

```bash
pytest tests/test_notify_mac.py tests/test_clear_mac_apps_static.py -v
```

Expected: all tests pass.

- [ ] **Step 2: Run shell syntax checks**

Run:

```bash
bash -n custom_bins/notify-mac
zsh -n custom_bins/clear-mac-apps
bash -n claude/hooks/watchdog.sh
bash -n scripts/security/audit_dependencies.sh
```

Expected: all commands exit 0.

- [ ] **Step 3: Run notification dry-run smoke tests**

Run:

```bash
custom_bins/notify-mac --dry-run --mode simple --title "Test" --message "Hello"
custom_bins/notify-mac --dry-run --mode rich --title "Test" --message "Hello" --group "test"
custom_bins/notify-mac --dry-run --mode prompt --title "Test" --message "Hello"
```

Expected: commands exit 0 and print selected backend plus payload.

- [ ] **Step 4: Run app clearing dry-run**

Run:

```bash
custom_bins/clear-mac-apps --dry-run
```

Expected: command exits 0 and prints categorized apps. If macOS returns System Events error `-10827`, report that the test was blocked by local Automation/System Events state.

- [ ] **Step 5: Review git diff**

Run:

```bash
git diff --stat HEAD
git diff HEAD -- custom_bins/notify-mac custom_bins/clear-mac-apps config/clear_mac_apps.conf claude/skills/macos-notifications tests/test_notify_mac.py tests/test_clear_mac_apps_static.py
```

Expected: diff only contains planned notification helper, app clearing, skill, and tests.

## Self-Review

**Spec coverage:** The plan covers general macOS notification policy, compares backend roles by encoding them into `notify-mac`, keeps `clear-mac-apps` on simple built-in notifications, runs non-focus quit work concurrently in subprocesses, keeps focus-sensitive window closing sequential, prevents browser force-kill, reports apps that fail to quit, and creates a globally exposed skill.

**Placeholder scan:** No deferred-work markers remain. Code-changing steps include concrete code or exact replacement snippets.

**Type and name consistency:** The plan consistently uses `notify-mac`, `macos-notifications`, `failed_to_quit`, `RESULT_DIR`, `run_quit_worker`, `wait_for_quit_workers`, `collect_failed_quits`, `is_browser_like_app`, `quit_app_gracefully`, and `force-quit-ok`.
