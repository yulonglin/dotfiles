"""Regression tests for the EX-6/EX-7 safety gate in scripts/vault/vault_sync.py.

The gate decides whether it is safe to tighten Obsidian's folder exclusion.
Exclusion is *not* retroactive: if it lands while remote `node_modules` rows are
still live, those ~285 MB strand on the server permanently with no way to
reclaim the quota. The invariant is therefore **zero live rows under the exact
folder being excluded** -- not "some tombstones exist somewhere".

That invariant has now been got wrong three times, each time in the same shape:

  QR-6  counted `local_files`, where no row ever carries `deleted`
        (structurally always zero).
  P1    counted `server_files` vault-wide, so staging the 25 runs/ files made
        the count nonzero while every node_modules row was still live.
  P2    counted tombstones under the right prefix but unlocked on `>= 1`, so a
        sync that died after one row unlocked the exclusion for the other
        26,983.

The shared lesson is that a gate is only as good as the thing the tests
actually call. The previous version of this file re-implemented the gate's SQL
in a local `counts()` helper, so reverting any production gate left every test
green -- it tested a copy of the logic, not the logic. Every test below drives
the shipped `cmd_verify` / `cmd_filters` / `cmd_tripwire` entry points end to
end, from SYNC_ROOT discovery through the real state.db copy (WAL sidecars
included) to the real `die()`.

Run: uv run --no-project --with pytest python -m pytest tests/test_vault_sync_gate.py
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
TOOL = REPO / "scripts" / "vault" / "vault_sync.py"

TOMBSTONE = '{"deleted":true,"folder":false}'
TOMBSTONE_DIR = '{"deleted":true,"folder":true}'
LIVE = '{"deleted":false,"folder":false}'


def load_tool():
    spec = importlib.util.spec_from_file_location("vault_sync_under_test", TOOL)
    mod = importlib.util.module_from_spec(spec)
    # Register before exec: @dataclass resolves its module via sys.modules.
    sys.modules["vault_sync_under_test"] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def vs():
    return load_tool()


# --------------------------------------------------------------------------
# Fixtures that build a real on-disk sync state directory
# --------------------------------------------------------------------------


def rows_for(vs, *, tombstones=0, live=0, tombstone_dirs=0, elsewhere=0, under=None):
    """server_files rows shaped like the real table: (path, data-as-JSON)."""
    folder = under if under is not None else vs.EXCLUDED_FOLDER
    out = []
    for i in range(tombstones):
        out.append((f"{folder}/gone{i}.js", TOMBSTONE))
    for i in range(tombstone_dirs):
        out.append((f"{folder}/d{i}", TOMBSTONE_DIR))
    for i in range(live):
        out.append((f"{folder}/pkg{i}/index.js", LIVE))
    for i in range(elsewhere):
        out.append((f"research/monitorability/runs/r{i}.jsonl", TOMBSTONE))
    return out


DEFAULT_VAULT_PATH = object()  # sentinel: `vault_path=None` must mean "key absent"


def make_sync_root(vs, monkeypatch, tmp_path, rows, *, wal=False, local_rows=(),
                   excluded=(), vault_path=DEFAULT_VAULT_PATH):
    """A SYNC_ROOT the shipped find_state_dir()/copy_state_db() can walk for real.

    `wal=True` leaves the inserts uncheckpointed in state.db-wal by holding the
    writer open, reproducing the state a SIGTERM'd sync leaves behind. Reading
    state.db alone would then see none of them.

    `vault_path` is what config.json declares this sync state describes: the
    sentinel writes the real VAULT, a string writes that string, and None omits
    the key entirely.
    """
    root = tmp_path / "sync"
    state = root / "vault-abc123"
    state.mkdir(parents=True)
    cfg = {vs.EXCLUSION_KEY: list(excluded),
           "allowTypes": ["image", "pdf"], "encryptionKey": "x"}
    if vault_path is DEFAULT_VAULT_PATH:
        cfg["vaultPath"] = str(vs.VAULT)
    elif vault_path is not None:
        cfg["vaultPath"] = vault_path
    (state / "config.json").write_text(json.dumps(cfg))

    db = sqlite3.connect(state / "state.db")
    if wal:
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA wal_autocheckpoint=0")
    db.execute("CREATE TABLE server_files (path TEXT, data TEXT)")
    db.execute("CREATE TABLE local_files (path TEXT, data TEXT)")
    db.executemany("INSERT INTO server_files VALUES (?,?)", rows)
    db.executemany("INSERT INTO local_files VALUES (?,?)", local_rows)
    db.commit()
    if wal:
        assert (state / "state.db-wal").exists(), "test setup: expected an uncheckpointed WAL"
        # Deliberately left open: closing the last connection checkpoints.
    else:
        db.close()

    monkeypatch.setattr(vs, "SYNC_ROOT", root)
    return state


def verify(vs) -> int:
    return vs.cmd_verify(argparse.Namespace())


def filters(vs, **over) -> int:
    args = argparse.Namespace(approved_by="tester", approval_note="test", dry_run=True)
    for k, v in over.items():
        setattr(args, k, v)
    return vs.cmd_filters(args)


def stub_ob(vs, monkeypatch) -> str:
    """Make resolve_ob() answer without obsidian-headless installed.

    Only the tests that get *past* the gate need this: cmd_filters composes the
    `ob sync-config` argv for logging before it checks --dry-run, so resolve_ob()
    is reached on every unlocked path. Left un-stubbed, those tests die on
    "`ob` not found on PATH" from a machine-shaped dependency rather than from
    anything about the gate -- which is exactly how they came to be red on main.

    Deliberately NOT an autouse fixture: test_filters_never_invokes_ob_when_blocked
    proves the stop *precedes* the irreversible call by making resolve_ob() throw,
    and a blanket stub would quietly defeat it.
    """
    path = "/stub/bin/ob"
    monkeypatch.setattr(vs, "resolve_ob", lambda: path)
    return path


# --------------------------------------------------------------------------
# The three historical defects. Each must stop the gate.
# --------------------------------------------------------------------------


def test_p2_one_tombstone_does_not_unlock_while_rows_are_live(vs, monkeypatch, tmp_path):
    """The Critical: a sync that died after one row must not unlock the exclusion.

    This is the state a SIGTERM'd or rate-limited sync leaves behind, and it is
    the most likely state to meet in practice -- which is exactly why a
    `tombstones >= 1` gate is dangerous rather than merely imprecise.
    """
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=1, live=100))
    with pytest.raises(SystemExit):
        verify(vs)
    with pytest.raises(SystemExit):
        filters(vs)


def test_p1_unrelated_deletions_do_not_unlock(vs, monkeypatch, tmp_path):
    """The exact state after `stage --what runs` + sync: 25 tombstones, none here."""
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, elsewhere=25, live=100))
    with pytest.raises(SystemExit):
        verify(vs)
    with pytest.raises(SystemExit):
        filters(vs)


def test_qr6_local_files_tombstones_do_not_unlock(vs, monkeypatch, tmp_path):
    """Deletions recorded locally but never pushed are not evidence of anything."""
    make_sync_root(
        vs,
        monkeypatch,
        tmp_path,
        rows_for(vs, live=100),
        local_rows=[(f"{vs.EXCLUDED_FOLDER}/gone{i}.js", TOMBSTONE) for i in range(500)],
    )
    with pytest.raises(SystemExit):
        verify(vs)


# --------------------------------------------------------------------------
# The prefix must mean this folder and nothing else
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "sibling",
    [
        # `_` is a single-character LIKE wildcard, so a LIKE-based prefix test
        # matches all of these. substr() comparison does not.
        "research/monitorability/slides/slidev/node-modules",
        "research/monitorability/slides/slidev/nodeXmodules",
        # LIKE is ASCII case-insensitive by default; the real matcher is not.
        "research/monitorability/slides/slidev/NODE_MODULES",
        # Plain suffix collision.
        "research/monitorability/slides/slidev/node_modules-old",
    ],
)
def test_sibling_directories_cannot_unlock_the_gate(vs, monkeypatch, tmp_path, sibling):
    assert sibling != vs.EXCLUDED_FOLDER
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=500, under=sibling))
    with pytest.raises(SystemExit):
        verify(vs)


def test_sibling_live_rows_do_not_block_a_clean_target(vs, monkeypatch, tmp_path):
    """The prefix must be exact in both directions, not merely conservative."""
    rows = rows_for(vs, tombstones=20) + rows_for(
        vs, live=50, under="research/monitorability/slides/slidev/node-modules"
    )
    make_sync_root(vs, monkeypatch, tmp_path, rows)
    assert verify(vs) == 0


# --------------------------------------------------------------------------
# The tombstone predicate itself
# --------------------------------------------------------------------------


# Every case here pairs the ambiguous rows with REAL tombstones. Without that
# pairing the folder has zero tombstones, so `exclusion_blocker` stops on its
# "no rows at all" branch and the test passes no matter what the predicate does
# to the ambiguous rows -- which is exactly how the three-valued-logic defect
# below survived a green suite. With a real tombstone present, the live count is
# the only thing that can block, so these tests bind the predicate itself.
AMBIGUOUS = [
    pytest.param('{"deleted":%s,"folder":false}' % v, id=f"deleted={v}")
    for v in ['"0"', '"no"', "{}", "[]", '"false"', "0", "null", "1", '"true"']
] + [
    pytest.param('{"folder":false}', id="key-absent"),
    pytest.param("not valid json at all", id="malformed-json"),
    pytest.param("", id="empty-string"),
    pytest.param(None, id="NULL-blob"),
]


@pytest.mark.parametrize("data", AMBIGUOUS)
def test_ambiguous_rows_block_even_beside_real_tombstones(vs, monkeypatch, tmp_path, data):
    """Anything not unambiguously JSON `true` counts as LIVE, so ambiguity blocks.

    Covers three distinct ways a row used to escape classification:
      * broad truthiness -- `"deleted":"0"` read as deleted;
      * SQL three-valued logic -- an absent key made both IS_TOMBSTONE and
        NOT(IS_TOMBSTONE) evaluate to NULL, so the row matched NEITHER count and
        vanished, leaving `tombstones > 0, live == 0` and an unlocked gate;
      * `{"deleted":1}` / `{"deleted":"true"}` -- indistinguishable from a real
        `true` under json_extract, so classification now uses json_type.
    """
    rows = [(f"{vs.EXCLUDED_FOLDER}/real{i}.js", TOMBSTONE) for i in range(30)]
    rows += [(f"{vs.EXCLUDED_FOLDER}/amb{i}.js", data) for i in range(5)]
    make_sync_root(vs, monkeypatch, tmp_path, rows)
    with pytest.raises(SystemExit):
        verify(vs)


def test_row_accounting_covers_every_row_under_the_target(vs, monkeypatch, tmp_path):
    """tombstones + live must equal the rows examined -- no row falls through.

    The structural backstop. Each gate defect so far was some row not being
    counted where it belonged; the counts still looked plausible, so nothing
    caught it. Asserting the classifier is total catches that class directly.
    """
    rows = [(f"{vs.EXCLUDED_FOLDER}/t{i}.js", TOMBSTONE) for i in range(10)]
    rows += [(f"{vs.EXCLUDED_FOLDER}/l{i}.js", LIVE) for i in range(4)]
    rows += [(f"{vs.EXCLUDED_FOLDER}/weird{i}.js", d)
             for i, d in enumerate(['{"folder":false}', "bad json", None, '{"deleted":1}'])]
    state = make_sync_root(vs, monkeypatch, tmp_path, rows)

    conn = vs.open_ro(state / "state.db")
    counted = vs.count_target_rows(conn)
    examined = vs.scalar(
        conn,
        "SELECT COUNT(*) FROM server_files WHERE %s" % vs.under_target(vs.EXCLUDED_FOLDER)[0],
        vs.under_target(vs.EXCLUDED_FOLDER)[1],
    )
    conn.close()

    assert examined == len(rows)
    assert counted.tombstones + counted.live == examined
    assert counted.tombstones == 10          # only the literal `true` rows
    assert counted.live == len(rows) - 10    # everything else, ambiguity included


@pytest.mark.parametrize("declared", ["/home/yulong/some-other-vault", None])
def test_state_db_for_a_different_vault_is_refused(vs, monkeypatch, tmp_path, declared):
    """One state.db existing does not make it THIS vault's state.db.

    Every gate count comes from this database. A state dir describing another
    vault would report zero live rows under node_modules simply because that
    vault has no such folder -- and zero live rows is what unlocks EX-7.
    """
    rows = [(f"{vs.EXCLUDED_FOLDER}/t{i}.js", TOMBSTONE) for i in range(30)]
    make_sync_root(vs, monkeypatch, tmp_path, rows, vault_path=declared)
    with pytest.raises(SystemExit):
        verify(vs)


def test_null_path_rows_stop_the_tool(vs, monkeypatch, tmp_path):
    """A NULL path matches no prefix test, so it can never be attributed."""
    rows = [(f"{vs.EXCLUDED_FOLDER}/t{i}.js", TOMBSTONE) for i in range(30)]
    rows += [(None, LIVE)]
    make_sync_root(vs, monkeypatch, tmp_path, rows)
    with pytest.raises(SystemExit):
        verify(vs)


# --------------------------------------------------------------------------
# The states that legitimately pass, and the empty one that does not
# --------------------------------------------------------------------------


def test_existing_exclusions_are_re_listed_not_dropped(vs, monkeypatch, tmp_path, capsys):
    """--excluded-folders assigns the whole list, so omitting one un-excludes it.

    `ob sync-config --help`: "Folders to exclude, comma-separated (empty string
    to clear)". Passing only our own folder would silently un-exclude everything
    else already there, and a post-condition that merely asked "is our folder
    present?" would still report success.
    """
    make_sync_root(
        vs, monkeypatch, tmp_path,
        rows_for(vs, tombstones=24041, tombstone_dirs=2943),
        excluded=["some/other/folder", "a/third/one"],
    )
    stub_ob(vs, monkeypatch)
    assert filters(vs) == 0
    printed = capsys.readouterr().out
    sent = [ln for ln in printed.splitlines() if "--excluded-folders" in ln]
    assert sent, "expected the composed ob command to be logged"
    assert "some/other/folder" in sent[0]
    assert "a/third/one" in sent[0]
    assert vs.EXCLUDED_FOLDER in sent[0]


def test_fully_synced_deletions_unlock_the_gate(vs, monkeypatch, tmp_path):
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=24041, tombstone_dirs=2943))
    assert verify(vs) == 0
    stub_ob(vs, monkeypatch)
    assert filters(vs) == 0


def test_empty_target_folder_is_a_stop(vs, monkeypatch, tmp_path):
    """No rows at all means the deletions never landed, or this is the wrong DB."""
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, elsewhere=25))
    with pytest.raises(SystemExit):
        verify(vs)


def test_wal_resident_tombstones_are_counted(vs, monkeypatch, tmp_path):
    """A SIGTERM'd sync never checkpoints; reading state.db alone would miss it."""
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=200), wal=True)
    assert verify(vs) == 0


