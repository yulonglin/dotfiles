"""Tests for custom_bins/things-orphans: which Things to-dos count as orphans."""

import importlib.machinery
import importlib.util
import sqlite3
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "custom_bins" / "things-orphans"


def load():
    loader = importlib.machinery.SourceFileLoader("things_orphans", str(BIN))
    spec = importlib.util.spec_from_loader("things_orphans", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def make_db():
    con = sqlite3.connect(":memory:")
    con.execute(
        "create table TMTask (uuid text, title text, type int, status int, trashed int,"
        " project text, area text, heading text, start int, rt1_recurrenceRule blob,"
        " creationDate real)"
    )
    rows = [
        # uuid, title, type, status, trashed, project, area, heading, start, rrule
        ("orphan-anytime", "loose anytime", 0, 0, 0, None, None, None, 1, None),
        ("orphan-someday", "loose someday", 0, 0, 0, None, None, None, 2, b"r"),
        ("inbox", "inbox item", 0, 0, 0, None, None, None, 0, None),
        ("in-project", "filed", 0, 0, 0, "P", None, None, 1, None),
        ("in-area", "filed", 0, 0, 0, None, "A", None, 1, None),
        ("under-heading", "filed", 0, 0, 0, None, None, "H", 1, None),
        ("cancelled", "done", 0, 2, 0, None, None, None, 1, None),
        ("trashed", "gone", 0, 0, 1, None, None, None, 1, None),
        ("a-project", "project row", 1, 0, 0, None, None, None, 1, None),
        ("notice", "File orphaned Things to-dos", 0, 0, 0, None, None, None, 1, None),
    ]
    con.executemany("insert into TMTask values (?,?,?,?,?,?,?,?,?,?,0)", rows)
    return con


def test_only_loose_open_anytime_or_someday_todos_are_orphans():
    mod = load()
    found = {i["uuid"]: i for i in mod.orphans(make_db())}
    assert set(found) == {"orphan-anytime", "orphan-someday"}
    assert found["orphan-someday"]["repeating"] is True
    assert found["orphan-anytime"]["link"] == "things:///show?id=orphan-anytime"


def test_notify_skips_when_its_own_todo_is_still_open():
    mod = load()
    con = make_db()
    assert mod.notify_open(con) is True
    assert "still open" in mod.notify(mod.orphans(con), con)


def test_notify_with_no_orphans_adds_nothing():
    mod = load()
    assert mod.notify([], make_db()) == "no orphans; nothing added"
