from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "helpers" / "sync_mcp_servers.py"


def write_sample_files(tmp_path: Path) -> tuple[Path, Path, Path]:
    source = tmp_path / "mcp-servers.json"
    claude = tmp_path / "settings.json"
    codex = tmp_path / "config.toml"

    source.write_text(
        json.dumps(
            {
                "mcpServers": {
                    "bear": {
                        "command": "/Applications/Bear.app/Contents/MacOS/bearcli",
                        "args": ["mcp-server"],
                    }
                }
            },
            indent=2,
        )
        + "\n"
    )
    claude.write_text(
        json.dumps(
            {
                "permissions": {"allow": []},
                "mcpServers": {},
            },
            indent=2,
        )
        + "\n"
    )
    codex.write_text(
        '\n'.join(
            [
                'model = "gpt-5.5"',
                "",
                "[mcp_servers.playwright]",
                'command = "npx"',
                'args = ["@playwright/mcp@latest"]',
                "",
            ]
        )
    )
    return source, claude, codex


def run_sync(
    source: Path,
    claude: Path,
    codex: Path,
    *extra_args: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--source",
            str(source),
            "--claude-settings",
            str(claude),
            "--codex-config",
            str(codex),
            *extra_args,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )


def test_check_reports_drift_without_writing(tmp_path: Path) -> None:
    source, claude, codex = write_sample_files(tmp_path)
    before_claude = claude.read_text()
    before_codex = codex.read_text()

    result = run_sync(source, claude, codex, "--check")

    assert result.returncode == 1
    assert "Claude MCP drift" in result.stdout
    assert "Codex MCP drift" in result.stdout
    assert claude.read_text() == before_claude
    assert codex.read_text() == before_codex


def test_apply_updates_managed_entries_and_preserves_unmanaged_codex(
    tmp_path: Path,
) -> None:
    source, claude, codex = write_sample_files(tmp_path)

    result = run_sync(source, claude, codex, "--apply")

    assert result.returncode == 0, result.stderr
    claude_data = json.loads(claude.read_text())
    assert claude_data["mcpServers"] == {
        "bear": {
            "command": "/Applications/Bear.app/Contents/MacOS/bearcli",
            "args": ["mcp-server"],
        }
    }
    codex_text = codex.read_text()
    assert "[mcp_servers.playwright]" in codex_text
    assert "# BEGIN SHARED MCP SERVERS" in codex_text
    assert "[mcp_servers.bear]" in codex_text
    assert 'command = "/Applications/Bear.app/Contents/MacOS/bearcli"' in codex_text