def test_wal_resident_live_rows_still_block(vs, monkeypatch, tmp_path):
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=200, live=5), wal=True)
    with pytest.raises(SystemExit):
        verify(vs)


# --------------------------------------------------------------------------
# filters must not reach the mutation when the gate says no
# --------------------------------------------------------------------------


def test_filters_never_invokes_ob_when_blocked(vs, monkeypatch, tmp_path):
    """Proves the stop precedes the irreversible call, not merely accompanies it."""
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=1, live=100))

    def explode() -> str:
        raise AssertionError("resolve_ob() reached despite live rows under the target")

    monkeypatch.setattr(vs, "resolve_ob", explode)
    with pytest.raises(SystemExit):
        filters(vs)


def test_filters_refuses_empty_file_types(vs, monkeypatch, tmp_path):
    """EX-7: an empty --file-types silently falls back to a wider default."""
    make_sync_root(vs, monkeypatch, tmp_path, rows_for(vs, tombstones=100))
    monkeypatch.setattr(vs, "FILE_TYPES", "")
    with pytest.raises(SystemExit):
        filters(vs)


def test_config_printing_withholds_secrets(vs, capsys):
    """EX-10: encryption material must never reach a terminal or a log."""
    vs.print_config_safely({"encryptionKey": "SECRET-K", "encryptionSalt": "SECRET-S",
                            vs.EXCLUSION_KEY: ["a"]})
    out = capsys.readouterr().out
    assert "SECRET-K" not in out and "SECRET-S" not in out
    assert "withheld" in out


