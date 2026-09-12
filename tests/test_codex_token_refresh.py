"""Keeping the Codex CLI token alive for the statusline's quota read.

The timestamps below are the real shapes written by the Codex CLI (Rust, so
nanosecond precision, which datetime.fromisoformat will not take before Python
3.11). No token, account id or email appears here.
"""

import datetime
import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

REFRESH = Path(__file__).resolve().parent.parent / "custom_bins" / "codex-token-refresh"
_loader = importlib.machinery.SourceFileLoader("codex_token_refresh", str(REFRESH))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
refresh = importlib.util.module_from_spec(_spec)
_loader.exec_module(refresh)


def write_auth(home: Path, stamp: str | None) -> None:
    home.mkdir(parents=True, exist_ok=True)
    body: dict = {"auth_mode": "chatgpt", "tokens": {"account_id": "redacted"}}
    if stamp is not None:
        body["last_refresh"] = stamp
    (home / "auth.json").write_text(json.dumps(body))


def iso(when: datetime.datetime) -> str:
    """Nanosecond precision, the way the CLI writes it."""
    return when.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f000Z")


class TestTimestampParsing:
    def test_nanosecond_precision_is_accepted(self, tmp_path):
        """The real observed stamp.

        Note what this covers where. Python 3.11 accepts the Z suffix and a
        9-digit fraction outright, so on 3.11+ (this suite runs 3.14, the unit
        runs 3.12) it certifies the stdlib and passes with the truncation
        removed. On 3.10 -- the floor this file's PEP 604 annotations set, and
        what a 22.04 or RunPod box gives you -- fromisoformat rejects both and
        the truncation is the only reason this passes. It is kept for that box,
        not for this one.
        """
        write_auth(tmp_path, "2026-09-06T06:06:06.916739921Z")
        parsed = refresh.last_refresh(tmp_path)
        assert parsed is not None
        assert parsed.year == 2026 and parsed.month == 9 and parsed.day == 6
        assert parsed.tzinfo is not None

    def test_plain_second_precision(self, tmp_path):
        write_auth(tmp_path, "2026-09-06T06:06:06Z")
        assert refresh.last_refresh(tmp_path) is not None

    def test_missing_stamp(self, tmp_path):
        write_auth(tmp_path, None)
        assert refresh.last_refresh(tmp_path) is None

    def test_naive_stamp_is_assumed_utc(self, tmp_path):
        """A stamp with no offset must not come back naive.

        age_hours() subtracts it from an aware now(), so a naive value raises
        TypeError instead of being handled. The fractional branch above already
        coerces a naive stamp to UTC, so this one does too.
        """
        write_auth(tmp_path, "2026-09-06T06:06:06")
        parsed = refresh.last_refresh(tmp_path)
        assert parsed is not None
        assert parsed.tzinfo is not None, "naive stamp will detonate in age_hours()"
        refresh.age_hours(parsed)

    def test_unparseable_stamp(self, tmp_path):
        write_auth(tmp_path, "not a date")
        assert refresh.last_refresh(tmp_path) is None

    def test_absent_auth_file(self, tmp_path):
        assert refresh.last_refresh(tmp_path) is None

    def test_age_of_a_known_stamp(self, tmp_path):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=30)
        write_auth(tmp_path, iso(old))
        assert 29.5 < refresh.age_hours(refresh.last_refresh(tmp_path)) < 30.5


    def test_a_short_fraction_keeps_its_own_microseconds(self, tmp_path):
        """The offset must not be read as part of the fraction.

        Collecting every digit in the tail turns `.12+05:30` into 120530
        microseconds -- a stamp 0.12 s past the second read as 0.12053 s past
        it, and worse for other offsets. Unreachable while the CLI writes a
        fixed nine digits, which is why it is a nit and not a bug.
        """
        write_auth(tmp_path, "2026-09-06T06:06:06.12+05:30")
        parsed = refresh.last_refresh(tmp_path)
        assert parsed is not None
        assert parsed.microsecond == 120000
        assert parsed.utcoffset() == datetime.timedelta(hours=5, minutes=30)


