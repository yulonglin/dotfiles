"""Stale-cooldown detection for the model-router Codex upstream.

The payloads below are the real shapes observed in
~/.local/state/model-router/logs/cliproxyapi.log on 2026-09-09 and 2026-09-11,
with the account-identifying auth filename removed. No token, account id or
request content appears here.

Anything that decides whether to restart the service is exercised through the
real HTTP parser, in TestThroughTheRealProbe. Handing `run()` a probe dict
assembled by hand can certify a property the parser does not have: the first
version of this suite proved that a short cooldown is left alone by injecting a
duration the router never actually sends in a response body.
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


# A local refusal. Note it quotes the upstream error that caused it, so the
# string "usage_limit_reached" is present even though nothing left the machine.
# Note also what it does NOT carry: any indication of how long it will hold.
LOCAL_COOLDOWN = (
    '{"type":"error","error":{"type":"rate_limit_error","message":'
    '"All credentials for model gpt-6-astra are cooling down via provider codex '
    '(last error: usage_limit_reached: The usage limit has been reached)"}}'
)

# A genuine upstream refusal, round-tripped to OpenAI.
UPSTREAM_LIMIT = (
    '{"error":{"type":"usage_limit_reached","message":"The usage limit has been '
    'reached","plan_type":"prolite","resets_at":1789436526,"eligible_promo":null,'
    '"resets_in_seconds":568157}}'
)

# The router's own selection log line. It carries the remaining cooldown -- but
# it is a log line, not a response body, and this tool never reads the log.
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
    def test_resets_at_is_read_from_the_upstream_payload(self):
        assert cooldown.resets_at(UPSTREAM_LIMIT) == 1789436526

    def test_resets_at_absent_when_not_offered(self):
        assert cooldown.resets_at(LOCAL_COOLDOWN) is None

    def test_a_local_refusal_says_nothing_about_how_long_it_will_hold(self):
        """Why the age is measured locally: the body carries no duration.

        `remaining=` lives in the selection log line, which is not a response
        body and which this tool never reads.
        """
        assert "remaining" not in LOCAL_COOLDOWN
        assert "remaining=" in SELECTION_LINE


class TestCooldownAge:
    """The only clock this tool trusts is its own."""

    @pytest.fixture(autouse=True)
    def _isolate_state(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)

    def test_a_first_sighting_is_recorded_and_ages_nothing(self):
        now = time.time()
        assert cooldown.cooldown_age(now) == 0.0
        assert cooldown.read_state()["local_cooldown_since_unix"] == now

    def test_a_later_sighting_measures_from_the_first(self):
        now = time.time()
        cooldown.write_state(local_cooldown_since_unix=now - 3600)
        assert cooldown.cooldown_age(now) == pytest.approx(3600)

    def test_serving_normally_resets_the_clock(self):
        now = time.time()
        cooldown.write_state(local_cooldown_since_unix=now - 3600,
                             hold_restarts_until_unix=now + 3600)
        cooldown.clear_guards()
        assert cooldown.cooldown_age(now) == 0.0
        assert cooldown.restart_blocked(now) is None

    def test_a_timestamp_from_the_future_restarts_the_clock(self):
        """A clock jump backwards must not read as a days-old cooldown."""
        now = time.time()
        cooldown.write_state(local_cooldown_since_unix=now + 86400)
        assert cooldown.cooldown_age(now) == 0.0


class TestRestartGuard:
    @pytest.fixture(autouse=True)
    def _isolate_state(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)

    def test_nothing_blocks_a_first_restart(self):
        assert cooldown.restart_blocked(time.time()) is None

    def test_a_recent_restart_blocks_another(self):
        now = time.time()
        cooldown.write_state(last_restart_unix=now - 60)
        assert "settling" in cooldown.restart_blocked(now)

    def test_an_old_restart_does_not_block(self):
        now = time.time()
        cooldown.write_state(last_restart_unix=now - cooldown.RESTART_COOLDOWN_SECONDS - 1)
        assert cooldown.restart_blocked(now) is None

    def test_a_hold_blocks_restarts_while_it_lasts(self):
        """A confirmed limit or a failed bounce stops the next one."""
        now = time.time()
        cooldown.hold_restarts(now)
        assert "holding off restarts" in cooldown.restart_blocked(now + 60)

    def test_the_hold_expires_on_its_own(self):
        now = time.time()
        cooldown.hold_restarts(now)
        assert cooldown.restart_blocked(now + cooldown.CONFIRMED_HOLD_SECONDS + 1) is None

    def test_the_hold_is_hours_not_days(self):
        """Defect 1's ceiling, pinned: no local guard may outlive one workday."""
        assert cooldown.CONFIRMED_HOLD_SECONDS <= 12 * 3600