# --------------------------------------------------------------------------
# EX-9 tripwire: a scan that looked at nothing must not report clean
# --------------------------------------------------------------------------


def test_tripwire_refuses_to_report_clean_on_a_missing_vault(vs, monkeypatch, tmp_path):
    make_sync_root(vs, monkeypatch, tmp_path, [])
    monkeypatch.setattr(vs, "VAULT", tmp_path / "does-not-exist")
    with pytest.raises(SystemExit):
        vs.cmd_tripwire(argparse.Namespace(max_file_mb=vs.DEFAULT_MAX_FILE_MB))


@pytest.mark.skipif(hasattr(__import__("os"), "geteuid") and __import__("os").geteuid() == 0,
                    reason="root ignores directory permissions, so nothing is unreadable")
def test_tripwire_refuses_to_report_clean_when_a_subtree_is_unreadable(vs, monkeypatch, tmp_path):
    """A partial scan is not a clean scan.

    os.walk swallows per-directory errors by default, so an unreadable subtree
    silently contributes nothing and the run reports "Clean. No findings." --
    indistinguishable from a vault that really is clean.
    """
    import os as _os

    make_sync_root(vs, monkeypatch, tmp_path, [])
    vault = tmp_path / "vault"
    locked = vault / "locked"
    locked.mkdir(parents=True)
    (locked / "big.bin").write_bytes(b"x")
    _os.chmod(locked, 0o000)
    monkeypatch.setattr(vs, "VAULT", vault)
    try:
        with pytest.raises(SystemExit):
            vs.cmd_tripwire(argparse.Namespace(max_file_mb=vs.DEFAULT_MAX_FILE_MB))
    finally:
        _os.chmod(locked, 0o700)


