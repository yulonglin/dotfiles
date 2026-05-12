#!/usr/bin/env python3
"""PermissionRequest hook: LLM-based permission classifier.

Calls an Anthropic model to classify tool actions as allow/deny, mimicking auto mode.
Fails open (exit 0 = normal prompt) on any error, but emits a loud warning
instead of failing silently when the hook is misconfigured or Anthropic rejects
the request.
Always active — no env var gate.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

RULES_PATH = os.path.join(os.path.dirname(__file__), "auto_classify_rules.md")
API_URL = "https://api.anthropic.com/v1/messages"
MODEL = "claude-sonnet-4-6"
MAX_TOKENS = 100
TIMEOUT_SECONDS = 12
LOG_PATH = os.path.expanduser("~/.cache/claude/auto-classify.log")
NO_KEY_FLAG = os.path.expanduser("~/.cache/claude/auto-classify-no-key-warned")
MAX_INPUT_CHARS = 2000
MAX_LOG_BYTES = 1_000_000  # 1MB
MAX_USER_MSG_CHARS = 200  # Truncation limit per user message
MAX_USER_MESSAGES = 7  # Number of recent user messages to include

# GitHub owners (users + orgs) whose repos are trusted for relaxed permissions.
# Add orgs you work with regularly. Personal repos get extra relaxations.
TRUSTED_GITHUB_OWNERS = {"yulonglin", "anthropics", "alignment-research"}
PERSONAL_GITHUB_USERS = {"yulonglin"}

# Cache file written by SessionStart hook (detect_repo_trust.sh)
TRUST_CACHE = os.path.expanduser("~/.cache/claude/repo-trust.json")

# Feature flags (set via environment variables)
INCLUDE_USER_MESSAGE = os.environ.get("AUTO_CLASSIFY_USER_MESSAGE", "1") != "0"

ANSI_RESET = "\033[0m"
ANSI_RED = "\033[1;31m"
ANSI_YELLOW = "\033[1;33m"
ANSI_CYAN = "\033[1;36m"

# ── Sensitive credential files: hard deny ────────────────────────────
# Files that should NEVER be read by any tool. No masking — just block.
# Each entry: (path pattern, reason, alternative)
SENSITIVE_PATHS: list[tuple[str, str, str]] = [
    ("/.config/sops/age/keys.txt", "age private key (decryption master key)", "Use `sops -d` to decrypt files, or `with-secrets KEY -- printenv KEY` for individual secrets"),
    ("/.ssh/id_", "SSH private key", "Use `ssh-add -l` to list loaded keys, or `ssh-keygen -l -f <pubkey>` for fingerprints"),
    ("/.config/bws/token", "Bitwarden Secrets Manager token", "Use `bws secret list` to interact with secrets via CLI"),
    ("/.aws/credentials", "AWS credentials", "Use `aws configure list` to check config, or `aws sts get-caller-identity` to verify auth"),
    ("/.aws/config", "AWS config (may contain SSO tokens)", "Use `aws configure list` to check config"),
    ("/.kube/config", "Kubernetes config (cluster credentials)", "Use `kubectl config view --minify` to see non-secret config"),
    ("/.git-credentials", "Git credential store (plaintext passwords)", "Use `git credential-cache` or check remote with `git remote -v`"),
    ("/.claude/.credentials.json", "Claude Code auth credentials", "Already authenticated — no need to read credentials"),
    ("/.netrc", "Network credentials (plaintext logins)", "Use tool-specific auth commands instead"),
]


def check_sensitive_path(file_path: str) -> tuple[str, str] | None:
    """Check if a file path matches a sensitive credential file.

    Returns (reason, alternative) if blocked, None if allowed.
    Works for both Read tool file_path and paths extracted from Bash commands.
    """
    # Expand ~ to home dir for comparison
    home = os.path.expanduser("~")
    # Normalize: if path starts with ~, expand it
    normalized = file_path.replace("~", home) if file_path.startswith("~") else file_path

    for path_fragment, reason, alternative in SENSITIVE_PATHS:
        # Check if the path fragment appears in the normalized path
        # Use home + fragment for absolute paths, or just fragment for relative
        full_pattern = home + path_fragment
        if full_pattern in normalized or normalized.endswith(path_fragment):
            return reason, alternative
        # Also catch: the fragment without leading / for partial matches
        # e.g., ".ssh/id_rsa" in "/Users/foo/.ssh/id_rsa"
        if path_fragment.lstrip("/") in normalized:
            return reason, alternative

    return None


def _resolve_path_pair(file_path: str) -> list[str]:
    """Return the path itself plus its realpath (symlink target), if different.

    Always check both: a symlink at ./mylink → ~/.ssh/id_rsa must trip the
    sensitive check on the target, not just the surface path.
    """
    paths = [file_path]
    try:
        abs_path = os.path.abspath(os.path.expanduser(file_path))
        real = os.path.realpath(abs_path)
        if abs_path not in paths:
            paths.append(abs_path)
        if real not in paths:
            paths.append(real)
    except (OSError, ValueError):
        pass
    return paths


def fast_deny_sensitive_path(tool_name: str, tool_input: dict) -> dict | None:
    """Deny tool calls that read or write sensitive credential files.

    Covers Read, Edit, Write, MultiEdit, NotebookEdit, and Bash read commands.
    Resolves symlinks so `./link → ~/.ssh/id_rsa` is also blocked.
    """
    candidate_paths: list[str] = []

    if tool_name in ("Read", "Edit", "Write", "MultiEdit"):
        fp = tool_input.get("file_path", "")
        if fp:
            candidate_paths.append(fp)
    elif tool_name == "NotebookEdit":
        fp = tool_input.get("notebook_path") or tool_input.get("file_path", "")
        if fp:
            candidate_paths.append(fp)
    elif tool_name == "Bash":
        cmd = tool_input.get("command", "")
        # Extract file paths from simple read commands
        # Match: cat/head/tail/bat/less/more <path>
        import shlex
        try:
            tokens = shlex.split(cmd)
        except ValueError:
            tokens = cmd.split()
        if tokens and tokens[0] in ("cat", "head", "tail", "bat", "less", "more"):
            for token in tokens[1:]:
                if not token.startswith("-"):
                    candidate_paths.append(token)
    else:
        return None

    for raw in candidate_paths:
        for path in _resolve_path_pair(raw):
            result = check_sensitive_path(path)
            if result:
                reason, alternative = result
                return _build_sensitive_deny(raw, reason, alternative)
    return None


# Backwards-compatible alias for any external callers.
fast_deny_sensitive_read = fast_deny_sensitive_path


# ── Always-surface "question to user" tool calls ─────────────────────
# Some tool calls are themselves questions the agent wants the user to
# answer. Auto-classify must never silently allow these — the user has
# to actually see the question, not just an allow stamp. We bail out
# before the classifier runs and fall through to the normal permission
# prompt (no allow/deny decision emitted).
_INTERACTIVE_BASH_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bread\s+(?:-[a-zA-Z]+\s+)*-p\b"),
     "`read -p` prompts inside Bash; stdin isn't wired to the user in Claude Code."),
    (re.compile(r"\bgum\s+(?:confirm|input|choose|filter|file|write|spin)\b"),
     "`gum` interactive commands won't reach the user from a Claude Code Bash call."),
    (re.compile(r"\bgh\s+auth\s+login\b(?!.*--with-token)"),
     "`gh auth login` is interactive; the user should run it themselves (`!gh auth login`)."),
    (re.compile(r"\bgcloud\s+auth\s+login\b(?!.*--no-browser)"),
     "`gcloud auth login` is interactive; the user should run it themselves."),
]


def detect_question_to_user(tool_name: str, tool_input: dict) -> tuple[str, str] | None:
    """Return (reason, suggestion) if this tool call is itself a question to the user.

    The classifier must not auto-allow these — they have to surface to the user.
    """
    if tool_name == "AskUserQuestion":
        return ("AskUserQuestion is a direct question to the user — never auto-allow.", "")
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        for pattern, reason in _INTERACTIVE_BASH_PATTERNS:
            if pattern.search(cmd):
                return (reason, "Use the AskUserQuestion tool to ask the user instead.")
    return None


# Phrases that indicate the classifier is hedging in its `reason` field even
# when it returned `allow`. If we see these, downgrade to `unsure` so the user
# decides. Keep narrow — generic words like "confirm" / "verify" appear in
# legitimate allow reasons too.
_HEDGE_PHRASES = (
    "should the user",
    "ask the user",
    "check with the user",
    "user should confirm",
    "user should verify",
    "not sure",
    "unsure",
    "unclear",
    "uncertain",
    "might want to confirm",
    "may want to confirm",
)


def reason_hedges(reason: str) -> bool:
    """True if the classifier's reason text reads like an open question, not a decision."""
    if not reason:
        return False
    text = reason.lower()
    if "?" in text:
        return True
    return any(phrase in text for phrase in _HEDGE_PHRASES)


