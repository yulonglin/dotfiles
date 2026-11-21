from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sync_claude_to_antigravity.sh"


def run_sync(target_dir: Path, dotfiles_dir: Path, claude_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "bash",
            str(SCRIPT),
            "--target-dir",
            str(target_dir),
            "--dotfiles-dir",
            str(dotfiles_dir),
            "--claude-dir",
            str(claude_dir),
        ],
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
    (dotfiles / "scripts" / "helpers").mkdir(parents=True)

    (dotfiles / "antigravity" / "skills.json").write_text(
        (ROOT / "antigravity" / "skills.json").read_text()
    )
    (dotfiles / "antigravity" / "AGENTS.md").write_text(
        (ROOT / "antigravity" / "AGENTS.md").read_text()
    )
    (dotfiles / "claude" / "CLAUDE.md").write_text("# Global CLAUDE.md\n")
    (dotfiles / "claude" / "settings.json").write_text('{"mcpServers": {}}\n')
    (dotfiles / "codex" / "config.toml").write_text('model = "gpt-6.2-astra"\n')
    (dotfiles / "config" / "mcp-servers.json").write_text('{"mcpServers": {}}\n')
    (dotfiles / "scripts" / "helpers" / "sync_mcp_servers.py").symlink_to(
        ROOT / "scripts" / "helpers" / "sync_mcp_servers.py"
    )

    (dotfiles / "claude" / "rules" / "safety.md").write_text("# Safety\nNever rm -rf.\n")
    (dotfiles / "claude" / "rules" / "background-jobs.md").write_text("# Background Jobs\nClaude only.\n")
    return dotfiles, dotfiles / "claude"


def test_sync_projects_skills_rules_and_mcp(tmp_path: Path) -> None:
    dotfiles, claude_dir = make_fixture_dotfiles(tmp_path)
    target = tmp_path / "gemini-config"

    res = run_sync(target, dotfiles, claude_dir)
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

    # MCP config seeded with context7
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


def test_real_repo_rules_stay_under_antigravity_per_file_cap(tmp_path: Path) -> None:
    target = tmp_path / "gemini-config"
    res = run_sync(target, ROOT, ROOT / "claude")
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
