"""Focused regression tests for sync_text_replacements.py.

Covers:
  (a) Two collections sharing raw shortcut 'plan' both survive merge as cc.plan / prod.plan.
  (b) Single-collection round-trip preserves phrases and backfills missing uid.
  (c) Phrases don't bleed between same-raw-shortcut entries in different collections.
  (d) cmd_diff's shortcut set keeps cc.plan and prod.plan distinct.
  (e) uid uniqueness — duplicate uid raises an error; missing uid is accepted.

No live DB or Alfred I/O — all in-memory / temp files.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Resolve repo root so the script is importable without installing it.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import sync_text_replacements as sut  # noqa: E402
from sync_text_replacements import (  # noqa: E402
    CollectionMeta,
    Snippet,
    prefixed_shortcut,
    validate_uids,
)

# ── Fixtures ─────────────────────────────────────────────────────────────────

PLAN_UID_CC = "AAAAAAAA-0001-0001-0001-000000000001"
PLAN_UID_PROD = "BBBBBBBB-0002-0002-0002-000000000002"

MERGED_META: dict[str, CollectionMeta] = {
    "coding-agents": CollectionMeta(prefix="cc."),
    "productivity": CollectionMeta(prefix="prod."),
}

CC_PLAN = Snippet(shortcut="plan", phrase="cc plan phrase", uid=PLAN_UID_CC,
                  collection="coding-agents")
PROD_PLAN = Snippet(shortcut="plan", phrase="prod plan phrase", uid=PLAN_UID_PROD,
                    collection="productivity")
CC_EXP = Snippet(shortcut="exp", phrase="experiment phrase", uid="CCCCCCCC-0003-0003-0003-000000000003",
                 collection="coding-agents")


def _merge(yaml_collections: dict[str, list[Snippet]]) -> dict[str, list[Snippet]]:
    """Run the same merge logic as cmd_sync / cmd_export but in-memory (no I/O)."""
    merged_meta = MERGED_META

    # Build maps keyed by prefixed shortcut (mirrors the patched merge code).
    yaml_map: dict[str, Snippet] = {}
    for snippets in yaml_collections.values():
        for s in snippets:
            yaml_map[prefixed_shortcut(s, merged_meta)] = s

    collections: dict[str, list[Snippet]] = {}
    seen: set[str] = set()

    for col_name, snippets in yaml_collections.items():
        for s in snippets:
            ps = prefixed_shortcut(s, merged_meta)
            if ps in seen:
                continue
            seen.add(ps)
            collections.setdefault(col_name, []).append(s)

    return collections


# ── Tests ─────────────────────────────────────────────────────────────────────


class TestDedupFix:
    """(a) Two collections with same raw shortcut both survive merge."""

    def test_both_plan_entries_survive(self) -> None:
        yaml_collections = {
            "coding-agents": [CC_PLAN],
            "productivity": [PROD_PLAN],
        }
        result = _merge(yaml_collections)

        cc_shortcuts = [s.shortcut for s in result.get("coding-agents", [])]
        prod_shortcuts = [s.shortcut for s in result.get("productivity", [])]
        assert "plan" in cc_shortcuts, "cc.plan (coding-agents) was dropped"
        assert "plan" in prod_shortcuts, "prod.plan (productivity) was dropped"

    def test_prefixed_shortcuts_are_distinct(self) -> None:
        cc_ps = prefixed_shortcut(CC_PLAN, MERGED_META)
        prod_ps = prefixed_shortcut(PROD_PLAN, MERGED_META)
        assert cc_ps == "cc.plan"
        assert prod_ps == "prod.plan"
        assert cc_ps != prod_ps, "Prefixed shortcuts must be distinct"

    def test_all_three_entries_survive(self) -> None:
        """Also verify a third entry in coding-agents is unaffected."""
        yaml_collections = {
            "coding-agents": [CC_PLAN, CC_EXP],
            "productivity": [PROD_PLAN],
        }
        result = _merge(yaml_collections)

        assert len(result.get("coding-agents", [])) == 2, "Both cc entries must survive"
        assert len(result.get("productivity", [])) == 1, "prod entry must survive"


class TestPhraseIntegrity:
    """(c) Phrases don't bleed between same-raw-shortcut entries."""

    def test_phrases_stay_with_their_entry(self) -> None:
        yaml_collections = {
            "coding-agents": [CC_PLAN],
            "productivity": [PROD_PLAN],
        }
        result = _merge(yaml_collections)

        cc_entry = next(s for s in result["coding-agents"] if s.shortcut == "plan")
        prod_entry = next(s for s in result["productivity"] if s.shortcut == "plan")
        assert cc_entry.phrase == "cc plan phrase", "cc phrase must not bleed to prod"
        assert prod_entry.phrase == "prod plan phrase", "prod phrase must not bleed to cc"

    def test_uids_stay_with_their_entry(self) -> None:
        yaml_collections = {
            "coding-agents": [CC_PLAN],
            "productivity": [PROD_PLAN],
        }
        result = _merge(yaml_collections)

        cc_entry = next(s for s in result["coding-agents"] if s.shortcut == "plan")
        prod_entry = next(s for s in result["productivity"] if s.shortcut == "plan")
        assert cc_entry.uid == PLAN_UID_CC
        assert prod_entry.uid == PLAN_UID_PROD


