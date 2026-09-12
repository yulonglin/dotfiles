"""Cooldown reporting for the model-router Codex upstream, and its one restart rule.

The payloads below are the real shapes observed in
~/.local/state/model-router/logs/cliproxyapi.log on 2026-09-09 and 2026-09-11, with the
account-identifying auth filename removed. No token, account id or request content
appears here.

Every restart-or-not assertion goes through the real HTTP parser, in
TestThroughTheRealProbe. Handing `run()` a probe dict assembled by hand certifies a
property the parser does not have, which is how two defects reached review wearing green
badges: one test injected a duration the router never sends, and a later pair injected
probe results instead of driving the exception paths the failures used.

The tests seeded with `local_cooldown_since_unix` are seeding a key the current code never
reads. It is deliberate: it is what the previous design measured, so those tests fail
against that design on behaviour -- a restart that happens -- rather than on a missing
symbol.
"""

import importlib.machinery
import importlib.util
import io
import time
import urllib.error
from pathlib import Path

import pytest

CHECK = Path(__file__).resolve().parent.parent / "custom_bins" / "model-router-cooldown-check"
_loader = importlib.machinery.SourceFileLoader("model_router_cooldown_check", str(CHECK))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
cooldown = importlib.util.module_from_spec(_spec)
_loader.exec_module(cooldown)


# A local refusal. Note it quotes the upstream error that caused it, so the string
# "usage_limit_reached" is present even though nothing left the machine. Note also what it
# does NOT carry: any indication of how long it will hold.
LOCAL_COOLDOWN = (
    '{"type":"error","error":{"type":"rate_limit_error","message":'
    '"All credentials for model gpt-6-astra are cooling down via provider codex '
    '(last error: usage_limit_reached: The usage limit has been reached)"}}'
)

# A genuine upstream refusal, round-tripped to OpenAI. `resets_in_seconds` is the field
# the one restart rule is built on: a duration, so it elapses on our own clock.
UPSTREAM_LIMIT = (
    '{"error":{"type":"usage_limit_reached","message":"The usage limit has been '
    'reached","plan_type":"prolite","resets_at":1789436526,"eligible_promo":null,'
    '"resets_in_seconds":568157}}'
)

# The same refusal without a duration. Upstream is not obliged to name one.
UPSTREAM_LIMIT_NO_WINDOW = (
    '{"error":{"type":"usage_limit_reached","message":"The usage limit has been reached"}}'
)

# The router's own selection log line. It carries the remaining cooldown -- but it is a
# log line, not a response body, and this tool never reads the log.
SELECTION_LINE = (
    'auth unavailable: 1 of 1 candidate(s) for model "gpt-6-astra" (provider=codex) '
    "are in cooldown: [provider=codex, reason=quota, remaining=96h32m3s]"
)


class _Response:
    """A 200 from the router, in the shape urllib's opener hands back."""

    def __init__(self, body="{}"):
        self.status = 200
        self._body = body.encode()

    def read(self, size=None):
        return self._body if size is None else self._body[:size]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class _Opener:
    """Stands in for urllib's opener and serves a queue of outcomes."""

    def __init__(self, outcomes):
        self.outcomes = list(outcomes)

    def open(self, request, timeout=None):
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome


def _refusal(body, status=429):
    return urllib.error.HTTPError(
        "http://127.0.0.1:8787/t/x/v1/messages", status, "refused", {},
        io.BytesIO(body.encode()))


def _expired_window(now, window_s=3600, age_s=7200):
    """A limit this tool watched itself whose own window has since run out."""
    return {"at_unix": now - age_s, "window_s": window_s, "model": "gpt-6-astra"}


