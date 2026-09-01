"""Roster-picking and config-rewriting tests for `openrouter-cli council`.

Two guards in the picking rule are load-bearing and were both found by running
the naive version against the live catalogue, not by reasoning about it:

  * without the price cap, Epoch's ranking seats gpt-5.5-pro ($30/$180) over
    gpt-5.6-sol ($2/$10) for 0.6 index points;
  * without the same-product-line constraint, "prefer the newest unscored
    sibling" seats glm-5.3-flash, qwen3.8-flash and muse-spark-1.2-contributor
    -- a roster of cheap tiers wearing the word "newest".

Both are pinned here because both are silent failures: the roster still looks
plausible, and only the bill or the answer quality reveals it.

The rewrite tests exist because tomllib reads TOML but cannot write it, so the
seats block is spliced textually. The commentary in openrouter-models.toml is
the institutional memory of why each guard exists, so losing it to a serialiser
round-trip would be a real defect rather than a cosmetic one.
"""

import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

_PATH = Path(__file__).resolve().parent.parent / "custom_bins" / "openrouter-cli"
_loader = importlib.machinery.SourceFileLoader("openrouter_cli", str(_PATH))
_spec = importlib.util.spec_from_loader("openrouter_cli", _loader)
orc = importlib.util.module_from_spec(_spec)
_loader.exec_module(orc)


def row(slug, out, created, din=1.0):
    family = slug.split("/", 1)[0]
    return {"slug": slug, "family": family, "tail": slug.split("/", 1)[1],
            "in": din, "out": out, "created": created}


class TestPickSeat:
    def test_takes_the_highest_scorer_in_the_family(self):
        rows = [row("x/big", 5, 100), row("x/small", 5, 100)]
        scores = {"big": 90.0, "small": 10.0}
        assert orc.pick_seat("x", rows, scores, 60.0)["slug"] == "x/big"

    def test_price_cap_excludes_the_top_scorer(self):
        """The gpt-5.5-pro case: highest score, absurd price, must not seat."""
        rows = [row("x/pro", 180, 100), row("x/std", 10, 100)]
        scores = {"pro": 161.7, "std": 161.1}
        assert orc.pick_seat("x", rows, scores, 60.0)["slug"] == "x/std"

    def test_newer_unscored_sibling_wins_the_seat(self):
        """The glm-5.3 case: the index has not reached the newest release."""
        rows = [row("x/thing-5.2", 5, 100), row("x/thing-5.3", 5, 200)]
        got = orc.pick_seat("x", rows, {"thing52": 90.0}, 60.0)
        assert got["slug"] == "x/thing-5.3"
        assert got["basis"] == "newest-in-line"
        assert got["score"] == 0.0

    def test_newer_unscored_DIFFERENT_line_does_not_win(self):
        """The glm-5.3-flash case: a cheap tier is not a newer sibling."""
        rows = [row("x/thing-5.2", 5, 100), row("x/thing-5.3-flash", 1, 200)]
        got = orc.pick_seat("x", rows, {"thing52": 90.0}, 60.0)
        assert got["slug"] == "x/thing-5.2", "a -flash tier must not take the seat"
        assert got["basis"] == "eci"

    def test_older_unscored_sibling_does_not_win(self):
        rows = [row("x/thing-5.2", 5, 200), row("x/thing-5.1", 5, 100)]
        got = orc.pick_seat("x", rows, {"thing52": 90.0}, 60.0)
        assert got["slug"] == "x/thing-5.2"

    def test_family_with_nothing_under_the_cap_returns_none(self):
        """Must degrade to a reported gap, never crash a scheduled job."""
        assert orc.pick_seat("x", [row("x/pro", 999, 100)], {"pro": 9.0}, 60.0) is None

    def test_absent_family_returns_none(self):
        assert orc.pick_seat("nope", [row("x/a", 5, 100)], {}, 60.0) is None

    def test_all_unscored_falls_back_to_newest(self):
        rows = [row("x/a", 5, 100), row("x/b", 5, 300)]
        got = orc.pick_seat("x", rows, {}, 60.0)
        assert got["slug"] == "x/b" and got["basis"] == "newest-in-line"


class TestRenderSeats:
    def test_round_trips_through_tomllib(self):
        import tomllib
        picked = [{"alias": "one", "slug": "a/one", "family": "a",
                   "score": 12.5, "basis": "eci"}]
        parsed = tomllib.loads(orc.render_seats(picked))
        assert parsed["seats"][0]["slug"] == "a/one"
        assert parsed["seats"][0]["score"] == 12.5


CONFIG_TEMPLATE = '''# A comment that must survive.
chair = "a/chair"
reviewed = "2020-01-01"

# BEGIN council-auto
seats = [
  { alias = "old", slug = "a/old", family = "a", score = 1.0, basis = "eci" },
]
# END council-auto

# A trailing comment that must also survive.
[fusion]
max_tool_calls = 4
'''


def write_cfg(tmp_path, text=CONFIG_TEMPLATE):
    p = tmp_path / "models.toml"
    p.write_text(text)
    return p


NEW = [{"alias": "new", "slug": "b/new", "family": "b", "score": 2.0,
        "basis": "eci"}]


