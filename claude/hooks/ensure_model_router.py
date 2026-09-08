#!/usr/bin/env python3
"""Bounded recovery of the installed macOS router before Claude needs it.

Only the default loopback URL authenticated by the local ingress token is ours.
Never install anything, override an explicit disable, or kill a running router.
"""

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
from pathlib import Path


LABEL = "com.alignment-hive.model-router"
PORT = 8787
HEALTH_PATH = "/__model-router/health"
REPAIR_SECONDS = 12.0


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
    return bool(path and path.group(1) == str(plist)
                and program and program.group(1) == "/bin/bash"
                and arguments and [line[2:] for line in arguments.group(1).splitlines()] == expected)


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

    def remaining():
        left = deadline - time.monotonic()
        if left <= 0:
            raise GuardError("recovery timed out; inspect the model-router service and retry.")
        return left

    def launchctl(*args):
        return subprocess.run(["/bin/launchctl", *args], capture_output=True, text=True,
                              timeout=min(3.0, remaining()), check=False)

    try:
        if "ANTHROPIC_BASE_URL" in env:
            base_url = env["ANTHROPIC_BASE_URL"]
        else:
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
            launchctl("bootstrap", domain, str(plist))
        elif not running:
            if not loaded_definition_matches(service_state.stdout, plist, expected):
                raise GuardError("loaded service does not match the expected router launcher; no service changes made.")
            launchctl("kickstart", target)

        while deadline > time.monotonic():
            if healthy(base_url, min(0.7, remaining())):
                if running:
                    return None
                return {"systemMessage": "Model router recovered; the local service is ready."}
            time.sleep(min(0.25, max(0.0, deadline - time.monotonic())))
        if running:
            raise GuardError("service is running but its local health endpoint is unavailable; inspect router logs and retry. The running service was left intact.")
        raise GuardError("recovery timed out; inspect the model-router service and retry.")
    except GuardError as error:
        return notice(event, str(error))
    except subprocess.TimeoutExpired:
        return notice(event, "service inspection or recovery timed out; inspect the model-router service and retry.")
    except (OSError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
        # Never print exception text, process output, URLs, or settings contents.
        return notice(event, "could not read router configuration or inspect its service; check settings, ingress token, and installed LaunchAgent.")


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
