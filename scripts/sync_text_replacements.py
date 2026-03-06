#!/usr/bin/env python3
"""Sync text replacements between macOS, Alfred snippets, and a YAML config file.

YAML format: top-level keys = Alfred collection names.
All entries sync to both macOS text replacements AND Alfred snippets unless:
  - alfred_only: true  → Alfred only (for case-sensitive shortcuts, long prompts)
  - enabled: false     → disabled (Alfred: dontautoexpand; macOS: soft-deleted)

Requires Full Disk Access for the terminal app (System Settings → Privacy → Full Disk Access)
when Alfred preferences are synced via Dropbox/iCloud.

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
import platform
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import time
import unicodedata
import uuid
from dataclasses import dataclass
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
DOT_DIR = SCRIPT_DIR.parent
YAML_PATH = DOT_DIR / "config" / "text_replacements.yaml"

TEXT_REPLACEMENTS_DB = Path.home() / "Library" / "KeyboardServices" / "TextReplacements.db"

BACKUP_DIR = Path.home() / ".local" / "share" / "text-replacements-backup"
MAX_BACKUPS = 10

# CoreData epoch: 2001-01-01 00:00:00 UTC
COREDATA_EPOCH_OFFSET = 978307200.0

DEFAULT_COLLECTION = "default"


# ── Data Model ───────────────────────────────────────────────────────────────


@dataclass
class Snippet:
    shortcut: str
    phrase: str
    name: str = ""
    uid: str = ""
    collection: str = DEFAULT_COLLECTION
    alfred_only: bool = False
    enabled: bool = True


@dataclass
class CollectionMeta:
    """Alfred collection metadata from info.plist."""

    prefix: str = ""
    suffix: str = ""


# ── Text Normalization ───────────────────────────────────────────────────────


def normalize_text(s: str | None) -> str:
    if s is None:
        return ""
    return unicodedata.normalize("NFC", s)


def phrases_equal(a: str, b: str) -> bool:
    """Compare phrases ignoring trailing whitespace (block scalars add trailing newlines)."""
    return normalize_text(a).rstrip() == normalize_text(b).rstrip()


# ── Alfred Path Detection ───────────────────────────────────────────────────


def get_alfred_snippets_dir() -> Path | None:
    """Auto-detect Alfred's snippets directory from its sync folder preference."""
    if platform.system() != "Darwin":
        return None

    # Check Alfred's configured sync folder
    try:
        result = subprocess.run(
            ["defaults", "read", "com.runningwithcrayons.Alfred-Preferences", "syncfolder"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            sync_folder = result.stdout.strip()
            # Expand ~ in path
            sync_folder = str(Path(sync_folder).expanduser())
            snippets_dir = Path(sync_folder) / "Alfred.alfredpreferences" / "snippets"
            if snippets_dir.exists():
                return snippets_dir
    except Exception:
        pass

    # Fallback: local Alfred preferences
    local = (
        Path.home()
        / "Library"
        / "Application Support"
        / "Alfred"
        / "Alfred.alfredpreferences"
        / "snippets"
    )
    if local.exists():
        return local

    return None


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
                entries.append(Snippet(shortcut=shortcut, phrase=phrase))
    finally:
        conn.close()
    return entries


def _sync_nsglobaldomain_plist(entries: list[Snippet]) -> None:
    """Sync entries to NSGlobalDomain NSUserDictionaryReplacementItems (legacy plist store)."""
    plist_path = Path.home() / "Library" / "Preferences" / ".GlobalPreferences.plist"
    if not plist_path.exists():
        return
    with open(plist_path, "rb") as f:
        prefs = plistlib.load(f)
    prefs["NSUserDictionaryReplacementItems"] = [
        {"on": True, "replace": e.shortcut, "with": e.phrase}
        for e in entries
    ]
    with open(plist_path, "wb") as f:
        plistlib.dump(prefs, f)


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

    conn = sqlite3.connect(str(TEXT_REPLACEMENTS_DB))
    try:
        z_max = conn.execute("SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_ENT = 1").fetchone()[0]

        existing = {}
        for row in conn.execute(
            "SELECT Z_PK, ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0"
        ):
            existing[normalize_text(row[1])] = (row[0], normalize_text(row[2]))

        now_coredata = time.time() - COREDATA_EPOCH_OFFSET
        new_count = updated_count = pruned_count = 0

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

        if prune and existing:
            for shortcut, (pk, _) in existing.items():
                conn.execute(
                    "UPDATE ZTEXTREPLACEMENTENTRY SET ZWASDELETED = 1, "
                    "ZNEEDSSAVETOCLOUD = 1, ZTIMESTAMP = ? WHERE Z_PK = ?",
                    (now_coredata, pk),
                )
                pruned_count += 1

        conn.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = 1", (z_max,))
        conn.commit()
        print(f"  macOS: {new_count} added, {updated_count} updated, {pruned_count} pruned")
    finally:
        conn.close()

    # Sync the NSGlobalDomain plist (legacy store that System Settings also reads)
    _sync_nsglobaldomain_plist(entries)

    # Restart cfprefsd (flushes plist cache) and kbd (triggers iCloud sync)
    subprocess.run(["killall", "cfprefsd"], capture_output=True)
    subprocess.run(["killall", "kbd"], capture_output=True)
    # kbd auto-restarts via launchd; it reads ZNEEDSSAVETOCLOUD=1 and syncs to iCloud


# ── Alfred Snippets (JSON) ──────────────────────────────────────────────────


def read_alfred_entries(snippets_dir: Path) -> tuple[list[Snippet], dict[str, CollectionMeta]]:
    """Read all Alfred snippets. Returns (entries, collection_metadata)."""
    entries = []
    collection_meta: dict[str, CollectionMeta] = {}

    for collection_dir in snippets_dir.iterdir():
        if not collection_dir.is_dir():
            continue

        collection_name = collection_dir.name
        meta = CollectionMeta()

        # Read collection info.plist for prefix/suffix
        info_plist = collection_dir / "info.plist"
        if info_plist.exists():
            try:
                with open(info_plist, "rb") as f:
                    plist_data = plistlib.load(f)
                meta.prefix = plist_data.get("snippetkeywordprefix", "")
                meta.suffix = plist_data.get("snippetkeywordsuffix", "")
            except Exception:
                pass

        collection_meta[collection_name] = meta

        for json_file in collection_dir.glob("*.json"):
            try:
                data = json.loads(json_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

            snippet_data = data.get("alfredsnippet", {})
            keyword = normalize_text(snippet_data.get("keyword", ""))
            if not keyword:
                continue

            entries.append(
                Snippet(
                    shortcut=keyword,
                    phrase=normalize_text(snippet_data.get("snippet", "")),
                    name=normalize_text(snippet_data.get("name", "")),
                    uid=snippet_data.get("uid", ""),
                    collection=collection_name,
                    enabled=not snippet_data.get("dontautoexpand", False),
                )
            )

    return entries, collection_meta


def write_alfred_entries(
    entries: list[Snippet],
    snippets_dir: Path,
    collection_meta: dict[str, CollectionMeta],
    prune: bool = False,
    restart: bool = True,
    dry_run: bool = False,
) -> None:
    if dry_run:
        print(f"  [dry-run] Would write {len(entries)} entries to Alfred snippets")
        return

    # Group entries by collection
    by_collection: dict[str, list[Snippet]] = {}
    for entry in entries:
        by_collection.setdefault(entry.collection, []).append(entry)

    # Index all existing files across all collections
    existing_files: dict[str, dict[str, Path]] = {}  # collection -> {uid: path}
    existing_by_keyword: dict[str, dict[str, Path]] = {}  # collection -> {keyword: path}
    for collection_dir in snippets_dir.iterdir():
        if not collection_dir.is_dir():
            continue
        col_name = collection_dir.name
        existing_files[col_name] = {}
        existing_by_keyword[col_name] = {}
        for json_file in collection_dir.glob("*.json"):
            try:
                data = json.loads(json_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            sd = data.get("alfredsnippet", {})
            uid = sd.get("uid", "")
            kw = normalize_text(sd.get("keyword", ""))
            if uid:
                existing_files[col_name][uid] = json_file
            if kw:
                existing_by_keyword[col_name][kw] = json_file

    new_count = updated_count = pruned_count = 0
    written_uids: dict[str, set[str]] = {}  # collection -> set of written UIDs

    for col_name, col_entries in by_collection.items():
        collection_dir = snippets_dir / col_name
        collection_dir.mkdir(parents=True, exist_ok=True)

        # Write info.plist if collection is new and has metadata
        info_plist = collection_dir / "info.plist"
        if not info_plist.exists() and col_name in collection_meta:
            meta = collection_meta[col_name]
            plist_data = {}
            if meta.prefix:
                plist_data["snippetkeywordprefix"] = meta.prefix
            if meta.suffix:
                plist_data["snippetkeywordsuffix"] = meta.suffix
            if plist_data:
                with open(info_plist, "wb") as f:
                    plistlib.dump(plist_data, f)

        written_uids[col_name] = set()
        col_existing_uid = existing_files.get(col_name, {})
        col_existing_kw = existing_by_keyword.get(col_name, {})

        for entry in col_entries:
            keyword = normalize_text(entry.shortcut)
            phrase = normalize_text(entry.phrase)
            name = entry.name or ""
            uid = entry.uid

            # Find existing file
            target_file = None
            if uid and uid in col_existing_uid:
                target_file = col_existing_uid[uid]
            elif keyword in col_existing_kw:
                target_file = col_existing_kw[keyword]

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
            if not entry.enabled:
                snippet_json["alfredsnippet"]["dontautoexpand"] = True

            written_uids[col_name].add(uid)

            if target_file:
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
                target_file = collection_dir / f"{uid}.json"
                target_file.write_text(
                    json.dumps(snippet_json, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8",
                )
                new_count += 1

    # Prune
    if prune:
        for col_name, uid_map in existing_files.items():
            written = written_uids.get(col_name, set())
            for uid, fpath in uid_map.items():
                if uid not in written:
                    fpath.unlink()
                    pruned_count += 1

    print(f"  Alfred: {new_count} added, {updated_count} updated, {pruned_count} pruned")

    if restart and (new_count > 0 or updated_count > 0 or pruned_count > 0):
        subprocess.run(["killall", "Alfred"], capture_output=True)
        time.sleep(1)
        subprocess.run(["open", "-a", "Alfred 5"], capture_output=True)
        print("  Alfred restarted to reload snippets")


# ── YAML Read/Write ─────────────────────────────────────────────────────────


def read_yaml(path: Path) -> tuple[dict[str, list[Snippet]], dict[str, CollectionMeta]]:
    """Read YAML. Returns (collections dict, collection metadata)."""
    from ruamel.yaml import YAML

    if not path.exists():
        return {}, {}

    yaml = YAML()
    yaml.preserve_quotes = True
    data = yaml.load(path)
    if data is None:
        return {}, {}

    collections: dict[str, list[Snippet]] = {}
    collection_meta: dict[str, CollectionMeta] = {}

    for col_name, col_data in data.items():
        if col_name == "_meta":
            # Collection metadata section
            for meta_col, meta_data in (col_data or {}).items():
                collection_meta[meta_col] = CollectionMeta(
                    prefix=str(meta_data.get("prefix", "")),
                    suffix=str(meta_data.get("suffix", "")),
                )
            continue

        snippets = []
        for item in col_data or []:
            if item is None:
                continue
            snippets.append(
                Snippet(
                    shortcut=normalize_text(str(item.get("shortcut", ""))),
                    phrase=normalize_text(str(item.get("phrase", ""))),
                    name=normalize_text(str(item.get("name", ""))) if "name" in item else "",
                    uid=str(item.get("uid", "")) if "uid" in item else "",
                    collection=col_name,
                    alfred_only=bool(item.get("alfred_only", False)),
                    enabled=bool(item.get("enabled", True)),
                )
            )
        collections[col_name] = snippets

    return collections, collection_meta


def write_yaml(
    path: Path,
    collections: dict[str, list[Snippet]],
    collection_meta: dict[str, CollectionMeta],
    dry_run: bool = False,
) -> None:
    from ruamel.yaml import YAML
    from ruamel.yaml.scalarstring import LiteralScalarString

    total = sum(len(v) for v in collections.values())
    if dry_run:
        print(f"  [dry-run] Would write {total} entries to {path}")
        return

    yaml = YAML()
    yaml.default_flow_style = False
    yaml.allow_unicode = True
    yaml.width = 120

    data = {}

    # Write collection metadata if any have prefixes/suffixes
    meta_data = {}
    for col_name, meta in collection_meta.items():
        if meta.prefix or meta.suffix:
            entry = {}
            if meta.prefix:
                entry["prefix"] = meta.prefix
            if meta.suffix:
                entry["suffix"] = meta.suffix
            meta_data[col_name] = entry
    if meta_data:
        data["_meta"] = meta_data

    # Write collections (default first, then alphabetical)
    col_order = []
    if DEFAULT_COLLECTION in collections:
        col_order.append(DEFAULT_COLLECTION)
    col_order.extend(sorted(c for c in collections if c != DEFAULT_COLLECTION))

    for col_name in col_order:
        items = []
        for s in sorted(collections[col_name], key=lambda x: x.shortcut):
            item: dict = {"shortcut": s.shortcut}
            if "\n" in s.phrase:
                item["phrase"] = LiteralScalarString(s.phrase)
            else:
                item["phrase"] = s.phrase
            if s.name:
                item["name"] = s.name
            if s.uid:
                item["uid"] = s.uid
            if s.alfred_only:
                item["alfred_only"] = True
            if not s.enabled:
                item["enabled"] = False
            items.append(item)
        if items:
            data[col_name] = items

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.dump(data, f)

    print(f"  Wrote {total} entries ({len(collections)} collections) to {path}")


# ── Backup ───────────────────────────────────────────────────────────────────


def backup_current_state(snippets_dir: Path | None) -> str:
    timestamp = time.strftime("%Y%m%d_%H%M%S", time.gmtime())
    backup_path = BACKUP_DIR / timestamp
    backup_path.mkdir(parents=True, exist_ok=True)

    if platform.system() == "Darwin":
        # Back up the actual SQLite DB (+ WAL/SHM sidecars) for real rollback
        if TEXT_REPLACEMENTS_DB.exists():
            for suffix in ("", "-wal", "-shm"):
                src = TEXT_REPLACEMENTS_DB.parent / (TEXT_REPLACEMENTS_DB.name + suffix)
                if src.exists():
                    shutil.copy2(src, backup_path / src.name)

    if snippets_dir and snippets_dir.exists():
        alfred_backup = backup_path / "alfred"
        shutil.copytree(snippets_dir, alfred_backup, dirs_exist_ok=True)

    if YAML_PATH.exists():
        shutil.copy2(YAML_PATH, backup_path / "text_replacements.yaml")

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


# ── Helper: flatten collections to lists ─────────────────────────────────────


def all_snippets(collections: dict[str, list[Snippet]]) -> list[Snippet]:
    return [s for snippets in collections.values() for s in snippets]


def macos_eligible(s: Snippet) -> bool:
    """Should this snippet be synced to macOS text replacements?"""
    return not s.alfred_only and s.enabled


def prefixed_shortcut(s: Snippet, meta: dict[str, CollectionMeta]) -> str:
    """Return shortcut with collection prefix applied (for macOS)."""
    cm = meta.get(s.collection)
    if cm and cm.prefix:
        return cm.prefix + s.shortcut
    return s.shortcut


# ── Commands ─────────────────────────────────────────────────────────────────


def cmd_export(args: argparse.Namespace) -> None:
    """Export macOS + Alfred entries to YAML."""
    print("Exporting text replacements to YAML...")

    snippets_dir = get_alfred_snippets_dir()
    macos_entries = read_macos_entries()
    alfred_entries, alfred_meta = (
        read_alfred_entries(snippets_dir) if snippets_dir else ([], {})
    )

    # Read existing YAML to preserve manual edits
    existing_collections, existing_meta = read_yaml(YAML_PATH)
    merged_meta = {**existing_meta, **alfred_meta}
    existing_map: dict[str, Snippet] = {}
    for snippets in existing_collections.values():
        for s in snippets:
            existing_map[s.shortcut] = s

    # Build prefix reverse map from YAML entries
    prefix_to_raw: dict[str, str] = {}
    for s in existing_map.values():
        ps = prefixed_shortcut(s, merged_meta)
        if ps != s.shortcut:
            prefix_to_raw[ps] = s.shortcut

    # macOS map keyed by raw shortcut (strip prefix if recognized)
    macos_map: dict[str, Snippet] = {}
    for e in macos_entries:
        raw = prefix_to_raw.get(e.shortcut, e.shortcut)
        macos_map[raw] = Snippet(shortcut=raw, phrase=e.phrase, uid=e.uid,
                                 collection=e.collection, enabled=e.enabled)

    alfred_map = {e.shortcut: e for e in alfred_entries}

    # Build merged collections
    collections: dict[str, list[Snippet]] = {}
    seen: set[str] = set()

    # 1. Preserve existing YAML entries, update phrases from system state
    for col_name, snippets in existing_collections.items():
        for s in snippets:
            if s.shortcut in seen:
                continue
            seen.add(s.shortcut)

            if s.shortcut in macos_map and not s.alfred_only:
                if not phrases_equal(s.phrase, macos_map[s.shortcut].phrase):
                    s.phrase = macos_map[s.shortcut].phrase
            if s.shortcut in alfred_map:
                alfred_s = alfred_map[s.shortcut]
                if not phrases_equal(s.phrase, alfred_s.phrase):
                    s.phrase = alfred_s.phrase
                if not s.uid and alfred_s.uid:
                    s.uid = alfred_s.uid
                if not s.name and alfred_s.name:
                    s.name = alfred_s.name

            collections.setdefault(col_name, []).append(s)

    # 2. Add new Alfred entries (placed in their collection)
    for entry in alfred_entries:
        if entry.shortcut in seen:
            continue
        seen.add(entry.shortcut)
        collections.setdefault(entry.collection, []).append(entry)

    # 3. Add macOS-only entries (no Alfred match) to default collection
    for shortcut, entry in macos_map.items():
        if shortcut in seen:
            continue
        seen.add(shortcut)
        entry.collection = DEFAULT_COLLECTION
        collections.setdefault(DEFAULT_COLLECTION, []).append(entry)

    write_yaml(YAML_PATH, collections, merged_meta, dry_run=args.dry_run)


def cmd_import(args: argparse.Namespace) -> None:
    """Import YAML entries to macOS + Alfred."""
    print("Importing text replacements from YAML...")

    if not YAML_PATH.exists():
        print(f"Error: YAML file not found at {YAML_PATH}", file=sys.stderr)
        sys.exit(1)

    snippets_dir = get_alfred_snippets_dir()

    if not args.dry_run:
        backup_current_state(snippets_dir)

    collections, collection_meta = read_yaml(YAML_PATH)
    all_entries = all_snippets(collections)

    # macOS: all enabled, non-alfred-only entries (with collection prefix applied)
    macos_entries = [
        Snippet(shortcut=prefixed_shortcut(s, collection_meta), phrase=s.phrase,
                uid=s.uid, collection=s.collection, enabled=s.enabled)
        for s in all_entries if macos_eligible(s)
    ]
    write_macos_entries(macos_entries, prune=args.prune, dry_run=args.dry_run)

    # Alfred: all entries with raw shortcuts (Alfred applies prefix at runtime)
    if snippets_dir:
        restart = not getattr(args, "no_restart_alfred", False)
        write_alfred_entries(
            all_entries, snippets_dir, collection_meta,
            prune=args.prune, restart=restart, dry_run=args.dry_run,
        )


def cmd_sync(args: argparse.Namespace) -> None:
    """Bidirectional sync: YAML <-> macOS + Alfred."""
    print("Syncing text replacements (bidirectional)...")

    snippets_dir = get_alfred_snippets_dir()

    if not args.dry_run:
        backup_current_state(snippets_dir)

    yaml_collections, yaml_meta = read_yaml(YAML_PATH)
    macos_entries = read_macos_entries()
    alfred_entries, alfred_meta = (
        read_alfred_entries(snippets_dir) if snippets_dir else ([], {})
    )

    merged_meta = {**yaml_meta, **alfred_meta}

    # Build lookup maps
    yaml_map: dict[str, Snippet] = {}
    for snippets in yaml_collections.values():
        for s in snippets:
            yaml_map[s.shortcut] = s

    # Build reverse prefix map: prefixed_shortcut -> raw_shortcut
    prefix_to_raw: dict[str, str] = {}
    for s in yaml_map.values():
        ps = prefixed_shortcut(s, merged_meta)
        if ps != s.shortcut:
            prefix_to_raw[ps] = s.shortcut

    # Map macOS entries by raw shortcut (strip prefix if recognized)
    macos_map: dict[str, Snippet] = {}
    for e in macos_entries:
        raw = prefix_to_raw.get(e.shortcut, e.shortcut)
        macos_map[raw] = Snippet(shortcut=raw, phrase=e.phrase, uid=e.uid,
                                 collection=e.collection, enabled=e.enabled)

    alfred_map = {e.shortcut: e for e in alfred_entries}

    # Warn on case-only duplicates
    all_shortcuts = set(yaml_map) | set(macos_map) | set(alfred_map)
    lower_map: dict[str, list[str]] = {}
    for sc in all_shortcuts:
        lower_map.setdefault(sc.lower(), []).append(sc)
    for lower, variants in lower_map.items():
        if len(set(variants)) > 1:
            print(f"  Warning: case-only duplicates: {set(variants)}", file=sys.stderr)

    # Merge into collections
    collections: dict[str, list[Snippet]] = {}
    seen: set[str] = set()

    # 1. Update existing YAML entries from system state
    for col_name, snippets in yaml_collections.items():
        for s in snippets:
            if s.shortcut in seen:
                continue
            seen.add(s.shortcut)

            if s.shortcut in macos_map and not s.alfred_only:
                if not phrases_equal(macos_map[s.shortcut].phrase, s.phrase):
                    s.phrase = macos_map[s.shortcut].phrase
            if s.shortcut in alfred_map:
                alfred_s = alfred_map[s.shortcut]
                if not phrases_equal(alfred_s.phrase, s.phrase):
                    s.phrase = alfred_s.phrase
                if not s.uid and alfred_s.uid:
                    s.uid = alfred_s.uid
                if not s.name and alfred_s.name:
                    s.name = alfred_s.name

            collections.setdefault(col_name, []).append(s)

    # 2. New Alfred entries
    for entry in alfred_entries:
        if entry.shortcut in seen:
            continue
        seen.add(entry.shortcut)
        collections.setdefault(entry.collection, []).append(entry)

    # 3. New macOS-only entries
    for shortcut, entry in macos_map.items():
        if shortcut in seen:
            continue
        seen.add(shortcut)
        entry.collection = DEFAULT_COLLECTION
        collections.setdefault(DEFAULT_COLLECTION, []).append(entry)

    # Write YAML
    write_yaml(YAML_PATH, collections, merged_meta, dry_run=args.dry_run)

    # Write back to systems
    all_entries = all_snippets(collections)

    # macOS: apply collection prefix to shortcuts
    macos_import = [
        Snippet(shortcut=prefixed_shortcut(s, merged_meta), phrase=s.phrase,
                uid=s.uid, collection=s.collection, enabled=s.enabled)
        for s in all_entries if macos_eligible(s)
    ]
    write_macos_entries(macos_import, prune=args.prune, dry_run=args.dry_run)

    # Alfred: raw shortcuts (Alfred applies prefix at runtime)
    if snippets_dir:
        restart = not getattr(args, "no_restart_alfred", False)
        write_alfred_entries(
            all_entries, snippets_dir, merged_meta,
            prune=args.prune, restart=restart, dry_run=args.dry_run,
        )


def cmd_diff(args: argparse.Namespace) -> None:
    """Show differences between YAML, macOS, and Alfred."""
    snippets_dir = get_alfred_snippets_dir()
    yaml_collections, yaml_meta = read_yaml(YAML_PATH)
    macos_entries = read_macos_entries()
    alfred_entries, alfred_meta = read_alfred_entries(snippets_dir) if snippets_dir else ([], {})

    merged_meta = {**yaml_meta, **alfred_meta}

    # YAML map keyed by raw shortcut
    yaml_map: dict[str, Snippet] = {}
    for snippets in yaml_collections.values():
        for s in snippets:
            yaml_map[s.shortcut] = s

    # Build prefixed→raw reverse map for macOS comparison
    prefix_to_raw: dict[str, str] = {}
    raw_to_prefixed: dict[str, str] = {}
    for s in yaml_map.values():
        ps = prefixed_shortcut(s, merged_meta)
        if ps != s.shortcut:
            prefix_to_raw[ps] = s.shortcut
            raw_to_prefixed[s.shortcut] = ps

    # macOS map keyed by raw shortcut (strip prefix if recognized)
    macos_map: dict[str, Snippet] = {}
    for e in macos_entries:
        raw = prefix_to_raw.get(e.shortcut, e.shortcut)
        macos_map[raw] = Snippet(shortcut=raw, phrase=e.phrase)

    alfred_map = {e.shortcut: e for e in alfred_entries}

    all_shortcuts = sorted(set(yaml_map) | set(macos_map) | set(alfred_map))

    diffs = []
    for sc in all_shortcuts:
        in_yaml = sc in yaml_map
        in_macos = sc in macos_map
        in_alfred = sc in alfred_map

        issues = []
        if in_yaml and not in_macos and macos_eligible(yaml_map[sc]):
            issues.append("missing from macOS")
        if in_yaml and not in_alfred:
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

    yaml_backup = backup_path / "text_replacements.yaml"
    if yaml_backup.exists():
        shutil.copy2(yaml_backup, YAML_PATH)
        print("  Restored YAML from backup")

    snippets_dir = get_alfred_snippets_dir()
    alfred_backup = backup_path / "alfred"
    if alfred_backup.exists() and snippets_dir:
        # Safe swap: stage → rename old → rename staged → clean up
        staging = snippets_dir.parent / (snippets_dir.name + ".restoring")
        shutil.copytree(alfred_backup, staging, dirs_exist_ok=True)
        old_dir = snippets_dir.parent / (snippets_dir.name + ".bak")
        if snippets_dir.exists():
            if old_dir.exists():
                shutil.rmtree(old_dir)
            snippets_dir.rename(old_dir)
        staging.rename(snippets_dir)
        if old_dir.exists():
            shutil.rmtree(old_dir)
        print("  Restored Alfred snippets from backup")

    print(f"Restored from {backup_path.name}")
    print("Note: macOS text replacements require 'import' to restore from YAML")


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync text replacements between macOS, Alfred, and YAML config"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_export = subparsers.add_parser("export", help="Export macOS + Alfred -> YAML")
    p_export.add_argument("--dry-run", action="store_true")

    p_import = subparsers.add_parser("import", help="YAML -> macOS + Alfred")
    p_import.add_argument("--dry-run", action="store_true")
    p_import.add_argument("--prune", action="store_true", help="Remove entries not in YAML")
    p_import.add_argument("--no-restart-alfred", action="store_true")

    p_sync = subparsers.add_parser("sync", help="Bidirectional merge")
    p_sync.add_argument("--dry-run", action="store_true")
    p_sync.add_argument("--prune", action="store_true")
    p_sync.add_argument("--no-restart-alfred", action="store_true")

    subparsers.add_parser("diff", help="Show differences without writing")

    p_restore = subparsers.add_parser("restore", help="Restore from backup")
    p_restore.add_argument("timestamp", nargs="?", default=None)

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
