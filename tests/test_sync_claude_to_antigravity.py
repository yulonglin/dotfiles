from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sync_claude_to_antigravity.sh"


def run_sync(
    target_dir: Path,
    dotfiles_dir: Path,
    claude_dir: Path,
    settings_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        "bash",
        str(SCRIPT),
        "--target-dir",
        str(target_dir),
        "--dotfiles-dir",
        str(dotfiles_dir),
        "--claude-dir",
        str(claude_dir),
    ]
    if settings_path is not None:
        cmd.extend(["--settings-path", str(settings_path)])
    return subprocess.run(
        cmd,
        check=False,
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def make_fixture_dotfiles(tmp_path: Path) -> tuple[Path, Path]:
    dotfiles = tmp_path / "dotfiles"
    (dotfiles / "antigravity").mkdir(parents=True)
    (dotfiles / "claude" / "rules").mkdir(parents=True)
    (dotfiles / "codex").mkdir(parents=True)
    (dotfiles / "config").mkdir(parents=True)
    (dotfiles / "custom_bins").mkdir(parents=True)
    (dotfiles / "scripts" / "helpers").mkdir(parents=True)

    (dotfiles / "antigravity" / "skills.json").write_text(
        (ROOT / "antigravity" / "skills.json").read_text()
    )
    (dotfiles / "antigravity" / "AGENTS.md").write_text(
        (ROOT / "antigravity" / "AGENTS.md").read_text()
    )
    (dotfiles / "antigravity" / "permissions.json").write_text(
        (ROOT / "antigravity" / "permissions.json").read_text()
    )
    (dotfiles / "claude" / "CLAUDE.md").write_text("# Global CLAUDE.md\n")
    (dotfiles / "claude" / "settings.json").write_text(
        json.dumps(
            {
                "mcpServers": {},
                "permissions": {
                    "allow": [
                        "Read",
                        "Bash(model-router-wire *)",
                        "Bash(mutool draw *)",
                        "Bash(claude rm:*)",
                    ],
                    "ask": [
                        "Bash(claude rm *--discard-unpushed*)",
                    ],
                    "deny": [
                        "Bash(git reset --hard *)",
                        "Bash(shred *)",
                        "Bash(poweroff)",
                        "Bash(* | bash*)",
                        "Bash(find * -delete *)",
                    ],
                },
            }
        )
        + "\n"
    )
    (dotfiles / "codex" / "config.toml").write_text('model = "gpt-6.2-astra"\n')
    (dotfiles / "config" / "mcp-servers.json").write_text('{"mcpServers": {}}\n')
    (dotfiles / "scripts" / "helpers" / "sync_mcp_servers.py").symlink_to(
        ROOT / "scripts" / "helpers" / "sync_mcp_servers.py"
    )
    (dotfiles / "scripts" / "helpers" / "sync_antigravity_settings.py").symlink_to(
        ROOT / "scripts" / "helpers" / "sync_antigravity_settings.py"
    )
    slack_bin = dotfiles / "custom_bins" / "slack-mcp-stdio"
    slack_bin.write_text("#!/usr/bin/env bash\nexit 0\n")
    slack_bin.chmod(slack_bin.stat().st_mode | stat.S_IXUSR)

    (dotfiles / "claude" / "rules" / "safety.md").write_text("# Safety\nNever rm -rf.\n")
    (dotfiles / "claude" / "rules" / "background-jobs.md").write_text(
        "# Background Jobs\nClaude only.\n"
    )
    return dotfiles, dotfiles / "claude"


def test_sync_projects_skills_rules_mcp_and_settings(tmp_path: Path) -> None:
    dotfiles, claude_dir = make_fixture_dotfiles(tmp_path)
    target = tmp_path / "gemini-config"
    settings_path = tmp_path / "antigravity-cli" / "settings.json"

    res = run_sync(target, dotfiles, claude_dir, settings_path=settings_path)
    assert res.returncode == 0, res.stderr

    assert (target / "skills.json").is_symlink()
    assert (target / "skills.json").resolve() == (dotfiles / "antigravity" / "skills.json").resolve()
    assert (target / "AGENTS.md").is_symlink()
    assert (target / "AGENTS.md").resolve() == (dotfiles / "antigravity" / "AGENTS.md").resolve()
    assert (target / "GEMINI.md").is_symlink()
    assert (target / "GEMINI.md").resolve() == (claude_dir / "CLAUDE.md").resolve()

    # Portable rule projected with always_on frontmatter; background-jobs excluded
    safety_dst = target / "rules" / "safety.md"
    assert safety_dst.exists() and not safety_dst.is_symlink()
    safety_text = safety_dst.read_text()
    assert safety_text.startswith("---\ntrigger: always_on\n---\n")
    assert "Never rm -rf." in safety_text
    assert not (target / "rules" / "background-jobs.md").exists()

    # MCP config seeded with context7 and slack-mcp-stdio
    mcp = json.loads((target / "mcp_config.json").read_text())
    assert mcp["mcpServers"]["context7"] == {"url": "https://mcp.context7.com/mcp"}
    assert mcp["mcpServers"]["slack"] == {
        "command": str(dotfiles / "custom_bins" / "slack-mcp-stdio")
    }

    # Settings synced with auto mode, curated MCP allowlist, and Claude Bash rules
    settings = json.loads(settings_path.read_text())
    assert settings["agentMode"] == "auto"
    assert settings["enableTerminalSandbox"] is True

    allow = settings["permissions"]["allow"]
    deny = settings["permissions"]["deny"]
    assert "mcp(bear/get_note)" in allow
    assert "mcp(bear/read_note_content)" in allow
    assert "mcp(context7/*)" in allow
    assert "mcp(slack/slack_read_channel)" in allow
    assert "command(model-router-wire)" in allow
    assert "command(mutool draw)" in allow
    # claude rm is skipped because Claude's ask refinement isn't expressible as a prefix rule
    assert "command(claude rm)" not in allow
    # Mutating Bear/Slack tools must not be allowlisted
    assert "mcp(bear/edit_note)" not in allow
    assert "mcp(slack/slack_send_message)" not in allow

    assert "command(git reset --hard)" in deny
    assert "command(shred)" in deny
    assert "command(poweroff)" in deny
    # No sentinel comment strings inside permission arrays
    assert all(not entry.startswith("#") for entry in allow + deny)


def test_sync_preserves_user_settings_and_prunes_stale_managed_rules(tmp_path: Path) -> None:
    dotfiles, claude_dir = make_fixture_dotfiles(tmp_path)
    target = tmp_path / "gemini-config"
    settings_path = tmp_path / "antigravity-cli" / "settings.json"
    settings_path.parent.mkdir(parents=True)
    settings_path.write_text(
        json.dumps(
            {
                "theme": "dark",
                "agentMode": "default",
                "permissions": {
                    "allow": ["command(my-custom-tool)"],
                    "ask": ["command(deploy-prod)"],
                    "deny": [],
                },
            }
        )
        + "\n"
    )

    assert run_sync(target, dotfiles, claude_dir, settings_path=settings_path).returncode == 0
    first = json.loads(settings_path.read_text())
    assert first["theme"] == "dark"
    assert first["agentMode"] == "auto"
    assert "command(my-custom-tool)" in first["permissions"]["allow"]
    assert "command(deploy-prod)" in first["permissions"]["ask"]
    assert "command(mutool draw)" in first["permissions"]["allow"]

    # Remove mutool draw from Claude settings; re-sync should prune it but keep user rules
    claude_data = json.loads((claude_dir / "settings.json").read_text())
    claude_data["permissions"]["allow"].remove("Bash(mutool draw *)")
    (claude_dir / "settings.json").write_text(json.dumps(claude_data) + "\n")

    assert run_sync(target, dotfiles, claude_dir, settings_path=settings_path).returncode == 0
    second = json.loads(settings_path.read_text())
    assert "command(mutool draw)" not in second["permissions"]["allow"]
    assert "command(my-custom-tool)" in second["permissions"]["allow"]
    assert "command(deploy-prod)" in second["permissions"]["ask"]
    assert second["theme"] == "dark"


def test_sync_handles_preexisting_empty_mcp_config(tmp_path: Path) -> None:
    dotfiles, claude_dir = make_fixture_dotfiles(tmp_path)
    target = tmp_path / "gemini-config"
    target.mkdir(parents=True)
    (target / "mcp_config.json").write_text("")

    res = run_sync(target, dotfiles, claude_dir)
    assert res.returncode == 0, res.stderr
    mcp = json.loads((target / "mcp_config.json").read_text())
    assert mcp["mcpServers"]["context7"] == {"url": "https://mcp.context7.com/mcp"}


def test_sync_prunes_stale_managed_rules_and_preserves_custom_rules(tmp_path: Path) -> None:
    dotfiles, claude_dir = make_fixture_dotfiles(tmp_path)
    target = tmp_path / "gemini-config"
    (claude_dir / "rules" / "temp-rule.md").write_text("# Temp\nTemporary.\n")

    assert run_sync(target, dotfiles, claude_dir).returncode == 0
    assert (target / "rules" / "temp-rule.md").exists()

    # Add a user-authored rule and remove the source temp-rule
    custom_rule = target / "rules" / "custom-local.md"
    custom_rule.write_text("---\ntrigger: manual\n---\n# My custom rule\n")
    (claude_dir / "rules" / "temp-rule.md").unlink()

    res = run_sync(target, dotfiles, claude_dir)
    assert res.returncode == 0, res.stderr
    assert not (target / "rules" / "temp-rule.md").exists()
    assert custom_rule.exists()
    assert "My custom rule" in custom_rule.read_text()
    assert "1 pruned" in res.stdout


def test_real_repo_rules_and_settings_sync(tmp_path: Path) -> None:
    target = tmp_path / "gemini-config"
    settings_path = tmp_path / "antigravity-cli" / "settings.json"
    res = run_sync(target, ROOT, ROOT / "claude", settings_path=settings_path)
    assert res.returncode == 0, res.stderr
    assert "per-file cap" not in res.stderr

    skills_manifest = json.loads((ROOT / "antigravity" / "skills.json").read_text())
    assert skills_manifest["entries"][0]["path"] == "~/.claude/skills"
    assert "^synced$" in skills_manifest["entries"][0]["exclude"]

    projected = sorted(p.name for p in (target / "rules").glob("*.md"))
    assert "safety.md" in projected
    assert "communication.md" in projected
    assert "background-jobs.md" not in projected
    for p in (target / "rules").glob("*.md"):
        assert len(p.read_bytes()) <= 24_000

    settings = json.loads(settings_path.read_text())
    assert settings["agentMode"] == "auto"
    assert "command(git reset --hard)" in settings["permissions"]["deny"]
    assert "command(git push --force)" in settings["permissions"]["deny"]
    assert "mcp(bear/get_note)" in settings["permissions"]["allow"]
    assert "mcp(slack/slack_search_public)" in settings["permissions"]["allow"]
    # Ensure real repo test did not leak anything into ~/.gemini
    assert os.path.exists(settings_path)