class TestClockSkew:
    """Where the line sits between skew and a corrupt stamp.

    Frozen `now`, so the equality cases are exact rather than whatever the wall
    clock did between two statements.
    """

    NOW = datetime.datetime(2026, 9, 12, 12, 0, tzinfo=datetime.timezone.utc)

    def _ahead_by(self, **delta):
        return self.NOW + datetime.timedelta(**delta)

    def test_age_is_measured_against_the_given_now(self):
        stamp = self.NOW - datetime.timedelta(hours=30)
        assert refresh.age_hours(stamp, now=self.NOW) == 30.0

    def test_a_stamp_exactly_at_the_tolerance_is_not_ahead(self):
        stamp = self._ahead_by(hours=refresh.FUTURE_SKEW_TOLERANCE_HOURS)
        assert not refresh.stamp_is_ahead(stamp, now=self.NOW)

    def test_one_microsecond_past_the_tolerance_is_ahead(self):
        stamp = self._ahead_by(
            hours=refresh.FUTURE_SKEW_TOLERANCE_HOURS, microseconds=1)
        assert refresh.stamp_is_ahead(stamp, now=self.NOW)

    def test_a_few_seconds_ahead_is_ordinary_skew(self):
        assert not refresh.stamp_is_ahead(self._ahead_by(seconds=5), now=self.NOW)

    def test_hours_ahead_is_not_skew(self):
        assert refresh.stamp_is_ahead(self._ahead_by(hours=6), now=self.NOW)

    def test_a_stamp_in_the_past_is_never_ahead(self):
        assert not refresh.stamp_is_ahead(self._ahead_by(days=-4000), now=self.NOW)


class _Harness:
    """Shared rig: a private CODEX_HOME and a refresher that never leaves it."""

    @pytest.fixture(autouse=True)
    def _isolate(self, tmp_path, monkeypatch):
        self.home = tmp_path / ".codex"
        monkeypatch.setattr(refresh, "codex_home", lambda: self.home)
        monkeypatch.setattr(refresh.shutil, "which", lambda name: "/usr/bin/codex")
        self.calls = []

    def _refresher(self, monkeypatch, *, advances: bool, succeeds: bool = True):
        def fake(executable, home):
            self.calls.append(executable)
            if advances:
                write_auth(home, iso(datetime.datetime.now(datetime.timezone.utc)))
            return succeeds
        monkeypatch.setattr(refresh, "refresh", fake)

    def _run(self, monkeypatch, argv):
        monkeypatch.setattr(refresh.sys, "argv", ["codex-token-refresh", *argv])
        return refresh.main()


class TestSpendDecision(_Harness):
    """Whether a run spends a real upstream request."""

    def test_a_fresh_token_is_left_alone(self, monkeypatch):
        write_auth(self.home, iso(datetime.datetime.now(datetime.timezone.utc)))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert self.calls == [], "spent a request on a token that did not need it"

    def test_an_aged_token_is_refreshed(self, monkeypatch):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=30)
        write_auth(self.home, iso(old))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert len(self.calls) == 1

    def test_force_spends_even_on_a_fresh_token(self, monkeypatch):
        write_auth(self.home, iso(datetime.datetime.now(datetime.timezone.utc)))
        self._refresher(monkeypatch, advances=False)
        assert self._run(monkeypatch, ["--force"]) == refresh.OK
        assert len(self.calls) == 1

    def test_force_on_a_valid_token_is_not_a_failure(self, monkeypatch):
        """Codex rewrites auth.json only when it actually refreshes, so a
        still-valid token legitimately does not advance. That is success."""
        write_auth(self.home, iso(datetime.datetime.now(datetime.timezone.utc)))
        self._refresher(monkeypatch, advances=False)
        assert self._run(monkeypatch, ["--force"]) == refresh.OK

    def test_an_aged_token_that_will_not_advance_is_a_failure(self, monkeypatch):
        """The real breakage: old token, request made, still old afterwards."""
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=6)
        write_auth(self.home, iso(old))
        self._refresher(monkeypatch, advances=False)
        assert self._run(monkeypatch, []) == refresh.FAILED

    def test_a_failed_request_reports_failure(self, monkeypatch):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=6)
        write_auth(self.home, iso(old))
        self._refresher(monkeypatch, advances=False, succeeds=False)
        assert self._run(monkeypatch, []) == refresh.FAILED

    def test_threshold_is_configurable(self, monkeypatch):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=8)
        write_auth(self.home, iso(old))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, ["--max-age-hours", "6"]) == refresh.OK
        assert len(self.calls) == 1, "8h-old token should refresh under a 6h threshold"

    def test_an_aged_naive_stamp_does_not_crash_the_run(self, monkeypatch):
        """The crash site: a stamp with no offset reached age_hours() raw."""
        write_auth(self.home, "2026-09-06T06:06:06")
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert len(self.calls) == 1

    def test_not_logged_in_is_not_a_failure(self, monkeypatch):
        """A box that never uses Codex must not run a failing unit daily."""
        assert self._run(monkeypatch, []) == refresh.UNAVAILABLE
        assert self.calls == []

    def test_codex_absent_with_a_token_present_is_a_failure(self, monkeypatch):
        """A credential that exists and cannot be refreshed is not a quiet state.

        The unit treats exit 2 as success, so returning UNAVAILABLE here would
        stay green while the token it guards ages out. Only a missing auth.json
        -- nothing to keep fresh -- is quiet.
        """
        write_auth(self.home, iso(datetime.datetime.now(datetime.timezone.utc)))
        monkeypatch.setattr(refresh.shutil, "which", lambda name: None)
        assert self._run(monkeypatch, []) == refresh.FAILED
        assert self.calls == []

    def test_a_token_exactly_at_the_threshold_refreshes(self, monkeypatch):
        """The comparison is strict: at the threshold the token is already old."""
        at = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=6)
        write_auth(self.home, iso(at))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, ["--max-age-hours", "6"]) == refresh.OK
        assert len(self.calls) == 1, "a token at the threshold was read as fresh"


