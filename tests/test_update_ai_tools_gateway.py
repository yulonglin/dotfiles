"""Exercise the real updater with stubbed commands; no package updates run."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


UPDATER = Path(__file__).resolve().parents[1] / 'custom_bins/update-ai-tools'


class UpdaterGatewayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.log = self.home / 'events'
        for name in ('brew', 'bun', 'uv', 'ty', 'agy', 'opencode'):
            self.script(name, 'exit 0\n')
        self.script('claude', 'echo claude >> "$HOME/events"\nexit "${CLAUDE_STATUS:-0}"\n')
        self.script('codex-manager', 'echo codex >> "$HOME/events"\nexit "${CODEX_STATUS:-0}"\n')
        self.checker = self.home / '.claude/hooks/check_model_router_update.py'
        self.checker.parent.mkdir(parents=True)
        self.checker.write_text('import os, pathlib, sys\n'
                               'assert sys.argv[1:] == ["--force"]\n'
                               'with (pathlib.Path.home()/"events").open("a") as f: f.write("check\\n")\n'
                               'sys.exit(int(os.environ.get("CHECK_STATUS", "0")))\n')

    def script(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\n' + body)
        p.chmod(0o755)

    def run_updater(self, *args, **extra):
        env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ':/usr/bin:/bin',
                   CODEX_INSTALL_MANAGER=str(self.bin / 'codex-manager'))
        env.update(extra)
        return subprocess.run(['/bin/bash', str(UPDATER), *args], env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)

    def test_success_runs_check_after_claude_before_codex(self):
        result = self.run_updater()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ['claude', 'check', 'codex'])

    def test_check_failure_propagates_and_other_updates_continue(self):
        result = self.run_updater(CHECK_STATUS='1')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ['claude', 'check', 'codex'])

    def test_claude_failure_skips_check_and_continues(self):
        result = self.run_updater(CLAUDE_STATUS='2')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ['claude', 'codex'])

    def test_codex_failure_keeps_existing_status(self):
        result = self.run_updater(CODEX_STATUS='7')
        self.assertEqual(result.returncode, 7, result.stdout)

    def test_dry_run_only_describes_check(self):
        result = self.run_updater('--dry-run')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('infrastructure', result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ['codex'])


if __name__ == '__main__':
    unittest.main()
