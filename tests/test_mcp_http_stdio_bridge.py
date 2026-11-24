from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
from typing import Any

_BRIDGE_PATH = (
    Path(__file__).resolve().parents[1] / "scripts" / "helpers" / "mcp_http_stdio_bridge.py"
)
_SPEC = importlib.util.spec_from_file_location("mcp_http_stdio_bridge", _BRIDGE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
bridge_mod = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(bridge_mod)


class _FakeResponse:
    def __init__(self, status: int, headers: dict[str, str], body: bytes) -> None:
        self.status = status
        self._headers = {k.lower(): v for k, v in headers.items()}
        self._body = body

    def read(self) -> bytes:
        return self._body

    def getheader(self, name: str, default: str | None = None) -> str | None:
        return self._headers.get(name.lower(), default)


class _FakeConnection:
    def __init__(self, handler: Any) -> None:
        self._handler = handler
        self._response: _FakeResponse | None = None

    def request(
        self,
        method: str,
        path: str,
        body: bytes = b"",
        headers: dict[str, str] | None = None,
    ) -> None:
        self._response = self._handler(method, path, body, headers or {})

    def getresponse(self) -> _FakeResponse:
        assert self._response is not None
        return self._response

    def close(self) -> None:
        return


def test_bridge_handles_json_sse_notifications_and_session_id() -> None:
    seen_headers: list[dict[str, str]] = []

    def handler(
        method: str, path: str, body: bytes, headers: dict[str, str]
    ) -> _FakeResponse:
        assert method == "POST"
        assert path == "/mcp"
        payload = json.loads(body.decode("utf-8"))
        seen_headers.append(
            {
                "auth": headers.get("Authorization", ""),
                "sid": headers.get("Mcp-Session-Id", ""),
            }
        )
        rpc_method = payload.get("method")
        if rpc_method == "initialize":
            return _FakeResponse(
                200,
                {"Content-Type": "application/json", "Mcp-Session-Id": "sess-123"},
                json.dumps({"jsonrpc": "2.0", "id": payload["id"], "result": {"ok": True}}).encode(
                    "utf-8"
                ),
            )
        if rpc_method == "notifications/initialized":
            return _FakeResponse(202, {}, b"")
        if rpc_method == "tools/list":
            sse = (
                "event: message\n"
                'data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"slack_read_channel"}]}}\n\n'
            )
            return _FakeResponse(200, {"Content-Type": "text/event-stream"}, sse.encode("utf-8"))
        return _FakeResponse(401, {"Content-Type": "text/plain"}, b"unauthorized")

    bridge = bridge_mod.StreamableHttpBridge(
        url="https://mcp.slack.com/mcp", bearer_token="xoxp-secret-test"
    )
    bridge._connect = lambda: _FakeConnection(handler)  # type: ignore[method-assign]

    stdin_lines = "\n".join(
        [
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {"protocolVersion": "2025-03-26"},
                }
            ),
            json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}),
            json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}),
            json.dumps({"jsonrpc": "2.0", "id": 3, "method": "boom", "params": {}}),
        ]
    )
    out = io.StringIO()
    rc = bridge.serve(io.StringIO(stdin_lines + "\n"), out)
    assert rc == 0

    responses = [json.loads(line) for line in out.getvalue().strip().splitlines()]
    assert len(responses) == 3
    assert responses[0] == {"jsonrpc": "2.0", "id": 1, "result": {"ok": True}}
    assert responses[1]["id"] == 2
    assert responses[1]["result"]["tools"][0]["name"] == "slack_read_channel"
    assert responses[2]["id"] == 3
    assert "401" in responses[2]["error"]["message"]
    assert "xoxp-secret-test" not in out.getvalue()

    assert seen_headers[0] == {"auth": "Bearer xoxp-secret-test", "sid": ""}
    assert seen_headers[1] == {"auth": "Bearer xoxp-secret-test", "sid": "sess-123"}
    assert seen_headers[2] == {"auth": "Bearer xoxp-secret-test", "sid": "sess-123"}


def test_main_rejects_missing_or_wrong_prefix_token(monkeypatch: Any) -> None:
    monkeypatch.delenv("TEST_SLACK_TOKEN", raising=False)
    assert (
        bridge_mod.main(
            ["--url", "https://mcp.slack.com/mcp", "--bearer-env", "TEST_SLACK_TOKEN"]
        )
        == 1
    )

    monkeypatch.setenv("TEST_SLACK_TOKEN", "xoxb-wrong-type")
    assert (
        bridge_mod.main(
            [
                "--url",
                "https://mcp.slack.com/mcp",
                "--bearer-env",
                "TEST_SLACK_TOKEN",
                "--token-prefix",
                "xoxp-",
            ]
        )
        == 1
    )
