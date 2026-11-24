#!/usr/bin/env python3
"""Stdio-to-Streamable-HTTP MCP bridge using stdlib only.

Reads newline-delimited JSON-RPC messages from stdin, forwards each to a remote
MCP Streamable HTTP endpoint (spec 2025-03-26) with a Bearer token from an
environment variable, tracks `Mcp-Session-Id`, handles both `application/json`
and `text/event-stream` (SSE) responses, and emits newline-delimited JSON-RPC
messages on stdout.

Never prints tokens or Authorization headers to stdout or stderr.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import ssl
import sys
import urllib.parse
from typing import Any


def _emit(payload: Any, out: Any) -> None:
    if isinstance(payload, list):
        for item in payload:
            _emit(item, out)
        return
    out.write(json.dumps(payload, separators=(",", ":"), ensure_ascii=False) + "\n")
    out.flush()


def _parse_sse_events(body: str) -> list[Any]:
    """Parse SSE `data:` blocks into decoded JSON payloads."""
    events: list[Any] = []
    data_lines: list[str] = []

    def flush() -> None:
        if not data_lines:
            return
        raw = "\n".join(data_lines).strip()
        data_lines.clear()
        if not raw or raw == "[DONE]":
            return
        try:
            events.append(json.loads(raw))
        except json.JSONDecodeError:
            pass

    for raw_line in body.splitlines():
        line = raw_line.rstrip("\r")
        if line == "":
            flush()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip(" "))
    flush()
    return events


def _make_error_response(req_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


class StreamableHttpBridge:
    def __init__(
        self,
        url: str,
        bearer_token: str,
        timeout: float = 60.0,
        protocol_version: str = "2025-03-26",
    ) -> None:
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError(f"invalid MCP HTTP URL: {url}")
        self.scheme = parsed.scheme
        self.host = parsed.hostname or ""
        self.port = parsed.port or (443 if self.scheme == "https" else 80)
        self.path = parsed.path or "/"
        if parsed.query:
            self.path = f"{self.path}?{parsed.query}"
        self.bearer_token = bearer_token
        self.timeout = timeout
        self.protocol_version = protocol_version
        self.session_id: str | None = None
        self.ssl_context = ssl.create_default_context() if self.scheme == "https" else None

    def _connect(self) -> http.client.HTTPConnection:
        if self.scheme == "https":
            return http.client.HTTPSConnection(
                self.host,
                self.port,
                timeout=self.timeout,
                context=self.ssl_context,
            )
        return http.client.HTTPConnection(self.host, self.port, timeout=self.timeout)

    def send_message(self, message: dict[str, Any]) -> list[Any]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": f"Bearer {self.bearer_token}",
            "MCP-Protocol-Version": self.protocol_version,
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id

        body_bytes = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        conn = self._connect()
        try:
            conn.request("POST", self.path, body=body_bytes, headers=headers)
            resp = conn.getresponse()
            raw_body = resp.read().decode("utf-8", errors="replace")
            status = resp.status
            content_type = (resp.getheader("Content-Type") or "").lower()
            sid = resp.getheader("Mcp-Session-Id")
            if sid:
                self.session_id = sid
        finally:
            conn.close()

        has_id = "id" in message and message["id"] is not None
        if status == 202 or (status == 204) or (200 <= status < 300 and not raw_body.strip()):
            return []

        if status >= 400:
            if has_id:
                snippet = raw_body.strip()[:300]
                return [
                    _make_error_response(
                        message["id"],
                        -32000,
                        f"MCP HTTP {status}: {snippet}" if snippet else f"MCP HTTP {status}",
                    )
                ]
            return []

        if "text/event-stream" in content_type:
            return _parse_sse_events(raw_body)

        if raw_body.strip():
            parsed = json.loads(raw_body)
            return parsed if isinstance(parsed, list) else [parsed]
        return []

    def serve(self, inp: Any, out: Any) -> int:
        for line in inp:
            stripped = line.strip()
            if not stripped:
                continue
            try:
                message = json.loads(stripped)
            except json.JSONDecodeError as exc:
                print(f"mcp-http-stdio-bridge: invalid JSON on stdin: {exc}", file=sys.stderr)
                continue
            if not isinstance(message, dict):
                continue

            if message.get("method") == "initialize":
                params = message.get("params")
                if isinstance(params, dict) and isinstance(params.get("protocolVersion"), str):
                    self.protocol_version = params["protocolVersion"]

            try:
                responses = self.send_message(message)
            except Exception as exc:  # noqa: BLE001
                req_id = message.get("id")
                if req_id is not None:
                    _emit(
                        _make_error_response(req_id, -32000, f"MCP bridge transport error: {exc}"),
                        out,
                    )
                else:
                    print(f"mcp-http-stdio-bridge: transport error: {exc}", file=sys.stderr)
                continue

            for resp in responses:
                _emit(resp, out)
        return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Remote MCP Streamable HTTP endpoint URL")
    parser.add_argument(
        "--bearer-env",
        required=True,
        help="Environment variable holding the Bearer token",
    )
    parser.add_argument(
        "--token-prefix",
        default="",
        help="Optional required prefix for the token (e.g. 'xoxp-')",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
        help="Per-request HTTP timeout in seconds (default: 60)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    token = os.environ.get(args.bearer_env, "")
    if not token or any(ch.isspace() for ch in token):
        print(
            f"mcp-http-stdio-bridge: {args.bearer_env} is missing or invalid",
            file=sys.stderr,
        )
        return 1
    if args.token_prefix and not token.startswith(args.token_prefix):
        print(
            f"mcp-http-stdio-bridge: {args.bearer_env} must start with {args.token_prefix!r}",
            file=sys.stderr,
        )
        return 1

    bridge = StreamableHttpBridge(url=args.url, bearer_token=token, timeout=args.timeout)
    return bridge.serve(sys.stdin, sys.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
