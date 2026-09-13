#!/usr/bin/env python3
"""Bounded recovery of the installed macOS router before Claude needs it.

Only the default loopback URL authenticated by the local ingress token is ours.
Never install anything, override an explicit disable, or kill a running router.
"""

import datetime
import http.client
import json
import os
import platform
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


LABEL = "com.alignment-hive.model-router"
PORT = 8787
HEALTH_PATH = "/__model-router/health"
REPAIR_SECONDS = 12.0


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


class GuardError(Exception):
    """A diagnostic with fixed text, safe to show without leaking credentials."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def healthy(base_url, timeout):
    """A degraded upstream is still a live router; restarting cannot fix it."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(base_url + HEALTH_PATH, timeout=timeout) as response:
            data = json.loads(response.read(4096))
            return (response.status == 200 and isinstance(data, dict)
                    and data.get("status") in ("ok", "degraded")
                    and isinstance(data.get("version"), str) and bool(data["version"])
                    and ("cliproxy-upstream" in data or "codex-upstream" in data))
    except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException):
        return False


def loaded_definition_matches(output, plist, expected):
    """launchctl print's top-level fields must describe the installed launcher."""
    path = re.search(r"^\tpath = (.+)$", output, re.MULTILINE)
    program = re.search(r"^\tprogram = (.+)$", output, re.MULTILINE)
    arguments = re.search(r"^\targuments = \{\n((?:\t\t[^\n]*\n)*)\t\}", output, re.MULTILINE)
    try:
        same_plist = bool(path and Path(path.group(1)).resolve(strict=True) == plist.resolve(strict=True))
    except (OSError, RuntimeError):
        same_plist = False
    return bool(same_plist
                and program and program.group(1) == "/bin/bash"
                and arguments and [line[2:] for line in arguments.group(1).splitlines()] == expected)


def safe_version(path):
    try:
        with path.open("rb") as source:
            value = source.read(128).decode("ascii").strip()
        return value if re.fullmatch(r"v?\d+(?:\.\d+){1,3}", value) else None
    except (OSError, ValueError):
        return None


def log_metadata(path):
    """Summarize a bounded tail; never persist log lines or request contents."""
    try:
        with path.open("rb") as source:
            info = os.fstat(source.fileno())
            source.seek(max(0, info.st_size - 16384))
            tail = source.read(16384)
        text = tail.decode("utf-8", errors="replace")
        markers = {name: len(re.findall(pattern, text, re.IGNORECASE)) for name, pattern in {
            "startup": r"\b(?:starting|started|listening)\b",
            "shutdown": r"\b(?:shutdown|shutting down|terminated|exiting)\b",
            "error": r"\b(?:error|failed|panic)\b",
        }.items()}
        return {"size_bytes": info.st_size, "modified_unix": info.st_mtime,
                "tail_bytes": len(tail), "markers": markers}
    except OSError:
        return {"available": False}


def service_metadata(result):
    """Extract only top-level, allowlisted launchctl fields."""
    fields = {"returncode": result.returncode}
    state = re.search(r"^\tstate = (running|waiting|exited|spawn scheduled|not running)\s*$", result.stdout, re.MULTILINE)
    if state:
        fields["state"] = state.group(1)
    for label, key in [("pid", "pid"), ("runs", "runs"), ("last exit code", "last_exit_code"),
                       ("last exit status", "last_exit_status")]:
        found = re.search(r"^\t" + label + r" = (-?\d+)\s*$", result.stdout, re.MULTILINE)
        if found:
            fields[key] = int(found.group(1))
    signal = re.search(r"^\tlast terminating signal = (?:[A-Za-z ]+: )?(\d+)\s*$", result.stdout, re.MULTILINE)
    if signal:
        fields["last_exit_signal"] = int(signal.group(1))
    return fields


