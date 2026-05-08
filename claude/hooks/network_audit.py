#!/usr/bin/env python3
"""PreToolUse hook: Network intent extraction and audit logging.

Extracts domain targets from Bash commands, logs them to a structured
JSONL file, and surfaces a systemMessage so the user sees what network
access a command needs and why — before the sandbox prompts for it.

Fires on every Bash tool use but exits silently (no output) for commands
with no detected network intent. No API calls — pure regex extraction.
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

LOG_PATH = os.path.expanduser("~/.cache/claude/network-audit.jsonl")
MAX_LOG_BYTES = 2_000_000  # 2MB, then rotate

# ── Domain extraction patterns ──────────────────────────────────────

# URLs in command arguments
_URL_RE = re.compile(r'https?://([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)')

# Git remote URLs: git@host:owner/repo or https://host/owner/repo
_GIT_SSH_RE = re.compile(r'git@([a-zA-Z0-9][-a-zA-Z0-9.]+):(\S+?)(?:\.git)?(?:\s|$|")')
_GIT_HTTPS_RE = re.compile(r'https?://([a-zA-Z0-9][-a-zA-Z0-9.]+)/([^\s"\']+?)(?:\.git)?(?:\s|$|")')

# SSH targets: ssh [flags] user@host or ssh [flags] host
_SSH_RE = re.compile(r'\bssh\s+(?:-\S+\s+)*(?:\S+@)?([a-zA-Z0-9][-a-zA-Z0-9.]+)')
_SCP_RE = re.compile(r'\bscp\s+.*?(?:\S+@)?([a-zA-Z0-9][-a-zA-Z0-9.]+):')

# ── Purpose classification ──────────────────────────────────────────

# (pattern, purpose_template) — purpose_template can use {domain}, {match}
_PURPOSE_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # Git operations
    (re.compile(r'\bgit\s+push\b'), "git push to remote"),
    (re.compile(r'\bgit\s+pull\b'), "git pull from remote"),
    (re.compile(r'\bgit\s+fetch\b'), "git fetch from remote"),
    (re.compile(r'\bgit\s+clone\b'), "git clone repository"),
    (re.compile(r'\bgit\s+ls-remote\b'), "git ls-remote (probe remote refs)"),
    (re.compile(r'\bgit\s+submodule\b'), "git submodule operation"),

    # GitHub CLI
    (re.compile(r'\bgh\s+pr\b'), "GitHub CLI: pull request operation"),
    (re.compile(r'\bgh\s+issue\b'), "GitHub CLI: issue operation"),
    (re.compile(r'\bgh\s+api\b'), "GitHub CLI: API call"),
    (re.compile(r'\bgh\s+(?:repo|gist|release|run|workflow)\b'), "GitHub CLI operation"),

    # Package managers
    (re.compile(r'\bnpm\s+(?:install|ci|update|publish)\b'), "npm package operation"),
    (re.compile(r'\bbun\s+(?:install|add|update|publish)\b'), "bun package operation"),
    (re.compile(r'\bpnpm\s+(?:install|add|update|publish)\b'), "pnpm package operation"),
    (re.compile(r'\bpip\s+install\b'), "pip package install"),
    (re.compile(r'\buv\s+(?:pip\s+install|sync|add|lock)\b'), "uv package operation"),
    (re.compile(r'\bcargo\s+(?:install|build|update|publish)\b'), "cargo operation"),

    # HTTP clients
    (re.compile(r'\bcurl\b'), "curl HTTP request"),
    (re.compile(r'\bwget\b'), "wget download"),
    (re.compile(r'\bhttpie\b|\bhttp\s'), "httpie request"),

    # SSH/SCP — anchor at command-start to avoid matching .ssh/ paths
    (re.compile(r'(?:^|[\s;&|()`])ssh\s'), "SSH connection"),
    (re.compile(r'(?:^|[\s;&|()`])scp\s'), "SCP file transfer"),
    (re.compile(r'\brsync\b.*(?:-e\s+ssh|:)'), "rsync over SSH"),

    # Docker
    (re.compile(r'\bdocker\s+(?:pull|push|login|build)\b'), "Docker registry operation"),

    # DNS/network probing
    (re.compile(r'\bnslookup\b|\bdig\b|\bhost\b'), "DNS lookup"),
    (re.compile(r'\bping\b'), "ping/connectivity check"),
    (re.compile(r'\bnc\b|\bnetcat\b'), "netcat connection"),

    # Python network
    (re.compile(r'\brequests\.(?:get|post|put|delete|patch)\b'), "Python requests HTTP call"),
    (re.compile(r'\bhttpx\b'), "Python httpx HTTP call"),
    (re.compile(r'\burllib\b'), "Python urllib HTTP call"),

    # Misc
    (re.compile(r'\bcodex\s+exec\b'), "Codex CLI (may need api.openai.com)"),
    (re.compile(r'\bgemini\b.*-p\b'), "Gemini CLI (may need googleapis.com)"),
]

# Well-known implicit domains for tools that don't have URLs in the command
_IMPLICIT_DOMAINS: dict[str, list[str]] = {
    "npm": ["registry.npmjs.org"],
    "bun": ["registry.npmjs.org"],
    "pnpm": ["registry.npmjs.org"],
    "pip": ["pypi.org", "files.pythonhosted.org"],
    "uv": ["pypi.org", "files.pythonhosted.org"],
    "cargo": ["crates.io", "static.crates.io", "index.crates.io"],
    "gh": ["api.github.com", "github.com"],
    "docker": ["registry-1.docker.io", "auth.docker.io"],
    "codex": ["api.openai.com"],
    "gemini": ["generativelanguage.googleapis.com"],
}


def extract_domains(command: str) -> list[str]:
    """Extract target domains from a shell command."""
    domains: set[str] = set()

    # Explicit URLs
    for match in _URL_RE.finditer(command):
        domains.add(match.group(1))

    # Git SSH URLs
    for match in _GIT_SSH_RE.finditer(command):
        domains.add(match.group(1))

    # SSH/SCP targets
    for match in _SSH_RE.finditer(command):
        host = match.group(1)
        if "." in host or host == "localhost":
            domains.add(host)

    for match in _SCP_RE.finditer(command):
        domains.add(match.group(1))

    return sorted(domains)


def extract_implicit_domains(command: str) -> list[str]:
    """Infer domains from tool names when no explicit URL is present."""
    domains: set[str] = set()
    cmd_first = command.strip().split()[0] if command.strip() else ""

    for tool, tool_domains in _IMPLICIT_DOMAINS.items():
        if re.search(rf'\b{re.escape(tool)}\b', command):
            domains.update(tool_domains)

    return sorted(domains)


def classify_purpose(command: str) -> str:
    """Classify the network purpose of a command."""
    for pattern, purpose in _PURPOSE_PATTERNS:
        if pattern.search(command):
            return purpose
    return "unknown network operation"


def extract_git_remote_domain(cwd: str) -> str | None:
    """Try to get the domain from git remote origin in CWD."""
    try:
        import subprocess
        proc = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=3,
        )
        if proc.returncode == 0:
            url = proc.stdout.strip()
            # git@github.com:owner/repo.git
            m = _GIT_SSH_RE.search(url + " ")
            if m:
                return m.group(1)
            # https://github.com/owner/repo.git
            m = _GIT_HTTPS_RE.search(url + " ")
            if m:
                return m.group(1)
            # Fallback: parse as URL
            parsed = urlparse(url)
            if parsed.hostname:
                return parsed.hostname
    except Exception:
        pass
    return None


def is_network_command(command: str) -> bool:
    """Quick check if a command has any network intent."""
    for pattern, _ in _PURPOSE_PATTERNS:
        if pattern.search(command):
            return True
    return False


def log_entry(entry: dict) -> None:
    """Append a JSONL entry to the audit log."""
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        # Rotate if too large
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG_BYTES:
            with open(LOG_PATH, "r") as f:
                lines = f.readlines()
            with open(LOG_PATH, "w") as f:
                f.writelines(lines[len(lines) // 2:])
        with open(LOG_PATH, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def format_message(purpose: str, domains: list[str], implicit_domains: list[str], command_short: str) -> str:
    """Format a concise systemMessage for the user."""
    all_domains = domains + [d for d in implicit_domains if d not in domains]

    if not all_domains:
        return f"\033[0;36m🌐 Network:\033[0m {purpose}"

    domain_str = ", ".join(all_domains[:5])
    if len(all_domains) > 5:
        domain_str += f" (+{len(all_domains) - 5} more)"

    return f"\033[0;36m🌐 Network:\033[0m {purpose} → {domain_str}"


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = hook_input.get("tool_input", {})
    command = tool_input.get("command", "")
    cwd = hook_input.get("cwd", "")

    if not command or not is_network_command(command):
        sys.exit(0)

    # Extract network intent
    purpose = classify_purpose(command)
    domains = extract_domains(command)
    implicit_domains = extract_implicit_domains(command)

    # For git commands without explicit URL, resolve from remote
    if not domains and command.strip().startswith("git "):
        remote_domain = extract_git_remote_domain(cwd)
        if remote_domain:
            domains = [remote_domain]

    # Log the entry
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    command_short = command[:200] + "..." if len(command) > 200 else command
    entry = {
        "timestamp": ts,
        "purpose": purpose,
        "domains": domains,
        "implicit_domains": implicit_domains,
        "command": command_short,
        "cwd": cwd,
    }
    log_entry(entry)

    # Surface to user
    msg = format_message(purpose, domains, implicit_domains, command_short)
    json.dump({"systemMessage": msg}, sys.stdout)


if __name__ == "__main__":
    main()
