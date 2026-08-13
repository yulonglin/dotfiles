#!/usr/bin/env bash
# Tests for the central hook feature gate and active advisory registrations.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
GATE="$DIR/hook_feature.py"
WRAPPER="$DIR/hook_feature.sh"
PASS=0
FAIL=0
TMP=""

for cand in "${TMPDIR:-}" /tmp/claude /tmp .; do
    [ -n "$cand" ] || continue
    if mkdir -p "$cand/hook-feature-tests.$$" 2>/dev/null; then
        TMP="$cand/hook-feature-tests.$$"
        break
    fi
done
[ -n "$TMP" ] || { printf 'no writable temp dir found\n' >&2; exit 1; }
trap 'trash "$TMP" >/dev/null 2>&1 || true' EXIT

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

run_gate() {
    local conf=$1
    shift
    CLAUDE_HOOK_FEATURES_FILE="$conf" python3 "$GATE" "$@"
}

run_wrapper() {
    local conf=$1
    shift
    CLAUDE_HOOK_FEATURES_FILE="$conf" bash "$WRAPPER" "$@"
}

expect_status() {
    local desc=$1 want=$2
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq "$want" ]; then ok; else bad "$desc (expected $want, got $rc)"; fi
}

printf '%s\n' '=== hierarchical lookup ==='
MISSING="$TMP/missing.conf"
expect_status "missing config defaults on" 0 run_gate "$MISSING" enabled nudges.modern-tools

CONF="$TMP/features.conf"
printf '%s\n' 'nudges = off' > "$CONF"
expect_status "parent off disables child" 1 run_gate "$CONF" enabled nudges.modern-tools

printf '%s\n' 'nudges = off' 'nudges.modern-tools = on' > "$CONF"
expect_status "exact child overrides parent" 0 run_gate "$CONF" enabled nudges.modern-tools
expect_status "sibling still inherits parent" 1 run_gate "$CONF" enabled nudges.experiment-jobs

printf '%s\n' 'nudges = on' 'nudges.modern-tools = off' > "$CONF"
expect_status "exact off overrides parent" 1 run_gate "$CONF" enabled nudges.modern-tools
expect_status "other child inherits on" 0 run_gate "$CONF" enabled nudges.experiment-jobs

printf '%s\n' '# comment' 'nudges = maybe' 'not a setting' > "$CONF"
expect_status "invalid values fail open" 0 run_gate "$CONF" enabled nudges.modern-tools

printf '%s\n' '=== checked-in policy ==='
expect_status "checked-in config disables nudges" 1 python3 "$GATE" enabled nudges.modern-tools

printf '%s\n' '=== command gate ==='
printf '%s\n' 'nudges = off' > "$CONF"
SENTINEL="$TMP/ran"
# shellcheck disable=SC2016  # $1 expands inside the child bash, not this test shell.
out=$(printf 'payload' | run_wrapper "$CONF" run nudges.test -- bash -c 'cat; touch "$1"' _ "$SENTINEL")
if [ -z "$out" ] && [ ! -e "$SENTINEL" ]; then ok; else bad "disabled command was not silent and side-effect free"; fi
expect_status "disabled command returns success" 0 run_wrapper "$CONF" run nudges.test -- false
if CLAUDE_HOOK_FEATURES_FILE="$CONF" python3 - "$WRAPPER" <<'PY'
import os
import subprocess
import sys

payload = b"x" * 200_000
result = subprocess.run(
    ["bash", sys.argv[1], "run", "nudges.test", "--", "false"],
    input=payload,
    env=os.environ,
    timeout=3,
)
raise SystemExit(result.returncode)
PY
then ok; else bad "disabled command did not drain a large stdin payload"; fi

printf '%s\n' 'nudges = on' > "$CONF"
# shellcheck disable=SC2016  # $1 expands inside the child bash, not this test shell.
out=$(printf 'payload' | run_wrapper "$CONF" run nudges.test -- bash -c 'cat; touch "$1"' _ "$SENTINEL")
if [ "$out" = "payload" ] && [ -e "$SENTINEL" ]; then ok; else bad "enabled command did not preserve stdin or execute"; fi
expect_status "soft child failure cannot block" 0 run_wrapper "$CONF" run nudges.test -- bash -c 'exit 2'
expect_status "missing gate implementation fails open" 0 env CLAUDE_HOOK_FEATURE_PY="$TMP/missing.py" bash "$WRAPPER" run nudges.test -- false

