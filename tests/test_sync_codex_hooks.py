"""Migration coverage using the imported hooks observed on 2026-09-08.

All installation targets and symlink destinations are temporary directories.
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/setup/sync_codex_hooks.py"
# Actual imported manifest, with only its machine-specific target substituted.
IMPORTED_MANIFEST = r'''
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/check_loop_bypass.sh'",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "python3 '{target}/hooks/network_audit.py'",
            "timeout": 3,
            "statusMessage": "Auditing network intent"
          },
          {
            "type": "command",
            "command": "'{target}/hooks/nudge_modern_tools.sh'",
            "timeout": 3
          },
          {
            "type": "command",
            "command": "'{target}/hooks/warn_dep_install.sh'",
            "timeout": 3
          }
        ]
      },
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/check_agent_depth.sh'",
            "timeout": 3
          }
        ]
      },
      {
        "matcher": "WebFetch",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/check_webfetch_domain.sh'",
            "timeout": 3
          }
        ]
      },
      {
        "matcher": "mcp__claude-in-chrome__tabs_context_mcp",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/block_tab_group_creation.sh'",
            "timeout": 3
          }
        ]
      },
      {
        "matcher": "mcp__claude_ai_Gmail__gmail_create_draft",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/nudge_html_email.sh'",
            "timeout": 3
          }
        ]
      },
      {
        "matcher": "EnterPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/require_plan_approval.sh'",
            "timeout": 3
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/with-anthropic-key.sh' python3 '{target}/hooks/auto_classify.py'",
            "timeout": 15
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Grep",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/retry_omitted_grep.sh'",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/agent_spawned.sh'",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/check_git_root.sh'",
            "timeout": 3
          },
          {
            "type": "command",
            "command": "'{target}/hooks/check_venv.sh'",
            "timeout": 3
          },
          {
            "type": "command",
            "command": "'{target}/hooks/session_start_notes.sh'",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "'{target}/hooks/show_auth_account.sh'",
            "timeout": 5
          },
          {
            "type": "command",
            "command": "'{target}/hooks/context_auto_apply.sh'",
            "timeout": 10
          },
          {
            "type": "command",
            "command": "'{target}/hooks/check_things_mcp.sh'",
            "timeout": 3
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/watchdog_mark.sh' working",
            "timeout": 3
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'{target}/hooks/watchdog_mark.sh' idle",
            "timeout": 3
          },
          {
            "type": "command",
            "command": "'{target}/hooks/nudge_remember.sh'",
            "timeout": 3
          },
          {
            "type": "command",
            "command": "'{target}/hooks/with-anthropic-key.sh' '{target}/hooks/session_rename_auto.sh'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
'''


def snapshot(directory: Path) -> dict[str, bytes]:
    return {
        str(path.relative_to(directory)): path.read_bytes()
        for path in directory.rglob("*") if path.is_file()
    }


def seed_target(tmp_path: Path) -> Path:
    target = tmp_path / "codex-home"
    target.mkdir()
    (target / "hooks").mkdir()
    (target / "hooks.json").write_text(IMPORTED_MANIFEST.replace("{target}", str(target)) + "\n")
    (target / "AGENTS.md").write_text("# Personal guidance\n\nKeep this exact custom instruction.\n")
    (target / "hooks/nudge_modern_tools.sh").write_text("#!/bin/bash\nexit 2\n")
    (target / "hooks/custom.sh").write_text("#!/bin/bash\nprintf 'custom'\n")
    (target / "config.toml").write_text('model = "personal-model"\n')
    (target / "history.jsonl").write_text('{"text":"private history fixture"}\n')
    return target


def run_sync(target: Path, *, apply: bool = False, use_env: bool = False) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(SCRIPT)]
    environment = os.environ.copy()
    if use_env:
        environment["CODEX_HOME"] = str(target)
    else:
        command += ["--target", str(target)]
    if apply:
        command += ["--apply"]
    return subprocess.run(command, cwd=ROOT, env=environment, text=True, capture_output=True)


def test_dry_run_preserves_actual_imported_manifest_and_all_files(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    before = snapshot(target)
    result = run_sync(target)
    assert result.returncode == 0, result.stderr
    assert "Would update:" in result.stdout
    assert snapshot(target) == before
    assert not (target / "backups").exists()


def test_apply_preserves_custom_handlers_metadata_and_unrelated_files(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    existing = json.loads((target / "hooks.json").read_text())
    custom = {"type": "command", "command": str(target / "hooks/custom.sh"), "timeout": 17, "statusMessage": "Custom status"}
    unfamiliar = {"type": "command", "command": "bash /some/other/project/hooks/nudge_modern_tools.sh", "timeout": 8}
    group = existing["hooks"]["PreToolUse"][0]
    group["customMetadata"] = {"preserve": True}
    group["hooks"] += [custom, unfamiliar]
    custom_group = {"matcher": "*", "customMetadata": "keep", "hooks": [{"type": "prompt", "prompt": "Custom prompt"}]}
    existing["hooks"]["CustomEvent"] = [custom_group]
    existing["customTopLevel"] = [1, 2, 3]
    existing["description"] = "Personal description"
    (target / "hooks.json").write_text(json.dumps(existing) + "\n")
    before = snapshot(target)
    source_before = snapshot(ROOT / "codex")

    result = run_sync(target, apply=True)
    assert result.returncode == 0, result.stderr
    installed = json.loads((target / "hooks.json").read_text())
    assert installed["customTopLevel"] == [1, 2, 3]
    assert installed["description"] == "Personal description"
    assert installed["hooks"]["CustomEvent"] == [custom_group]
    assert installed["hooks"]["PreToolUse"][0] == {
        "matcher": "Bash", "customMetadata": {"preserve": True}, "hooks": [custom, unfamiliar]
    }
    for event in ["Stop", "PermissionRequest", "PostToolUse", "UserPromptSubmit"]:
        assert event not in installed["hooks"]
    maintained = json.loads((ROOT / "codex/hooks.json").read_text())
    assert installed["hooks"]["SessionStart"] == maintained["hooks"]["SessionStart"]
    assert installed["hooks"]["PreToolUse"][1:] == maintained["hooks"]["PreToolUse"]
    assert (target / "AGENTS.md").read_text().startswith(before["AGENTS.md"].decode())
    for name in ["config.toml", "history.jsonl", "hooks/custom.sh"]:
        assert (target / name).read_bytes() == before[name]
    for source in (ROOT / "codex/hooks").glob("*"):
        if source.is_file() and source.suffix in (".py", ".sh"):
            assert (target / "hooks" / source.name).read_bytes() == source.read_bytes()
    assert snapshot(ROOT / "codex") == source_before


def test_backups_exactly_preserve_replaced_bytes_and_second_apply_is_noop(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    before = snapshot(target)
    first = run_sync(target, apply=True)
    assert first.returncode == 0, first.stderr
    backups = list((target / "backups").iterdir())
    assert len(backups) == 1
    for name in ["hooks.json", "AGENTS.md", "hooks/nudge_modern_tools.sh"]:
        saved = backups[0] / name
        assert saved.read_bytes() == before[name]
        assert saved.stat().st_mode & 0o777 == 0o600
    after_first = snapshot(target)
    second = run_sync(target, apply=True)
    assert second.returncode == 0, second.stderr
    assert "already synchronized" in second.stdout
    assert snapshot(target) == after_first
    assert list((target / "backups").iterdir()) == backups


def test_codex_home_environment_selects_custom_target(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    result = run_sync(target, apply=True, use_env=True)
    assert result.returncode == 0, result.stderr
    assert (target / "hooks/context.py").exists()
    assert "BEGIN CODEX TOOL COMPATIBILITY" in (target / "AGENTS.md").read_text()
    installed = json.loads((target / "hooks.json").read_text())
    assert list(installed["hooks"]) == ["PreToolUse", "SessionStart"]


def assert_file_symlink_refused(tmp_path: Path, name: str) -> None:
    target = seed_target(tmp_path)
    path = target / name
    outside = tmp_path / "outside-file"
    path.rename(outside)
    path.symlink_to(outside)
    before = snapshot(target)
    outside_before = outside.read_bytes()
    result = run_sync(target, apply=True)
    assert result.returncode != 0
    assert "symlink" in result.stderr.lower()
    assert path.is_symlink()
    assert snapshot(target) == before
    assert outside.read_bytes() == outside_before
    assert not (target / "backups").exists()


def test_refuses_symlinked_hooks_directory_before_any_writes(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    outside = tmp_path / "outside-hooks"
    (target / "hooks").rename(outside)
    (target / "hooks").symlink_to(outside, target_is_directory=True)
    before = snapshot(target)
    outside_before = snapshot(outside)
    result = run_sync(target, apply=True)
    assert result.returncode != 0
    assert "symlink" in result.stderr.lower()
    assert snapshot(target) == before
    assert snapshot(outside) == outside_before
    assert not (target / "backups").exists()


def test_recognized_script_mentioned_as_data_does_not_own_custom_handler(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    existing = json.loads((target / "hooks.json").read_text())
    custom = {"type": "command", "command": "printf '%s' " + str(target / "hooks/context.py")}
    existing["hooks"]["Stop"][0]["hooks"].append(custom)
    (target / "hooks.json").write_text(json.dumps(existing))
    result = run_sync(target, apply=True)
    assert result.returncode == 0, result.stderr
    installed = json.loads((target / "hooks.json").read_text())
    assert installed["hooks"].get("Stop") == [{"hooks": [custom]}]


def test_refuses_changed_file_symlinks_without_partial_install(tmp_path: Path) -> None:
    for name in ["hooks.json", "AGENTS.md", "hooks/nudge_modern_tools.sh"]:
        case = tmp_path / name.replace("/", "-")
        case.mkdir()
        assert_file_symlink_refused(case, name)


def test_empty_codex_home_defaults_to_home_dotcodex(tmp_path: Path) -> None:
    target = seed_target(tmp_path)
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    target = target.rename(fake_home / ".codex")
    environment = os.environ.copy()
    environment.update(HOME=str(fake_home), CODEX_HOME="")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--apply"], cwd=tmp_path,
        env=environment, text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert (target / "hooks/context.py").exists()
    assert "BEGIN CODEX TOOL COMPATIBILITY" in (target / "AGENTS.md").read_text()
    assert not (tmp_path / "hooks.json").exists()
    assert not (tmp_path / "AGENTS.md").exists()


def test_source_target_manifest_alias_preserves_custom_handler_idempotently(tmp_path: Path) -> None:
    fake_repo = tmp_path / "repository"
    source = fake_repo / "codex"
    (source / "hooks").mkdir(parents=True)
    for name in ["hooks.json", "AGENTS.md", "tool-compatibility.md"]:
        shutil.copy2(ROOT / "codex" / name, source / name)
    for script in (ROOT / "codex/hooks").glob("*"):
        if script.is_file() and script.suffix in (".py", ".sh"):
            shutil.copy2(script, source / "hooks" / script.name)
    manifest = source / "hooks.json"
    data = json.loads(manifest.read_text())
    custom = {"matcher": "*", "hooks": [{"type": "command", "command": "/custom/hooks/notify.sh", "timeout": 9}]}
    data["hooks"].setdefault("Stop", []).append(custom)
    manifest.write_text(json.dumps(data, indent=2) + "\n")
    agents = source / "AGENTS.md"
    agents.write_text(agents.read_text().rstrip() + "\n\n" + (source / "tool-compatibility.md").read_text())
    target = tmp_path / ".codex"
    target.symlink_to(source, target_is_directory=True)
    before = snapshot(source)

    spec = importlib.util.spec_from_file_location("sync_codex_hooks_alias_test", SCRIPT)
    assert spec is not None and spec.loader is not None
    installer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(installer)
    output = io.StringIO()
    with mock.patch.object(installer, "REPO", fake_repo), contextlib.redirect_stdout(output):
        installer.install(target, apply=True)
        installer.install(target, apply=True)

    assert snapshot(source) == before
    assert target.is_symlink()
    assert json.loads(manifest.read_text())["hooks"]["Stop"] == [custom]
    assert output.getvalue().count("already synchronized") == 2
    assert not (source / "backups").exists()


def standalone_suite() -> unittest.TestSuite:
    # pytest can also collect these tests; stdlib runner avoids installing it.
    suite = unittest.TestSuite()
    for name, test in sorted(globals().items()):
        if name.startswith("test_") and callable(test):
            def run(test=test):
                with tempfile.TemporaryDirectory(prefix="codex-hook-sync-test-") as directory:
                    test(Path(directory))
            suite.addTest(unittest.FunctionTestCase(run, description=name))
    return suite


def load_tests(loader, tests, pattern):
    return standalone_suite()


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(standalone_suite())
    sys.exit(not result.wasSuccessful())
