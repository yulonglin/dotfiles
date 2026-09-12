#!/usr/bin/env python3
"""Validate router infrastructure once per installed Claude/router revision.

No upgrades, service changes or model-generation requests. SessionStart runs this
asynchronously; --force is the explicit post-update check used by the updater.
"""
import argparse
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request


MAX_REPORT = 32768
COOLDOWN = 300


def managed_env(env):
    """The `env` block of the model-router managed settings drop-in.

    Claude Code copies a settings `env` block into the process environment, so a
    hook a session launches already has ANTHROPIC_BASE_URL whichever settings
    level set it. A hook launched from a plain shell does not, and since the
    gateway keys moved to the root-owned drop-in the user settings file no
    longer carries them either, so read the drop-in before falling back to it.
    """
    path = env.get("MODEL_ROUTER_MANAGED") or (
        "/Library/Application Support/ClaudeCode/managed-settings.d/50-model-router.json"
        if sys.platform == "darwin"
        else "/etc/claude-code/managed-settings.d/50-model-router.json")
    try:
        block = json.loads(Path(path).read_text()).get("env")
    except (OSError, ValueError):
        return {}
    return block if isinstance(block, dict) else {}


def read_json(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def file_revision(path):
    try:
        resolved = path.resolve()
        info = resolved.stat()
        return [str(resolved), info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_ino]
    except OSError:
        return [str(path), "missing"]


def active_plugins(home):
    registry = read_json(home / ".claude/plugins/installed_plugins.json")
    plugins = registry.get("plugins", {})
    entries = plugins.get("model-router@alignment-hive", []) if isinstance(plugins, dict) else []
    return [entry for entry in entries if isinstance(entry, dict)] if isinstance(entries, list) else []


def fingerprint(home, binary):
    state = home / ".local/state/model-router"
    paths = [state / "launcher/binary-version", state / "launcher/bootstrap.sh"]
    entries = active_plugins(home)
    for entry in entries:
        if isinstance(entry.get("installPath"), str):
            root = Path(entry["installPath"])
            paths.extend([root / ".claude-plugin/plugin.json", root / "binary-version",
                          root / "scripts/bootstrap.sh"])
    revisions = [[str(path), file_revision(path),
                  path.read_text()[:4096] if path.name == "binary-version" and path.is_file() else None]
                 for path in paths]
    data = [file_revision(binary), entries, revisions]
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def versions_ready(home, base_url):
    """A plugin refresh may still be replacing the stable launcher/live service."""
    entries = active_plugins(home)
    if not entries:
        # The smoke test reports an absent plugin; no extra version claim here.
        return True
    pins = set()
    for entry in entries:
        pin = Path(entry.get("installPath", "")) / "binary-version"
        if not pin.is_file():
            return False
        pins.add(pin.read_text().strip())
    launcher = home / ".local/state/model-router/launcher/binary-version"
    if not launcher.is_file() or pins != {launcher.read_text().strip()}:
        return False
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(base_url + "/__model-router/health", timeout=2) as response:
            health = json.loads(response.read(4096))
        return isinstance(health, dict) and health.get("version") in pins
    except (OSError, ValueError, http.client.HTTPException):
        return False


def redact(text, token, env):
    # Drop URLs wholesale: local ingress tokens and upstream URL passwords must
    # never land in reports. Replace known secrets before pattern-based cleanup.
    secrets = [token] + [value for key, value in env.items()
                         if re.search(r"KEY|TOKEN|SECRET|PASSWORD", key, re.I) and len(value) >= 4]
    for secret in sorted(set(secrets), key=len, reverse=True):
        if secret:
            text = text.replace(secret, "[redacted]")
    text = re.sub(r"https?://[^\s<>\"']+", "[redacted-url]", text)
    text = re.sub(r"(?i)(bearer\s+)[^\s,;\"']+", r"\1[redacted]", text)
    text = re.sub(r"(?i)((?:[\w-]*(?:api[_-]?key|token|secret|password)|authorization)[\"']?\s*[:=]\s*[\"']?)[^\s,;\"']+", r"\1[redacted]", text)
    text = re.sub(r"\bsk-[A-Za-z0-9_-]+", "[redacted]", text)
    return text


def private_write(path, text):
    fd, name = tempfile.mkstemp(prefix=".update-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as output:
            output.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def run_smoke(script, binary, env, timeout):
    """Drain output while retaining only a bounded prefix; kill descendants too."""
    child_env = dict(env, CLAUDE_BIN=str(binary), MODEL_ROUTER_UPDATE_CHECK="1")
    process = subprocess.Popen(["/bin/bash", str(script), "--skip-probes"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               env=child_env, start_new_session=True)
    chunks = bytearray()
    truncated = False
    deadline = time.monotonic() + min(60, timeout)
    expired = False
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    expired = True
                    break
                for key, _ in selector.select(min(remaining, 0.1)):
                    data = os.read(key.fileobj.fileno(), 8192)
                    if not data:
                        selector.unregister(key.fileobj)
                    else:
                        truncated = truncated or len(chunks) + len(data) > MAX_REPORT
                        if len(chunks) < MAX_REPORT:
                            chunks.extend(data[:MAX_REPORT - len(chunks)])
            if not expired:
                try:
                    process.wait(timeout=max(0.01, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    expired = True
    finally:
        if expired or process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait()
        process.stdout.close()
    if truncated:
        # Never retain a cut-off credential that redaction cannot recognize.
        chunks = chunks[:chunks.rfind(b"\n") + 1]
    return (1 if expired else process.returncode), chunks.decode("utf-8", errors="replace"), expired


def check_update(force=False, *, home=None, env=None, repo=None, timeout=60, now=None):
    home = Path.home() if home is None else Path(home)
    env = dict(os.environ if env is None else env)
    repo = Path(__file__).resolve().parents[2] if repo is None else Path(repo)
    if env.get("MODEL_ROUTER_UPDATE_CHECK") == "1":
        return 0, None
    if env.get("XDG_STATE_HOME") and Path(env["XDG_STATE_HOME"]) != home / ".local/state":
        return 0, None
    state = home / ".local/state/model-router"
    try:
        config_env = read_json(home / ".claude/settings.json").get("env", {})
        base_url = env.get("ANTHROPIC_BASE_URL")
        if base_url is None:
            base_url = managed_env(env).get("ANTHROPIC_BASE_URL") or config_env.get("ANTHROPIC_BASE_URL", "")
        token_path = state / "ingress-token"
        if not token_path.is_file():
            return 0, None
        token = token_path.read_text().strip()
        if not token or base_url != "http://127.0.0.1:8787/t/" + token:
            return 0, None
        binary = home / ".local/bin/claude"
        if not binary.is_file():
            found = shutil.which("claude", path=env.get("PATH", ""))
            if not found:
                return 1, "Model router: Claude executable unavailable; infrastructure validation skipped."
            binary = Path(found)
        directory = state / "update-check"
        if directory.is_symlink():
            return 1, "Model router: validation state directory is a symlink; check skipped."
        directory.mkdir(mode=0o700, exist_ok=True)
        directory.chmod(0o700)
        lock_fd = os.open(str(directory / "lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(lock_fd, "w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return (1, "Model router: another infrastructure check is in progress; retry --force after it completes.") if force else (0, None)
            revision = fingerprint(home, binary)
            cache = read_json(directory / "state.json")
            timestamp = time.time() if now is None else now
            report_path = directory / "report.txt"
            if not force and cache.get("fingerprint") == revision:
                if cache.get("success") and versions_ready(home, base_url):
                    return 0, None
                if not cache.get("success") and timestamp - cache.get("checked_at", 0) < COOLDOWN:
                    return 1, "Model router: previous infrastructure check failed; retry after five minutes or use --force. Report: " + str(report_path)
            status, output, expired = run_smoke(repo / "tests/test_model_router_gateway.sh", binary, env, timeout)
            reason = "infrastructure smoke checks passed (no model-generation probes)."
            if expired:
                reason = "infrastructure smoke checks timed out."
            elif status:
                reason = "infrastructure smoke checks failed."
            elif fingerprint(home, binary) != revision or not versions_ready(home, base_url):
                status = 1
                reason = "installed or running versions changed during validation; retry next session."
                # A refresh is not a persistent failure; allow next startup retry.
                timestamp = 0
            report = redact(reason + "\n" + output, token, env).encode("utf-8")[:MAX_REPORT]
            private_write(report_path, report.decode("utf-8", errors="ignore"))
            private_write(directory / "state.json", json.dumps({"fingerprint": revision,
                          "success": status == 0, "checked_at": timestamp}) + "\n")
            message = "Model router: " + reason
            if status:
                message += " Report: " + str(report_path)
            return (1 if status else 0), message
    except (OSError, ValueError, TypeError, AttributeError):
        # Exception strings may contain an authenticated URL; never print them.
        return 1, "Model router: could not complete infrastructure validation; inspect local configuration and validation state permissions."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="rerun checks and return a failing exit status on failure")
    args = parser.parse_args()
    if not args.force:
        try:
            payload = json.load(sys.stdin)
            if not isinstance(payload, dict) or payload.get("hook_event_name", "SessionStart") != "SessionStart":
                return 0
        except ValueError:
            print(json.dumps({"systemMessage": "Model router: invalid hook input; infrastructure validation skipped."}))
            return 0
    status, message = check_update(force=args.force)
    if message:
        print(message if args.force else json.dumps({"systemMessage": message}))
    return status if args.force else 0


if __name__ == "__main__":
    sys.exit(main())
