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

# Council seats are the roster: they supply the alias table AND the default
# fusion panel, so there is no separate `panel` key to keep in step.
CFG = {
    "council": {
        "chair": "anthropic/claude-opus-4-8",
        "advisor_families": ["a", "b"],
        "seats": [
            {"slug": "a/one", "alias": "one", "family": "a", "score": 9.0,
             "basis": "eci"},
            {"slug": "b/two", "alias": "two", "family": "b", "score": 8.0,
             "basis": "eci"},
        ],
    },
    "models": [{"slug": "c/three", "alias": "three"}],
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


class TestFusionRequestBody:
    """The fusion request must not force tool use.

    On 2026-11-01 every fusion call with the Opus 5.5 chair failed with an
    opaque `Model call failed: invalid request (400)`. The same chair given a
    plain function tool and `tool_choice: "required"` showed the real cause,
    from Anthropic upstream: `tool_choice: type "tool" and "any" are not
    supported for this model.` Fusion is now requested by system instruction
    with `tool_choice: "auto"`, and fusion_result() fails closed if skipped.
    """

    def body(self, capsys):
        import argparse
        import json
        ns = argparse.Namespace(prompt="q", panel=None, dry_run=True)
        orc.cmd_fusion(ns, CFG)
        return json.loads(capsys.readouterr().out)

    def test_tool_choice_is_not_forced(self, capsys):
        assert self.body(capsys)["tool_choice"] not in ("required", "any")

    def test_system_message_asks_for_fusion_before_the_prompt(self, capsys):
        msgs = self.body(capsys)["messages"]
        assert msgs[0]["role"] == "system"
        assert "openrouter:fusion" in msgs[0]["content"]
        assert msgs[-1] == {"role": "user", "content": "q"}

    def test_skipped_tool_names_the_likely_cause(self, capsys):
        with pytest.raises(SystemExit):
            orc.fusion_result(good_response("answered directly"))
        assert "without calling fusion" in capsys.readouterr().err


def sse(*events):
    """Encode events as the byte lines urlopen yields for a stream."""
    import json
    out = [b": OPENROUTER PROCESSING\n", b"\n"]
    for e in events:
        out += [f"data: {json.dumps(e)}\n".encode(), b"\n"]
    return out + [b"data: [DONE]\n"]


class TestAssembleStream:
    """Every chat completion streams, because OpenRouter's edge closes a
    non-streamed request after 60 s of silence (a 4 KB fusion brief died at
    60.0 s with RemoteDisconnected on 2026-11-01). The reassembled response
    must look exactly like the non-streamed one to every reader."""

    def test_content_usage_and_fusion_record_reassemble(self):
        import json
        result = {"status": "ok", "models": ["a/one"], "analysis": {}}
        resp = orc.assemble_stream(sse(
            {"id": "gen-1", "model": "x/chair", "choices": [{"delta": {
                "role": "assistant", "content": "Hel",
                "reasoning_details": [{"type": "reasoning.server_tool_call",
                                       "tool_name": "openrouter:fusion",
                                       "result": json.dumps(result)}]}}]},
            {"id": "gen-1", "model": "x/chair", "choices": [{"delta": {"content": "lo"},
                                                             "finish_reason": "stop"}]},
            {"id": "gen-1", "choices": [], "usage": {"cost": 0.5}},
        ))
        assert orc.extract_content(resp) == "Hello"
        assert orc.fusion_result(resp) == result
        assert resp["id"] == "gen-1" and resp["model"] == "x/chair"
        assert resp["usage"] == {"cost": 0.5}

    def test_fragmented_reasoning_entries_are_joined(self):
        resp = orc.assemble_stream(sse(
            {"choices": [{"delta": {"reasoning_details": [
                {"type": "reasoning.text", "index": 0, "text": "thi"}]}}]},
            {"choices": [{"delta": {"reasoning_details": [
                {"type": "reasoning.text", "index": 0, "text": "nk"}]}}]},
        ))
        details = resp["choices"][0]["message"]["reasoning_details"]
        assert details == [{"type": "reasoning.text", "index": 0, "text": "think"}]

    def test_mid_stream_error_still_dies(self):
        resp = orc.assemble_stream(sse(
            {"choices": [{"delta": {"content": "partial"}}]},
            {"error": {"code": 502, "message": "provider disconnected"},
             "choices": [{"delta": {}, "finish_reason": "error"}]},
        ))
        with pytest.raises(SystemExit):
            orc.extract_content(resp)

    def test_starved_answer_is_still_detected(self):
        resp = orc.assemble_stream(sse(
            {"choices": [{"delta": {"content": ""}, "finish_reason": "length",
                          "native_finish_reason": "max_tokens"}]},
        ))
        assert orc.reasoning_starved(resp)

    def test_disconnect_dies_with_a_clear_message(self, monkeypatch, capsys):
        import http.client

        def boom(*a, **k):
            raise http.client.RemoteDisconnected("Remote end closed connection")
        monkeypatch.setattr(orc.urllib.request, "urlopen", boom)
        with pytest.raises(SystemExit):
            orc.post_json("https://example.invalid", {}, "k")
        assert "connection lost" in capsys.readouterr().err