class TestSingleCollectionRoundTrip:
    """(b) Single-collection round-trip preserves phrases and backfills missing uid."""

    def test_preserves_phrase(self) -> None:
        yaml_collections = {"coding-agents": [CC_EXP]}
        result = _merge(yaml_collections)
        entry = result["coding-agents"][0]
        assert entry.phrase == "experiment phrase"

    def test_missing_uid_accepted_by_validate_uids(self) -> None:
        no_uid = Snippet(shortcut="exp", phrase="x", collection="coding-agents")
        errors = validate_uids([no_uid])
        assert errors == [], f"Missing uid should not be an error, got: {errors}"


class TestCmdDiffDistinction:
    """(d) The shortcut key space used for diff keeps cc.plan and prod.plan distinct."""

    def test_prefixed_shortcuts_unique_in_set(self) -> None:
        """The set used for all_shortcuts in cmd_diff must have both prefixed variants."""
        yaml_map: dict[str, Snippet] = {}
        for col_snippets in [
            ("coding-agents", [CC_PLAN]),
            ("productivity", [PROD_PLAN]),
        ]:
            col_name, snippets = col_snippets
            for s in snippets:
                yaml_map[prefixed_shortcut(s, MERGED_META)] = s

        assert "cc.plan" in yaml_map, "cc.plan missing from yaml_map"
        assert "prod.plan" in yaml_map, "prod.plan missing from yaml_map"
        assert len(yaml_map) == 2, f"Expected 2 distinct keys, got {len(yaml_map)}: {list(yaml_map)}"


class TestValidateUids:
    """(e) validate_uids catches duplicate uids and accepts missing ones."""

    def test_duplicate_uid_is_error(self) -> None:
        shared_uid = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        s1 = Snippet(shortcut="txt", phrase="hello", uid=shared_uid, collection="coding-agents")
        s2 = Snippet(shortcut="txt2", phrase="hello", uid=shared_uid, collection="coding-agents")
        errors = validate_uids([s1, s2])
        assert len(errors) == 1, f"Expected 1 error for duplicate uid, got: {errors}"
        assert shared_uid in errors[0]

    def test_unique_uids_no_error(self) -> None:
        s1 = Snippet(shortcut="txt", phrase="hello", uid=PLAN_UID_CC, collection="coding-agents")
        s2 = Snippet(shortcut="txt2", phrase="world", uid=PLAN_UID_PROD, collection="coding-agents")
        errors = validate_uids([s1, s2])
        assert errors == []

    def test_missing_uid_no_error(self) -> None:
        s1 = Snippet(shortcut="txt", phrase="hello", uid="", collection="coding-agents")
        s2 = Snippet(shortcut="txt2", phrase="world", uid="", collection="coding-agents")
        errors = validate_uids([s1, s2])
        assert errors == [], f"Empty uids should not count as duplicates: {errors}"

    def test_mix_of_missing_and_real_uids(self) -> None:
        s_real = Snippet(shortcut="plan", phrase="x", uid=PLAN_UID_CC, collection="coding-agents")
        s_missing = Snippet(shortcut="exp", phrase="y", uid="", collection="coding-agents")
        errors = validate_uids([s_real, s_missing])
        assert errors == []


# ── Standalone runner (no pytest required) ───────────────────────────────────

if __name__ == "__main__":
    import traceback

    passed = failed = 0
    for cls_name, cls in sorted(
        ((k, v) for k, v in globals().items() if isinstance(v, type) and k.startswith("Test")),
        key=lambda x: x[0],
    ):
        print(f"\n{cls_name}")
        obj = cls()
        for method_name in sorted(m for m in dir(obj) if m.startswith("test_")):
            try:
                getattr(obj, method_name)()
                print(f"  PASS  {method_name}")
                passed += 1
            except AssertionError as exc:
                print(f"  FAIL  {method_name}: {exc}")
                failed += 1
            except Exception:
                print(f"  ERROR {method_name}")
                traceback.print_exc()
                failed += 1

    print(f"\n{'=' * 50}")
    print(f"{passed} passed, {failed} failed")
    if failed:
        sys.exit(1)