class TestThroughTheRealProbe:
    """No mocked probe: HTTP bodies go through the parser that ships.

    A restart decision made from a hand-built probe dict proves nothing about
    the payloads the router actually sends, so every restart-or-not assertion
    that matters lives here.
    """

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
        assert result["resets_at"] is None

    def test_a_first_undated_local_cooldown_is_never_restarted(self, monkeypatch):
        """Regression, defect 2: an ordinary brief cooldown got a restart.

        The real refusal body carries no duration, so the old short-cooldown
        guard could not fire and every first sighting reached restart_service.
        Nothing here distinguishes this from a cooldown that clears by itself a
        minute later, so the answer is to do nothing and look again next run.
        """
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        code, result = cooldown.run(fix=True)
        assert result["probe"]["kind"] == "local_cooldown"
        assert self.restarts == []
        assert result["fixed"] is False
        assert code == cooldown.STALE
        assert "stale" not in result["summary"].lower()

    def test_the_same_cooldown_still_holding_an_hour_later_is_cleared(self, monkeypatch):
        """The observed incident, once the age is one this tool measured."""
        cooldown.write_state(local_cooldown_since_unix=time.time() - 3600)
        self._http(monkeypatch, _refusal(LOCAL_COOLDOWN), _Response())
        code, result = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert result["fixed"] is True
        assert len(self.restarts) == 1

    def test_a_genuine_upstream_limit_is_never_restarted(self, monkeypatch):
        self._http(monkeypatch, _refusal(UPSTREAM_LIMIT))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert self.restarts == []

    def test_a_router_that_does_not_answer_touches_nothing(self, monkeypatch):
        self._http(monkeypatch, OSError("connection refused"))
        with pytest.raises(cooldown.CheckError):
            cooldown.run(fix=True)
        assert self.restarts == []


