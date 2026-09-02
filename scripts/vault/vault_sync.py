#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Vault sync quota remediation tool.

Implements the execution plan in ~/vault/specs/2026-07-27-vault-sync-execution.md.
Subcommands map one-to-one onto the spec's steps:

    gate      EX-2   read-only state.db sanity checks + positive control
    stage     EX-3   compute the deletion set (twin-verified, per file)
              EX-4   move it out of the vault with mv, never rm
    sync      EX-5   bidirectional sync so the deletions reach the server
    verify    EX-6   read tombstones from server_files, split by folder
    filters   EX-7   the single sync-config call that tightens the filters
    tripwire  EX-9   detect regenerable dirs and oversized files

Ordering is load-bearing. Exclusion is non-retroactive: tightening the filters
before the deletions have synced strands the remote copies permanently. `filters`
therefore refuses to run without a recorded approval, and `verify` hard-stops on a
tombstone count of zero.

EX-10: encryptionKey and encryptionSalt must never reach a terminal, a log or a
commit. Config printing is allowlisted by key name -- see SAFE_CONFIG_KEYS.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

VAULT = Path("/home/yulong/vault")
RUNS_DIR = VAULT / "research/monitorability/runs"
OUT_DIR = Path("/home/yulong/projects/nla-vs-cot/out")
SYNC_ROOT = Path.home() / ".config/obsidian-headless/sync"

# Vault-relative, no leading or trailing slash. A trailing slash is a silent
# no-op in the ob matcher, which compares `path == folder or path.startswith(folder + "/")`.
EXCLUDED_FOLDER = "research/monitorability/slides/slidev/node_modules"
NODE_MODULES = VAULT / EXCLUDED_FOLDER

# EX-7: exactly these two flags, and --file-types is never the empty string.
# Passing "" does not clear the setting -- it drops allowTypes and falls back to
# the built-in default of image,audio,pdf,video, which is wider than we want.
FILE_TYPES = "image,pdf"

DEFAULT_HOLDING_ROOT = Path("/home/yulong/scratch")

# This file has exactly one copy. It is untracked in git, absent from out/, and
# over the per-file service cap so it was never on the remote. It must never
# enter the deletion set; the twin check already excludes it, this is the belt.
PROTECTED = {
    VAULT
    / "research/monitorability/runs/2026-07-23_jlens-judge-input-output-review"
    / "report_judge_input_output_jlens_n150x2.html",
}

# EX-10. Anything not named here is withheld, including keys added by future
# versions of the CLI -- the allowlist fails closed.
SAFE_CONFIG_KEYS = frozenset(
    {
        "vaultId",
        "vaultName",
        "vaultPath",
        "deviceName",
        "conflictStrategy",
        "allowTypes",
        "allowSpecialFiles",
        "ignoreFolders",
        "syncConfigs",
        "configDir",
        "syncMode",
        "host",
        "encryptionVersion",
        "version",
    }
)

# The CLI flag is --excluded-folders, but the key persisted to config.json and
# read back by the runtime matcher is `ignoreFolders`:
#     t.ignoreFolders = s.excludedFolders.split(",").map(n => n.trim())
#     _allowSyncFile(e, t) { for (let r of this.ignoreFolders) ... }
# Reading `excludedFolders` back always yields nothing, which would make the
# EX-7 post-condition fail on a successful write and leave the EX-9 tripwire
# permanently blind. Verified against obsidian-headless/cli.js on 2026-07-28.
EXCLUSION_KEY = "ignoreFolders"

# EX-2 baseline, measured 2026-07-27 against the untouched state.db.
BASELINE = {
    "server_rows": 27644,
    "local_rows": 27691,
    "server_with_deleted_key": 27644,
    "local_with_deleted_key": 0,
    "node_modules_rows": 26984,
    "tombstones": 0,
}

# Directories that regenerate from a lockfile or a build step and should never
# occupy sync quota. Checked by the tripwire against the live exclusion list.
REGENERABLE_DIRS = (
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
    ".next",
    ".turbo",
    "dist",
    "build",
    "target",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
)

# Manifest filename -> the sibling directories that manifest can regenerate.
# Drives pre-emptive exclusion: a regenerable directory is only safe to exclude
# BEFORE it exists, because exclusion is not retroactive. Once `bun install` has
# run and the tree has synced, excluding it strands those rows on the server
# with no way to reclaim the quota -- which is exactly how the 271 MB incident
# became unrecoverable. Waiting for the directory to appear is waiting too long.
MANIFEST_REGENERABLE = {
    "package.json": ("node_modules",),
    "bun.lock": ("node_modules",),
    "package-lock.json": ("node_modules",),
    "pnpm-lock.yaml": ("node_modules",),
    "yarn.lock": ("node_modules",),
    "pyproject.toml": (".venv", "venv", "__pycache__"),
    "requirements.txt": (".venv", "venv"),
    "uv.lock": (".venv",),
    "Cargo.toml": ("target",),
}

# The Obsidian Sync per-file cap. Files above it never reach the remote at all,
# so they are a silent-failure class, not a quota class.
DEFAULT_MAX_FILE_MB = 5.00

MB = 1024 * 1024

# `deleted` lives inside the data JSON blob, not in a column. json_type
# distinguishes an absent key from a present-but-false one, which is the whole
# point of check (a): local_files carries no `deleted` key at all, so a counter
# reading that table is structurally always zero (the QR-6 defect).
HAS_DELETED_KEY = "json_type(data, '$.deleted') IS NOT NULL"

# Only a literal JSON `true` counts as deleted.
#
# `json_type` rather than `json_extract`, because json_extract cannot tell the
# two apart: it yields the integer 1 for both `{"deleted":true}` and
# `{"deleted":1}`. json_type yields 'true' for the first and 'integer' for the
# second. Looseness here points the wrong way -- a spurious tombstone is
# precisely what unlocks the irreversible filter change -- so anything that is
# not unambiguously a JSON true is treated as live and blocks.
#
# The predicate must also be TOTAL: exactly 0 or 1 for every row, never NULL and
# never an error. Two ways it previously failed that, both of which made rows
# vanish from BOTH counts and so unlocked the gate:
#
#   * SQL three-valued logic. A row with no `deleted` key made json_extract
#     return NULL, so `... IN (1,'true')` was NULL, and `NOT (NULL)` was also
#     NULL. Neither COUNT matched it. Three rows in, one accounted for -- and
#     `tombstones > 0 and live == 0` then read as "safe to exclude".
#   * A malformed `data` blob made json_extract raise "malformed JSON", which
#     aborted the counting query outright.
#
# CASE guards the extraction behind json_valid (SQLite evaluates only the taken
# branch), and COALESCE collapses a missing key to 0. Verified against literal
# true/1/"true"/false/null/0, a non-JSON blob, and a NULL blob.
IS_TOMBSTONE = (
    "COALESCE(CASE WHEN json_valid(data) "
    "THEN json_type(data, '$.deleted') = 'true' END, 0)"
)

# Deliberately the complement of IS_TOMBSTONE, not a positive test for
# `deleted:false`. A row we cannot confidently call deleted must count as LIVE,
# because live rows are what block the exclusion -- ambiguity has to fail closed.
# Total because IS_TOMBSTONE is total, so tombstones + live == rows examined;
# count_target_rows() asserts exactly that.
IS_LIVE = f"NOT ({IS_TOMBSTONE})"