class Incident:
    """Best-effort private evidence; capture failure must never prevent recovery."""

    def __init__(self, home, event):
        state = home / ".local/state/model-router"
        stamp = datetime.datetime.now(datetime.timezone.utc)
        self.path = state / "diagnostics" / ("incident-" + stamp.strftime("%Y%m%dT%H%M%S.%fZ-") + uuid.uuid4().hex + ".json")
        self.failed = False
        self.saved = False
        self.data = {"utc": stamp.isoformat(), "event": event, "action": "none",
                     "outcome": "pending", "launchctl": {}}
        try:
            versions = home / ".claude/plugins/cache/alignment-hive/model-router"
            installed = [safe_version(path) for path in sorted(versions.glob("*/binary-version"))[-5:]]
            self.data["versions"] = {"stable": safe_version(state / "launcher/binary-version"),
                                     "cached_pins": sorted(set(value for value in installed if value))}
            self.data["log"] = log_metadata(state / "logs/router.log")
            self.update()
        except OSError:
            self.failed = True

    def update(self, **fields):
        self.data.update(fields)
        temporary = None
        try:
            directory = self.path.parent
            directory.mkdir(mode=0o700, exist_ok=True)
            if directory.is_symlink():
                raise OSError("diagnostics directory must not be a symlink")
            directory.chmod(0o700)
            temporary = directory / (".incident-" + uuid.uuid4().hex + ".tmp")
            fd = os.open(str(temporary), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, "w") as output:
                os.fchmod(output.fileno(), 0o600)
                json.dump(self.data, output, sort_keys=True)
                output.write("\n")
            os.replace(str(temporary), str(self.path))
            temporary = None
            self.saved = True
            for old in sorted(directory.glob("incident-*.json"))[:-10]:
                try:
                    old.unlink()
                except FileNotFoundError:
                    pass  # Concurrent captures can prune the same old incident.
        except (OSError, ValueError):
            self.failed = True
        finally:
            if temporary is not None:
                try:
                    temporary.unlink()
                except OSError:
                    pass

    def record_process(self, action, result):
        entry = service_metadata(result) if action == "print" else {"returncode": result.returncode}
        if action == "print-disabled" and result.returncode == 0:
            found = re.search(r'"' + re.escape(LABEL) + r'"\s*=>\s*(true|false|disabled|enabled)\b', result.stdout)
            entry["explicitly_disabled"] = bool(found and found.group(1) in ("true", "disabled"))
        self.data["launchctl"][action] = entry
        self.update()

    def suffix(self):
        detail = " Diagnostics: " + str(self.path) + "." if self.saved else ""
        if self.failed:
            detail += " Diagnostic capture failed or is incomplete."
        return detail


def notice(event, message):
    message = "Model router: " + message
    output = {"systemMessage": message}
    if event == "UserPromptSubmit":
        output.update(decision="block", reason=message)
    return output


