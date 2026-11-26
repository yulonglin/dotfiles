"""Tests for custom_bins/obs-watchdog: the freeze and screen-stop decisions, the
BMP decoding, and the stdlib obs-websocket client against a fake server that
follows the obs-websocket v5 auth spec."""

from __future__ import annotations

import base64
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import socket
import struct
import threading
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "custom_bins" / "obs-watchdog"


def _load():
    loader = importlib.machinery.SourceFileLoader("obs_watchdog", str(SCRIPT))
    spec = importlib.util.spec_from_loader("obs_watchdog", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


wd = _load()


def _bmp(pixels: bytes) -> str:
    header = b"BM" + b"\0" * 8 + struct.pack("<I", 54) + b"\0" * 40
    return "data:image/bmp;base64," + base64.b64encode(header + pixels).decode()


def _noisy(seed: int) -> bytes:
    return hashlib.sha256(str(seed).encode()).digest() * 400


# ── frame_verdict ────────────────────────────────────────────────────────────


def test_live_camera_never_freezes():
    cam: dict = {}
    assert [wd.frame_verdict(_noisy(i), cam) for i in range(6)] == ["live"] * 6


def test_identical_frames_freeze_after_three_checks():
    cam: dict = {}
    frame = _noisy(1)
    assert [wd.frame_verdict(frame, cam) for _ in range(3)] == ["live", "same", "frozen"]


def test_flat_frame_is_never_called_frozen():
    cam: dict = {}
    dark = bytes([3]) * 9000
    assert [wd.frame_verdict(dark, cam) for _ in range(5)] == ["flat"] * 5


def test_a_new_frame_resets_the_count():
    cam: dict = {}
    a, b = _noisy(1), _noisy(2)
    verdicts = [wd.frame_verdict(f, cam) for f in (a, a, b, b, b)]
    assert verdicts == ["live", "same", "live", "same", "frozen"]


def test_bmp_pixels_skips_the_header():
    assert wd.bmp_pixels(_bmp(b"\x01\x02\x03")) == b"\x01\x02\x03"
    with pytest.raises(ValueError):
        wd.bmp_pixels("data:image/png;base64," + base64.b64encode(b"\x89PNG....").decode())


# ── pending_screen_stop ──────────────────────────────────────────────────────

LOG = (
    "14:01:42.709: Starting Virtual Camera output to Program\n"
    "20:37:40.459: [ mac-screencapture ]: Stream stopped as no capture source was not found.\n"
)


def test_screen_stop_is_pending_until_handled():
    idx = wd.pending_screen_stop("a.txt", LOG, {})
    assert idx == LOG.index("[ mac-screencapture ]")
    assert wd.pending_screen_stop("a.txt", LOG, {"log": "a.txt", "offset": idx}) is None


def test_a_later_stop_or_new_log_is_pending_again():
    idx = LOG.index("[ mac-screencapture ]")
    later = LOG + '21:10:00.000: [ mac-screencapture ]: Stream stopped with error -3821 ("x")\n'
    assert wd.pending_screen_stop("a.txt", later, {"log": "a.txt", "offset": idx}) > idx
    assert wd.pending_screen_stop("b.txt", LOG, {"log": "a.txt", "offset": idx}) == idx


def test_no_stop_line_means_nothing_pending():
    assert wd.pending_screen_stop("a.txt", "Starting Virtual Camera\n", {}) is None


# ── websocket client against a fake obs-websocket server ─────────────────────

PASSWORD = "hunter2-test"


def _serve(conn: socket.socket, seen: list) -> None:
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += conn.recv(4096)
    key = [l.split(b": ", 1)[1] for l in buf.split(b"\r\n") if l.lower().startswith(b"sec-websocket-key")][0]
    accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
    conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")

    def send(obj):  # server frames are unmasked; use the 16-bit length path
        data = json.dumps(obj).encode()
        conn.sendall(bytes([0x81, 126]) + struct.pack(">H", len(data)) + data)

    def recv():
        b0, b1 = conn.recv(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", conn.recv(2))[0]
        mask = conn.recv(4)
        data = b""
        while len(data) < n:
            data += conn.recv(n - len(data))
        return json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    salt, challenge = "c2FsdA==", "Y2hhbGxlbmdl"
    send({"op": 0, "d": {"rpcVersion": 1, "authentication": {"salt": salt, "challenge": challenge}}})
    ident = recv()
    secret = base64.b64encode(hashlib.sha256((PASSWORD + salt).encode()).digest()).decode()
    want = base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()
    if ident["d"].get("authentication") != want:
        conn.sendall(bytes([0x88, 2]) + struct.pack(">H", 4009))
        return
    send({"op": 2, "d": {"negotiatedRpcVersion": 1}})
    req = recv()["d"]
    seen.append(req)
    send({"op": 5, "d": {"eventType": "Noise"}})  # an event in between must be skipped
    ok = req["requestType"] != "Fail"
    send({"op": 7, "d": {"requestId": req["requestId"], "requestType": req["requestType"],
                         "requestStatus": {"result": ok, "code": 100 if ok else 600, "comment": "nope"},
                         "responseData": {"outputActive": True}}})


def _fake_server(seen: list) -> int:
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)

    def run():
        conn, _ = srv.accept()
        with conn:
            _serve(conn, seen)
        srv.close()

    threading.Thread(target=run, daemon=True).start()
    return srv.getsockname()[1]


def test_client_authenticates_and_calls():
    seen: list = []
    obs = wd.OBS(_fake_server(seen), PASSWORD, timeout=5)
    assert obs.call("GetVirtualCamStatus") == {"outputActive": True}
    assert seen[0]["requestType"] == "GetVirtualCamStatus"
    obs.close()


def test_wrong_password_is_a_connection_error():
    with pytest.raises(ConnectionError):
        wd.OBS(_fake_server([]), "wrong", timeout=5)


def test_failed_request_raises_obs_error():
    obs = wd.OBS(_fake_server([]), PASSWORD, timeout=5)
    with pytest.raises(wd.OBSError):
        obs.call("Fail")
    obs.close()


# ── setup ────────────────────────────────────────────────────────────────────


def test_setup_enables_websocket_and_keeps_password(tmp_path, monkeypatch):
    cfg = tmp_path / "config.json"
    cfg.write_text(json.dumps({"server_enabled": False, "auth_required": True,
                               "server_password": "keep-me", "server_port": 4455}))
    monkeypatch.setattr(wd, "WS_CONFIG", cfg)
    monkeypatch.setenv("OBS_WATCHDOG_ASSUME_PIDS", "")
    assert wd.setup() == 0
    data = json.loads(cfg.read_text())
    assert data["server_enabled"] is True and data["server_password"] == "keep-me"
    assert oct(os.stat(cfg).st_mode & 0o777) == "0o600"


def test_setup_generates_a_password_when_missing(tmp_path, monkeypatch):
    cfg = tmp_path / "plugin_config" / "config.json"
    monkeypatch.setattr(wd, "WS_CONFIG", cfg)
    monkeypatch.setenv("OBS_WATCHDOG_ASSUME_PIDS", "")
    assert wd.setup() == 0
    assert len(json.loads(cfg.read_text())["server_password"]) >= 24
