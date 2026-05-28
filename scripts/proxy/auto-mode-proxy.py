#!/usr/bin/env python3
"""Local Anthropic API proxy that swaps the auto-mode classifier model.

When Claude Code calls api.anthropic.com to classify a tool action for auto
mode, it sends a request whose system prompt starts with "You are a security
monitor for autonomous AI". When opus-4-7 capacity is tight, that request
fails and blocks every tool call.

This proxy listens on 127.0.0.1:18080 and forwards all traffic to
api.anthropic.com unchanged EXCEPT classifier requests, whose model field is
rewritten from claude-opus-4-* to claude-sonnet-4-6.

Activate by exporting ANTHROPIC_BASE_URL=http://127.0.0.1:18080 before
launching Claude Code. See config/auto-mode-proxy.plist for a launchd
template (NOT installed by default).

Inspired by github.com/grechman/auto-mode-fix-to-sonnet (Linux/systemd).
This file is the macOS/launchd port using only Python stdlib.
"""
from __future__ import annotations

import json
import logging
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError

UPSTREAM = "https://api.anthropic.com"
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("AUTO_MODE_PROXY_PORT", "18080"))
TARGET_MODEL = os.environ.get("AUTO_MODE_PROXY_TARGET", "claude-sonnet-4-6")
CLASSIFIER_FINGERPRINT = "You are a security monitor for autonomous AI"

LOG_PATH = os.path.expanduser("~/.cache/claude/auto-mode-proxy.log")
os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("auto-mode-proxy")


def _is_classifier_payload(body: bytes) -> bool:
    """Detect Claude Code's auto-mode classifier request by system prompt opener."""
    try:
        payload = json.loads(body)
    except (ValueError, TypeError):
        return False
    system = payload.get("system")
    if isinstance(system, str):
        return system.startswith(CLASSIFIER_FINGERPRINT)
    if isinstance(system, list):
        for block in system:
            if isinstance(block, dict):
                text = block.get("text", "")
                if isinstance(text, str) and text.startswith(CLASSIFIER_FINGERPRINT):
                    return True
    return False


def _rewrite_model(body: bytes) -> tuple[bytes, str | None]:
    """If this is a classifier request, rewrite the model field. Returns (new_body, original_model)."""
    try:
        payload = json.loads(body)
    except (ValueError, TypeError):
        return body, None
    original = payload.get("model")
    if not isinstance(original, str):
        return body, None
    if original.startswith("claude-opus") and _is_classifier_payload(body):
        payload["model"] = TARGET_MODEL
        return json.dumps(payload).encode("utf-8"), original
    return body, None


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:
        log.debug(format, *args)

    def _proxy(self, method: str) -> None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""

        new_body, original_model = _rewrite_model(body) if body else (body, None)
        if original_model:
            log.info("rewrote classifier model %s -> %s", original_model, TARGET_MODEL)

        url = UPSTREAM + self.path
        headers = {k: v for k, v in self.headers.items() if k.lower() != "host"}
        if new_body != body:
            headers["Content-Length"] = str(len(new_body))

        req = urlrequest.Request(url, data=new_body if new_body else None, headers=headers, method=method)
        try:
            with urlrequest.urlopen(req, timeout=60) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() in ("transfer-encoding", "connection"):
                        continue
                    self.send_header(k, v)
                self.end_headers()
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except HTTPError as e:
            log.warning("upstream HTTPError %s on %s", e.code, self.path)
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() in ("transfer-encoding", "connection"):
                    continue
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(e.read())
        except URLError as e:
            log.error("upstream URLError on %s: %s", self.path, e)
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            err = json.dumps({"error": {"type": "proxy_error", "message": str(e)}}).encode()
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)

    def do_GET(self) -> None:
        self._proxy("GET")

    def do_POST(self) -> None:
        self._proxy("POST")

    def do_PUT(self) -> None:
        self._proxy("PUT")

    def do_DELETE(self) -> None:
        self._proxy("DELETE")


def main() -> None:
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    log.info("listening on http://%s:%d -> %s (rewrite opus -> %s)", LISTEN_HOST, LISTEN_PORT, UPSTREAM, TARGET_MODEL)
    print(f"auto-mode-proxy listening on http://{LISTEN_HOST}:{LISTEN_PORT}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")


if __name__ == "__main__":
    main()