IS_FOLDER = "COALESCE(CASE WHEN json_valid(data) THEN json_type(data, '$.folder') = 'true' END, 0)"


def under_target(folder: str) -> tuple[str, tuple]:
    """SQL fragment + params matching `folder` itself and everything beneath it.

    Deliberately NOT `path LIKE folder || '/%'`. SQLite's LIKE treats `_` as a
    single-character wildcard and is ASCII case-insensitive by default, and
    EXCLUDED_FOLDER contains an underscore -- so a pattern meant for
    `node_modules/` also matches `node-modules/x.js`, `nodeXmodules/x.js` and
    `NODE_MODULES/x.js`. A tombstone under any of those unrelated directories
    would satisfy a gate about this one. substr() comparison has no
    metacharacters and is case-sensitive, so there is nothing to escape and no
    way for a sibling directory to sneak through.
    """
    child = folder + "/"
    return "(path = ? OR substr(path, 1, ?) = ?)", (folder, len(child), child)


def path_is_excluded(rel: str, excluded: Sequence[str]) -> bool:
    """Whether a vault-relative path is hidden by an ignoreFolders entry.

    The local-filesystem twin of under_target() above, and it must stay one:
    both encode the same ob matcher, so a divergence between them would let the
    server-row gate and the local walk disagree about what a given exclusion
    covers. cli.js does `e === r || e.startsWith(r + "/")` -- vault-relative,
    segment-safe, case-sensitive, and with no wildcard support whatsoever.
    """
    return any(rel == f or rel.startswith(f + "/") for f in excluded)


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")


def log(msg: str = "") -> None:
    print(msg, flush=True)


def rule(title: str) -> None:
    log()
    log(f"== {title} " + "=" * max(0, 66 - len(title)))


def fmt_mb(n_bytes: int) -> str:
    return f"{n_bytes / MB:.2f} MB"


def die(msg: str, clean: bool = True) -> None:
    """Abort. `clean=False` when a mutating call may already have landed.

    The reassurance must be a parameter, never a constant: a post-condition
    check runs *after* its mutation, so hardcoding "nothing changed" there
    tells the operator the opposite of the truth at the one moment it matters.
    """
    log()
    log(f"ABORT: {msg}")
    if clean:
        log("No filesystem change was made by this step.")
    else:
        log("WARNING: a mutating call already ran -- do NOT assume this step "
            "was a no-op. Inspect the live state before retrying.")
    raise SystemExit(1)


def resolve_ob() -> str:
    """Absolute path to the `ob` CLI, or abort with a legible message.

    `ob` is a bun global shim (`~/.bun/bin/ob` -> obsidian-headless/cli.js), and
    ~/.bun/bin is absent from the minimal PATH that systemd user units and cron
    inherit -- the same gap that left the EX-9 tripwire dead at exit 127. Bare
    `subprocess.run(["ob", ...])` would raise a raw FileNotFoundError traceback,
    and in `sync` that lands *after* the EX-4 move, leaving the vault staged but
    unsynced with no explanation of why. Resolve up front and say so plainly.
    """
    found = shutil.which("ob")
    if found:
        return found
    fallback = Path.home() / ".bun" / "bin" / "ob"
    if fallback.exists():
        return str(fallback)
    die(
        f"`ob` not found on PATH ({os.environ.get('PATH', '')!r}) and not at "
        f"{fallback}. Install obsidian-headless, or run from a shell whose PATH "
        "includes ~/.bun/bin."
    )
    raise AssertionError("unreachable")  # die() never returns; keeps type checkers happy


# --------------------------------------------------------------------------
# sync state discovery
# --------------------------------------------------------------------------


def find_state_dir() -> Path:
    if not SYNC_ROOT.is_dir():
        die(f"sync state root not found: {SYNC_ROOT}")
    candidates = [d for d in sorted(SYNC_ROOT.iterdir()) if (d / "state.db").is_file()]
    if not candidates:
        die(f"no vault state directory with a state.db under {SYNC_ROOT}")
    if len(candidates) > 1:
        die(
            "multiple vault state directories found, refusing to guess: "
            + ", ".join(d.name for d in candidates)
        )
    state_dir = candidates[0]

    # "Exactly one state.db exists" does NOT mean "that state.db is this vault's".
    # Every count the EX-6 gate turns on comes from this database, so if it ever
    # describes a different vault the gate would be answering a question about
    # somewhere else -- reporting zero live rows under node_modules simply because
    # that vault has no such folder, and unlocking the irreversible filter change.
    # config.json records vaultPath; require it to be the vault we operate on.
    declared = (read_config(state_dir) or {}).get("vaultPath")
    if not declared:
        die(f"{state_dir/'config.json'} declares no vaultPath, so it cannot be "
            f"confirmed to describe {VAULT}")
    if Path(declared).expanduser().resolve() != VAULT.resolve():
        die(f"sync state at {state_dir} describes {declared}, not {VAULT} -- "
            "refusing to read counts for a different vault")
    return state_dir


def read_config(state_dir: Path) -> dict:
    path = state_dir / "config.json"
    if not path.is_file():
        die(f"config.json not found at {path}")
    return json.loads(path.read_text())


def print_config_safely(cfg: dict) -> None:
    """EX-10: allowlist by key name, never dump the object."""
    shown = 0
    for key in sorted(cfg):
        if key in SAFE_CONFIG_KEYS:
            log(f"    {key}: {cfg[key]!r}")
            shown += 1
    withheld = len(cfg) - shown
    if withheld:
        log(f"    ({withheld} further key(s) withheld -- may contain secret material)")


STATE_DB_FILES = ("state.db", "state.db-wal", "state.db-shm")


def state_db_fingerprint(state_dir: Path) -> dict[str, tuple[int, int]]:
    """(size, mtime_ns) for each state.db file that exists, for tear detection."""
    marks: dict[str, tuple[int, int]] = {}
    for name in STATE_DB_FILES:
        try:
            st = (state_dir / name).stat()
        except FileNotFoundError:
            continue
        marks[name] = (st.st_size, st.st_mtime_ns)
    return marks


