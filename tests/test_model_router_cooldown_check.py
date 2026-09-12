"""Stale-cooldown detection for the model-router Codex upstream.

The payloads below are the real shapes observed in
~/.local/state/model-router/logs/cliproxyapi.log on 2026-09-09 and 2026-09-11,
with the account-identifying auth filename removed. No token, account id or
request content appears here.
"""

import importlib.machinery
import importlib.util
import time
from pathlib import Path

import pytest

CHECK = Path(__file__).resolve().parent.parent / "custom_bins" / "model-router-cooldown-check"
_loader = importlib.machinery.SourceFileLoader("model_router_cooldown_check", str(CHECK))
_spec = importlib.util.spec_from_loader(_loader.name, _loader)
cooldown = importlib.util.module_from_spec(_spec)
_loader.exec_module(cooldown)


# A local refusal. Note it quotes the upstream error that caused it, so the
# string "usage_limit_reached" is present even though nothing left the machine.
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

# The router's own selection log line, which carries the remaining cooldown.
SELECTION_LINE = (
    'auth unavailable: 1 of 1 candidate(s) for model "gpt-6-astra" (provider=codex) '
    "are in cooldown: [provider=codex, reason=quota, remaining=96h32m3s]"
)


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

    @pytest.mark.parametrize("text,expected", [
        ("remaining=96h32m3s", 96 * 3600 + 32 * 60 + 3),
        ("remaining=15m", 15 * 60),
        ("remaining=45s", 45),
        ("remaining=2h", 7200),
    ])
    def test_cooldown_remaining(self, text, expected):
        assert cooldown.cooldown_remaining(text) == expected

    def test_cooldown_remaining_absent(self):
        assert cooldown.cooldown_remaining(UPSTREAM_LIMIT) is None


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

    def test_a_recorded_genuine_limit_blocks_restarts(self):
        """Having confirmed the quota really is spent, stop bouncing the service."""
        now = time.time()
        cooldown.write_state(upstream_limit_resets_at=int(now + 3600))
        assert "genuine quota limit" in cooldown.restart_blocked(now)

    def test_an_elapsed_genuine_limit_stops_blocking(self):
        now = time.time()
        cooldown.write_state(upstream_limit_resets_at=int(now - 1))
        assert cooldown.restart_blocked(now) is None


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
                "kind": kind, "resets_at": None, "cooldown_remaining_s": None} | extra

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
        assert cooldown.read_state()["upstream_limit_resets_at"] == 1789436526

    def test_short_cooldown_is_ordinary_backoff(self, monkeypatch):
        self._probes(monkeypatch, self._result("local_cooldown", cooldown_remaining_s=120))
        code, _ = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert self.restarts == []

    def test_long_cooldown_is_reported_but_not_fixed_without_the_flag(self, monkeypatch):
        self._probes(monkeypatch, self._result("local_cooldown", cooldown_remaining_s=96 * 3600))
        code, result = cooldown.run(fix=False)
        assert code == cooldown.STALE
        assert self.restarts == []
        assert "--fix" in result["summary"]

    def test_stale_cooldown_is_cleared_and_confirmed(self, monkeypatch):
        """The observed incident: 96h lockout, quota actually fine."""
        self._probes(monkeypatch,
                     self._result("local_cooldown", cooldown_remaining_s=96 * 3600),
                     self._result("ok"))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.OK
        assert result["fixed"] is True
        assert len(self.restarts) == 1

    def test_a_real_lockout_survives_the_restart_and_is_recorded(self, monkeypatch):
        """Restarting settles it: if the quota is truly spent, say so and stand down."""
        self._probes(monkeypatch,
                     self._result("local_cooldown", cooldown_remaining_s=96 * 3600),
                     self._result("upstream_limit", resets_at=1789436526))
        code, result = cooldown.run(fix=True)
        assert code == cooldown.EXHAUSTED
        assert result["fixed"] is False
        assert cooldown.read_state()["upstream_limit_resets_at"] == 1789436526

    def test_recovery_clears_a_stale_recorded_limit(self, monkeypatch):
        cooldown.write_state(upstream_limit_resets_at=1789436526)
        self._probes(monkeypatch, self._result("ok"))
        code, _ = cooldown.run(fix=False)
        assert code == cooldown.OK
        assert cooldown.read_state()["upstream_limit_resets_at"] is None