def test_tripwire_reports_clean_on_a_genuinely_clean_vault(vs, monkeypatch, tmp_path):
    vault = tmp_path / "vault"
    (vault / "notes").mkdir(parents=True)
    (vault / "notes" / "a.md").write_text("hello")
    # Before make_sync_root: the fixture stamps the *current* VAULT into
    # config.json's vaultPath, which find_state_dir now insists must match.
    monkeypatch.setattr(vs, "VAULT", vault)
    make_sync_root(vs, monkeypatch, tmp_path, [])
    assert vs.cmd_tripwire(argparse.Namespace(max_file_mb=vs.DEFAULT_MAX_FILE_MB)) == 0


# --------------------------------------------------------------------------
# The snapshot the counts are read from must be whole.
# --------------------------------------------------------------------------


def test_a_torn_state_db_snapshot_is_refused(vs, monkeypatch, tmp_path, capsys):
    """A sync writing mid-copy can drop rows, and dropped rows read as absent.

    copy_state_db() copies state.db and its sidecars one file at a time. A
    concurrent writer makes that mixture inconsistent, and a page split caught
    in flight can drop rows from the copy outright. Missing rows are not
    misclassified rows -- count_target_rows()'s accounting invariant balances
    only the rows actually present, so it passes while `live` reads low, and a
    low `live` is what unlocks the irreversible filter change.
    """
    rows = [(f"{vs.EXCLUDED_FOLDER}/t{i}.js", TOMBSTONE) for i in range(30)]
    state = make_sync_root(vs, monkeypatch, tmp_path, rows)
    real_copy2 = vs.shutil.copy2

    def copy2_then_write(src, dst, *a, **kw):
        out = real_copy2(src, dst, *a, **kw)
        db = sqlite3.connect(state / "state.db")
        db.execute("INSERT INTO server_files VALUES (?,?)", ("mid-copy.md", LIVE))
        db.commit()
        db.close()
        return out

    monkeypatch.setattr(vs.shutil, "copy2", copy2_then_write)
    with pytest.raises(SystemExit):
        verify(vs)
    assert "torn" in capsys.readouterr().out.lower()