def _build_sensitive_deny(path: str, reason: str, alternative: str) -> dict:
    return {
        "decision": "deny",
        "reason": f"BLOCKED: {path} contains {reason}. This file must never be read by AI agents.",
        "suggestion": alternative,
    }


# ── Fast-path allowlist ──────────────────────────────────────────────
# Patterns that bypass the API call entirely. These are commands where
# classifiers repeatedly hallucinate false positives despite explicit rules.

# Commands that are always safe when run in a trusted/personal repo.
# Checked against the Bash tool's "command" field.
# Optional prefix: direnv exec . (used in projects with .envrc)
_DIRENV_PREFIX = r"(?:direnv\s+exec\s+\.\s+)?"
# Optional prefix: uv run [flags]
_UV_PREFIX = r"(?:uv\s+run\b.*?\s+)?"
# Combined optional prefix
_CMD_PREFIX = _DIRENV_PREFIX + _UV_PREFIX

FAST_ALLOW_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # python -c / python3 -c with multiline code (classifiers false-positive on # comments)
    # Only at start of command — piped python3 -c is NOT safe to fast-allow because
    # it bypasses UNSAFE_SHELL_PATTERNS checking on the upstream command.
    (re.compile(rf"^{_CMD_PREFIX}python3?\s+-c\s"), "python -c one-liner check"),
    # inspect eval/experiment commands (AI safety research tooling)
    (re.compile(rf"^{_CMD_PREFIX}inspect\s+(eval|run|log|list|info|view|score)\b"), "inspect eval/experiment"),
    (re.compile(rf"^{_CMD_PREFIX}python3?\s+-m\s+inspect_ai\b"), "inspect_ai module"),
    # codex exec (sandboxed CLI — review, task, etc.; exec is a codex subcommand, not shell exec)
    (re.compile(r"codex\s+exec\b"), "codex exec (sandboxed CLI)"),
    # .agent-claims/ operations (multi-agent coordination, ephemeral files only)
    (re.compile(r"^(?:mkdir\s+-p|cat|ls|rm\s+-f|printf|for\b).*\.agent-claims"), "agent claims coordination"),
    # gws (Google Workspace CLI) — read and create operations are safe.
    # Deletes are caught by block_gws_delete.sh PreToolUse hook.
    # Verbs: list, get, search, export, create, insert, send (with --draft)
    # gws read-only: verb must appear as a standalone token (not inside JSON/flags),
    # and no shell chaining operators allowed. Write verbs (create, insert, update,
    # send) go through auto_classify for proper intent evaluation.
    (re.compile(r"^gws\s+(?:(?!&&|[|]{2}|;)\S+\s+)*(list|get|search|export)\s"), "gws read-only operation"),
    # claude/codex/gemini --version/--help: pure info, no side effects
    (re.compile(r"^(claude|codex|gemini)\s+--(version|help)\b"), "CLI version/help check"),
]


