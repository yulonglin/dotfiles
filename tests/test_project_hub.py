"""project-hub contract tests on a throwaway HOME.

Run with `uv run --no-project python tests/test_project_hub.py` (or pytest).
No network, no real HOME touched; git is the only external tool used.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BIN = REPO / "custom_bins/project-hub"


def enc(path: Path) -> str:
    """Claude Code project-dir name: every non-alphanumeric char becomes "-"."""
    return re.sub(r"[^a-zA-Z0-9]", "-", str(path))


class ProjectHubTest(unittest.TestCase):
    def setUp(self) -> None:
        # resolve(): on macOS /tmp is a symlink to /private/tmp, and the tool
        # works on canonical paths, so an unresolved HOME never matches.
        self.tmp = Path(tempfile.mkdtemp(prefix="project-hub-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.home = self.tmp / "home"
        self.volume = self.tmp / "volume"
        (self.home / "projects").mkdir(parents=True)
        (self.home / ".claude/projects").mkdir(parents=True)
        self.volume.mkdir()
        dot = self.tmp / "dotfiles/config"
        dot.mkdir(parents=True)
        (dot / "storage.conf").write_text(f"STORAGE_VOLUME={self.volume}\n")
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "DOT_DIR": str(self.tmp / "dotfiles"),
            "PROJECT_HUB_FORCE_TIERED": "1",
        }

    def run_hub(
        self, *args: str, env: dict | None = None, ok: bool = True
    ) -> subprocess.CompletedProcess[str]:
        r = subprocess.run(
            [sys.executable, str(BIN), *args],
            env=env or self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        if ok:
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r

    def git(self, *a: str, cwd: Path) -> str:
        return subprocess.run(
            ["git", *a], cwd=cwd, text=True, capture_output=True, check=True
        ).stdout

    def make_repo(self, path: Path) -> Path:
        path.mkdir(parents=True)
        self.git("init", "-q", "-b", "main", cwd=path)
        self.git("config", "user.email", "t@example.com", cwd=path)
        self.git("config", "user.name", "t", cwd=path)
        (path / "README.md").write_text("x\n")
        (path / ".gitignore").write_text("logs/\nout/\n")
        (path / "out").mkdir()
        (path / "out/keep.json").write_text("{}")
        (path / "logs").mkdir()
        (path / "logs/a.eval").write_text("cold")
        self.git("add", "-f", "README.md", ".gitignore", "out/keep.json", cwd=path)
        self.git("commit", "-qm", "init", cwd=path)
        wt = path / ".claude/worktrees/feature"
        wt.parent.mkdir(parents=True)
        self.git("worktree", "add", "-q", str(wt), "-b", "feature", cwd=path)
        return path

    def test_new_links_bulk_dirs_to_volume_when_tiered(self) -> None:
        self.run_hub("new", "proj")
        hub = self.home / "projects/proj"
        for d in ("data", "runs", "external", "archive"):
            self.assertTrue((hub / d).is_symlink(), d)
            self.assertEqual(
                Path(os.readlink(hub / d)), self.volume / "projects/proj" / d
            )
            self.assertTrue((hub / d).is_dir())
        self.assertTrue((hub / "CLAUDE.md").is_file())

    def test_new_plain_dirs_without_volume(self) -> None:
        env = {**self.env, "PROJECT_HUB_FORCE_TIERED": "0"}
        self.run_hub("new", "flat", env=env)
        hub = self.home / "projects/flat"
        for d in ("data", "runs"):
            self.assertTrue((hub / d).is_dir() and not (hub / d).is_symlink(), d)

    def test_adopt_moves_repo_repairs_worktrees_and_renames_claude_dirs(self) -> None:
        self.run_hub("new", "proj")
        src = self.make_repo(self.home / "code/thing")
        enc_old = str(src).replace("/", "-")
        (self.home / ".claude/projects" / enc_old).mkdir()
        (
            self.home / ".claude/projects" / f"{enc_old}--claude-worktrees-feature"
        ).mkdir()
        (
            self.home / ".claude/projects" / f"{enc_old}-other"
        ).mkdir()  # a different repo, must stay
        self.run_hub("adopt", "proj", f"code={src}", "--no-sync")
        dest = self.home / "projects/proj/code"
        self.assertTrue((dest / ".git").is_dir())
        self.assertFalse(src.exists())
        listed = self.git("worktree", "list", "--porcelain", cwd=dest)
        self.assertIn(f"worktree {dest / '.claude/worktrees/feature'}", listed)
        self.assertNotIn(str(src), listed)
        self.assertEqual(
            self.git("status", "--porcelain", cwd=dest / ".claude/worktrees/feature"),
            "",
        )
        enc_new = enc(dest)
        proj = self.home / ".claude/projects"
        self.assertTrue((proj / enc_new).is_dir() and not (proj / enc_new).is_symlink())
        self.assertTrue((proj / enc_old).is_symlink())
        self.assertEqual(os.readlink(proj / enc_old), enc_new)
        self.assertTrue((proj / f"{enc_new}--claude-worktrees-feature").is_dir())
        self.assertTrue(
            (proj / f"{enc_old}-other").is_dir()
            and not (proj / f"{enc_old}-other").is_symlink()
        )

    def test_adopt_matches_both_claude_encodings_of_a_dotted_path(self) -> None:
        # Claude Code 2.1.26x encodes every non-alphanumeric char as '-'; older
        # releases mapped only '/'. Both kinds of dir exist on a real box.
        self.run_hub("new", "proj")
        src = self.make_repo(self.home / "code/thing.v2")
        current = enc(src)
        legacy = str(src).replace("/", "-")
        proj = self.home / ".claude/projects"
        (proj / current).mkdir()
        (proj / f"{current}--claude-worktrees-feature").mkdir()
        (proj / f"{legacy}-.claude-worktrees-old").mkdir()
        (proj / f"{current}--other").mkdir()  # not a worktree variant: stays
        self.run_hub("adopt", "proj", f"code={src}", "--no-sync")
        new = enc(self.home / "projects/proj/code")
        self.assertTrue((proj / new).is_dir())
        self.assertTrue((proj / f"{new}--claude-worktrees-feature").is_dir())
        self.assertTrue((proj / f"{new}-.claude-worktrees-old").is_dir())
        self.assertEqual(os.readlink(proj / current), new)
        self.assertTrue(
            (proj / f"{current}--other").is_dir()
            and not (proj / f"{current}--other").is_symlink()
        )

    def test_shebang_runs_under_uv(self) -> None:
        r = subprocess.run(
            [str(BIN), "--help"], text=True, capture_output=True, check=False
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("project-hub new", r.stdout)

    def test_adopt_refuses_existing_role_and_bulk_role(self) -> None:
        self.run_hub("new", "proj")
        src = self.make_repo(self.home / "code/thing")
        r = self.run_hub("adopt", "proj", f"runs={src}", ok=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("bulk dir", r.stderr)
        self.assertTrue(src.exists())

    def test_tier_refuses_tracked_files_and_moves_cold_ignored_dir(self) -> None:
        self.run_hub("new", "proj")
        src = self.make_repo(self.home / "code/thing")
        self.run_hub("adopt", "proj", f"code={src}", "--no-sync")
        code = self.home / "projects/proj/code"
        r = self.run_hub("tier", "proj/code", "out", ok=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("tracked", r.stderr)
        self.assertTrue((code / "out").is_dir() and not (code / "out").is_symlink())
        r = self.run_hub("tier", "proj/code", "logs", ok=False)
        self.assertIn("written in the last", r.stderr)
        old = 0
        os.utime(code / "logs/a.eval", (old, old))
        (self.home / "projects/proj/paper").mkdir()
        r = self.run_hub("tier", "proj/code", "../paper", ok=False)
        self.assertIn("not inside", r.stderr)
        self.run_hub("tier", "proj/code", "./logs/", "--quiet-minutes", "1")
        self.assertTrue((code / "logs").is_symlink())
        self.assertEqual(os.readlink(code / "logs"), "../runs/logs")
        self.assertEqual((code / "logs/a.eval").read_text(), "cold")
        self.assertTrue((self.volume / "projects/proj/runs/logs/a.eval").is_file())
        self.assertEqual(self.git("status", "--porcelain", cwd=code), "")

    def test_tier_cross_fs_refuses_to_merge_into_another_repos_dir(self) -> None:
        # Hetzner path: repo on NVMe, runs/ on the volume, so tier copies with rsync.
        env = {**self.env, "PROJECT_HUB_FORCE_COPY": "1"}
        self.run_hub("new", "proj")
        hub = self.home / "projects/proj"
        for role in ("code", "code-sprint"):
            src = self.make_repo(self.home / f"code/{role}")
            (src / "logs/a.eval").write_text(role)
            os.utime(src / "logs/a.eval", (0, 0))
            self.run_hub("adopt", "proj", f"{role}={src}", "--no-sync")
        self.run_hub("tier", "proj/code", "logs", env=env)
        runs_logs = self.volume / "projects/proj/runs/logs"
        self.assertEqual((runs_logs / "a.eval").read_text(), "code")
        self.assertFalse((runs_logs / ".project-hub-tier-source").exists())
        self.assertEqual(os.readlink(hub / "code/logs"), "../runs/logs")
        r = self.run_hub("tier", "proj/code-sprint", "logs", env=env, ok=False)
        self.assertIn("not an interrupted tier", r.stderr)
        self.assertEqual((runs_logs / "a.eval").read_text(), "code")
        sprint_logs = hub / "code-sprint/logs"
        self.assertTrue(sprint_logs.is_dir() and not sprint_logs.is_symlink())
        self.assertEqual((sprint_logs / "a.eval").read_text(), "code-sprint")

    def test_tier_cross_fs_resumes_an_interrupted_copy(self) -> None:
        env = {**self.env, "PROJECT_HUB_FORCE_COPY": "1"}
        self.run_hub("new", "proj")
        src = self.make_repo(self.home / "code/thing")
        self.run_hub("adopt", "proj", f"code={src}", "--no-sync")
        code = self.home / "projects/proj/code"
        (code / "logs/b.eval").write_text("late")
        for f in ("a.eval", "b.eval"):
            os.utime(code / "logs" / f, (0, 0))
        # State an interrupted run leaves: marker written, a.eval already moved.
        dest = self.volume / "projects/proj/runs/logs"
        dest.mkdir(parents=True)
        (dest / ".project-hub-tier-source").write_text(f"{code / 'logs'}\n")
        (code / "logs/a.eval").rename(dest / "a.eval")
        self.run_hub("tier", "proj/code", "./logs/", env=env)
        self.assertEqual(os.readlink(code / "logs"), "../runs/logs")
        self.assertEqual(
            sorted(p.name for p in (code / "logs").iterdir()), ["a.eval", "b.eval"]
        )

    def test_tier_refuses_names_that_escape_the_hub(self) -> None:
        self.run_hub("new", "proj")
        for target in ("../x/code", "proj/", "proj/../proj"):
            r = self.run_hub("tier", target, "logs", ok=False)
            self.assertIn("plain directory name", r.stderr, target)

    def test_new_refuses_when_volume_projects_links_back_into_home(self) -> None:
        (self.volume / "projects").symlink_to(self.home / "projects")
        r = self.run_hub("new", "proj", ok=False)
        self.assertIn("forward link", r.stderr)
        self.assertFalse((self.home / "projects/proj").exists())

    def test_new_makes_plain_dirs_when_the_hub_itself_links_onto_the_volume(
        self,
    ) -> None:
        real = self.volume / "projects/onvol"
        real.mkdir(parents=True)
        (self.home / "projects/onvol").symlink_to(real)
        self.run_hub("new", "onvol")
        for d in ("data", "runs", "external", "archive"):
            self.assertTrue((real / d).is_dir() and not (real / d).is_symlink(), d)

    def test_status_reports_links(self) -> None:
        self.run_hub("new", "proj")
        out = self.run_hub("status", "proj").stdout
        self.assertIn("runs", out)
        self.assertIn("-> ", out)


if __name__ == "__main__":
    unittest.main()