def test_a_structurally_damaged_snapshot_is_refused(vs, monkeypatch, tmp_path, capsys):
    """Timing that happens to look clean is not proof the pages are intact."""
    rows = [(f"{vs.EXCLUDED_FOLDER}/t{i}.js", TOMBSTONE) for i in range(400)]
    state = make_sync_root(vs, monkeypatch, tmp_path, rows)
    db_file = state / "state.db"
    raw = bytearray(db_file.read_bytes())
    assert len(raw) > 8192, "test setup: need more than one page to corrupt"
    raw[4096:5120] = b"\xde\xad\xbe\xef" * 256  # clobber a b-tree page, not the header
    db_file.write_bytes(raw)

    with pytest.raises(SystemExit):
        verify(vs)
    out = capsys.readouterr().out.lower()
    assert "quick_check" in out or "malformed" in out


# --------------------------------------------------------------------------
# Pre-emptive exclusion: shut the door before the directory exists
#
# Exclusion is not retroactive, so the only safe moment to exclude a
# regenerable directory is while the server still has zero rows under it. The
# tripwire therefore derives candidates from the *manifests* that would create
# them (package.json -> node_modules, pyproject.toml -> .venv, ...) rather than
# waiting for the directory to appear and cost quota. Zero-server-rows is the
# entire safety condition; every test below exists to keep it load-bearing.
# --------------------------------------------------------------------------