class TestClassify:
    def test_success_is_ok(self):
        assert cooldown.classify(200, "") == "ok"

    def test_local_cooldown_wins_over_the_quoted_upstream_error(self):
        """The bug this tool exists to catch: both strings are present."""
        assert "usage_limit_reached" in LOCAL_COOLDOWN
        assert cooldown.classify(429, LOCAL_COOLDOWN) == "local_cooldown"

    def test_genuine_upstream_limit(self):
        assert cooldown.classify(429, UPSTREAM_LIMIT) == "upstream_limit"

    def test_selection_log_shape_also_reads_as_local(self):
        assert cooldown.classify(429, SELECTION_LINE) == "local_cooldown"

    def test_unknown_429_is_plain_rate_limiting(self):
        assert cooldown.classify(429, '{"error":"slow down"}') == "rate_limited"

    def test_non_429_failure_is_error(self):
        assert cooldown.classify(500, "boom") == "error"


class TestPayloadParsing:
    def test_the_window_is_read_from_a_genuine_upstream_refusal(self):
        assert cooldown.resets_in_seconds(UPSTREAM_LIMIT) == 568157

    def test_a_genuine_refusal_need_not_name_a_window(self):
        assert cooldown.resets_in_seconds(UPSTREAM_LIMIT_NO_WINDOW) is None

    def test_a_local_refusal_says_nothing_about_how_long_it_will_hold(self):
        """Why sightings prove nothing: the body carries no duration at all.

        `remaining=` lives in the selection log line, which is not a response body and
        which this tool never reads.
        """
        assert cooldown.resets_in_seconds(LOCAL_COOLDOWN) is None
        assert "remaining" not in LOCAL_COOLDOWN
        assert "remaining=" in SELECTION_LINE


class TestStateDurability:
    @pytest.fixture(autouse=True)
    def _isolate_state(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)

    def test_a_write_that_lands_reads_back_true(self):
        assert cooldown.write_state(hold_restarts_until_unix=123.0) is True
        assert cooldown.read_state()["hold_restarts_until_unix"] == 123.0

    def test_a_write_that_cannot_land_says_so(self, monkeypatch):
        monkeypatch.setattr(cooldown.Path, "write_text", _unwritable)
        assert cooldown.write_state(hold_restarts_until_unix=123.0) is False


def _unwritable(self, *args, **kwargs):
    raise OSError("read-only file system")


class TestRecordedLimit:
    """The only evidence a restart may rest on, and the ways it is refused."""

    @pytest.fixture(autouse=True)
    def _isolate_state(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)

    def test_nothing_recorded_is_no_evidence(self):
        assert cooldown.recorded_limit(time.time()) is None

    def test_the_window_expires_on_our_clock_from_when_we_saw_it(self):
        now = time.time()
        cooldown.write_state(observed_limit={"at_unix": now, "window_s": 600, "model": "m"})
        assert cooldown.recorded_limit(now)["expires_unix"] == now + 600

    def test_a_record_from_the_future_is_no_evidence(self):
        """A clock jump backwards must not present an unexpired window as expired."""
        now = time.time()
        cooldown.write_state(observed_limit={"at_unix": now + 86400, "window_s": 60, "model": "m"})
        assert cooldown.recorded_limit(now) is None

    def test_a_malformed_record_is_no_evidence(self):
        cooldown.write_state(observed_limit={"at_unix": "yesterday", "window_s": None})
        assert cooldown.recorded_limit(time.time()) is None


class TestRestartHold:
    @pytest.fixture(autouse=True)
    def _isolate_state(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)

    def test_nothing_holds_a_first_bounce(self):
        assert cooldown.restart_hold(time.time()) is None

    def test_arming_holds_the_next_one_and_spends_the_evidence(self):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        assert cooldown.arm_restart_hold(now) is True
        assert "standing down" in cooldown.restart_hold(now + 60)
        assert cooldown.recorded_limit(now) is None

    def test_the_hold_expires_on_its_own(self):
        now = time.time()
        cooldown.arm_restart_hold(now)
        assert cooldown.restart_hold(now + cooldown.RESTART_HOLD_SECONDS + 1) is None

    def test_the_hold_is_hours_not_days(self):
        """No local guard may outlive one workday: that is the outage being watched for."""
        assert cooldown.RESTART_HOLD_SECONDS <= 12 * 3600

    def test_arming_reports_failure_when_it_cannot_be_written(self, monkeypatch):
        monkeypatch.setattr(cooldown.Path, "write_text", _unwritable)
        assert cooldown.arm_restart_hold(time.time()) is False