# Commands that are always read-only or harmless — used to auto-allow
# compound shell statements (for/while/if/&&) that Claude Code's parser
# can't handle ("Unhandled node type: string").
SAFE_SHELL_COMMANDS: set[str] = {
    # File inspection (read-only)
    "cat", "head", "tail", "less", "more", "bat", "wc", "file", "stat",
    "ls", "eza", "tree", "du", "dust", "df", "duf", "realpath", "dirname",
    "basename", "readlink",
    # PDF inspection (read-only, poppler-utils)
    "pdftotext", "pdfinfo", "pdfimages", "pdftohtml",
    # Search (read-only)
    "grep", "rg", "find", "fd", "ag", "ack",
    # Text processing (read-only — sed/sd without -i, awk)
    "sed", "awk", "cut", "tr", "sort", "uniq", "diff", "comm", "paste",
    "column", "fmt", "fold", "rev", "tac", "nl", "expand", "unexpand",
    "jq", "jless", "sd",
    # Shell builtins / control flow
    "echo", "printf", "test", "[", "true", "false", ":", "read",
    "break", "continue", "return", "exit", "shift", "set",
    "cd", "pwd", "pushd", "popd",
    # Variable / environment
    "export", "local", "declare", "typeset", "unset", "env", "printenv",
    # Git (read-only subcommands checked via UNSAFE_SHELL_PATTERNS denylist)
    "git",
    # Misc safe
    "date", "sleep", "which", "type", "command", "hash", "id", "whoami",
    "hostname", "uname", "arch", "nproc", "sha256sum", "md5sum", "b2sum",
    "any2md", "shellcheck",
    # Filesystem (write ops — acceptable risk for personal repos, destructive
    # variants caught by UNSAFE_SHELL_PATTERNS)
    "mkdir", "touch", "chmod", "ln", "tee", "cp", "mv",
}
# NOTE: python, python3, uv, rm, kill intentionally excluded — they are
# handled by FAST_ALLOW_PATTERNS for specific safe invocations only.

