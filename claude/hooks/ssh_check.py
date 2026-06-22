#!/usr/bin/env python3
"""PermissionRequest hook: allow SSH to known hosts, ask for raw IPs.

Reads PermissionRequest JSON on stdin.
Outputs {"decision":"allow"} for hosts in ~/.ssh/config.
Outputs {"decision":"ask"} for hardcoded IPv4/IPv6 addresses.
Exits 0 with no output to fall through to the next hook (auto_classify.py).
"""

import json
import re
import sys
from pathlib import Path

# Flags that consume the next token as their value (ssh/scp/sftp manual)
SSH_VALUE_FLAGS = set("bcDEeFIiJLlmopQRSWw")

IPV4_RE = re.compile(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$")
# IPv6: at least 2 colons, only hex digits and colons (covers :: compressed form)
IPV6_RE = re.compile(r"^[0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4}){2,7}$")


def is_ipv4(s):
    return bool(IPV4_RE.match(s))


def is_ipv6(s):
    return IPV6_RE.match(s) and s.count(":") >= 2


def strip_userinfo(token):
    """Remove user@ prefix."""
    if "@" in token:
        return token.split("@", 1)[1]
    return token


def extract_host_token(token):
    """Extract host from a token that may be user@host or user@host:path (scp)."""
    t = strip_userinfo(token)
    # For scp remote args: host:path — split on first colon ONLY if result isn't IPv6
    # IPv6 addresses with port are bracketed: [2001:db8::1]:path
    if t.startswith("["):
        # Bracketed IPv6: [addr]:port or [addr]
        m = re.match(r"^\[([^\]]+)\]", t)
        if m:
            return m.group(1)
    # If it looks like IPv6 (multiple colons before any /), don't split
    if t.count(":") >= 2:
        return t
    # Otherwise split on first colon for scp path
    return t.split(":", 1)[0]


def ssh_config_hosts():
    """Return set of lowercase Host names from ~/.ssh/config (no wildcards)."""
    hosts = set()
    config_path = Path.home() / ".ssh" / "config"
    try:
        for line in config_path.read_text(errors="replace").splitlines():
            stripped = line.strip()
            if stripped.lower().startswith("host "):
                for h in stripped.split()[1:]:
                    if "*" not in h and "?" not in h:
                        hosts.add(h.lower())
    except OSError:
        pass
    return hosts


def tokenize_ssh(cmd):
    """Split command into tokens, handling quoted strings simply."""
    # Basic split; not full shell parsing but good enough for SSH command lines
    return cmd.split()


def parse_ssh_target(tokens):
    """Parse SSH command tokens to find the target [user@]host.

    Returns the host string (without user@), or None if not found.
    """
    i = 1  # skip command name
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("-"):
            flag = t[1:2]
            if len(t) == 2 and flag in SSH_VALUE_FLAGS:
                i += 2  # skip flag and its value token
            elif len(t) > 2 and flag in SSH_VALUE_FLAGS:
                i += 1  # value is attached: -p22
            else:
                i += 1  # boolean flag
        else:
            # First positional arg is [user@]host
            return extract_host_token(t)
    return None


def find_raw_ip(cmd):
    """Scan all tokens in cmd for a raw IPv4 or IPv6 address.

    Returns (kind, addr) or None.
    """
    for token in tokenize_ssh(cmd):
        host = extract_host_token(token)
        if not host:
            continue
        if is_ipv4(host):
            return ("IPv4", host)
        if is_ipv6(host):
            return ("IPv6", host)
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    cmd = data.get("tool_input", {}).get("command", "")
    if not cmd:
        return

    # Only handle ssh/scp/sftp commands (allow pipeline: e.g. | ssh)
    if not re.search(r"(?:^|\|)\s*(ssh|scp|sftp)\s", cmd):
        return

    # Step 1: scan all tokens for raw IPs (covers scp where IP can be src or dst)
    ip_match = find_raw_ip(cmd)
    if ip_match:
        kind, addr = ip_match
        print(json.dumps({
            "decision": "ask",
            "reason": f"SSH/SCP to hardcoded {kind} {addr} — please confirm",
        }))
        return

    # Step 2: for ssh/sftp only, check if target host is in ~/.ssh/config
    if re.search(r"(?:^|\|)\s*(ssh|sftp)\s", cmd):
        tokens = tokenize_ssh(cmd)
        # Find the ssh/sftp token to start parsing from
        for idx, t in enumerate(tokens):
            if t in ("ssh", "sftp"):
                tokens = tokens[idx:]
                break
        host = parse_ssh_target(tokens)
        if host:
            known = ssh_config_hosts()
            if host.lower() in known:
                print(json.dumps({
                    "decision": "allow",
                    "reason": f"SSH to known host {host} (in ~/.ssh/config)",
                }))
                return

    # Fall through to auto_classify.py for unknown named hosts


if __name__ == "__main__":
    main()