class TestThroughTheRealProbe:
    """No mocked probe: HTTP bodies go through the parser that ships."""

    @pytest.fixture(autouse=True)
    def _isolate(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)
        monkeypatch.setattr(cooldown, "load_endpoint", lambda: ("http://127.0.0.1:8787/t/x", "x"))
        monkeypatch.setattr(cooldown, "codex_routes", lambda: ["gpt-6-astra"])
        self.restarts = []
        monkeypatch.setattr(cooldown, "restart_service",
                            lambda timeout: self.restarts.append(timeout))
        monkeypatch.setattr(cooldown, "wait_healthy", lambda base_url, deadline: True)

    def _http(self, monkeypatch, *outcomes):
        opener = _Opener(outcomes)
        monkeypatch.setattr(cooldown.urllib.request, "build_opener", lambda *a, **k: opener)

    def test_the_real_local_refusal_parses_as_a_local_cooldown(self, monkeypatch):
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN))
        result = cooldown.probe("http://127.0.0.1:8787/t/x", "x", "gpt-6-astra", 1.0)
        assert result["kind"] == "local_cooldown"
        assert result["resets_in_s"] is None

    def test_two_sightings_an_hour_apart_are_not_one_hour_of_cooldown(self, monkeypatch):
        """Finding 3, the reason the age heuristic is gone rather than patched again.

        Between the two runs the routes may have served every request that was actually
        made. Time between observations is not persistence of one refusal, so no number
        of sightings may reach a restart.
        """
        now = time.time()
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN))
        cooldown.run(fix=True)
        monkeypatch.setattr(cooldown.time, "time", lambda: now + 3600)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert result["fixed"] is False

    def test_a_local_cooldown_with_no_observed_limit_is_only_reported(self, monkeypatch):
        """Three days of sightings still buy nothing, because they establish nothing."""
        cooldown.write_state(local_cooldown_since_unix=time.time() - 3 * 86400)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert result["fixed"] is False
        assert "never saw that limit itself" in " ".join(result["undetermined"])

    def test_the_report_says_what_it_saw_and_what_it_could_not_establish(self, monkeypatch):
        """Declining is the main output now, so it has to be worth reading."""
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN))
        _, result = cooldown.run(fix=False)
        rendered = cooldown.render(result)
        assert "never left this machine" in rendered
        assert "cannot say" in rendered
        assert "in cooldown" in rendered and "quota page" in rendered

    def test_a_genuine_upstream_limit_records_its_window_and_restarts_nothing(self, monkeypatch):
        self._http(monkeypatch, _refusal(UPSTREAM_LIMIT))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert self.restarts == []
        assert cooldown.read_state()["observed_limit"]["window_s"] == 568157

    def test_a_genuine_limit_naming_no_window_records_nothing_actionable(self, monkeypatch):
        """No duration means no clock to run, so that limit can never authorise a bounce."""
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        self._http(monkeypatch, _refusal(UPSTREAM_LIMIT_NO_WINDOW))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert cooldown.read_state()["observed_limit"] is None
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        cooldown.run(fix=True)
        assert self.restarts == []

    def test_a_limit_still_inside_its_own_window_is_not_restarted(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit={"at_unix": now - 60, "window_s": 3600, "model": "m"})
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert "of its own window to run" in result["summary"]

    def test_a_limit_that_outlived_its_own_window_is_the_one_restart(self, monkeypatch):
        """The whole remaining scope: observed limit, its window expired, still refusing."""
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        code, result = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert result["fixed"] is True
        assert self.restarts == [15.0]
        assert cooldown.read_state()["observed_limit"] is None
        assert cooldown.restart_hold(time.time()) is None

    def test_that_restart_needs_the_flag(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN))
        _, result = cooldown.run(fix=False)
        assert self.restarts == []
        assert "--fix" in result["summary"]

    def test_a_confirmation_probe_that_raises_still_leaves_the_hold_recorded(self, monkeypatch):
        """Finding 1: the hold is written before the bounce, so nothing can skip it.

        Cooldown at t=0, restart at t=1h, the confirmation probe times out. The old order
        wrote the hold after the second probe, so this path recorded none and the next
        hourly run bounced again.
        """
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now),
                             local_cooldown_since_unix=now - 3600)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), OSError("timed out"))
        with pytest.raises(cooldown.CheckError):
            cooldown.run(fix=True)
        assert len(self.restarts) == 1
        assert (cooldown.read_state().get("hold_restarts_until_unix") or 0) > now
        assert cooldown.read_state().get("observed_limit") is None
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        cooldown.run(fix=True)
        assert len(self.restarts) == 1

    def test_a_first_probe_that_raises_discards_the_recorded_window(self, monkeypatch):
        """Finding 2: a transport failure must invalidate the evidence, not preserve it.

        Refusal at t=0, timeout at t=1h, fresh refusal at t=2h. The old code carried the
        age across the timeout and restarted on it; the window recorded before a router
        we can no longer reach is worth the same nothing.
        """
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now),
                             local_cooldown_since_unix=now - 3600)
        self._http(monkeypatch, OSError("timed out"))
        with pytest.raises(cooldown.CheckError):
            cooldown.run(fix=True)
        assert cooldown.read_state().get("observed_limit") is None
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert result["fixed"] is False

    def test_an_unwritable_state_file_refuses_to_restart(self, monkeypatch):
        """Finding 4: the documented fail-safe, now actually enforced.

        Suppressing the write while still trusting the stored evidence is a restart every
        hour, forever. A guard that cannot be recorded is a reason not to act.
        """
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now),
                             local_cooldown_since_unix=now - 3600)
        monkeypatch.setattr(cooldown.Path, "write_text", _unwritable)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert result["fixed"] is False
        assert str(cooldown.state_path()) in " ".join(result["undetermined"])

    def test_a_restart_that_did_not_clear_it_is_not_repeated(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _refusal(LOCAL_COOLDOWN))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert len(self.restarts) == 1
        assert cooldown.restart_hold(time.time() + 3600) is not None
        assert cooldown.read_state().get("observed_limit") is None

    def test_a_router_that_does_not_come_back_is_not_bounced_again(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        monkeypatch.setattr(cooldown, "wait_healthy", lambda base_url, deadline: False)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert len(self.restarts) == 1
        assert cooldown.restart_hold(time.time() + 3600) is not None

    def test_an_active_hold_stops_a_second_restart(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now),
                             hold_restarts_until_unix=now + 3600)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        _, result = cooldown.run(fix=True)
        assert self.restarts == []
        assert "standing down" in result["summary"]

    def test_serving_routes_clear_the_hold_and_the_observation(self, monkeypatch):
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now),
                             hold_restarts_until_unix=now + 3600)
        self._http(monkeypatch, _Response())
        code, _ = cooldown.run(fix=False)
        assert code == cooldown.OK
        assert cooldown.read_state()["observed_limit"] is None
        assert cooldown.restart_hold(time.time()) is None

    def test_an_unexpected_response_discards_the_window(self, monkeypatch):
        """A 5xx says nothing about the cooldown table, so the evidence lapses."""
        now = time.time()
        cooldown.write_state(observed_limit=_expired_window(now))
        self._http(monkeypatch, _refusal("boom", status=503))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert self.restarts == []
        assert cooldown.read_state().get("observed_limit") is None

    def test_a_router_that_does_not_answer_touches_nothing(self, monkeypatch):
        self._http(monkeypatch, OSError("connection refused"))
        with pytest.raises(cooldown.CheckError):
            cooldown.run(fix=True)
        assert self.restarts == []