def make_vault(vs, monkeypatch, tmp_path, files):
    """A real on-disk vault for predicted_exclusions()/cmd_tripwire() to walk.

    Call before make_sync_root: that fixture stamps the *current* VAULT into
    config.json's vaultPath, which find_state_dir insists must match.
    """
    vault = tmp_path / "vault"
    vault.mkdir(parents=True, exist_ok=True)
    for rel, body in files.items():
        p = vault / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
    monkeypatch.setattr(vs, "VAULT", vault)
    return vault


def tripwire(vs, **over):
    args = argparse.Namespace(max_file_mb=vs.DEFAULT_MAX_FILE_MB,
                              auto_exclude=False, dry_run=False)
    for k, v in over.items():
        setattr(args, k, v)
    return vs.cmd_tripwire(args)


def test_predicted_exclusions_derives_siblings_of_every_manifest(vs, monkeypatch, tmp_path):
    make_vault(vs, monkeypatch, tmp_path, {
        "site/package.json": "{}",
        "tool/pyproject.toml": "",
        "rs/Cargo.toml": "",
        "notes/a.md": "hello",
    })
    found = set(vs.predicted_exclusions([]))
    assert "site/node_modules" in found
    assert "rs/target" in found
    assert {"tool/.venv", "tool/venv", "tool/__pycache__"} <= found
    assert not any(f.startswith("notes/") for f in found), \
        "a directory with no manifest can regenerate nothing"


def test_predicted_exclusions_does_not_re_propose_what_is_already_excluded(vs, monkeypatch,
                                                                          tmp_path):
    """--excluded-folders is whole-list assignment, so a duplicate is not
    harmless noise -- it is a second copy of the same string in the list that
    gets written back to config.json."""
    make_vault(vs, monkeypatch, tmp_path, {"a/package.json": "{}", "b/package.json": "{}"})
    assert vs.predicted_exclusions(["a/node_modules"]) == ["b/node_modules"]


def test_predicted_exclusions_stops_descending_into_an_excluded_parent(vs, monkeypatch, tmp_path):
    """Excluding `a` already covers `a/node_modules`; re-adding the child would
    grow the list forever across nightly runs."""
    make_vault(vs, monkeypatch, tmp_path, {"a/deep/package.json": "{}", "b/package.json": "{}"})
    assert vs.predicted_exclusions(["a"]) == ["b/node_modules"]