def copy_state_db(state_dir: Path, dest_dir: Path) -> Path:
    """Copy state.db plus any -wal/-shm sidecars, refusing a torn snapshot.

    A sync killed by SIGTERM never checkpoints, so fresh tombstones sit in the
    WAL rather than the main database file. Reading state.db alone would miss
    them entirely. The sidecars are frequently absent on a cleanly checkpointed
    database -- that is the normal case, not an error.

    Copying three files one at a time is not atomic. If a sync writes to the
    database while we are partway through, the copy mixes pages from two
    different states, and a b-tree page split caught mid-flight can drop rows
    from the copy outright. Rows that vanish are not misclassified rows: the
    accounting invariant in count_target_rows() balances only the rows actually
    present, so it passes, and `live` reads low for no reason the counts reveal.
    Zero live rows is exactly what unlocks the irreversible EX-7 filter change,
    which makes a torn snapshot a member of the same class as the four gate
    defects already fixed -- so it gets the same treatment: refuse to proceed.

    The check is a before/after fingerprint. Any concurrent write bumps
    st_mtime_ns, and a checkpoint that removes -wal changes the file set, so a
    mismatch means "something moved under us" without needing to identify what
    was writing. quick_check then rejects a copy that is structurally torn even
    if the timing happened to look clean.
    """
    src = state_dir / "state.db"
    dest = dest_dir / "state.db"
    before = state_db_fingerprint(state_dir)
    shutil.copy2(src, dest)
    for suffix in ("-wal", "-shm"):
        sidecar = state_dir / f"state.db{suffix}"
        if sidecar.exists():
            shutil.copy2(sidecar, dest_dir / f"state.db{suffix}")
            log(f"    copied sidecar state.db{suffix} ({fmt_mb(sidecar.stat().st_size)})")
    after = state_db_fingerprint(state_dir)
    if before != after:
        changed = sorted(set(before) ^ set(after)) or sorted(
            name for name in before if before[name] != after[name]
        )
        die(f"sync state changed while being copied ({', '.join(changed)}) -- the "
            "snapshot may be torn and undercount live rows. Stop any running sync "
            "and re-run this command")

    try:
        with contextlib.closing(open_ro(dest)) as conn:
            verdict = conn.execute("PRAGMA quick_check").fetchone()[0]
    except sqlite3.DatabaseError as exc:
        # Damage bad enough to be rejected at open time raises instead of
        # reporting a verdict. Folding it into `verdict` rather than dying here
        # keeps this to a single guard: two death branches, only one of which a
        # test can actually reach, would leave the other free to rot or be
        # deleted with nothing failing.
        verdict = f"unreadable -- {exc}"
    if verdict != "ok":
        die(f"copied sync state fails PRAGMA quick_check ({verdict!r}) -- refusing "
            "to read counts from a damaged snapshot")
    return dest


