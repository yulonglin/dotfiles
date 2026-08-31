"""Response-contract tests for custom_bins/openrouter-cli.

OpenRouter embeds failures inside HTTP-200 bodies, and fusion keeps
status "ok" through partial panel collapse. These fixtures pin the
fail-closed behaviour so a refactor cannot quietly reopen either hole.
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

CFG = {
    "judge": "anthropic/claude-opus-4-8",
    "panel": ["a/one", "b/two"],
    "models": [
        {"slug": "a/one", "alias": "one"},
        {"slug": "b/two", "alias": "two"},
    ],
}


def good_response(content="fine"):
    return {"choices": [{"finish_reason": "stop", "message": {"content": content}}]}


class TestExtractContent:
    def test_good_content_passes_through(self):
        assert orc.extract_content(good_response("hello")) == "hello"

    def test_top_level_error_dies(self):
        with pytest.raises(SystemExit):
            orc.extract_content({"error": {"code": 429, "message": "limited"}})

    def test_no_choices_dies(self):
        with pytest.raises(SystemExit):
            orc.extract_content({"choices": []})

    def test_choice_level_error_dies_despite_partial_content(self):
        resp = {"choices": [{
            "finish_reason": "error",
            "error": {"code": 502, "message": "provider disconnected"},
            "message": {"content": "partial output before the crash"},
        }]}
        with pytest.raises(SystemExit):
            orc.extract_content(resp)

    def test_empty_content_dies(self):
        with pytest.raises(SystemExit):
            orc.extract_content(good_response("  "))

    def test_non_string_content_dies(self):
        with pytest.raises(SystemExit):
            orc.extract_content(good_response(None))


class TestParsePanel:
    def test_none_selects_config_default(self):
        assert orc.parse_panel(None, CFG) == ["a/one", "b/two"]

    def test_aliases_resolve(self):
        assert orc.parse_panel("one,two", CFG) == ["a/one", "b/two"]

    def test_explicit_empty_flag_dies_rather_than_widening_to_default(self):
        with pytest.raises(SystemExit):
            orc.parse_panel("", CFG)

    def test_blank_entry_dies(self):
        with pytest.raises(SystemExit):
            orc.parse_panel("one,,two", CFG)

    def test_duplicates_via_alias_and_slug_die(self):
        with pytest.raises(SystemExit):
            orc.parse_panel("one,a/one", CFG)

    def test_more_than_eight_die(self):
        spec = ",".join(f"x/m{i}" for i in range(9))
        with pytest.raises(SystemExit):
            orc.parse_panel(spec, CFG)


class TestFusionResult:
    def test_result_extracted_from_reasoning_details(self):
        resp = {"choices": [{"message": {"reasoning_details": [
            {"tool_name": "openrouter:fusion", "result": '{"status": "ok"}'},
        ]}}]}
        assert orc.fusion_result(resp) == {"status": "ok"}

    def test_missing_tool_record_dies(self):
        with pytest.raises(SystemExit):
            orc.fusion_result(good_response())

    def test_unparseable_result_dies(self):
        resp = {"choices": [{"message": {"reasoning_details": [
            {"tool_name": "openrouter:fusion", "result": "not json"},
        ]}}]}
        with pytest.raises(SystemExit):
            orc.fusion_result(resp)


class TestFusionIntegrity:
    PANEL = ["a/one", "b/two"]

    def full_result(self):
        # Live shape (flat `models` list), 2026-08-26.
        return {"status": "ok", "analysis": {"consensus": []}, "models": list(self.PANEL)}

    def test_full_panel_has_no_problems(self):
        assert orc.check_fusion_integrity(self.full_result(), self.PANEL) == []

    def test_docs_shape_responses_list_also_accepted(self):
        result = {"status": "ok", "analysis": {},
                  "responses": [{"model": m, "content": "x"} for m in self.PANEL]}
        assert orc.check_fusion_integrity(result, self.PANEL) == []

    def test_status_ok_with_failed_models_is_flagged(self):
        result = self.full_result()
        result["failed_models"] = [{"model": "b/two", "error": "timeout"}]
        assert any("failed panel models" in p
                   for p in orc.check_fusion_integrity(result, self.PANEL))

    def test_missing_panel_member_is_flagged(self):
        result = self.full_result()
        result["models"] = ["a/one"]
        assert any("no response from: b/two" in p
                   for p in orc.check_fusion_integrity(result, self.PANEL))

    def test_omitted_analysis_is_flagged(self):
        result = self.full_result()
        del result["analysis"]
        assert any("no structured analysis" in p
                   for p in orc.check_fusion_integrity(result, self.PANEL))

    def test_error_status_is_flagged(self):
        result = {"status": "error", "failure_reason": "all_models_failed"}
        assert any("fusion status 'error'" in p
                   for p in orc.check_fusion_integrity(result, self.PANEL))

    def test_no_participant_field_at_all_is_flagged(self):
        result = {"status": "ok", "analysis": {}}
        assert any("cannot verify the panel" in p
                   for p in orc.check_fusion_integrity(result, self.PANEL))