def ensure_router(event, *, home=None, env=None, system=None, budget=REPAIR_SECONDS):
    if (platform.system() if system is None else system) != "Darwin":
        return None
    if event not in ("SessionStart", "UserPromptSubmit"):
        return None
    home = Path.home() if home is None else Path(home)
    env = os.environ if env is None else env
    deadline = time.monotonic() + budget
    incident = None

    def finish(result, outcome):
        if incident is not None:
            incident.update(outcome=outcome, detail=result.get("reason", result["systemMessage"]))
            suffix = incident.suffix()
            result["systemMessage"] += suffix
            if "reason" in result:
                result["reason"] += suffix
        return result

    def remaining():
        left = deadline - time.monotonic()
        if left <= 0:
            raise GuardError("recovery timed out; inspect the model-router service and retry.")
        return left

    def launchctl(*args):
        try:
            result = subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True,
                                    timeout=min(3.0, remaining()), check=False)
        except subprocess.TimeoutExpired:
            if incident is not None:
                incident.data["launchctl"][args[0]] = {"timed_out": True}
                incident.update()
            if args[0] in ("bootstrap", "kickstart"):
                # launchd may have queued a throttled start despite the CLI timeout.
                # Readiness polling uses the remaining global budget; never reissue.
                return None
            raise
        if incident is not None:
            incident.record_process(args[0], result)
        return result

    try:
        if "ANTHROPIC_BASE_URL" in env:
            # An empty value here stays an explicit off; only the unset case
            # falls through to the files below.
            base_url = env["ANTHROPIC_BASE_URL"]
        else:
            base_url = managed_env(env).get("ANTHROPIC_BASE_URL", "")
            if not base_url:
                settings = home / ".claude/settings.json"
                if not settings.exists():
                    return None
                config = json.loads(settings.read_text())
                base_url = config.get("env", {}).get("ANTHROPIC_BASE_URL", "")
        if not isinstance(base_url, str) or not base_url.startswith("http://127.0.0.1:%s/t/" % PORT):
            return None
        state = home / ".local/state/model-router"
        # The recovery contract covers the default installation only.
        if env.get("XDG_STATE_HOME") and Path(env["XDG_STATE_HOME"]) != home / ".local/state":
            return None
        token_path = state / "ingress-token"
        if not token_path.exists():
            return None
        token = token_path.read_text().strip()
        if not token or base_url != "http://127.0.0.1:%s/t/%s" % (PORT, token):
            return None
        if healthy(base_url, min(0.7, remaining())):
            return None

        incident = Incident(home, event)
        domain = "gui/%s" % os.getuid()
        target = domain + "/" + LABEL
        disabled = launchctl("print-disabled", domain)
        if disabled.returncode:
            raise GuardError("could not inspect the service disable state; no service changes made.")
        if re.search(r'"' + re.escape(LABEL) + r'"\s*=>\s*(?:true|disabled)\b', disabled.stdout):
            raise GuardError("service is explicitly disabled; re-enable it deliberately before retrying.")

        plist = home / "Library/LaunchAgents" / (LABEL + ".plist")
        launcher = state / "launcher/bootstrap.sh"
        with plist.open("rb") as source:
            service = plistlib.load(source)
        expected = ["/bin/bash", str(launcher), "serve"]
        if (service.get("Label") != LABEL or service.get("ProgramArguments") != expected
                or service.get("Program") not in (None, "/bin/bash") or not launcher.is_file()):
            raise GuardError("installed service does not match the expected router launcher; no service changes made.")
        service_state = launchctl("print", target)
        running = service_state.returncode == 0 and bool(re.search(r"\bstate\s*=\s*running\b", service_state.stdout))
        if service_state.returncode:
            # A simultaneous SessionStart/plugin bootstrap may win this race.
            # Readiness determines success, not bootstrap's exit status.
            incident.update(action="bootstrap")
            launchctl("bootstrap", domain, str(plist))
        elif not running:
            if not loaded_definition_matches(service_state.stdout, plist, expected):
                raise GuardError("loaded service does not match the expected router launcher; no service changes made.")
            incident.update(action="kickstart")
            launchctl("kickstart", target)

        while deadline > time.monotonic():
            if healthy(base_url, min(0.7, remaining())):
                return finish({"systemMessage": "Model router recovered; the local service is ready."}, "recovered")
            time.sleep(min(0.25, max(0.0, deadline - time.monotonic())))
        if running:
            raise GuardError("service is running but its local health endpoint is unavailable; inspect router logs and retry. The running service was left intact.")
        raise GuardError("recovery timed out; inspect the model-router service and retry.")
    except GuardError as error:
        return finish(notice(event, str(error)), "failed")
    except subprocess.TimeoutExpired:
        return finish(notice(event, "service inspection or recovery timed out; inspect the model-router service and retry."), "failed")
    except (OSError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
        # Never print exception text, process output, URLs, or settings contents.
        return finish(notice(event, "could not read router configuration or inspect its service; check settings, ingress token, and installed LaunchAgent."), "failed")


def main():
    try:
        payload = json.load(sys.stdin)
        event = payload.get("hook_event_name", "SessionStart")
    except (ValueError, AttributeError):
        print(json.dumps(notice("SessionStart", "could not parse hook input; recovery was skipped.")))
        return
    result = ensure_router(event)
    if result:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
