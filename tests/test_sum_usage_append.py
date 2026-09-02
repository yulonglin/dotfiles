"""Usage aggregation across a multi-call rung.

Split from test_council_roster.py only because the council rungs fan out: a
17-call run has no single response to take usage from, so logging the chair's
usage alone would understate what was spent by roughly 16x -- the one thing the
call log exists to record accurately.
"""

import importlib.machinery
import importlib.util
from pathlib import Path

_PATH = Path(__file__).resolve().parent.parent / "custom_bins" / "openrouter-cli"
_loader = importlib.machinery.SourceFileLoader("openrouter_cli", str(_PATH))
_spec = importlib.util.spec_from_loader("openrouter_cli", _loader)
orc = importlib.util.module_from_spec(_spec)
_loader.exec_module(orc)


class TestSumUsage:
    def test_adds_numeric_fields_across_calls(self):
        answers = {
            "a": {"usage": {"cost": 0.01, "total_tokens": 100}},
            "b": {"usage": {"cost": 0.02, "total_tokens": 50}},
        }
        assert orc.sum_usage(answers) == {"cost": 0.03, "total_tokens": 150}

    def test_ignores_nested_details_and_failed_calls(self):
        """`prompt_tokens_details` is a dict; adding it would raise."""
        answers = {
            "a": {"usage": {"cost": 0.01, "prompt_tokens_details": {"cached": 1}}},
            "b": {"error": "provider failed"},
        }
        assert orc.sum_usage(answers) == {"cost": 0.01}

    def test_empty_fan_out_is_empty_dict_not_none(self):
        assert orc.sum_usage({}) == {}