# Commands that are destructive or need review even inside compound statements.
# Denylist checked BEFORE any allowlist — makes the denylist authoritative.
UNSAFE_SHELL_PATTERNS: list[re.Pattern[str]] = [
    # Destructive file operations
    re.compile(r"\brm\s+-r"),           # rm -rf, rm -r (recursive delete)
    re.compile(r"\bsed\s+-i\b"),        # in-place file modification
    # Network access
    re.compile(r"\bcurl\b"),
    re.compile(r"\bwget\b"),
    re.compile(r"\bssh\b"),
    re.compile(r"\bscp\b"),
    # Git destructive operations
    re.compile(r"\bgit\s+push\b"),
    re.compile(r"\bgit\s+reset\b"),
    re.compile(r"\bgit\s+checkout\s+--"),
    re.compile(r"\bgit\s+clean\b"),
    re.compile(r"\bgit\s+rebase\b"),
    re.compile(r"\bgit\s+branch\s+-[dD]\b"),
    re.compile(r"\bgit\s+stash\s+drop\b"),
    # Privilege escalation / code execution
    re.compile(r"\bsudo\b"),
    re.compile(r"\bdd\b"),
    re.compile(r"\bmkfs\b"),
    re.compile(r"\beval\b"),
    re.compile(r"\bexec\b"),  # shell exec; codex exec is caught by FAST_ALLOW_PATTERNS first
    re.compile(r"\bsource\b"),
    # Script execution (should go through auto_classify for repo trust check)
    re.compile(r"\bpython3?\b"),
    re.compile(r"\buv\s+run\b"),
    re.compile(r"\bcargo\s+run\b"),
    re.compile(r"\bgo\s+run\b"),
    re.compile(r"\bjust\b"),
    re.compile(r"\bmake\b"),
    # Package installation (typosquat risk)
    re.compile(r"\bpip\s+install\b"),
    re.compile(r"\bnpm\s+install\b"),
    re.compile(r"\buv\s+pip\s+install\b"),
    # tmux command injection (can send arbitrary input to other sessions)
    re.compile(r"\btmux\s+send-keys?\b"),
    re.compile(r"\btmux\s+send\b"),
]

# Regex to extract command names from shell text (first word of each statement).
_CMD_NAME_RE = re.compile(r"(?:^|[;&|]\s*|do\s+|then\s+|else\s+)([a-zA-Z_][\w.-]*)")
# Matches VAR=value or VAR="..." (shell variable assignment, not a command).
_VAR_ASSIGN_RE = re.compile(r"^[A-Z_][A-Z0-9_]*=")

_SHELL_KEYWORDS = frozenset({
    "for", "while", "until", "if", "then", "else", "elif",
    "fi", "do", "done", "in", "case", "esac", "function",
    "select", "time", "coproc", "name",
})


def _is_compound_shell_safe(command: str) -> bool:
    """Check if a compound shell command only uses safe sub-commands."""
    # First: reject if any explicitly unsafe pattern appears
    for pat in UNSAFE_SHELL_PATTERNS:
        if pat.search(command):
            return False

    # Extract command names and check against safe set
    cmd_names = _CMD_NAME_RE.findall(command)
    if not cmd_names:
        return False

    # Filter out shell keywords and variable assignments (VAR=value).
    # The regex captures "CLAIMS_DIR" from 'CLAIMS_DIR="..."' — detect by
    # checking if NAME= appears in the original command.
    actual_cmds = [c for c in cmd_names
                   if c not in _SHELL_KEYWORDS
                   and f"{c}=" not in command]

    return bool(actual_cmds) and all(c in SAFE_SHELL_COMMANDS for c in actual_cmds)


# Regex to collapse inline code arguments (-c "..." / -e '...') that confuse
# the classifier when truncated mid-string (# becomes a "shell comment" false positive).
# Preserves the command structure so the classifier can evaluate the surrounding shell.
_INLINE_CODE_RE = re.compile(
    r"""(python3?|ruby|perl|node)\s+(-[ce])\s+"""         # interpreter + flag
    r"""(["'])(.*?)\3""",                                  # quoted body
    re.DOTALL,
)


def _simplify_bash_for_classify(command: str) -> str:
    """Replace inline code bodies with a placeholder to avoid false positives.

    `gws ... | python3 -c "import json\\n# comment\\n..."` becomes
    `gws ... | python3 -c "(inline code)"` — the classifier evaluates the shell
    structure without tripping on Python/Ruby/Perl comments.
    """
    return _INLINE_CODE_RE.sub(r'\1 \2 \3(inline code)\3', command)


def fast_classify_bash(command: str) -> str | None:
    """Return an allow reason if the command matches a known-safe pattern, else None.

    Architecture:
    1. FAST_ALLOW_PATTERNS — high-confidence, specific patterns (e.g., python -c,
       inspect eval). Checked first because they match exact command structures where
       substring-based denylists produce false positives (e.g., "eval" in "inspect eval").
    2. _is_compound_shell_safe — fallback for compound commands (for/while/&&) that
       Claude Code's parser can't handle. This has its own denylist (UNSAFE_SHELL_PATTERNS)
       checked before the allowlist, so compound commands with dangerous subcommands
       are still caught.
    """
    cmd = command.strip()

    # Step 1: Specific allowlist patterns (high-confidence, bypass denylist)
    for pattern, reason in FAST_ALLOW_PATTERNS:
        if pattern.search(cmd):
            return reason

    # Step 2: Compound shell safety check (has its own denylist internally)
    if _is_compound_shell_safe(cmd):
        return "compound shell with safe commands only"

    return None


# ── Fast-allow for edits within trusted repos ────────────────────────
# Tools that target a single file path. Edits inside your own dotfiles
# (or other trusted GitHub orgs) shouldn't need an LLM round-trip.
PATH_BASED_EDIT_TOOLS = frozenset({"Edit", "Write", "MultiEdit", "NotebookEdit"})