class TestDecisions:
    """The probe-and-decide table, with no network and no service touched."""

    @pytest.fixture(autouse=True)
    def _isolate(self, tmp_path, monkeypatch):
        monkeypatch.setattr(cooldown, "state_dir", lambda: tmp_path)
        monkeypatch.setattr(cooldown, "load_endpoint", lambda: ("http://127.0.0.1:8787/t/x", "x"))
        monkeypatch.setattr(cooldown, "codex_routes", lambda: ["gpt-6-astra"])
        self.restarts = []
        monkeypatch.setattr(cooldown, "restart_service",
                            lambda timeout: self.restarts.append(timeout))
        monkeypatch.setattr(cooldown, "wait_healthy", lambda base_url, deadline: True)

    def _probes(self, monkeypatch, *responses):
        queue = list(responses)
        monkeypatch.setattr(cooldown, "probe",
                            lambda base_url, token, model, timeout: queue.pop(0))

    @staticmethod
    def _result(kind, **extra):
        return {"status": 200 if kind == "ok" else 429, "elapsed_ms": 1.0,
                "kind": kind, "resets_at": None} | extra

    @staticmethod
    def _aged():
        """A local cooldown this tool has already watched for long enough."""
        cooldown.write_state(
            local_cooldown_since_unix=time.time() - cooldown.MIN_COOLDOWN_AGE_SECONDS - 60)

    def test_serving_normally_needs_no_action(self, monkeypatch):
        self._probes(monkeypatch, self._result("ok"))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert self.restarts == []

    def test_genuine_limit_is_never_restarted(self, monkeypatch):
        self._probes(monkeypatch, self._result("upstream_limit", resets_at=1789436526))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert self.restarts == []
        assert cooldown.restart_blocked(time.time()) is not None

    def test_a_confirmed_limit_does_not_lock_recovery_out_for_days(self, monkeypatch):
        """Regression, defect 1: upstream's deadline must not become local policy.

        A genuine limit advertising a reset 96 hours out used to be stored
        verbatim and then prohibit every restart until that timestamp -- so the
        one action that could discover the quota was already back was the one
        action forbidden. The confirmation now expires on our own clock.
        """
        now = time.time()
        self._probes(monkeypatch, self._result("upstream_limit", resets_at=int(now + 96 * 3600)))
        assert cooldown.run(fix=True)[0] == cooldown.EXHAUSTED
        assert cooldown.restart_blocked(now + 60) is not None
        assert cooldown.restart_blocked(now + 24 * 3600) is None

    def test_a_confirmed_limit_holds_even_with_no_deadline_offered(self, monkeypatch):
        """The hold does not depend on upstream having named a reset at all."""
        self._probes(monkeypatch, self._result("upstream_limit"))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert cooldown.restart_blocked(time.time() + 60) is not None

    def test_a_cooldown_seen_for_the_first_time_is_only_recorded(self, monkeypatch):
        self._probes(monkeypatch, self._result("local_cooldown"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.STALE
        assert self.restarts == []
        assert result["cooldown_age_s"] == 0
        assert cooldown.read_state()["local_cooldown_since_unix"]

    def test_an_aged_cooldown_is_reported_but_not_fixed_without_the_flag(self, monkeypatch):
        self._aged()
        self._probes(monkeypatch, self._result("local_cooldown"))
        code, result = cooldown.run(fix=False)
        assert code == cooldown.STALE
        assert self.restarts == []
        assert "--fix" in result["summary"]

    def test_stale_cooldown_is_cleared_and_confirmed(self, monkeypatch):
        """The observed incident: a lockout that outlived the real window."""
        self._aged()
        self._probes(monkeypatch, self._result("local_cooldown"), self._result("ok"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert result["fixed"] is True
        assert len(self.restarts) == 1
        assert cooldown.read_state()["local_cooldown_since_unix"] is None

    def test_a_real_lockout_survives_the_restart_and_holds(self, monkeypatch):
        """Restarting settles it: if the quota is truly spent, say so and stand down."""
        self._aged()
        self._probes(monkeypatch,
                     self._result("local_cooldown"),
                     self._result("upstream_limit", resets_at=1789436526))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert result["fixed"] is False
        assert cooldown.restart_blocked(time.time() + 60) is not None

    def test_a_restart_that_did_not_help_is_not_repeated_next_hour(self, monkeypatch):
        """A bounce that changed nothing must not become an hourly bounce."""
        self._aged()
        self._probes(monkeypatch,
                     self._result("local_cooldown"),
                     self._result("local_cooldown"))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert len(self.restarts) == 1
        assert cooldown.restart_blocked(time.time() + 3600) is not None

    def test_a_router_that_does_not_come_back_is_not_bounced_again(self, monkeypatch):
        """Every restart either ends with serving routes or records a hold."""
        self._aged()
        monkeypatch.setattr(cooldown, "wait_healthy", lambda base_url, deadline: False)
        self._probes(monkeypatch, self._result("local_cooldown"))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert len(self.restarts) == 1
        assert cooldown.restart_blocked(time.time() + 3600) is not None

    def test_an_active_hold_stops_a_second_restart(self, monkeypatch):
        cooldown.hold_restarts(time.time())
        self._aged()
        self._probes(monkeypatch, self._result("local_cooldown"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.STALE
        assert self.restarts == []
        assert "holding off restarts" in result["summary"]

    def test_recovery_is_attempted_once_the_hold_expires(self, monkeypatch):
        now = time.time()
        cooldown.write_state(hold_restarts_until_unix=now - 1)
        self._aged()
        self._probes(monkeypatch, self._result("local_cooldown"), self._result("ok"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert result["fixed"] is True

    def test_recovery_clears_a_recorded_hold(self, monkeypatch):
        cooldown.write_state(hold_restarts_until_unix=time.time() + 3600,
                             local_cooldown_since_unix=time.time() - 3600)
        self._probes(monkeypatch, self._result("ok"))
        code, _ = cooldown.run(fix=False)
        assert code == cooldown.OK
        assert cooldown.restart_blocked(time.time()) is None
        assert cooldown.read_state()["local_cooldown_since_unix"] is None

    def test_an_unexpected_response_touches_nothing(self, monkeypatch):
        self._probes(monkeypatch, self._result("error", status=500))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.UNKNOWN
        assert self.restarts == []

    def test_an_error_between_cooldowns_restarts_the_age_clock(self, monkeypatch):
        """A router flapping must not accumulate its way into a restart.

        The neighbouring spelling of defect 2: the age is only evidence when it
        measures one uninterrupted run of refusals, so anything else resets it.
        """
        self._aged()
        self._probes(monkeypatch, self._result("error", status=500))
        assert cooldown.run(fix=True)[0] == cooldown.UNKNOWN
        self._probes(monkeypatch, self._result("local_cooldown"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.STALE
        assert result["cooldown_age_s"] == 0
        assert self.restarts == []

    def test_a_confirmed_limit_also_restarts_the_age_clock(self, monkeypatch):
        """The refusal that comes back after a real limit is a new one."""
        self._aged()
        self._probes(monkeypatch, self._result("upstream_limit"))
        assert cooldown.run(fix=True)[0] == cooldown.EXHAUSTED
        assert cooldown.read_state()["local_cooldown_since_unix"] is None