printf '%s\n' '=== active advisory registrations ==='
python3 - "$ROOT/claude/settings.json" "$ROOT/claude/hooks" <<'PY' || FAIL=$((FAIL + 1))
import json
import re
import shlex
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
hooks_dir = Path(sys.argv[2])
settings = json.loads(settings_path.read_text())
external = {
    "retry_omitted_grep.sh",
    "nudge_send_user_file.sh",
    "nudge_syspath.sh",
    "nudge_statusline_parity.sh",
    "codex_plan_write_reminder.mjs",
    "codex_code_review_reminder.mjs",
    "nudge_modern_tools.sh",
    "warn_dep_install.sh",
    "nudge_experiment_jobs.sh",
    "codex_git_add_reminder.mjs",
    "nudge_html_email.sh",
    "nudge_remember.sh",
    "simplify_nudge.sh",
    "nudge_vault_lint.sh",
    "check_git_root.sh",
    "check_venv.sh",
    "check_things_mcp.sh",
    "anthropic_keycheck.py",
}
mixed = {
    "session_rename_commit.sh": (
        "nudges.session-rename",
        '[[ "$feature_rc" -ne 1 ]]',
    ),
    "pre_session_start.sh": (
        "nudges.session-start-warnings",
        '[[ "$feature_rc" -eq 1 ]] && advisory_enabled=false',
    ),
}
state_only = {"simplify_track_reuse.py", "simplify_mark_dirty.sh"}
safety = {
    "block_destructive_git.sh",
    "block_email_send.sh",
    "block_gws_delete.sh",
    "block_secret_expansion.sh",
    "block_tab_group_creation.sh",
    "block_vault_structure.sh",
    "check_agent_depth.sh",
    "check_loop_bypass.sh",
    "check_webfetch_domain.sh",
    "guard_post_rebase.sh",
    "guard_settings_commit.sh",
    "mask_env_read.sh",
    "nudge_bg_prose_question.sh",
    "require_plan_approval.sh",
}
operational = {
    "agent_spawned.sh",
    "approval_classifier.py",
    "auto_commit.sh",
    "context_auto_apply.sh",
    "detect_repo_trust.sh",
    "fix_hook_permissions.sh",
    "hook_feature.sh",
    "inject_vault_layout.sh",
    "mark_failed_sync.sh",
    "network_audit.py",
    "reap_jobs.sh",
    "romp-postal-context.sh",
    "romp-postal-drain.sh",
    "romp-postal-ensure.sh",
    "romp-postal-revive.sh",
    "romp-summarize.sh",
    "romp-wake.sh",
    "session_rename_auto.sh",
    "session_start_notes.sh",
    "show_auth_account.sh",
    "ssh_check.py",
    "tmux-status.sh",
    "watchdog_mark.sh",
    "watchdog_start.sh",
    "watchdog_stop.sh",
    "with-anthropic-key.sh",
}
commands = [
    hook.get("command", "")
    for groups in settings["hooks"].values()
    for group in groups
    for hook in group.get("hooks", [])
]
errors = []

for script in sorted(external):
    matches = [command for command in commands if script in command]
    if not matches:
        errors.append(f"missing active advisory registration: {script}")
    elif not all("hook_feature.sh run nudges." in command and " -- " in command for command in matches):
        errors.append(f"advisory hook bypasses feature gate: {script}: {matches}")

for script, (feature, fail_open_contract) in mixed.items():
    matches = [command for command in commands if script in command]
    if not matches:
        errors.append(f"missing mixed hook registration: {script}")
    elif any("hook_feature" in command for command in matches):
        errors.append(f"mixed hook must stay directly registered: {script}: {matches}")
    source = (hooks_dir / script).read_text()
    call = rf'hook_feature\.py["\s]+enabled\s+{re.escape(feature)}(?:\s|[";>])'
    if not re.search(call, source):
        errors.append(f"mixed hook does not gate only its advisory output: {script}")
    if fail_open_contract not in source:
        errors.append(f"mixed hook must treat only exit 1 as disabled: {script}")

pre_session_source = (hooks_dir / "pre_session_start.sh").read_text()
if "if ! $classify_ok; then\n    # Loud terminal warning" not in pre_session_source:
    errors.append("degraded-classifier terminal alert must remain active when context nudges are off")

for script in state_only:
    matches = [command for command in commands if script in command]
    if not matches:
        errors.append(f"missing state-only hook: {script}")
    elif any("hook_feature" in command for command in matches):
        errors.append(f"state-only hook must stay active: {script}: {matches}")

for script in safety:
    matches = [command for command in commands if script in command]
    if not matches:
        errors.append(f"missing safety hook: {script}")
    elif any("hook_feature" in command for command in matches):
        errors.append(f"safety hook must not be feature-gated: {script}")

# Exhaustive partition: every hook script registered in settings must be
# classified. New hooks fail closed at review time until their role is explicit.
classified = external | set(mixed) | state_only | safety | operational
registered = set()
for command in commands:
    for token in shlex.split(command):
        if ".claude/hooks/" not in token:
            continue
        registered.add(Path(token).name)
for script in sorted(registered - classified):
    errors.append(f"unclassified registered hook: {script}")
for script in sorted(classified - registered):
    errors.append(f"classified hook is not registered: {script}")

if not (hooks_dir / "hook_feature.py").is_file() or not (hooks_dir / "hook_feature.sh").is_file():
    errors.append("settings gate implementation is missing")

if errors:
    print("\n".join(f"FAIL: {error}" for error in errors))
    raise SystemExit(1)
print(
    f"PASS: {len(external)} external advisories gated; "
    f"{len(mixed)} mixed hooks internally gated; "
    f"{len(state_only)} state hooks active; {len(safety)} safety hooks active"
)
PY
[ "$FAIL" -eq 0 ] && ok

printf '\nResults: %d passed, %d failed (total %d)\n' "$PASS" "$FAIL" "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