class TestRewriteSeats:
    def test_replaces_seats_and_stamps_the_date(self, tmp_path):
        import tomllib
        p = write_cfg(tmp_path)
        orc.rewrite_seats(p, NEW, "2026-09-01")
        cfg = tomllib.loads(p.read_text())
        assert cfg["seats"][0]["slug"] == "b/new"
        assert cfg["reviewed"] == "2026-09-01"

    def test_preserves_every_comment(self, tmp_path):
        p = write_cfg(tmp_path)
        orc.rewrite_seats(p, NEW, "2026-09-01")
        text = p.read_text()
        assert "# A comment that must survive." in text
        assert "# A trailing comment that must also survive." in text
        assert "[fusion]" in text

    def test_is_idempotent(self, tmp_path):
        p = write_cfg(tmp_path)
        orc.rewrite_seats(p, NEW, "2026-09-01")
        once = p.read_text()
        orc.rewrite_seats(p, NEW, "2026-09-01")
        assert p.read_text() == once

    def test_missing_markers_refuse(self, tmp_path):
        p = write_cfg(tmp_path, 'chair = "a/c"\nreviewed = "2020-01-01"\n')
        with pytest.raises(SystemExit):
            orc.rewrite_seats(p, NEW, "2026-09-01")

    def test_duplicate_markers_refuse(self, tmp_path):
        p = write_cfg(tmp_path, CONFIG_TEMPLATE + CONFIG_TEMPLATE)
        with pytest.raises(SystemExit):
            orc.rewrite_seats(p, NEW, "2026-09-01")

    def test_missing_reviewed_line_refuses(self, tmp_path):
        text = CONFIG_TEMPLATE.replace('reviewed = "2020-01-01"\n', "")
        p = write_cfg(tmp_path, text)
        with pytest.raises(SystemExit):
            orc.rewrite_seats(p, NEW, "2026-09-01")

    def test_a_bad_render_never_reaches_disk(self, tmp_path, monkeypatch):
        """Validation is before the write, so a failure leaves the old config."""
        p = write_cfg(tmp_path)
        before = p.read_text()
        monkeypatch.setattr(orc, "render_seats", lambda _: "seats = [ this is not toml")
        with pytest.raises(SystemExit):
            orc.rewrite_seats(p, NEW, "2026-09-01")
        assert p.read_text() == before


CFG = {
    "council": {
        "chair": "a/chair",
        "advisor_families": ["a", "b"],
        "seats": [
            {"slug": "a/one", "alias": "one", "family": "a"},
            {"slug": "b/two", "alias": "two", "family": "b"},
        ],
    },
    "models": [{"slug": "c/three", "alias": "three"}],
}


class TestResolution:
    def test_seat_alias_resolves(self):
        assert orc.resolve(CFG, "one") == "a/one"

    def test_off_roster_alias_resolves(self):
        assert orc.resolve(CFG, "three") == "c/three"

    def test_a_seat_beats_an_off_roster_entry_on_the_same_alias(self):
        cfg = {**CFG, "models": [{"slug": "z/stale", "alias": "one"}]}
        assert orc.resolve(cfg, "one") == "a/one"

    def test_unknown_name_dies(self):
        with pytest.raises(SystemExit):
            orc.resolve(CFG, "nope")

    def test_chair_falls_back_to_legacy_judge(self):
        assert orc.chair_of({"judge": "old/judge"}) == "old/judge"

    def test_chair_wins_over_legacy_judge(self):
        assert orc.chair_of({**CFG, "judge": "old/judge"}) == "a/chair"

    def test_configured_covers_chair_and_every_seat(self):
        slugs = {slug for _, slug in orc.configured(CFG)}
        assert {"a/chair", "a/one", "b/two", "c/three"} <= slugs


class TestAdvisorPair:
    def test_resolves_families_to_seated_slugs(self):
        assert orc.advisor_slugs(CFG) == ["a/one", "b/two"]

    def test_unseated_family_dies(self):
        cfg = {"council": {**CFG["council"], "advisor_families": ["a", "zzz"]}}
        with pytest.raises(SystemExit):
            orc.advisor_slugs(cfg)

    def test_no_families_configured_dies(self):
        with pytest.raises(SystemExit):
            orc.advisor_slugs({"council": {"seats": []}})


class TestCrossRank:
    def test_needs_at_least_three_live_answers(self):
        answers = {"a/one": {"content": "x"}, "b/two": {"content": "y"}}
        points, notes = orc.cross_rank(answers, "q", "key", 100)
        assert points == {} and notes

    def test_ballots_exclude_the_ranker_and_borda_totals(self, monkeypatch):
        answers = {f"m/{i}": {"content": f"answer {i}"} for i in range(3)}
        seen = {}

        def fake_ask(slug, prompt, key, max_tokens):
            seen[slug] = prompt
            # Rank whatever labels appear, in the order they appear.
            labels = [ln.split()[-1] for ln in prompt.splitlines()
                      if ln.startswith("### Answer ")]
            return "\n".join(labels), {}

        monkeypatch.setattr(orc, "ask_one", fake_ask)
        points, notes = orc.cross_rank(answers, "q", "key", 100)
        assert not notes
        for slug, prompt in seen.items():
            assert answers[slug]["content"] not in prompt, "a ranker saw its own answer"
            assert prompt.count("### Answer ") == 2
        # Three rankers, each awarding 2 then 1 point: 9 points distributed.
        assert sum(points.values()) == 9

    def test_an_unparseable_ballot_is_noted_not_fatal(self, monkeypatch):
        answers = {f"m/{i}": {"content": f"answer {i}"} for i in range(3)}
        monkeypatch.setattr(orc, "ask_one", lambda *a, **k: ("no labels here", {}))
        points, notes = orc.cross_rank(answers, "q", "key", 100)
        assert points == {s: 0.0 for s in answers}
        assert len(notes) == 3