def _tool_target_path(tool_name: str, tool_input: dict) -> str:
    if tool_name in ("Edit", "Write", "MultiEdit"):
        return tool_input.get("file_path", "") or ""
    if tool_name == "NotebookEdit":
        return tool_input.get("notebook_path", "") or tool_input.get("file_path", "") or ""
    return ""


# Process-local cache: git toplevel -> trust dict. Avoids forking git for
# every Edit when many files live in the same repo (the common case).
_FILE_TRUST_CACHE: dict[str, dict] = {}


def _git_toplevel_for(path: str) -> str:
    """Return the git toplevel containing `path`, or '' if none."""
    import subprocess
    if os.path.isdir(path):
        search_dir = path
    else:
        search_dir = os.path.dirname(path) or "."
    try:
        proc = subprocess.run(
            ["git", "-C", search_dir, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except Exception:
        pass
    return ""


def _classify_owner(remote_url: str) -> tuple[str, bool, bool]:
    """Extract owner from a github URL and classify trust."""
    owner = ""
    if "github.com:" in remote_url:
        owner = remote_url.split("github.com:", 1)[1].split("/")[0]
    elif "github.com/" in remote_url:
        owner = remote_url.split("github.com/", 1)[1].split("/")[0]
    owner_lower = owner.lower()
    trusted = owner_lower in {u.lower() for u in TRUSTED_GITHUB_OWNERS}
    personal = owner_lower in {u.lower() for u in PERSONAL_GITHUB_USERS}
    return owner, trusted, personal


def detect_file_repo_trust(file_path: str) -> dict | None:
    """Resolve file_path's containing git repo and classify its trust.

    Walks symlinks first so `~/.claude/foo → dotfiles/...` is classified by
    the dotfiles repo, even when Claude's CWD is somewhere unrelated.
    Returns None if the file isn't in a git repo or detection fails.
    """
    if not file_path:
        return None
    try:
        abs_path = os.path.abspath(os.path.expanduser(file_path))
        real_path = os.path.realpath(abs_path)
    except (OSError, ValueError):
        return None

    toplevel = _git_toplevel_for(real_path)
    if not toplevel:
        return None
    if toplevel in _FILE_TRUST_CACHE:
        return _FILE_TRUST_CACHE[toplevel]

    import subprocess
    trust = {"toplevel": toplevel, "remote_url": "", "owner": "",
             "trusted": False, "personal": False}
    try:
        proc = subprocess.run(
            ["git", "-C", toplevel, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode == 0:
            trust["remote_url"] = proc.stdout.strip()
            trust["owner"], trust["trusted"], trust["personal"] = _classify_owner(trust["remote_url"])
    except Exception:
        pass

    _FILE_TRUST_CACHE[toplevel] = trust
    return trust


def fast_allow_edit(tool_name: str, tool_input: dict, cwd_trust: dict) -> str | None:
    """Allow edits to files inside any trusted/personal repo.

    Two-stage check:
    1. Cheap path: if cwd's repo is trusted AND the file (resolving symlinks)
       lives under that repo, allow without extra git calls.
    2. Symlink-into-another-repo path: walk up from the file's resolved path
       to find its containing repo, classify trust there. Catches edits like
       `~/.claude/skills/foo.md → dotfiles/...` from a non-dotfiles cwd.
    """
    if tool_name not in PATH_BASED_EDIT_TOOLS:
        return None

    file_path = _tool_target_path(tool_name, tool_input)
    if not file_path:
        return None

    try:
        abs_path = os.path.abspath(os.path.expanduser(file_path))
        real_path = os.path.realpath(abs_path)
    except (OSError, ValueError):
        return None

    # Stage 1: cwd-based trust (no extra git call needed).
    if cwd_trust.get("personal") or cwd_trust.get("trusted"):
        toplevel = cwd_trust.get("toplevel") or cwd_trust.get("cwd") or ""
        if toplevel:
            try:
                real_top = os.path.realpath(toplevel)
                if real_path == real_top or real_path.startswith(real_top + os.sep):
                    scope = "personal" if cwd_trust.get("personal") else "trusted"
                    return f"{tool_name} within {scope} cwd-repo {os.path.basename(real_top)}"
            except (OSError, ValueError):
                pass

    # Stage 2: file-resolved trust (covers symlinks pointing into a different
    # trusted repo than cwd's).
    file_trust = detect_file_repo_trust(file_path)
    if file_trust and (file_trust.get("personal") or file_trust.get("trusted")):
        scope = "personal" if file_trust.get("personal") else "trusted"
        return f"{tool_name} within {scope} file-repo {os.path.basename(file_trust['toplevel'])}"

    return None


class AutoClassifyWarning(RuntimeError):
    """Fail-open warning that should be surfaced to the user."""

    def __init__(self, headline: str, details: str = "", suggestion: str = "") -> None:
        super().__init__(headline)
        self.headline = headline
        self.details = details
        self.suggestion = suggestion


def detect_repo_trust(cwd: str) -> dict:
    """Read cached repo trust level, falling back to git detection.

    The cache is written once per session by the SessionStart hook.
    This avoids a subprocess call on every PermissionRequest.
    """
    # Try cache first (written by SessionStart hook for the session's CWD)
    try:
        with open(TRUST_CACHE) as f:
            cached = json.load(f)
        if cached.get("cwd") == cwd:
            return cached
    except Exception:
        pass

    # Fallback: detect and cache
    import subprocess

    result = {
        "trusted": False, "personal": False,
        "remote_url": "", "owner": "", "cwd": cwd, "toplevel": "",
    }
    try:
        proc = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        )
        if proc.returncode != 0:
            return result
        url = proc.stdout.strip()
        result["remote_url"] = url

        # Extract owner from github.com URLs
        # git@github.com:owner/repo.git or https://github.com/owner/repo.git
        owner = ""
        if "github.com:" in url:
            owner = url.split("github.com:")[1].split("/")[0]
        elif "github.com/" in url:
            owner = url.split("github.com/")[1].split("/")[0]

        result["owner"] = owner
        result["trusted"] = owner.lower() in {u.lower() for u in TRUSTED_GITHUB_OWNERS}
        result["personal"] = owner.lower() in {u.lower() for u in PERSONAL_GITHUB_USERS}

        # Resolve git toplevel so fast-path can match files anywhere in the repo,
        # not just under cwd (e.g., editing dotfiles/scripts/x from dotfiles/claude/).
        try:
            top = subprocess.run(
                ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=5,
            )
            if top.returncode == 0:
                result["toplevel"] = top.stdout.strip()
        except Exception:
            pass

        # Cache for subsequent calls
        try:
            os.makedirs(os.path.dirname(TRUST_CACHE), exist_ok=True)
            with open(TRUST_CACHE, "w") as f:
                json.dump(result, f)
        except Exception:
            pass
    except Exception:
        pass
    return result


def log(msg: str) -> None:
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        # Rotate if log exceeds 1MB
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG_BYTES:
            with open(LOG_PATH, "r") as f:
                lines = f.readlines()
            with open(LOG_PATH, "w") as f:
                f.writelines(lines[len(lines) // 2 :])
        with open(LOG_PATH, "a") as f:
            from datetime import datetime, timezone
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            f.write(f"{ts} {msg}\n")
    except Exception:
        pass


def build_warning_message(headline: str, details: str = "", suggestion: str = "") -> str:
    lines = [f"{ANSI_RED}🚨 auto-classify problem:{ANSI_RESET} {headline}"]
    if details:
        lines.append(f"{ANSI_YELLOW}⚠ Details:{ANSI_RESET} {details}")
    if suggestion:
        lines.append(f"{ANSI_CYAN}💡 Action:{ANSI_RESET} {suggestion}")
    return "\n".join(lines)


def emit_warning(headline: str, details: str = "", suggestion: str = "") -> None:
    msg = build_warning_message(headline, details, suggestion)
    log(f"WARNING: {headline} — {details or 'no details'}")
    # Stderr → user sees in terminal immediately
    print(msg, file=sys.stderr)
    # Stdout → Claude sees via systemMessage in PermissionRequest hook output
    json.dump({
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
        },
        "systemMessage": msg,
    }, sys.stdout)


def parse_anthropic_error(exc: urllib.error.HTTPError) -> tuple[str, str]:
    raw = ""
    error_type = ""
    message = str(exc)

    try:
        raw = exc.read().decode("utf-8", errors="replace")
    except Exception:
        raw = ""

    if raw:
        try:
            payload = json.loads(raw)
            error = payload.get("error", {})
            if isinstance(error, dict):
                error_type = str(error.get("type", "") or "")
                message = str(error.get("message", "") or message)
        except Exception:
            message = raw[:500]

    return error_type.lower(), message


def classify_api_problem(status: int, error_type: str, message: str) -> AutoClassifyWarning:
    combined = f"{error_type} {message}".lower()

    if any(token in combined for token in ("credit", "balance", "quota", "billing", "payment")):
        return AutoClassifyWarning(
            "Anthropic API key appears to be out of credits.",
            f"HTTP {status}: {message}",
            "Top up Anthropic credits or switch to a funded key. Claude will fall back to the normal permission prompt until this is fixed.",
        )

    if status in (401, 403) or "authentication" in combined or "invalid x-api-key" in combined:
        return AutoClassifyWarning(
            "Anthropic API key was rejected.",
            f"HTTP {status}: {message}",
            "Check ANTHROPIC_API_KEY in dotfiles-secrets or the hook wrapper, then retry.",
        )

    if status == 429 or "rate limit" in combined:
        return AutoClassifyWarning(
            "Anthropic auto-classify is rate limited.",
            f"HTTP {status}: {message}",
            "Wait for the rate limit window to clear or use the normal permission prompt for now.",
        )

    return AutoClassifyWarning(
        "Anthropic auto-classify request failed.",
        f"HTTP {status}: {message}",
        "Check ~/.cache/claude/auto-classify.log for details. Claude will use the normal permission prompt.",
    )


def extract_recent_user_messages(transcript_path: str, count: int = MAX_USER_MESSAGES) -> str:
    """Extract the N most recent user messages from the transcript JSONL.

    Returns them oldest-first so the LLM sees conversational flow.
    Only includes human messages (not assistant, tool_use, or tool_result).
    Fails silently — returns empty string on any error.
    """
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)
            # Read more tail to find enough user messages (they're sparse in JSONL)
            f.seek(max(0, f.tell() - 120_000))
            tail = f.read().decode("utf-8", errors="replace")

        messages: list[str] = []
        for line in reversed(tail.strip().splitlines()):
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") != "human":
                continue
            text = _extract_text(entry.get("message", ""))
            if text:
                truncated = text[:MAX_USER_MSG_CHARS] + "..." if len(text) > MAX_USER_MSG_CHARS else text
                messages.append(truncated)
                if len(messages) >= count:
                    break

        # Reverse to oldest-first order
        messages.reverse()
        if len(messages) == 1:
            return messages[0]
        return "\n---\n".join(f"[{i+1}/{len(messages)}] {m}" for i, m in enumerate(messages))
    except Exception:
        pass
    return ""


def _extract_text(msg: str | dict | list) -> str:
    """Pull plain text from a transcript message field."""
    if isinstance(msg, str):
        return msg.strip()
    if isinstance(msg, dict):
        return _extract_text(msg.get("content", ""))
    if isinstance(msg, list):
        return " ".join(
            b.get("text", "") for b in msg if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
    return ""


def classify(tool_name: str, tool_input: dict, cwd: str, rules: str, user_message: str = "") -> dict | None:
    """Call the classifier model to classify the action. Returns parsed response or None."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise AutoClassifyWarning(
            "ANTHROPIC_API_KEY is not set for the auto-classify hook.",
            "The hook cannot call Anthropic, so it is falling back to the normal permission prompt.",
            "Run `secrets-edit` / `setup-envrc`, or fix `with-anthropic-key.sh` so the hook gets a key.",
        )

    # Simplify tool inputs to reduce false positives and token usage
    input_str = json.dumps(tool_input, indent=2)
    if tool_name == "Bash" and "command" in tool_input:
        input_str = json.dumps(
            {**tool_input, "command": _simplify_bash_for_classify(tool_input["command"])},
            indent=2,
        )
    if len(input_str) > MAX_INPUT_CHARS:
        input_str = input_str[:MAX_INPUT_CHARS] + "\n... (truncated)"

    user_msg = f"Tool: {tool_name}\nInput: {input_str}\nWorking directory: {cwd}"
    if user_message:
        user_msg += f"\nUser's recent messages:\n{user_message}"

    body = json.dumps({
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "system": rules,
        "messages": [{"role": "user", "content": user_msg}],
    }).encode()

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            data = json.loads(resp.read())
        text = data["content"][0]["text"].strip()
        # Extract JSON robustly: find first { to last }
        start = text.find("{")
        end = text.rfind("}")
        if start == -1 or end == -1:
            raise AutoClassifyWarning(
                "Anthropic returned a malformed auto-classify response.",
                text[:200],
                "Check ~/.cache/claude/auto-classify.log. Claude will fall back to the normal permission prompt.",
            )
        return json.loads(text[start : end + 1])
    except urllib.error.HTTPError as e:
        error_type, message = parse_anthropic_error(e)
        raise classify_api_problem(e.code, error_type, message) from e
    except urllib.error.URLError as e:
        raise AutoClassifyWarning(
            "Anthropic auto-classify could not reach the API.",
            str(e.reason),
            "Check your network connection. Claude will fall back to the normal permission prompt.",
        ) from e
    except AutoClassifyWarning:
        raise
    except Exception as e:
        raise AutoClassifyWarning(
            "Anthropic auto-classify crashed unexpectedly.",
            str(e),
            "Check ~/.cache/claude/auto-classify.log. Claude will fall back to the normal permission prompt.",
        ) from e


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "unknown")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd", "")
    transcript_path = hook_input.get("transcript_path", "")

    # Early key check: warn loudly once per session if no API key.
    # Flag file prevents spamming every tool call. Reset after 1 hour (new session).
    if not os.environ.get("ANTHROPIC_API_KEY"):
        should_warn = False
        try:
            if not os.path.exists(NO_KEY_FLAG):
                should_warn = True
            else:
                age = time.time() - os.path.getmtime(NO_KEY_FLAG)
                should_warn = age > 3600
        except OSError:
            should_warn = True  # Can't check flag → warn to be safe
        if should_warn:
            try:
                os.makedirs(os.path.dirname(NO_KEY_FLAG), exist_ok=True)
                with open(NO_KEY_FLAG, "w") as f:
                    f.write("")
            except OSError:
                pass  # Flag file write failed (sandbox) — still warn below
            emit_warning(
                "auto-classify has NO API key — all non-trivial commands will fall back to manual prompts.",
                "with-anthropic-key.sh could not inject ANTHROPIC_API_KEY.",
                "Check: is bws in PATH? Run `dotfiles-secrets shell ANTHROPIC_API_KEY` to test.",
            )
            return  # Single JSON payload per hook invocation

    # Fast-path: deny reads OR writes to sensitive credential files (before any allow)
    sensitive_deny = fast_deny_sensitive_path(tool_name, tool_input)
    if sensitive_deny:
        reason = sensitive_deny.get("reason", "Blocked sensitive file access")
        suggestion = sensitive_deny.get("suggestion", "")
        log(f"DENY (sensitive-path): {tool_name} — {reason}")
        msg = f"\033[1;31m🔒 BLOCKED:\033[0m {reason}"
        if suggestion:
            msg += f"\n\033[1;36m💡 Instead:\033[0m {suggestion}"
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "deny"},
            },
            "systemMessage": msg,
        }, sys.stdout)
        return

    # Always surface tool calls that are themselves questions to the user.
    # Never auto-allow — the user must actually see the question.
    question_info = detect_question_to_user(tool_name, tool_input)
    if question_info:
        reason, suggestion = question_info
        log(f"SURFACE (question-to-user): {tool_name} — {reason}")
        msg = f"\033[1;36m🛈 auto-classify:\033[0m {reason} Surfacing to you."
        if suggestion:
            msg += f"\n\033[1;36m💡\033[0m {suggestion}"
        json.dump({"systemMessage": msg}, sys.stdout)
        return

    # Detect repo trust once — used by both fast-allow and the LLM rules.
    trust = detect_repo_trust(cwd)

    # Fast-path: bypass API for known-safe Bash patterns
    if tool_name == "Bash":
        cmd = tool_input.get("command", "")
        fast_reason = fast_classify_bash(cmd)
        if fast_reason:
            log(f"ALLOW (fast-path): {tool_name} — {fast_reason}")
            json.dump({
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "allow"},
                }
            }, sys.stdout)
            return

    # Fast-path: bypass API for edits inside trusted/personal repos
    edit_reason = fast_allow_edit(tool_name, tool_input, trust)
    if edit_reason:
        log(f"ALLOW (fast-path): {tool_name} — {edit_reason}")
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }, sys.stdout)
        return

    try:
        with open(RULES_PATH) as f:
            rules = f.read()
    except Exception:
        emit_warning(
            "auto-classify rules file could not be read.",
            RULES_PATH,
            "Check the dotfiles checkout on this machine. Claude will use the normal permission prompt.",
        )
        return

    # Inject repo trust context into rules
    trust_section = f"""
## Repo Trust Context (auto-detected)

- **Remote URL**: {trust['remote_url'] or 'unknown'}
- **Owner**: {trust['owner'] or 'unknown'}
- **Trusted repo**: {trust['trusted']}
- **Personal repo**: {trust['personal']}
"""
    rules = rules.replace(
        "## Environment",
        f"## Environment\n{trust_section}",
    )

    user_message = ""
    if INCLUDE_USER_MESSAGE and transcript_path:
        user_message = extract_recent_user_messages(transcript_path)

    try:
        result = classify(tool_name, tool_input, cwd, rules, user_message)
    except AutoClassifyWarning as warning:
        emit_warning(warning.headline, warning.details, warning.suggestion)
        return

    # Unknown/missing decision → treat as unsure (warn, don't auto-approve)
    raw_decision = result.get("decision", "")
    decision = raw_decision.lower() if isinstance(raw_decision, str) else ""
    reason = result.get("reason", "")
    if decision not in ("allow", "deny", "unsure"):
        log(f"UNSURE (unrecognized decision={raw_decision!r}): {tool_name} — {reason}")
        decision = "unsure"
    else:
        log(f"{decision.upper()}: {tool_name} — {reason}")

    # If the classifier said allow but its reason hedges or asks a question,
    # downgrade to unsure so the user gets the final call.
    if decision == "allow" and reason_hedges(reason):
        log(f"DOWNGRADE allow→unsure (hedged reason): {tool_name} — {reason}")
        decision = "unsure"

    if decision == "deny":
        # Show warning but don't block — let user decide
        suggestion = result.get("suggestion", "")
        msg = f"\033[1;33m⚠ auto-classify:\033[0m {reason}"
        if suggestion:
            msg += f"\n\033[1;36m💡 Suggestion:\033[0m {suggestion}"
        json.dump({"systemMessage": msg}, sys.stdout)
        return

    if decision == "unsure":
        # Not auto-approving — surface warning and fall through to manual prompt
        msg = (
            f"\033[1;33m⚠ auto-classify unsure — not auto-approving.\033[0m "
            f"Please review and approve manually."
        )
        if reason:
            msg += f"\n\033[1;36m💡 Reason:\033[0m {reason}"
        json.dump({"systemMessage": msg}, sys.stdout)
        return

    output = {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": {
                "behavior": "allow",
            },
        }
    }
    json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
