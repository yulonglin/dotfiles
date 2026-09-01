"""The localStorage key must be unique per artifact, not per filename.

All artifacts are read from one origin, so two pages deriving the same key show
each other's comments — the cross-document leak that `artifact-writing` records
as the worst failure this layer can have. `artifacts/<slug>/spec.md` is the
standard layout, so a key derived from the filename stem alone would hand every
spec in the gallery the single key "review-spec".
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MD2ARTIFACT = REPO / "custom_bins" / "md2artifact"


def _load():
    spec = importlib.util.spec_from_loader(
        "md2artifact_cli",
        importlib.machinery.SourceFileLoader("md2artifact_cli", str(MD2ARTIFACT)),
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["md2artifact_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


md2 = _load()


def test_two_specs_in_different_artifacts_never_share_a_key(tmp_path):
    a = tmp_path / "editable-review-layer" / "spec.md"
    b = tmp_path / "context-ledger" / "spec.md"
    for p in (a, b):
        p.parent.mkdir(parents=True)
        p.write_text("# t\n")
    assert md2.storage_key(a) != md2.storage_key(b)


def test_a_generic_stem_is_qualified_by_its_artifact_directory(tmp_path):
    p = tmp_path / "editable-review-layer" / "spec.md"
    p.parent.mkdir(parents=True)
    p.write_text("# t\n")
    assert md2.storage_key(p) == "review-editable-review-layer-spec"


def test_plan_and_spec_in_one_artifact_stay_separate(tmp_path):
    d = tmp_path / "some-slug"
    d.mkdir()
    (d / "spec.md").write_text("# t\n")
    (d / "plan.md").write_text("# t\n")
    assert md2.storage_key(d / "spec.md") != md2.storage_key(d / "plan.md")


def test_a_specific_stem_keeps_its_historic_key(tmp_path):
    """Already-published pages must not be orphaned by the qualifying rule."""
    p = tmp_path / "whatever" / "context-ledger.md"
    p.parent.mkdir(parents=True)
    p.write_text("# t\n")
    assert md2.storage_key(p) == "review-context-ledger"


def test_every_generic_stem_is_actually_qualified(tmp_path):
    d = tmp_path / "slug-here"
    d.mkdir()
    for stem in md2.GENERIC_STEMS:
        p = d / f"{stem}.md"
        p.write_text("# t\n")
        assert md2.storage_key(p).startswith("review-slug-here-"), stem