def test_predicted_exclusions_ignores_dot_directories(vs, monkeypatch, tmp_path):
    """Obsidian never syncs dot-directories, so a lockfile inside one (a
    .claude worktree, say) can never consume quota and must not be proposed."""
    make_vault(vs, monkeypatch, tmp_path, {".claude/worktrees/x/package.json": "{}"})
    assert vs.predicted_exclusions([]) == []


def test_server_rows_under_does_not_match_a_sibling_prefix(vs, monkeypatch, tmp_path):
    """The safety condition is a row *count*, so a count that over-matches is a
    false stranding alarm and one that under-matches is a real stranding."""
    state = make_sync_root(vs, monkeypatch, tmp_path, [
        ("site/node_modules/a.js", LIVE),
        ("site/node_modules_old/b.js", LIVE),
        ("site/node-modules/c.js", LIVE),
        ("other/node_modules/d.js", LIVE),
    ])
    conn = sqlite3.connect(state / "state.db")
    try:
        assert vs.server_rows_under(conn, "site/node_modules") == 1
        assert vs.server_rows_under(conn, "site/nothing_here") == 0
    finally:
        conn.close()


def test_auto_exclude_refuses_a_path_that_already_has_server_rows(vs, monkeypatch, tmp_path,
                                                                  capsys):
    """The non-retroactive trap. Excluding a folder whose rows are live orphans
    them on the server with no way left to reclaim the quota -- the exact
    failure the whole gate exists to prevent, reached here by a nightly job
    nobody is watching."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path, [("site/node_modules/left-pad/index.js", LIVE)])

    calls = []

    def record(cmd, **kw):
        # A real CompletedProcess, so a regression fails on the explicit
        # assertion below rather than incidentally on a None return value.
        calls.append(cmd)
        return vs.subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(vs, "resolve_ob", lambda: "ob")
    monkeypatch.setattr(vs.subprocess, "run", record)

    assert tripwire(vs, auto_exclude=True) == 2
    assert calls == [], "a path with live server rows must never be excluded"
    assert "ALREADY ON SERVER" in capsys.readouterr().out


def test_auto_exclude_applies_zero_row_paths_and_re_lists_the_existing_ones(vs, monkeypatch,
                                                                           tmp_path):
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    state = make_sync_root(vs, monkeypatch, tmp_path, [("notes/a.md", LIVE)],
                           excluded=["already/there"])

    sent = {}

    def fake_run(cmd, **kw):
        sent["cmd"] = cmd
        folders = cmd[cmd.index("--excluded-folders") + 1].split(",")
        cfg = json.loads((state / "config.json").read_text())
        cfg[vs.EXCLUSION_KEY] = folders
        (state / "config.json").write_text(json.dumps(cfg))
        return vs.subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(vs, "resolve_ob", lambda: "ob")
    monkeypatch.setattr(vs.subprocess, "run", fake_run)

    # Nonzero even on success: the new filter does not take effect until the
    # daemon is restarted, so the run still needs a human to look at it.
    assert tripwire(vs, auto_exclude=True) == 2
    cmd = sent["cmd"]
    assert "--file-types" not in cmd, \
        "EX-7: an unattended job must not rewrite a setting it was not asked to change"
    folders = cmd[cmd.index("--excluded-folders") + 1].split(",")
    assert "already/there" in folders, "omitting an entry silently un-excludes it"
    assert "site/node_modules" in folders


def test_auto_exclude_is_inert_without_the_flag(vs, monkeypatch, tmp_path, capsys):
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path, [])

    def explode():
        raise AssertionError("reporting must never invoke ob")

    monkeypatch.setattr(vs, "resolve_ob", explode)
    assert tripwire(vs) == 2
    assert "--auto-exclude" in capsys.readouterr().out


def test_tripwire_without_the_flag_attribute_still_reports(vs, monkeypatch, tmp_path):
    """cmd_tripwire is also driven with a hand-built Namespace; a missing flag
    must mean report-only, not an AttributeError raised mid-report."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path, [])
    assert vs.cmd_tripwire(argparse.Namespace(max_file_mb=vs.DEFAULT_MAX_FILE_MB)) == 2


