"""Keeping the Codex CLI token alive for the statusline's quota read.

The timestamps below are the real shapes written by the Codex CLI (Rust, so
nanosecond precision, which datetime.fromisoformat will not take). No token,
account id or email appears here.
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
        """The real observed stamp. datetime.fromisoformat rejects 9 digits."""
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

    def test_unparseable_stamp(self, tmp_path):
        write_auth(tmp_path, "not a date")
        assert refresh.last_refresh(tmp_path) is None

    def test_absent_auth_file(self, tmp_path):
        assert refresh.last_refresh(tmp_path) is None

    def test_age_of_a_known_stamp(self, tmp_path):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=30)
        write_auth(tmp_path, iso(old))
        assert 29.5 < refresh.age_hours(refresh.last_refresh(tmp_path)) < 30.5


class TestSpendDecision:
    """Whether a run spends a real upstream request."""

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

    def test_not_logged_in_is_not_a_failure(self, monkeypatch):
        """A box that never uses Codex must not run a failing unit daily."""
        assert self._run(monkeypatch, []) == refresh.UNAVAILABLE
        assert self.calls == []

    def test_codex_absent_is_not_a_failure(self, monkeypatch):
        write_auth(self.home, iso(datetime.datetime.now(datetime.timezone.utc)))
        monkeypatch.setattr(refresh.shutil, "which", lambda name: None)
        assert self._run(monkeypatch, []) == refresh.UNAVAILABLE