def open_ro(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def scalar(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> int:
    return int(conn.execute(sql, params).fetchone()[0])


@dataclass(frozen=True)
class TargetRows:
    """server_files rows under the folder EX-7 is about to exclude."""

    tombstones: int
    tombstone_folders: int
    live: int

    @property
    def total(self) -> int:
        return self.tombstones + self.live


def count_target_rows(conn: sqlite3.Connection, folder: str = EXCLUDED_FOLDER) -> TargetRows:
    """The three numbers the EX-6 gate turns on, read from one connection.

    Both enforcement points (`verify` and `filters`) call this rather than
    each spelling out their own query -- when the same predicate was written
    twice, the two copies were free to drift, and a reviewer had to check both
    to know what the gate actually did.
    """
    # A NULL path is invisible to any prefix test -- `path = ?` and
    # `substr(path, ...)` are both NULL for it, so it can never appear under the
    # target no matter what it really is. There is no way to classify such a row,
    # so refuse to reason about the database at all rather than report counts
    # that silently omit it.
    orphans = scalar(conn, "SELECT COUNT(*) FROM server_files WHERE path IS NULL")
    if orphans:
        die(f"{orphans:,} rows in server_files have a NULL path -- they cannot be "
            "attributed to any folder, so the counts below would be incomplete")

    where, params = under_target(folder)
    q = f"SELECT COUNT(*) FROM server_files WHERE {{}} AND {where}"
    rows = TargetRows(
        tombstones=scalar(conn, q.format(IS_TOMBSTONE), params),
        tombstone_folders=scalar(conn, q.format(f"{IS_TOMBSTONE} AND {IS_FOLDER}"), params),
        live=scalar(conn, q.format(IS_LIVE), params),
    )

    # Structural backstop, not a redundant assertion. Every defect this gate has
    # had was some row failing to be counted where it should have been -- wrong
    # table, wrong prefix, wrong threshold, and then a predicate that returned
    # NULL so rows fell out of both buckets at once. Each was invisible because
    # the counts still looked plausible. Tombstones and live are complements by
    # construction, so they MUST sum to the number of rows examined; if a future
    # edit breaks that, this stops the tool instead of quietly unlocking it.
    examined = scalar(conn, f"SELECT COUNT(*) FROM server_files WHERE {where}", params)
    if rows.tombstones + rows.live != examined:
        die(f"row accounting failed under {folder}: {rows.tombstones:,} tombstoned + "
            f"{rows.live:,} live != {examined:,} examined. The classifier is leaking "
            "rows; refusing to act on these counts")
    return rows


def exclusion_blocker(rows: TargetRows, folder: str = EXCLUDED_FOLDER) -> str | None:
    """Why EX-7 must not run, or None if it is safe to tighten the exclusion.

    The invariant is about what is STILL ON THE SERVER, not about what has gone.
    Counting tombstones alone is fail-open, and that is how this gate was wrong
    for the third time: a sync that tombstoned a single row before dying leaves
    26,983 rows live, yet a `tombstones >= 1` test unlocks the non-retroactive
    exclusion that strands every one of them. Zero live rows is the only
    condition that makes the irreversible step safe.

    The tombstone count is still required, separately: a target folder with no
    rows of any kind means the deletions never reached the server, or that this
    is the wrong state.db -- either way there is nothing here to have confirmed.
    """
    if rows.live:
        return (
            f"{rows.live:,} rows under {folder} are still live on the server "
            f"({rows.tombstones:,} tombstoned). Exclusion is not retroactive, so "
            "tightening the filters now would strand those rows permanently."
        )
    if not rows.tombstones:
        return (
            f"no rows at all under {folder} -- neither live nor tombstoned. "
            "The deletions never reached the server, or this is the wrong state.db."
        )
    return None


# --------------------------------------------------------------------------
# EX-2: gate
# --------------------------------------------------------------------------


def cmd_gate(args: argparse.Namespace) -> int:
    state_dir = find_state_dir()
    rule("EX-2  read-only gate")
    log(f"  state dir: {state_dir}")

    with tempfile.TemporaryDirectory(prefix="vault-sync-gate-") as tmp:
        db = copy_state_db(state_dir, Path(tmp))
        conn = open_ro(db)

        server_rows = scalar(conn, "SELECT COUNT(*) FROM server_files")
        local_rows = scalar(conn, "SELECT COUNT(*) FROM local_files")

        # (a) local_files carries no `deleted` key -- the defective oracle.
        a = scalar(conn, f"SELECT COUNT(*) FROM local_files WHERE {HAS_DELETED_KEY}")
        # (b) server_files carries it on every row -- the correct oracle.
        b = scalar(conn, f"SELECT COUNT(*) FROM server_files WHERE {HAS_DELETED_KEY}")
        # (c) positive control: same machinery, predicate inverted, scoped to the
        #     node_modules prefix. If this returns 0 the JSON extraction is broken
        #     and check (d)'s zero would be meaningless.
        # under_target(), not `path LIKE folder || '/%'`: the same LIKE that had
        # to be removed from the gate was still here. A positive control that
        # over-matches is worse than useless -- it is meant to prove the JSON
        # extraction works, so counting rows from `node-modules/` or
        # `NODE_MODULES/` could report a healthy non-zero while the real prefix
        # holds nothing.
        nm_where, nm_params = under_target(EXCLUDED_FOLDER)
        c = scalar(
            conn,
            f"SELECT COUNT(*) FROM server_files WHERE {nm_where} AND {IS_LIVE}",
            nm_params,
        )
        # (d) the counter itself.
        d = scalar(conn, f"SELECT COUNT(*) FROM server_files WHERE {IS_TOMBSTONE}")
        conn.close()

    log()
    log(f"  server_files rows                          : {server_rows:>8,}")
    log(f"  local_files  rows                          : {local_rows:>8,}")
    log(f"  (a) local_files  rows with `deleted` key   : {a:>8,}   expect 0")
    log(f"  (b) server_files rows with `deleted` key   : {b:>8,}   expect == server rows")
    log(f"  (c) positive control, node_modules prefix  : {c:>8,}   expect > 0")
    log(f"  (d) tombstones vault-wide                  : {d:>8,}   expect 0 pre-deletion")

    failures: list[str] = []
    if a != 0:
        failures.append(f"(a) expected 0, got {a} -- local_files unexpectedly carries `deleted`")
    if b != server_rows:
        failures.append(f"(b) expected {server_rows}, got {b} -- not every server row carries the key")
    if c == 0:
        failures.append("(c) positive control returned 0 -- the JSON predicate is broken (EC-2)")
    if d != 0:
        failures.append(f"(d) expected 0 tombstones pre-deletion, got {d}")

    if failures:
        log()
        for f in failures:
            log(f"  FAIL {f}")
        die("structural gate failed")

    drift = []
    for label, got, want in (
        ("server_files rows", server_rows, BASELINE["server_rows"]),
        ("local_files rows", local_rows, BASELINE["local_rows"]),
        ("node_modules prefix rows", c, BASELINE["node_modules_rows"]),
    ):
        if got != want:
            drift.append(f"{label}: baseline {want:,}, now {got:,} (delta {got - want:+,})")

    if drift:
        log()
        log("  Counts have drifted from the 2026-07-27 baseline:")
        for line in drift:
            log(f"    - {line}")
        if not args.allow_drift:
            die("count drift from baseline; re-read the spec's measured state, then --allow-drift")
        log("  --allow-drift set, continuing.")

    log()
    log("  GATE PASSED. The counter reads 0 against a working query.")
    return 0


# --------------------------------------------------------------------------
# EX-3 / EX-4: stage
# --------------------------------------------------------------------------


@dataclass
class Candidate:
    path: Path
    size: int
    twin: Path | None = None
    reason: str = ""


@dataclass
class StagePlan:
    eligible: list[Candidate] = field(default_factory=list)
    ineligible: list[Candidate] = field(default_factory=list)

    @property
    def eligible_bytes(self) -> int:
        return sum(c.size for c in self.eligible)

    @property
    def ineligible_bytes(self) -> int:
        return sum(c.size for c in self.ineligible)


def file_digest(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while block := fh.read(chunk):
            h.update(block)
    return h.hexdigest()


def identical(a: Path, b: Path) -> bool:
    """Byte-identical, confirmed at run time by content.

    Name and size are screens, not evidence -- size equality is checked first
    only because it is free and rejects most non-twins without hashing.
    """
    if a.stat().st_size != b.stat().st_size:
        return False
    return file_digest(a) == file_digest(b)


def compute_runs_plan() -> StagePlan:
    """EX-3: every file under runs/, classified by whether a twin exists now.

    The 144.61 MB / 25-file figure from the prior session is context. It is never
    an input -- the set is recomputed live, per file, on every run.
    """
    plan = StagePlan()
    if not RUNS_DIR.is_dir():
        die(f"runs directory not found: {RUNS_DIR}")
    if not OUT_DIR.is_dir():
        die(f"twin source not found: {OUT_DIR}")

    for path in sorted(RUNS_DIR.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        size = path.stat().st_size
        if path in PROTECTED:
            plan.ineligible.append(Candidate(path, size, reason="protected: single known copy"))
            continue
        twin = OUT_DIR / path.relative_to(RUNS_DIR)
        if not twin.is_file():
            plan.ineligible.append(Candidate(path, size, reason="no twin in out/"))
            continue
        # A symlinked or hardlinked "twin" is not an independent second copy.
        # A symlink pointing back into the vault would compare byte-identical
        # against itself, and moving the target would leave a dangling link and
        # no surviving copy at all. Reject both; Decision 2's "two copies on the
        # same disk" premise requires two real ones.
        if twin.is_symlink():
            plan.ineligible.append(
                Candidate(path, size, twin, "twin is a symlink, not an independent copy")
            )
            continue
        if path.samefile(twin):
            plan.ineligible.append(
                Candidate(path, size, twin, "twin is the same inode (hardlink), not a second copy")
            )
            continue
        if not identical(path, twin):
            plan.ineligible.append(Candidate(path, size, twin, "twin differs in content"))
            continue
        plan.eligible.append(Candidate(path, size, twin, "byte-identical twin confirmed"))

    return plan


def fsync_dir(d: Path) -> None:
    """Persist a directory's own entries, not just the data of files within it.

    fsync on a file descriptor persists that file's contents; it says nothing
    about whether the *name* linking it into its parent has reached the disk.
    So a journal that fsyncs every append can still be entirely absent after a
    power loss, because the create was never durable -- which defeats the point
    of journalling at all. Best-effort: some filesystems refuse O_RDONLY fsync
    on a directory, and failing the whole stage over that would be worse than
    the weaker guarantee.
    """
    try:
        fd = os.open(str(d), os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def move_out(path: Path, holding: Path, base: Path) -> Path:
    """EX-4: mv, never rm. Structure is preserved so the move is reversible."""
    dest = holding / path.relative_to(base)
    dest.parent.mkdir(parents=True, exist_ok=True)
    # shutil.move onto an existing file silently renames over it on POSIX, and
    # onto an existing directory moves the source *inside* it -- either way the
    # manifest would then record a destination that does not describe reality.
    if dest.exists() or dest.is_symlink():
        die(f"refusing to move onto an existing path: {dest}")
    shutil.move(str(path), str(dest))
    # Within one filesystem this is a rename and only the two directory entries
    # need persisting. Across filesystems -- which `--holding` makes easy to ask
    # for -- shutil.move degrades to copy-then-unlink, so the copy's data has to
    # be on disk before the journal records the move as done; otherwise a power
    # loss leaves a "done" entry pointing at a file that lost its contents while
    # the original has already been unlinked.
    if dest.is_file() and not dest.is_symlink():
        try:
            fd = os.open(str(dest), os.O_RDONLY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        except OSError:
            pass
    fsync_dir(dest.parent)
    return dest


def cmd_stage(args: argparse.Namespace) -> int:
    rule("EX-3  deletion set, computed live")

    do_runs = args.what in ("runs", "both")
    do_nm = args.what in ("node-modules", "both")
    # Only hash when the runs/ scope is actually selected -- otherwise
    # `--what node-modules` pays ~126 MB of hashing on both sides for nothing,
    # and dies if OUT_DIR happens to be absent.
    plan = compute_runs_plan() if do_runs else StagePlan()

    if do_runs:
        log(f"  runs/ scanned under {RUNS_DIR}")
        log(f"  eligible   : {len(plan.eligible):>4} files  {fmt_mb(plan.eligible_bytes):>12}")
        log(f"  ineligible : {len(plan.ineligible):>4} files  {fmt_mb(plan.ineligible_bytes):>12}")

        if plan.eligible:
            log()
            log("  Eligible (byte-identical twin confirmed in out/):")
            for c in sorted(plan.eligible, key=lambda x: -x.size):
                log(f"    {fmt_mb(c.size):>10}  {c.path.relative_to(VAULT)}")

        # The residual the dropped 02b step would have handled. Surfaced in full
        # for the EX-11 review -- these are the files that stay in the vault.
        log()
        log("  Ineligible (stays in the vault):")
        for c in sorted(plan.ineligible, key=lambda x: -x.size):
            log(f"    {fmt_mb(c.size):>10}  {c.path.relative_to(VAULT)}")
            log(f"                {c.reason}")

    nm_bytes = 0
    if do_nm:
        if NODE_MODULES.is_dir():
            nm_bytes = sum(
                p.stat().st_size for p in NODE_MODULES.rglob("*") if p.is_file() and not p.is_symlink()
            )
            log()
            log(f"  node_modules: {EXCLUDED_FOLDER}")
            log(f"    {fmt_mb(nm_bytes)} on disk, regenerable from the lockfile")
        else:
            log()
            log(f"  node_modules already absent at {NODE_MODULES}")
            do_nm = False

    total = (plan.eligible_bytes if do_runs else 0) + nm_bytes
    log()
    log(f"  TOTAL TO MOVE: {fmt_mb(total)}")

    if not args.execute:
        log()
        log("  Dry run. Re-run with --execute to move (mv, not rm).")
        return 0

    rule("EX-4  move out of the vault")
    holding = Path(args.holding) if args.holding else DEFAULT_HOLDING_ROOT / f"vault-sync-holding-{utc_stamp()}"
    holding = holding.resolve()

    # EX-4 says "outside the vault". A holding dir inside it would satisfy "the
    # files moved" while defeating the entire point: nothing leaves the sync
    # scope, the sync emits no deletions, and verify hard-stops on zero.
    if holding == VAULT or VAULT in holding.parents:
        die(f"holding directory must be outside the vault, got {holding}")
    # Requiring a fresh directory closes the whole destination-collision class
    # in one line, rather than defending each move site separately.
    if holding.exists() and any(holding.iterdir()):
        die(f"holding directory already exists and is not empty: {holding}")
    holding.mkdir(parents=True, exist_ok=True)
    log(f"  holding: {holding}")

    manifest: list[dict] = []
    moved_bytes = 0

    # Append-as-we-go, so a crash mid-move (ENOSPC, SIGINT) still leaves a
    # record of every file already moved. manifest.json at the end is the
    # summary, not the only copy.
    journal_path = holding / "manifest.jsonl"

    journal_created = journal_path.exists()

    def journal(entry: dict) -> None:
        # fsync: the record has to survive a power loss between this write and
        # the move, not merely a Python-level crash.
        nonlocal journal_created
        with journal_path.open("a") as fh:
            fh.write(json.dumps(entry) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        if not journal_created:
            # The first append also created the file. fsync above persisted its
            # contents but not the directory entry naming it, so without this
            # the whole journal can vanish in a power loss -- the one failure
            # the journal exists to survive.
            fsync_dir(holding)
            journal_created = True

    def do_move(entry: dict, move) -> None:
        """Journal intent, move, journal completion.

        The ordering is load-bearing. Recording *after* the move means an ENOSPC
        on the journal write, or a SIGINT landing between the two statements,
        leaves the file already outside the vault with nothing naming where it
        went -- which is precisely the crash-recovery guarantee this journal
        exists to provide. Intent-first can only ever over-record: an intent
        with no matching "done" means "look for this one in the holding dir",
        which is recoverable. The reverse is not.
        """
        journal({**entry, "state": "intent"})
        dest = move()
        done = {**entry, "to": str(dest), "state": "done"}
        journal(done)
        manifest.append(done)

    if do_runs:
        for c in plan.eligible:
            do_move(
                {
                    "kind": "runs-duplicate",
                    "from": str(c.path),
                    "twin": str(c.twin),
                    "size": c.size,
                },
                # Bind c per-iteration; a bare closure would capture the loop
                # variable and move the last candidate every time.
                lambda c=c: move_out(c.path, holding / "runs", RUNS_DIR),
            )
            moved_bytes += c.size
        log(f"  moved {len(plan.eligible)} run files")

    if do_nm:
        dest = holding / "node_modules"
        if dest.exists() or dest.is_symlink():
            die(f"refusing to move onto an existing path: {dest}")
        def move_nm() -> Path:
            shutil.move(str(NODE_MODULES), str(dest))
            return dest

        do_move({"kind": "node-modules", "from": str(NODE_MODULES), "size": nm_bytes}, move_nm)
        moved_bytes += nm_bytes
        log(f"  moved node_modules ({fmt_mb(nm_bytes)})")

    manifest_path = holding / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {"created": utc_stamp(), "vault": str(VAULT), "moved_bytes": moved_bytes, "entries": manifest},
            indent=2,
        )
    )
    log()
    log(f"  {fmt_mb(moved_bytes)} moved. Manifest: {manifest_path}")
    log("  Reversible until the sync runs. Next: `sync`.")
    return 0


# --------------------------------------------------------------------------
# EX-5: sync
# --------------------------------------------------------------------------


def cmd_sync(args: argparse.Namespace) -> int:
    state_dir = find_state_dir()
    cfg = read_config(state_dir)

    rule("EX-5  bidirectional sync")

    # The deletions must propagate. A pull-only or mirror-remote mode would pull
    # the files straight back instead. Absence of the key is the bidirectional
    # default -- the tool asserts absence rather than setting a mode, because
    # setting one would persist it into config.json.
    mode = cfg.get("syncMode")
    if mode is None:
        log("  syncMode key absent -> bidirectional default. Not setting a mode.")
    elif mode == "bidirectional":
        log("  syncMode is explicitly 'bidirectional'. Not changing it.")
    else:
        die(f"syncMode is {mode!r}; deletions would not propagate. Fix before syncing.")

    cmd = [resolve_ob(), "sync", "--path", str(VAULT)]
    log(f"  $ {' '.join(cmd)}")
    if args.dry_run:
        log("  Dry run, not executing.")
        return 0

    # Deliberately no timeout. SIGTERM never checkpoints the WAL, which strands
    # fresh tombstones outside state.db and makes EX-6 read a stale zero.
    log()
    proc = subprocess.run(cmd, cwd=str(VAULT))
    log()
    if proc.returncode != 0:
        # Not clean: a sync that fails partway (quota, network) may already have
        # uploaded or deleted entries and updated state.db. Claiming "no change"
        # here would be a lie at the exact moment the operator needs the truth.
        die(
            f"ob sync exited {proc.returncode}. It may have applied some deletions "
            "before failing -- re-run `verify` to read the actual tombstone state "
            "before retrying.",
            clean=False,
        )
    log("  Sync completed. Next: `verify`.")
    return 0


# --------------------------------------------------------------------------
# EX-6: verify
# --------------------------------------------------------------------------


def cmd_verify(args: argparse.Namespace) -> int:
    state_dir = find_state_dir()
    rule("EX-6  tombstone read")

    with tempfile.TemporaryDirectory(prefix="vault-sync-verify-") as tmp:
        db = copy_state_db(state_dir, Path(tmp))
        conn = open_ro(db)
        total = scalar(conn, f"SELECT COUNT(*) FROM server_files WHERE {IS_TOMBSTONE}")
        folders = scalar(
            conn, f"SELECT COUNT(*) FROM server_files WHERE {IS_TOMBSTONE} AND {IS_FOLDER}"
        )
        # EX-6 quotes 24,041 files + 2,943 folders *under the prefix*. Report
        # that split too: the runs/ deletions shift the vault-wide totals, so
        # without this the operator sees neither expected number and may abort
        # a run that is in fact correct.
        rows = count_target_rows(conn)
        conn.close()

    files = total - folders
    log()
    log(f"  tombstones, file rows   : {files:>8,}")
    log(f"  tombstones, folder rows : {folders:>8,}")
    log(f"  tombstones, total       : {total:>8,}")
    log()
    log(f"  under {EXCLUDED_FOLDER}:")
    log(f"    tombstoned files   : {rows.tombstones - rows.tombstone_folders:>8,}"
        "   (EX-6 expects ~24,041)")
    log(f"    tombstoned folders : {rows.tombstone_folders:>8,}   (EX-6 expects ~2,943)")
    log(f"    tombstoned total   : {rows.tombstones:>8,}")
    log(f"    STILL LIVE         : {rows.live:>8,}   (must be 0 before EX-7)")
    log(f"  tombstones elsewhere in the vault : {total - rows.tombstones:>8,}")

    # The gate is about what remains on the server under the folder EX-7 will
    # exclude, not about how much has gone. Counting tombstones alone is
    # fail-open in both the scope and the threshold: `stage --what runs`
    # tombstones 25 runs/ files, and a sync that died after one node_modules row
    # leaves a tombstone under the prefix -- either would satisfy a "nonzero"
    # test while ~285 MB of remote node_modules is still live and about to be
    # stranded by a non-retroactive exclusion. Same defect class as QR-6 (right
    # table, wrong scope) and P1 (right table, wrong prefix): P2 is right prefix,
    # wrong threshold.
    blocker = exclusion_blocker(rows)
    if blocker:
        log()
        log(f"  {blocker}")
        if total and not rows.tombstones:
            log(f"  ({total:,} tombstones exist elsewhere in the vault -- most likely the")
            log("   runs/ deletions. They do NOT license the exclusion.)")
        die(f"EX-6 hard stop: {blocker} -- no filter change made")

    log()
    log(f"  {rows.tombstones:,} tombstones under {EXCLUDED_FOLDER}, and zero live rows.")
    log("  Every node_modules deletion reached the server.")
    log()
    log("  STOP. EX-11 requires Yulong's explicit approval of this split")
    log("  before `filters` may run. Pass it through:")
    log("      vault_sync.py filters --approved-by <name> --approval-note '<what was approved>'")
    return 0


# --------------------------------------------------------------------------
# EX-7: filters
# --------------------------------------------------------------------------


def cmd_filters(args: argparse.Namespace) -> int:
    state_dir = find_state_dir()
    cfg = read_config(state_dir)

    rule("EX-7  filter tightening")
    log("  Config before (non-secret keys only):")
    print_config_safely(cfg)

    if not FILE_TYPES:
        die("refusing to pass an empty --file-types; it falls back to a wider default")

    # EX-6's hard stop belongs to the tool, not to operator discipline. Gating
    # only on --approved-by would let `filters` run without `verify` ever having
    # been executed, tightening the exclusion while the deletions are still only
    # local -- which strands the remote copies permanently, with no undo.
    # Re-read the count here so the EX-6 -> EX-7 ordering is a code invariant.
    with tempfile.TemporaryDirectory(prefix="vault-sync-filters-") as tmp:
        conn = open_ro(copy_state_db(state_dir, Path(tmp)))
        # Same helper as cmd_verify, so the two enforcement points cannot drift
        # apart. The condition is zero LIVE rows under the excluded folder --
        # not "some tombstones exist", which any unrelated deletion or any
        # partially-completed sync would satisfy while the rows EX-7 is about to
        # orphan are still on the server.
        rows = count_target_rows(conn)
        total = scalar(conn, f"SELECT COUNT(*) FROM server_files WHERE {IS_TOMBSTONE}")
        conn.close()
    log()
    log(f"  EX-6 re-check, under {EXCLUDED_FOLDER}:")
    log(f"    tombstoned : {rows.tombstones:,}")
    log(f"    still live : {rows.live:,}")
    log(f"  (vault-wide tombstones, for context only: {total:,})")
    blocker = exclusion_blocker(rows)
    if blocker:
        log("  Exclusion is not retroactive: tightening now would strand the")
        log("  remote copies with no way to reclaim the quota they hold.")
        die(f"EX-6 hard stop: {blocker} -- refusing to tighten filters")

    log()
    log(f"  approved by : {args.approved_by}")
    log(f"  note        : {args.approval_note}")

    # --excluded-folders is whole-list ASSIGNMENT, not "add one": `ob sync-config
    # --help` documents it as "Folders to exclude, comma-separated (empty string
    # to clear)". Passing EXCLUDED_FOLDER alone therefore silently un-excludes
    # every other folder already in the list, and the post-condition below would
    # still pass because it only asked whether our own folder was present.
    # Re-list what is already there, plus ours. (At time of writing ignoreFolders
    # is null, so this is latent rather than live -- but anything excluded via the
    # Obsidian UI between now and EX-7 would otherwise be dropped without a word.)
    existing = [f for f in (cfg.get(EXCLUSION_KEY) or []) if isinstance(f, str) and f]
    want_excluded = existing + ([EXCLUDED_FOLDER] if EXCLUDED_FOLDER not in existing else [])
    if any("," in f for f in want_excluded):
        die(f"an existing excluded folder contains a comma, which is the list "
            f"separator: {[f for f in want_excluded if ',' in f]!r}")

    cmd = [
        resolve_ob(),
        "sync-config",
        "--path",
        str(VAULT),
        "--file-types",
        FILE_TYPES,
        "--excluded-folders",
        ",".join(want_excluded),
    ]
    log()
    log(f"  $ {' '.join(cmd)}")
    log("  --configs omitted: omission preserves the existing setting.")

    if args.dry_run:
        log("  Dry run, not executing.")
        return 0

    proc = subprocess.run(cmd, cwd=str(VAULT))
    if proc.returncode != 0:
        die(f"ob sync-config exited {proc.returncode}")

    cfg_after = read_config(state_dir)
    log()
    log("  Config after (non-secret keys only):")
    print_config_safely(cfg_after)

    # Post-condition checks run after the mutation, so clean=False: the config
    # write has already landed and the operator must not be told otherwise.
    # Assert the whole set, not just our own entry. Checking only for
    # EXCLUDED_FOLDER would pass while every previously-excluded folder had been
    # dropped -- the exact failure the whole-list assignment above guards against.
    excluded = cfg_after.get(EXCLUSION_KEY) or []
    if sorted(excluded) != sorted(want_excluded):
        die(f"exclusion did not take as intended: {EXCLUSION_KEY} is {excluded!r}, "
            f"expected {want_excluded!r}", clean=False)

    # EC-5 requires both halves verified, not just the exclusion.
    want_types = sorted(t.strip() for t in FILE_TYPES.split(","))
    got_types = sorted(cfg_after.get("allowTypes") or [])
    if got_types != want_types:
        die(f"file types did not take: allowTypes is {got_types!r}, expected {want_types!r}",
            clean=False)

    log()
    log(f"  Exclusion confirmed in config.json ({EXCLUSION_KEY}).")
    log(f"  File types confirmed: {got_types!r}")
    return 0


# --------------------------------------------------------------------------
# EX-9: tripwire
# --------------------------------------------------------------------------


def predicted_exclusions(excluded: list[str]) -> list[str]:
    """Vault-relative regenerable dirs a manifest implies, not already excluded.

    Returns paths whether or not they exist on disk -- that is the point. The
    directory that has not been created yet is precisely the one it is still
    safe to exclude.

    Dot-directories are skipped at the vault root ONLY. cli.js's own rule is
    `e.startsWith(".")` against the whole vault-relative path -- first segment,
    not any segment -- so `.claude/worktrees/**/node_modules` can never consume
    quota and excluding it would be noise in a list that must stay auditable.
    Its general any-segment dot rejection applies only under the Obsidian
    config dir. A nested `writing/site/.tmp/node_modules` therefore IS
    syncable, so the walk must keep descending into non-root dot-dirs.
    """

    def is_excluded(rel: str) -> bool:
        return path_is_excluded(rel, excluded)

    found: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(VAULT, onerror=lambda e: None):
        rel_dir = os.path.relpath(dirpath, VAULT)
        rel_dir = "" if rel_dir == "." else rel_dir
        if rel_dir and is_excluded(rel_dir):
            dirnames[:] = []
            continue
        # Prune already-generated trees, and root-level dot-dirs; neither can
        # host a manifest whose sibling we would need to exclude. Non-root
        # dot-dirs stay in the walk -- see the docstring.
        dirnames[:] = [
            d
            for d in dirnames
            if d not in REGENERABLE_DIRS and not (rel_dir == "" and d.startswith("."))
        ]
        for name in filenames:
            for child in MANIFEST_REGENERABLE.get(name, ()):
                rel = f"{rel_dir}/{child}" if rel_dir else child
                if not is_excluded(rel):
                    found.add(rel)
    return sorted(found)


def server_rows_under(conn: sqlite3.Connection, folder: str) -> int:
    """Every server_files row at or beneath `folder`, tombstoned or not.

    Tombstones count. A tombstoned row is still a row the server holds and
    still a path the remote knows about; excluding the folder freezes whatever
    state it is in, so "there is nothing there" is the only condition under
    which exclusion is unambiguously safe.
    """
    where, params = under_target(folder)
    return scalar(conn, f"SELECT count(*) FROM server_files WHERE {where}", params)


def server_file_rows_under(conn: sqlite3.Connection, folder: str) -> int:
    """Non-folder rows at or beneath `folder` -- the ones that hold bytes.

    Folder rows carry no content and cost no quota; this vault has 2,927 of
    them under a single already-excluded node_modules. Counting those in an
    ALARM would fire every night over nothing, and a channel that cries wolf
    nightly is one nobody reads -- the same failure the clean-run-stays-silent
    rule elsewhere in this file exists to prevent.

    The auto-exclude GATE deliberately keeps using the stricter
    server_rows_under(): declining to exclude costs a line in a report, while a
    wrong exclusion strands rows irreversibly. Alarm on what matters, gate on
    anything at all.
    """
    where, params = under_target(folder)
    return scalar(conn,
                  f"SELECT count(*) FROM server_files WHERE {where} AND NOT {IS_FOLDER}",
                  params)


def cmd_tripwire(args: argparse.Namespace) -> int:
    state_dir = find_state_dir()
    cfg = read_config(state_dir)
    excluded = list(cfg.get(EXCLUSION_KEY) or [])

    def is_excluded(rel: str) -> bool:
        return path_is_excluded(rel, excluded)

    max_bytes = int(args.max_file_mb * MB)
    regenerable: list[tuple[str, int]] = []
    oversized: list[tuple[str, int]] = []

    # os.walk swallows every error it meets, including a root that does not
    # exist: it yields nothing and the run prints "Clean. No findings." A
    # daily unattended check that reports clean because it looked at nothing
    # is worse than no check, because it is indistinguishable from a real
    # clean result. Fail loudly instead -- both for a missing root, and for
    # any directory that turns unreadable mid-walk.
    if not VAULT.is_dir():
        die(f"vault root is not a directory: {VAULT} -- refusing to report a clean scan")
    walk_errors: list[OSError] = []

    for dirpath, dirnames, filenames in os.walk(VAULT, onerror=walk_errors.append):
        rel_dir = os.path.relpath(dirpath, VAULT)
        rel_dir = "" if rel_dir == "." else rel_dir

        if rel_dir and is_excluded(rel_dir):
            dirnames[:] = []
            continue
        if ".git" in dirnames:
            dirnames.remove(".git")

        for name in list(dirnames):
            rel = f"{rel_dir}/{name}" if rel_dir else name
            if name in REGENERABLE_DIRS and not is_excluded(rel):
                # These trees churn (a build can unlink an entry mid-walk); a
                # vanished file must not kill the unattended daily run.
                size = 0
                for p in (Path(dirpath) / name).rglob("*"):
                    try:
                        if p.is_file() and not p.is_symlink():
                            size += p.stat().st_size
                    except OSError:
                        continue
                regenerable.append((rel, size))
                dirnames.remove(name)

        for name in filenames:
            full = Path(dirpath) / name
            if full.is_symlink() or not full.is_file():
                continue
            rel = f"{rel_dir}/{name}" if rel_dir else name
            try:
                size = full.stat().st_size
            except OSError:
                continue
            if size > max_bytes:
                oversized.append((rel, size))

    rule("EX-9  tripwire")
    log(f"  vault        : {VAULT}")
    log(f"  exclusions   : {excluded or 'none'}")
    log(f"  size ceiling : {args.max_file_mb:.2f} MB")

    if walk_errors:
        log()
        log(f"  UNREADABLE DIRECTORIES ({len(walk_errors)}):")
        for err in walk_errors[:20]:
            log(f"    {err.filename}: {err.strerror}")
        if len(walk_errors) > 20:
            log(f"    ... and {len(walk_errors) - 20} more")
        die("scan was incomplete; its result cannot be trusted")

    if regenerable:
        log()
        log(f"  UNEXCLUDED REGENERABLE DIRECTORIES ({len(regenerable)}):")
        for rel, size in sorted(regenerable, key=lambda x: -x[1]):
            log(f"    {fmt_mb(size):>12}  {rel}")

    if oversized:
        log()
        log(f"  FILES OVER THE {args.max_file_mb:.2f} MB CAP ({len(oversized)}):")
        log("    (these never reach the remote at all -- silent failure, not quota)")
        for rel, size in sorted(oversized, key=lambda x: -x[1]):
            log(f"    {fmt_mb(size):>12}  {rel}")

    # Pre-emptive exclusion. Everything above reports what already exists; this
    # asks what a lockfile in the vault could still create, and shuts the door
    # while the far side is empty.
    added: list[str] = []
    stranded: list[str] = []
    leaked: list[str] = []
    candidates = predicted_exclusions(excluded)
    # Exclusion is exactly the state in which rows can accrue unwatched: the
    # walk above prunes an excluded path and the regenerable report skips it, so
    # once a path is excluded nothing local ever looks at it again. But filters
    # are read only at client startup -- anything created between an exclusion
    # and the next restart is synced by the still-old filter, and then stays on
    # the server forever, invisible. Re-checking the server side is the only
    # thing that can see it, so do it for every excluded regenerable path on
    # every run, not just the ones we are about to add.
    #
    # Scope is deliberately the basename, which makes this complete for every
    # path --auto-exclude can ever add (each one is a MANIFEST_REGENERABLE
    # child, all of which are in REGENERABLE_DIRS) and incomplete for a
    # hand-excluded ANCESTOR of a regenerable tree -- excluding
    # `.../slides/slidev` hides rows under its node_modules from this alarm.
    # Widening to every excluded folder would fire on deliberate exclusions
    # like `Private`, whose whole purpose is to hold rows the operator does not
    # want synced, turning a nightly channel into noise. Watch what the tool
    # itself excludes; a human who excludes a parent owns that choice.
    watch = [f for f in excluded if f.rsplit("/", 1)[-1] in REGENERABLE_DIRS]
    if candidates or watch:
        with tempfile.TemporaryDirectory(prefix="vault-sync-tripwire-") as tmp:
            conn = open_ro(copy_state_db(state_dir, Path(tmp)))
            try:
                for rel in candidates:
                    (stranded if server_rows_under(conn, rel) else added).append(rel)
                leaked = [f for f in watch if server_file_rows_under(conn, f)]
            finally:
                conn.close()

    if leaked:
        log()
        log(f"  EXCLUDED BUT ON SERVER ({len(leaked)}):")
        for rel in leaked:
            log(f"    STRANDED rows under an excluded path   {rel}")
        log("    (the filter hides these locally; they still consume quota.")
        log("     un-exclude, restart, let the delete propagate, then re-exclude)")

    if candidates:
        log()
        log(f"  PREDICTED REGENERABLE PATHS ({len(candidates)}):")
        for rel in added:
            log(f"    safe to exclude (0 server rows)  {rel}")
        for rel in stranded:
            log(f"    ALREADY ON SERVER, not touched   {rel}")
        if stranded:
            log("    (excluding these would strand their rows -- delete, sync, then exclude)")

    # getattr, not attribute access: cmd_tripwire is also driven directly with a
    # hand-built Namespace, and an absent flag must mean "report only" rather
    # than an AttributeError raised halfway through a report.
    if added and getattr(args, "auto_exclude", False):
        want = excluded + added
        if any("," in f for f in want):
            die(f"an excluded folder contains the list separator: "
                f"{[f for f in want if ',' in f]!r}")
        # --excluded-folders is whole-list ASSIGNMENT; re-list what is already
        # there. --file-types is deliberately omitted rather than re-sent:
        # omission preserves it, and an unattended nightly job has no business
        # rewriting a setting it was not asked to change.
        cmd = [resolve_ob(), "sync-config", "--path", str(VAULT),
               "--excluded-folders", ",".join(want)]
        log()
        log(f"  $ {' '.join(cmd)}")
        if getattr(args, "dry_run", False):
            log("  Dry run, not executing.")
        else:
            proc = subprocess.run(cmd, cwd=str(VAULT))
            if proc.returncode != 0:
                die(f"ob sync-config exited {proc.returncode}")
            got = read_config(state_dir).get(EXCLUSION_KEY) or []
            if sorted(got) != sorted(want):
                die(f"exclusion did not take: {EXCLUSION_KEY} is {got!r}, "
                    f"expected {want!r}", clean=False)
            excluded = want
            log(f"  Excluded {len(added)} new path(s); {len(got)} total.")
            # Filters are read once, when the client starts. Until it is
            # restarted the running daemon still has the old list, so a
            # directory created before then syncs anyway -- and the config now
            # says otherwise, which is the worst of both.
            log("  RESTART REQUIRED: `ob sync --continuous` reads filters only at "
                "startup.")
    elif added:
        log()
        log("  Re-run with --auto-exclude to apply, or:")
        log(f"    ob sync-config --path {VAULT} \\")
        log(f"      --excluded-folders '{','.join(excluded + added)}'")

    if not regenerable and not oversized and not added and not stranded and not leaked:
        log()
        log("  Clean. No findings.")
        return 0

    log()
    log(f"  {len(regenerable)} regenerable dir(s), {len(oversized)} oversized file(s), "
        f"{len(added)} pre-emptive exclusion(s), {len(stranded)} already stranded, "
        f"{len(leaked)} excluded-but-on-server.")
    # Non-zero exit is the notification trigger: the cron wrapper notifies on
    # findings only, so a clean run must stay silent.
    return 2


# --------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vault_sync.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("gate", help="EX-2 read-only state.db checks")
    g.add_argument("--allow-drift", action="store_true", help="proceed despite drift from the baseline")
    g.set_defaults(func=cmd_gate)

    s = sub.add_parser("stage", help="EX-3/EX-4 compute the deletion set and move it out")
    s.add_argument("--what", choices=("runs", "node-modules", "both"), default="both")
    s.add_argument("--execute", action="store_true", help="actually move (default is dry run)")
    s.add_argument("--holding", help="holding directory outside the vault")
    s.set_defaults(func=cmd_stage)

    y = sub.add_parser("sync", help="EX-5 bidirectional sync")
    y.add_argument("--dry-run", action="store_true")
    y.set_defaults(func=cmd_sync)

    v = sub.add_parser("verify", help="EX-6 tombstone read, split by folder")
    v.set_defaults(func=cmd_verify)

    f = sub.add_parser("filters", help="EX-7 the single sync-config call")
    f.add_argument("--approved-by", required=True, help="who approved the EX-6 -> EX-7 transition")
    f.add_argument("--approval-note", required=True, help="what was approved, recorded in the log")
    f.add_argument("--dry-run", action="store_true")
    f.set_defaults(func=cmd_filters)

    t = sub.add_parser("tripwire", help="EX-9 regenerable dirs and oversized files")
    t.add_argument("--max-file-mb", type=float, default=DEFAULT_MAX_FILE_MB)
    # Off by default: every other read-only subcommand stays read-only unless
    # asked, and a tool that mutates sync config merely by being run is one
    # stray invocation away from a config nobody chose.
    t.add_argument(
        "--auto-exclude",
        action="store_true",
        help="add predicted regenerable paths with zero server rows to ignoreFolders",
    )
    t.add_argument("--dry-run", action="store_true")
    t.set_defaults(func=cmd_tripwire)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