def test_predicted_exclusions_finds_a_manifest_under_a_nested_dot_directory(
        vs, monkeypatch, tmp_path):
    """cli.js rejects a dot only in the FIRST path segment (`e.startsWith(".")`
    on the whole vault-relative path). A nested dot-dir is therefore syncable,
    so pruning every dot-dir would blind the walk to a real quota risk."""
    make_vault(vs, monkeypatch, tmp_path, {
        ".claude/worktrees/x/package.json": "{}",   # root dot-dir: unsyncable
        "site/.tmp/pkg/package.json": "{}",         # nested: syncable
    })
    # NB "pkg", not "build"/"dist": those are themselves in REGENERABLE_DIRS
    # and get pruned as already-generated trees, which would make this pass or
    # fail for a reason unrelated to the dot-dir rule under test.
    assert vs.predicted_exclusions([]) == ["site/.tmp/pkg/node_modules"]


def test_tripwire_reports_rows_that_appeared_under_an_already_excluded_path(
        vs, monkeypatch, tmp_path, capsys):
    """The back door: filters are read at client startup, so a tree created
    after an exclusion but before the restart is synced by the still-old
    filter. Every local scan then prunes that path, so the server side is the
    only thing that can still see the rows."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path,
                   [("site/node_modules/left-pad/readme.md", LIVE)],
                   excluded=["site/node_modules"])

    assert tripwire(vs) == 2
    out = capsys.readouterr().out
    assert "EXCLUDED BUT ON SERVER" in out
    assert "site/node_modules" in out


def test_tripwire_does_not_cry_leak_for_a_clean_or_non_regenerable_exclusion(
        vs, monkeypatch, tmp_path, capsys):
    """Scoped to regenerable basenames: a deliberately excluded user folder
    holding rows is a choice, not a leak, and must not raise the alarm that
    means 'quota is being consumed invisibly'."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path, [("Private/journal.md", LIVE)],
                   excluded=["site/node_modules", "Private"])

    assert tripwire(vs) == 0, "no findings: one exclusion is empty, one is deliberate"
    assert "EXCLUDED BUT ON SERVER" not in capsys.readouterr().out


LIVE_DIR = '{"deleted":false,"folder":true}'


def test_leak_alarm_ignores_folder_rows(vs, monkeypatch, tmp_path, capsys):
    """Folder rows hold no bytes. The live vault has 2,927 of them under one
    already-excluded node_modules, so counting them would fire this alarm every
    night over zero quota -- and a nightly false alarm is an unread channel."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path,
                   [("site/node_modules/a/b", LIVE_DIR),
                    ("site/node_modules/a/c", LIVE_DIR)],
                   excluded=["site/node_modules"])
    assert tripwire(vs) == 0
    assert "EXCLUDED BUT ON SERVER" not in capsys.readouterr().out


def test_leak_alarm_fires_on_a_real_file_under_an_excluded_path(
        vs, monkeypatch, tmp_path, capsys):
    """One real file among the folder rows is bytes on the server behind a
    filter that hides them locally -- exactly what nothing else can see."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path,
                   [("site/node_modules/a/b", LIVE_DIR),
                    ("site/node_modules/a/readme.md", LIVE)],
                   excluded=["site/node_modules"])
    assert tripwire(vs) == 2
    assert "EXCLUDED BUT ON SERVER" in capsys.readouterr().out


def test_auto_exclude_gate_still_counts_folder_rows(vs, monkeypatch, tmp_path, capsys):
    """The alarm is lenient, the gate is not: folder rows are still rows the
    server knows about, and excluding over them would freeze that state."""
    make_vault(vs, monkeypatch, tmp_path, {"site/package.json": "{}"})
    make_sync_root(vs, monkeypatch, tmp_path, [("site/node_modules/a", LIVE_DIR)])

    calls = []
    monkeypatch.setattr(vs, "resolve_ob", lambda: "ob")
    monkeypatch.setattr(vs.subprocess, "run",
                        lambda cmd, **kw: (calls.append(cmd),
                                           vs.subprocess.CompletedProcess(cmd, 0))[1])

    assert tripwire(vs, auto_exclude=True) == 2
    assert calls == [], "folder rows must still block a pre-emptive exclusion"
    assert "ALREADY ON SERVER" in capsys.readouterr().out