class TestAStampFromTheFuture(_Harness):
    """A stamp ahead of the clock must not read as "refreshed moments ago".

    age_hours() goes negative there, and a negative age is below every
    threshold, so the tool left the token alone, exited 0 and kept the unit
    green while nothing refreshed -- the staleness this tool exists to end,
    arriving through the opposite sign. A stamp whose age cannot be trusted is
    treated as stale, not as fresh.
    """

    def _stamp(self, **delta):
        now = datetime.datetime.now(datetime.timezone.utc)
        return iso(now + datetime.timedelta(**delta))

    def test_a_few_seconds_ahead_is_left_alone(self, monkeypatch, capsys):
        """Two clocks disagreeing by seconds is noise, not corruption."""
        write_auth(self.home, self._stamp(seconds=5))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert self.calls == [], "spent a request on ordinary clock skew"
        assert capsys.readouterr().out == "Token refreshed 0.0 h ago; leaving it.\n"

    def test_hours_ahead_spends_a_request(self, monkeypatch, capsys):
        write_auth(self.home, self._stamp(hours=6))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert len(self.calls) == 1, "a stamp 6 h ahead was read as fresh"
        assert capsys.readouterr().out.strip() == "Token refreshed."

    def test_years_ahead_that_does_not_correct_is_a_failure(self, monkeypatch, capsys):
        """The decades-green case: ten years ahead, and nothing rewrites it."""
        write_auth(self.home, self._stamp(days=3650))
        self._refresher(monkeypatch, advances=False)
        assert self._run(monkeypatch, []) == refresh.FAILED
        assert len(self.calls) == 1
        assert "ahead of the clock" in capsys.readouterr().out

    def test_years_ahead_self_heals_when_the_refresh_lands(self, monkeypatch):
        """The likely cause is a clock that ran ahead when Codex wrote the
        stamp, so the refresh usually corrects the file by itself."""
        write_auth(self.home, self._stamp(days=3650))
        self._refresher(monkeypatch, advances=True)
        assert self._run(monkeypatch, []) == refresh.OK
        assert not refresh.stamp_is_ahead(refresh.last_refresh(self.home))

    def test_a_refresh_that_writes_a_future_stamp_is_not_success(self, monkeypatch):
        """The reporting side of the same root cause: an aged token, a request
        made, and a stamp afterwards that cannot be believed."""
        write_auth(self.home, self._stamp(days=-6))
        ahead = self._stamp(hours=8)

        def fake(executable, home):
            self.calls.append(executable)
            write_auth(home, ahead)
            return True

        monkeypatch.setattr(refresh, "refresh", fake)
        assert self._run(monkeypatch, []) == refresh.FAILED

    def test_the_json_report_names_the_skew(self, monkeypatch, capsys):
        """A red unit is read through --json, so the cause belongs in it."""
        write_auth(self.home, self._stamp(days=3650))
        self._refresher(monkeypatch, advances=False)
        assert self._run(monkeypatch, ["--json"]) == refresh.FAILED
        assert json.loads(capsys.readouterr().out)["stamp_ahead_of_clock"] is True
