"""Fixture coverage for the scoped Codex plugin hook repair."""
import importlib.util
import json
import stat
import tempfile
import unittest
from unittest import mock
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/setup/repair_codex_plugin_hooks.py"
SPEC = importlib.util.spec_from_file_location("repair_codex_plugin_hooks", SCRIPT)
repair = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repair)


class PluginHookRepairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def fixture(self, name="core", version="new-version", native=None):
        root = self.root / "plugins/cache/ai-safety-plugins" / name / version
        legacy = root / ".claude-plugin/plugin.json"
        legacy.parent.mkdir(parents=True)
        original = {"name": name, "skills": "./skills", "custom": {"keep": True},
                    "hooks": {"PreToolUse": []}}
        legacy.write_text(json.dumps(original))
        if native is not None:
            target = root / ".codex-plugin/plugin.json"
            target.parent.mkdir()
            target.write_text(native)
        return root, legacy

    def test_append_preserves_unrelated_bytes(self):
        original = b'# keep comment\nmodel = "example"\n[plugins."keep@source"]\nenabled = true\n'
        updated = repair.repair_config(original)
        self.assertTrue(updated.startswith(original))
        self.assertEqual(updated.count(b"enabled = false"), 4)
        self.assertEqual(repair.repair_config(updated), updated)

    def test_changes_only_enabled_preserves_hash_and_comments(self):
        key = repair.DISABLED_KEYS[0]
        original = ('[hooks.state."' + key + '"] # keep\n  enabled = true # comment\n'
                    'trusted_hash = "sha256:retain"\n[plugins.other]\nenabled = true\n').encode()
        updated = repair.repair_config(original)
        self.assertTrue(updated.startswith(original.replace(b"  enabled = true", b"  enabled = false")))

    def test_existing_hash_only_and_crlf(self):
        original = ('[hooks.state."' + repair.DISABLED_KEYS[0] + '"]\r\n'
                    'trusted_hash = "retain"\r\n').encode()
        updated = repair.repair_config(original)
        self.assertIn(b'enabled = false\r\ntrusted_hash = "retain"', updated)
        self.assertNotIn(b"\n", updated.replace(b"\r\n", b""))
        self.assertEqual(repair.repair_config(updated), updated)

    def test_preserves_literal_table_and_missing_final_newline(self):
        original = ("[hooks.state.'" + repair.DISABLED_KEYS[0] + "']\nenabled = true").encode()
        updated = repair.repair_config(original)
        self.assertTrue(updated.startswith(original.replace(b"true", b"false")))
        self.assertEqual(updated.count(repair.DISABLED_KEYS[0].encode()), 1)

    def test_duplicate_or_invalid_settings_refused(self):
        header = '[hooks.state."' + repair.DISABLED_KEYS[0] + '"]\n'
        for original in (header + header, header + 'enabled = "true"\n',
                         header + 'enabled = true\nenabled = false\n', 'hooks = {}\n'):
            with self.subTest(original=original), self.assertRaises(ValueError):
                repair.repair_config(original.encode())

    def test_multiline_toml_refused_without_writes(self):
        with self.assertRaises(ValueError):
            repair.repair_config(("instructions = " + chr(34) * 3 + "\ntext\n" + chr(34) * 3).encode())

    def test_native_overlay_retains_metadata_and_legacy(self):
        root, legacy = self.fixture()
        before = legacy.read_bytes()
        changes = repair.plan_changes(self.root)
        target = root / ".codex-plugin/plugin.json"
        overlay = next(after for path, _, after in changes if path == target)
        parsed = json.loads(overlay)
        self.assertEqual(parsed["hooks"], {})
        self.assertEqual(parsed["custom"], {"keep": True})
        self.assertEqual(parsed["skills"], "./skills")
        self.assertEqual(legacy.read_bytes(), before)
        self.assertFalse(target.exists())

    def test_existing_native_preserved(self):
        root, _ = self.fixture(native='{"hooks": "./native.json", "keep": true}')
        before = (root / ".codex-plugin/plugin.json").read_bytes()
        self.assertEqual(len(repair.plan_changes(self.root)), 1)
        self.assertEqual((root / ".codex-plugin/plugin.json").read_bytes(), before)

    def test_unknown_hook_shape_preserved(self):
        _, legacy = self.fixture()
        legacy.write_text('{"name":"core","hooks":{"hooks":{}}}')
        self.assertEqual(len(repair.plan_changes(self.root)), 1)

    def test_all_versions_apply_and_idempotence(self):
        self.fixture("core", "1")
        self.fixture("core", "2")
        self.fixture("workflow", "local")
        for path, before, after in repair.plan_changes(self.root):
            repair.atomic_write(path, before, after)
        self.assertEqual(repair.plan_changes(self.root), [])

    def test_backup_mode_and_stale_write(self):
        target = self.root / "config.toml"
        target.write_bytes(b"original")
        target.chmod(0o640)
        backup = repair.atomic_write(target, b"original", b"updated")
        self.assertEqual(backup.read_bytes(), b"original")
        self.assertEqual(target.read_bytes(), b"updated")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)
        with self.assertRaises(ValueError):
            repair.atomic_write(target, b"original", b"clobber")
        self.assertEqual(target.read_bytes(), b"updated")

    def test_symlink_preserved(self):
        real = self.root / "real"
        real.write_bytes(b"original")
        link = self.root / "config.toml"
        link.symlink_to(real)
        with self.assertRaises(ValueError):
            repair.atomic_write(link, b"original", b"changed")
        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_bytes(), b"original")

    def test_codex_home_default(self):
        self.fixture()
        with mock.patch.dict("os.environ", {"CODEX_HOME": str(self.root)}):
            with mock.patch.object(repair, "plan_changes", wraps=repair.plan_changes) as plan:
                self.assertEqual(repair.main([]), 0)
                plan.assert_called_once_with(self.root)
        self.assertFalse((self.root / "config.toml").exists())

    def test_overlay_parent_symlink_escape_refused(self):
        root, _ = self.fixture()
        outside = self.root.parent / (self.root.name + "-outside")
        outside.mkdir()
        self.addCleanup(outside.rmdir)
        (root / ".codex-plugin").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "escapes Codex target"):
            repair.plan_changes(self.root)
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlinked_target_root_allowed(self):
        real = self.root / "real"
        real.mkdir()
        link = self.root / "codex"
        link.symlink_to(real, target_is_directory=True)
        for path, before, after in repair.plan_changes(link):
            repair.atomic_write(path, before, after, link)
        self.assertTrue((real / "config.toml").exists())
        self.assertTrue(link.is_symlink())

    def test_cli_dry_run_writes_nothing(self):
        self.fixture()
        before = sorted(str(p) for p in self.root.rglob("*"))
        self.assertEqual(repair.main(["--target", str(self.root)]), 0)
        self.assertEqual(sorted(str(p) for p in self.root.rglob("*")), before)


if __name__ == "__main__":
    unittest.main()
