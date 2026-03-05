#!/usr/bin/env python3
"""Sync text replacements between macOS, Alfred snippets, and a YAML config file.

Usage:
    uv run --with ruamel.yaml scripts/sync_text_replacements.py export [--dry-run]
    uv run --with ruamel.yaml scripts/sync_text_replacements.py import [--dry-run] [--prune]
    uv run --with ruamel.yaml scripts/sync_text_replacements.py sync [--dry-run] [--prune] [--no-restart-alfred]
    uv run --with ruamel.yaml scripts/sync_text_replacements.py diff
    uv run --with ruamel.yaml scripts/sync_text_replacements.py restore [timestamp]
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import unicodedata
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ── Constants ────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
DOT_DIR = SCRIPT_DIR.parent
YAML_PATH = DOT_DIR / "config" / "text_replacements.yaml"

TEXT_REPLACEMENTS_DB = Path.home() / "Library" / "KeyboardServices" / "TextReplacements.db"
ALFRED_SNIPPETS_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Alfred"
    / "Alfred.alfredpreferences"
    / "snippets"
)

BACKUP_DIR = Path.home() / ".local" / "share" / "text-replacements-backup"
MAX_BACKUPS = 10

# CoreData epoch: 2001-01-01 00:00:00 UTC
COREDATA_EPOCH_OFFSET = 978307200.0


# ── Data Model ───────────────────────────────────────────────────────────────


@dataclass
class Snippet:
    shortcut: str
    phrase: str
    name: str = ""
    uid: str = ""
    collection: str = ""  # Alfred collection name (empty = "Default Collection")
    enabled: bool = True  # Alfred: dontautoexpand; macOS: present vs soft-deleted
    section: str = "shared"  # shared, macos, alfred

    def key(self) -> str:
        return self.shortcut


# ── Text Normalization ───────────────────────────────────────────────────────


def normalize_text(s: str) -> str:
    if s is None:
        return ""
    return unicodedata.normalize("NFC", s)


def phrases_equal(a: str, b: str) -> bool:
    """Compare phrases ignoring trailing whitespace (block scalars add trailing newlines)."""
    return normalize_text(a).rstrip() == normalize_text(b).rstrip()


# ── macOS Text Replacements (SQLite) ────────────────────────────────────────


def read_macos_entries() -> list[Snippet]:
    if platform.system() != "Darwin":
        return []
    if not TEXT_REPLACEMENTS_DB.exists():
        print(f"Warning: TextReplacements.db not found at {TEXT_REPLACEMENTS_DB}", file=sys.stderr)
        return []

    entries = []
    conn = sqlite3.connect(str(TEXT_REPLACEMENTS_DB))
    try:
        cursor = conn.execute(
            "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0"
        )
        for row in cursor:
            shortcut, phrase = normalize_text(row[0]), normalize_text(row[1])
            if shortcut:
                entries.append(Snippet(shortcut=shortcut, phrase=phrase, section="macos"))
    finally:
        conn.close()
    return entries


def write_macos_entries(entries: list[Snippet], prune: bool = False, dry_run: bool = False) -> None:
    if platform.system() != "Darwin":
        return
    if not TEXT_REPLACEMENTS_DB.exists():
        print("Warning: TextReplacements.db not found, skipping macOS write", file=sys.stderr)
        return

    if dry_run:
        print(f"  [dry-run] Would write {len(entries)} entries to macOS text replacements")
        return

    # Stop keyboard services daemon to prevent iCloud sync conflicts
    subprocess.run(["killall", "kbd"], capture_output=True)

    import time

    conn = sqlite3.connect(str(TEXT_REPLACEMENTS_DB))
    try:
        # Get current Z_MAX for primary key
        z_max = conn.execute("SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = 1").fetchone()[0]

        # Read existing entries
        existing = {}
        for row in conn.execute(
            "SELECT Z_PK, ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0"
        ):
            existing[normalize_text(row[1])] = (row[0], normalize_text(row[2]))

        now_coredata = time.time() - COREDATA_EPOCH_OFFSET
        new_count = 0
        updated_count = 0

        for entry in entries:
            shortcut = normalize_text(entry.shortcut)
            phrase = normalize_text(entry.phrase)

            if shortcut in existing:
                pk, old_phrase = existing[shortcut]
                if old_phrase != phrase:
                    conn.execute(
                        "UPDATE ZTEXTREPLACEMENTENTRY SET ZPHRASE = ?, ZTIMESTAMP = ?, "
                        "ZNEEDSSAVETOCLOUD = 1 WHERE Z_PK = ?",
                        (phrase, now_coredata, pk),
                    )
                    updated_count += 1
                del existing[shortcut]
            else:
                z_max += 1
                unique_name = str(uuid.uuid4()).upper()
                conn.execute(
                    "INSERT INTO ZTEXTREPLACEMENTENTRY "
                    "(Z_PK, Z_ENT, Z_OPT, ZNEEDSSAVETOCLOUD, ZWASDELETED, "
                    "ZTIMESTAMP, ZPHRASE, ZSHORTCUT, ZUNIQUENAME) "
                    "VALUES (?, 1, 1, 1, 0, ?, ?, ?, ?)",
                    (z_max, now_coredata, phrase, shortcut, unique_name),
                )
                new_count += 1

        # Prune entries not in YAML
        pruned_count = 0
        if prune and existing:
            for shortcut, (pk, _) in existing.items():
                conn.execute(
                    "UPDATE ZTEXTREPLACEMENTENTRY SET ZWASDELETED = 1, "
                    "ZNEEDSSAVETOCLOUD = 1, ZTIMESTAMP = ? WHERE Z_PK = ?",
                    (now_coredata, pk),
                )
                pruned_count += 1

        # Update Z_MAX
        conn.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = 1", (z_max,))
        conn.commit()

        print(f"  macOS: {new_count} added, {updated_count} updated, {pruned_count} pruned")
    finally:
        conn.close()

    # Restart keyboard services
    subprocess.run(["killall", "cfprefsd"], capture_output=True)


# ── Alfred Snippets (JSON) ──────────────────────────────────────────────────


def read_alfred_entries() -> list[Snippet]:
    if not ALFRED_SNIPPETS_DIR.exists():
        return []

    entries = []
    for collection_dir in ALFRED_SNIPPETS_DIR.iterdir():
        if not collection_dir.is_dir():
            continue
        collection_name = collection_dir.name
        for json_file in collection_dir.glob("*.json"):
            if json_file.name == "info.plist":
                continue
            try:
                data = json.loads(json_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

            snippet_data = data.get("alfredsnippet", {})
            keyword = normalize_text(snippet_data.get("keyword", ""))
            if not keyword:
                continue  # Skip name-only entries (no shortcut)

            phrase = normalize_text(snippet_data.get("snippet", ""))
            name = normalize_text(snippet_data.get("name", ""))
            uid = snippet_data.get("uid", "")
            enabled = not snippet_data.get("dontautoexpand", False)

            entries.append(
                Snippet(
                    shortcut=keyword,
                    phrase=phrase,
                    name=name,
                    uid=uid,
                    collection=collection_name if collection_name != "Default Collection" else "",
                    enabled=enabled,
                    section="alfred",
                )
            )
    return entries


def write_alfred_entries(
    entries: list[Snippet], prune: bool = False, restart: bool = True, dry_run: bool = False
) -> None:
    if not ALFRED_SNIPPETS_DIR.exists():
        print("  Alfred snippets directory not found, skipping", file=sys.stderr)
        return

    if dry_run:
        print(f"  [dry-run] Would write {len(entries)} entries to Alfred snippets")
        return

    # Find default collection (or first collection)
    collection_dir = ALFRED_SNIPPETS_DIR / "Default Collection"
    if not collection_dir.exists():
        collections = [d for d in ALFRED_SNIPPETS_DIR.iterdir() if d.is_dir()]
        if not collections:
            print("  No Alfred snippet collections found", file=sys.stderr)
            return
        collection_dir = collections[0]

    # Index existing files by keyword
    existing_by_keyword: dict[str, Path] = {}
    existing_by_uid: dict[str, Path] = {}
    for json_file in collection_dir.glob("*.json"):
        if json_file.name == "info.plist":
            continue
        try:
            data = json.loads(json_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        snippet_data = data.get("alfredsnippet", {})
        kw = normalize_text(snippet_data.get("keyword", ""))
        uid = snippet_data.get("uid", "")
        if kw:
            existing_by_keyword[kw] = json_file
        if uid:
            existing_by_uid[uid] = json_file

    new_count = 0
    updated_count = 0
    written_keywords = set()

    for entry in entries:
        keyword = normalize_text(entry.shortcut)
        phrase = normalize_text(entry.phrase)
        name = entry.name or ""
        uid = entry.uid

        # Find existing file by UID first, then keyword
        target_file = None
        if uid and uid in existing_by_uid:
            target_file = existing_by_uid[uid]
        elif keyword in existing_by_keyword:
            target_file = existing_by_keyword[keyword]

        if not uid:
            uid = str(uuid.uuid4()).upper()

        snippet_json = {
            "alfredsnippet": {
                "snippet": phrase,
                "uid": uid,
                "name": name,
                "keyword": keyword,
            }
        }

        if target_file:
            # Check if content changed
            try:
                old_data = json.loads(target_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                old_data = {}
            if old_data != snippet_json:
                target_file.write_text(
                    json.dumps(snippet_json, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8",
                )
                updated_count += 1
        else:
            # Create new file
            filename = f"{uid}.json"
            target_file = collection_dir / filename
            target_file.write_text(
                json.dumps(snippet_json, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            new_count += 1

        written_keywords.add(keyword)

    # Prune
    pruned_count = 0
    if prune:
        for kw, fpath in existing_by_keyword.items():
            if kw not in written_keywords:
                fpath.unlink()
                pruned_count += 1

    print(f"  Alfred: {new_count} added, {updated_count} updated, {pruned_count} pruned")

    # Restart Alfred to reload snippets
    if restart and (new_count > 0 or updated_count > 0 or pruned_count > 0):
        subprocess.run(["killall", "Alfred"], capture_output=True)
        import time

        time.sleep(1)
        subprocess.run(["open", "-a", "Alfred 5"], capture_output=True)
        print("  Alfred restarted to reload snippets")


# ── YAML Read/Write ─────────────────────────────────────────────────────────


def read_yaml(path: Path) -> dict[str, list[Snippet]]:
    from ruamel.yaml import YAML

    if not path.exists():
        return {"shared": [], "macos": [], "alfred": []}

    yaml = YAML()
    yaml.preserve_quotes = True
    data = yaml.load(path)
    if data is None:
        return {"shared": [], "macos": [], "alfred": []}

    result: dict[str, list[Snippet]] = {"shared": [], "macos": [], "alfred": []}
    for section in ("shared", "macos", "alfred"):
        for item in data.get(section, []) or []:
            if item is None:
                continue
            result[section].append(
                Snippet(
                    shortcut=normalize_text(str(item.get("shortcut", ""))),
                    phrase=normalize_text(str(item.get("phrase", ""))),
                    name=normalize_text(str(item.get("name", ""))) if "name" in item else "",
                    uid=str(item.get("uid", "")) if "uid" in item else "",
                    section=section,
                )
            )
    return result


def write_yaml(path: Path, sections: dict[str, list[Snippet]], dry_run: bool = False) -> None:
    from ruamel.yaml import YAML
    from ruamel.yaml.scalarstring import LiteralScalarString

    if dry_run:
        total = sum(len(v) for v in sections.values())
        print(f"  [dry-run] Would write {total} entries to {path}")
        return

    yaml = YAML()
    yaml.default_flow_style = False
    yaml.allow_unicode = True
    yaml.width = 120

    data = {}
    for section in ("shared", "macos", "alfred"):
        items = []
        for s in sorted(sections.get(section, []), key=lambda x: x.shortcut):
            item: dict = {"shortcut": s.shortcut}
            # Use block scalar for multiline phrases
            if "\n" in s.phrase:
                item["phrase"] = LiteralScalarString(s.phrase)
            else:
                item["phrase"] = s.phrase
            if section == "alfred" or s.name:
                item["name"] = s.name
            if section == "alfred" and s.uid:
                item["uid"] = s.uid
            items.append(item)
        if items:
            data[section] = items

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.dump(data, f)

    print(f"  Wrote {sum(len(v) for v in sections.values())} entries to {path}")


# ── Backup ───────────────────────────────────────────────────────────────────


def backup_current_state() -> str:
    import time

    timestamp = time.strftime("%Y%m%d_%H%M%S", time.gmtime())
    backup_path = BACKUP_DIR / timestamp
    backup_path.mkdir(parents=True, exist_ok=True)

    # Backup macOS plist
    if platform.system() == "Darwin":
        plist_backup = backup_path / "macos.plist"
        result = subprocess.run(
            ["defaults", "export", "NSGlobalDomain", str(plist_backup)],
            capture_output=True,
        )
        if result.returncode != 0:
            print(f"  Warning: Failed to backup macOS plist", file=sys.stderr)

    # Backup Alfred snippets
    if ALFRED_SNIPPETS_DIR.exists():
        alfred_backup = backup_path / "alfred"
        shutil.copytree(ALFRED_SNIPPETS_DIR, alfred_backup, dirs_exist_ok=True)

    # Backup YAML
    if YAML_PATH.exists():
        shutil.copy2(YAML_PATH, backup_path / "text_replacements.yaml")

    # Prune old backups
    if BACKUP_DIR.exists():
        backups = sorted(
            [d for d in BACKUP_DIR.iterdir() if d.is_dir()],
            key=lambda d: d.name,
            reverse=True,
        )
        for old_backup in backups[MAX_BACKUPS:]:
            shutil.rmtree(old_backup)

    print(f"  Backup saved to {backup_path}")
    return timestamp


# ── Commands ─────────────────────────────────────────────────────────────────


def cmd_export(args: argparse.Namespace) -> None:
    """Export macOS + Alfred entries to YAML."""
    print("Exporting text replacements to YAML...")

    macos_entries = read_macos_entries()
    alfred_entries = read_alfred_entries()

    # Read existing YAML to preserve section placement
    existing = read_yaml(YAML_PATH)
    existing_shortcuts: dict[str, str] = {}  # shortcut -> section
    for section, snippets in existing.items():
        for s in snippets:
            existing_shortcuts[s.shortcut] = section

    # Build lookup maps
    macos_map = {e.shortcut: e for e in macos_entries}
    alfred_map = {e.shortcut: e for e in alfred_entries}

    # Merge into sections
    sections: dict[str, list[Snippet]] = {"shared": [], "macos": [], "alfred": []}
    seen: set[str] = set()

    # First, preserve existing YAML entries (update phrases from system state)
    for section, snippets in existing.items():
        for s in snippets:
            if s.shortcut in seen:
                continue
            seen.add(s.shortcut)
            # Update phrase from system state if changed (ignore trailing whitespace diffs)
            if s.shortcut in macos_map and section in ("shared", "macos"):
                if not phrases_equal(s.phrase, macos_map[s.shortcut].phrase):
                    s.phrase = macos_map[s.shortcut].phrase
            if s.shortcut in alfred_map and section in ("shared", "alfred"):
                if not phrases_equal(s.phrase, alfred_map[s.shortcut].phrase):
                    s.phrase = alfred_map[s.shortcut].phrase
                if not s.uid and alfred_map[s.shortcut].uid:
                    s.uid = alfred_map[s.shortcut].uid
                if not s.name and alfred_map[s.shortcut].name:
                    s.name = alfred_map[s.shortcut].name
            s.section = section
            sections[section].append(s)

    # Add new entries from macOS
    for shortcut, entry in macos_map.items():
        if shortcut in seen:
            continue
        seen.add(shortcut)
        if shortcut in alfred_map:
            # In both → shared (prefer longer phrase if they differ)
            alfred_entry = alfred_map[shortcut]
            phrase = entry.phrase
            if not phrases_equal(entry.phrase, alfred_entry.phrase):
                phrase = entry.phrase if len(entry.phrase) >= len(alfred_entry.phrase) else alfred_entry.phrase
            sections["shared"].append(
                Snippet(
                    shortcut=shortcut,
                    phrase=phrase,
                    name=alfred_entry.name,
                    uid=alfred_entry.uid,
                    section="shared",
                )
            )
        else:
            sections["macos"].append(Snippet(shortcut=shortcut, phrase=entry.phrase, section="macos"))

    # Add new entries from Alfred only
    for shortcut, entry in alfred_map.items():
        if shortcut in seen:
            continue
        seen.add(shortcut)
        entry.section = "alfred"
        sections["alfred"].append(entry)

    write_yaml(YAML_PATH, sections, dry_run=args.dry_run)


def cmd_import(args: argparse.Namespace) -> None:
    """Import YAML entries to macOS + Alfred."""
    print("Importing text replacements from YAML...")

    if not YAML_PATH.exists():
        print(f"Error: YAML file not found at {YAML_PATH}", file=sys.stderr)
        sys.exit(1)

    if not args.dry_run:
        backup_current_state()

    sections = read_yaml(YAML_PATH)

    # macOS entries: shared + macos
    macos_entries = sections["shared"] + sections["macos"]
    write_macos_entries(macos_entries, prune=args.prune, dry_run=args.dry_run)

    # Alfred entries: shared + alfred
    alfred_entries = sections["shared"] + sections["alfred"]
    restart = not getattr(args, "no_restart_alfred", False)
    write_alfred_entries(alfred_entries, prune=args.prune, restart=restart, dry_run=args.dry_run)


def cmd_sync(args: argparse.Namespace) -> None:
    """Bidirectional sync: YAML <-> macOS + Alfred."""
    print("Syncing text replacements (bidirectional)...")

    if not args.dry_run:
        backup_current_state()

    # Read all three sources
    yaml_sections = read_yaml(YAML_PATH)
    macos_entries = read_macos_entries()
    alfred_entries = read_alfred_entries()

    # Build maps
    yaml_map: dict[str, Snippet] = {}
    yaml_section_map: dict[str, str] = {}
    for section, snippets in yaml_sections.items():
        for s in snippets:
            yaml_map[s.shortcut] = s
            yaml_section_map[s.shortcut] = section

    macos_map = {e.shortcut: e for e in macos_entries}
    alfred_map = {e.shortcut: e for e in alfred_entries}

    # Check for case-only duplicates
    lower_map: dict[str, list[str]] = {}
    all_shortcuts = set(yaml_map) | set(macos_map) | set(alfred_map)
    for sc in all_shortcuts:
        lower_map.setdefault(sc.lower(), []).append(sc)
    for lower, variants in lower_map.items():
        if len(set(variants)) > 1:
            print(f"  Warning: case-only duplicates: {variants}", file=sys.stderr)

    # Merge
    merged: dict[str, list[Snippet]] = {"shared": [], "macos": [], "alfred": []}
    seen: set[str] = set()

    # Process all known shortcuts
    for shortcut in all_shortcuts:
        if shortcut in seen:
            continue
        seen.add(shortcut)

        in_yaml = shortcut in yaml_map
        in_macos = shortcut in macos_map
        in_alfred = shortcut in alfred_map
        yaml_section = yaml_section_map.get(shortcut)

        if in_yaml:
            base = yaml_map[shortcut]
            section = yaml_section

            # Same shortcut, different phrase → prefer system state
            if in_macos and not phrases_equal(macos_map[shortcut].phrase, base.phrase) and section in (
                "shared",
                "macos",
            ):
                base.phrase = macos_map[shortcut].phrase
            if in_alfred and not phrases_equal(alfred_map[shortcut].phrase, base.phrase) and section in (
                "shared",
                "alfred",
            ):
                base.phrase = alfred_map[shortcut].phrase
                if not base.uid and alfred_map[shortcut].uid:
                    base.uid = alfred_map[shortcut].uid
                if not base.name and alfred_map[shortcut].name:
                    base.name = alfred_map[shortcut].name

            base.section = section
            merged[section].append(base)
        else:
            # New entry from system — determine section
            if in_macos and in_alfred:
                section = "shared"
                alfred_e = alfred_map[shortcut]
                merged[section].append(
                    Snippet(
                        shortcut=shortcut,
                        phrase=macos_map[shortcut].phrase,
                        name=alfred_e.name,
                        uid=alfred_e.uid,
                        section=section,
                    )
                )
            elif in_macos:
                section = "macos"
                merged[section].append(
                    Snippet(shortcut=shortcut, phrase=macos_map[shortcut].phrase, section=section)
                )
            elif in_alfred:
                section = "alfred"
                e = alfred_map[shortcut]
                e.section = section
                merged[section].append(e)

    # Write updated YAML
    write_yaml(YAML_PATH, merged, dry_run=args.dry_run)

    # Import back to systems
    macos_import = merged["shared"] + merged["macos"]
    write_macos_entries(macos_import, prune=args.prune, dry_run=args.dry_run)

    alfred_import = merged["shared"] + merged["alfred"]
    restart = not getattr(args, "no_restart_alfred", False)
    write_alfred_entries(alfred_import, prune=args.prune, restart=restart, dry_run=args.dry_run)


def cmd_diff(args: argparse.Namespace) -> None:
    """Show differences between YAML, macOS, and Alfred."""
    yaml_sections = read_yaml(YAML_PATH)
    macos_entries = read_macos_entries()
    alfred_entries = read_alfred_entries()

    yaml_map: dict[str, Snippet] = {}
    for section, snippets in yaml_sections.items():
        for s in snippets:
            yaml_map[s.shortcut] = s

    macos_map = {e.shortcut: e for e in macos_entries}
    alfred_map = {e.shortcut: e for e in alfred_entries}

    all_shortcuts = sorted(set(yaml_map) | set(macos_map) | set(alfred_map))

    diffs = []
    for sc in all_shortcuts:
        in_yaml = sc in yaml_map
        in_macos = sc in macos_map
        in_alfred = sc in alfred_map

        issues = []
        if in_yaml and not in_macos:
            section = yaml_map[sc].section
            if section in ("shared", "macos"):
                issues.append("missing from macOS")
        if in_yaml and not in_alfred:
            section = yaml_map[sc].section
            if section in ("shared", "alfred"):
                issues.append("missing from Alfred")
        if in_macos and not in_yaml:
            issues.append("on macOS but not in YAML")
        if in_alfred and not in_yaml:
            issues.append("in Alfred but not in YAML")
        if in_yaml and in_macos and not phrases_equal(yaml_map[sc].phrase, macos_map[sc].phrase):
            issues.append("phrase differs (YAML vs macOS)")
        if in_yaml and in_alfred and not phrases_equal(yaml_map[sc].phrase, alfred_map[sc].phrase):
            issues.append("phrase differs (YAML vs Alfred)")

        if issues:
            diffs.append((sc, issues))

    if not diffs:
        print("All sources are in sync.")
    else:
        print(f"Found {len(diffs)} difference(s):")
        for sc, issues in diffs:
            for issue in issues:
                print(f"  {sc}: {issue}")


def cmd_restore(args: argparse.Namespace) -> None:
    """Restore from a backup."""
    if not BACKUP_DIR.exists():
        print("No backups found.", file=sys.stderr)
        sys.exit(1)

    backups = sorted([d for d in BACKUP_DIR.iterdir() if d.is_dir()], key=lambda d: d.name)
    if not backups:
        print("No backups found.", file=sys.stderr)
        sys.exit(1)

    if args.timestamp:
        backup_path = BACKUP_DIR / args.timestamp
        if not backup_path.exists():
            print(f"Backup not found: {args.timestamp}", file=sys.stderr)
            print("Available backups:")
            for b in backups:
                print(f"  {b.name}")
            sys.exit(1)
    else:
        backup_path = backups[-1]
        print(f"Restoring from latest backup: {backup_path.name}")

    # Restore YAML
    yaml_backup = backup_path / "text_replacements.yaml"
    if yaml_backup.exists():
        shutil.copy2(yaml_backup, YAML_PATH)
        print(f"  Restored YAML from backup")

    # Restore Alfred snippets
    alfred_backup = backup_path / "alfred"
    if alfred_backup.exists() and ALFRED_SNIPPETS_DIR.exists():
        # Remove current and copy backup
        shutil.rmtree(ALFRED_SNIPPETS_DIR)
        shutil.copytree(alfred_backup, ALFRED_SNIPPETS_DIR)
        print(f"  Restored Alfred snippets from backup")

    print(f"Restored from {backup_path.name}")
    print("Note: macOS text replacements restored via plist backup require manual import")
    print(f"  Plist backup: {backup_path / 'macos.plist'}")


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync text replacements between macOS, Alfred, and YAML config"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # export
    p_export = subparsers.add_parser("export", help="Export macOS + Alfred -> YAML")
    p_export.add_argument("--dry-run", action="store_true")

    # import
    p_import = subparsers.add_parser("import", help="YAML -> macOS + Alfred")
    p_import.add_argument("--dry-run", action="store_true")
    p_import.add_argument("--prune", action="store_true", help="Remove entries not in YAML")
    p_import.add_argument(
        "--no-restart-alfred", action="store_true", help="Don't restart Alfred after import"
    )

    # sync
    p_sync = subparsers.add_parser("sync", help="Bidirectional merge")
    p_sync.add_argument("--dry-run", action="store_true")
    p_sync.add_argument("--prune", action="store_true", help="Remove entries deleted from YAML")
    p_sync.add_argument(
        "--no-restart-alfred", action="store_true", help="Don't restart Alfred after sync"
    )

    # diff
    subparsers.add_parser("diff", help="Show differences without writing")

    # restore
    p_restore = subparsers.add_parser("restore", help="Restore from backup")
    p_restore.add_argument("timestamp", nargs="?", default=None, help="Backup timestamp")

    args = parser.parse_args()

    commands = {
        "export": cmd_export,
        "import": cmd_import,
        "sync": cmd_sync,
        "diff": cmd_diff,
        "restore": cmd_restore,
    }
    commands[args.command](args)


if __name__ == "__main__":
    main()
