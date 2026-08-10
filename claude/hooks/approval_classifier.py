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
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request

RULES_PATH = os.path.join(os.path.dirname(__file__), "approval_classifier_rules.md")
API_URL = "https://api.anthropic.com/v1/messages"
MODEL = "claude-sonnet-5"
MAX_TOKENS = 500
# Sonnet 5 runs ADAPTIVE thinking when `thinking` is omitted; Sonnet 4.6 ran
# thinking-off by omission. That difference is load-bearing here for two reasons:
# `max_tokens` caps thinking + response text together, so an adaptive reply would
# spend MAX_TOKENS reasoning and truncate before emitting the JSON verdict; and
# thinking costs latency this hook does not have (see the budget below). Disabled
# keeps the 4.6 behaviour exactly. Legal because no `effort` is set — it defaults
# to `high`, and disabled thinking is rejected only at `xhigh`/`max`.
THINKING = {"type": "disabled"}
LOG_PATH = os.path.expanduser("~/.cache/claude/approval-classifier.log")

# --- End-to-end time budget ---
# Two sequential backends with independent timeouts can outlive the hook that
# spawned them. Claude kills the PermissionRequest command after
# HOOK_TIMEOUT_SECONDS, and a killed process writes no health file and emits no
# warning — so the statusline keeps reporting "healthy" in exactly the case this
# whole feature exists to make visible. One budget, allocated explicitly, with
# the tail reserved for the epilogue.
#
# HOOK_TIMEOUT_SECONDS MUST match the PermissionRequest "timeout" in
# claude/settings.json. Worst case: 8s API + 18s subscription + 4s epilogue = 30s.
HOOK_TIMEOUT_SECONDS = 30
EPILOGUE_RESERVE_SECONDS = 4  # write_health + emit_warning + stdout flush
TOTAL_BUDGET_SECONDS = HOOK_TIMEOUT_SECONDS - EPILOGUE_RESERVE_SECONDS
TIMEOUT_SECONDS = 8  # API backend — fail fast so the fallback gets real room

# Monotonic, set at import so interpreter startup and module import count against
# the budget too; the hook's clock started before any of this ran.
_STARTED_MONOTONIC = time.monotonic()

# ...but the hook's clock started even earlier than THAT. The configured command
# is `with-anthropic-key.sh python3 approval_classifier.py`, and the wrapper does
# a live `dotfiles-secrets shell ANTHROPIC_API_KEY` (a network BWS call, ~0.5s
# typical and unbounded on a slow link) before exec'ing Python. Timing only from
# import overstates what is left, and the overstatement lands exactly where it
# hurts: a fallback started with "enough" budget gets killed mid-flight, writing
# no health file — the silent-stale case the budget exists to prevent.
#
# The wrapper stamps HOOK_START_ENV before doing any work; anything unparseable,
# negative, or larger than the whole budget is treated as 0 rather than trusted.
HOOK_START_ENV = "APPROVAL_CLASSIFIER_HOOK_START"


def _pre_python_elapsed() -> float:
    """Seconds burned by the wrapper before this interpreter started."""
    raw = os.environ.get(HOOK_START_ENV, "")
    if not raw:
        return 0.0
    try:
        elapsed = time.time() - float(raw)
    except (TypeError, ValueError):
        return 0.0
    # Clock skew, a stale inherited value, or a wrapper that never ran would all
    # show up as nonsense here. Clamp instead of letting it distort the budget.
    if not 0.0 <= elapsed <= TOTAL_BUDGET_SECONDS:
        return 0.0
    return elapsed


_PRE_PYTHON_SECONDS = _pre_python_elapsed()


def remaining_budget() -> float:
    """Seconds left before the hook deadline, minus the epilogue reserve."""
    spent = _PRE_PYTHON_SECONDS + (time.monotonic() - _STARTED_MONOTONIC)
    return TOTAL_BUDGET_SECONDS - spent

# --- Subscription fallback (second backend) ---
# When the API-key path fails for ANY reason (no key, 401/403, 429, provider
# 5xx, credits, workspace limit), classify via the Claude CLI under its OAuth
# login instead of falling straight through to a manual permission prompt.
#
# `--bare` is deliberately NOT used: its help states "OAuth and keychain are
# never read", so it is the one mode that cannot reach the subscription.
# Verified 2026-08-03 — `claude -p --bare` returns "Not logged in".
# Recursion is prevented by NESTED_ENV instead (checked at the top of main()),
# which the child inherits through the environment.
SUBSCRIPTION_MODEL = "sonnet"
# The CLI counterpart of the API path's `thinking: {"type": "disabled"}`. Sonnet 5
# runs ADAPTIVE thinking when nothing says otherwise, and on this backend that is
# a latency problem rather than a truncation one: there is no max_tokens here, so
# the child simply thinks for as long as it likes while the hook's deadline runs
# down. Claude Code 2.1.223 exposes no `--thinking` flag (checked `claude --help`);
# `--effort` is the only lever, taking low|medium|high|xhigh|max.
#
# Measured 2026-08-06, 6 interleaved pairs, same flags as below, wall seconds:
#   default    6.4  7.3 10.0  7.1 39.4 12.6   (max 39.4)
#   --effort low  4.7  4.5  4.8  4.7  8.6  5.9   (max 8.6)
# Faster in 6/6 pairs (exact Wilcoxon signed-rank p=0.031); the point of it is the
# tail, not the median — the default arm's 39.4s draw would have blown the whole
# budget. Verdicts stayed well-formed and agreed on the same decision. Caveat for
# whoever revisits this: 0/6 over the ~18s production window has a Wilson upper
# bound of 39%, so this shows the mechanism is real, NOT that the tail is gone.
SUBSCRIPTION_EFFORT = "low"
# Ceiling only. The value actually passed is min(this, remaining_budget()), and
# the attempt is skipped entirely below SUBSCRIPTION_MIN_SECONDS — starting a
# ~9s call with 2s left just guarantees a kill mid-flight.
SUBSCRIPTION_TIMEOUT_SECONDS = 60
# Re-examined when SUBSCRIPTION_EFFORT landed, and deliberately left at 6. The
# "~9s call" above predates effort-low and reads like an argument for raising
# this to ~9 to cover the measured 8.6s tail; it is not. A timed-out call and a
# skipped one end in exactly the same manual prompt (see the TimeoutExpired
# handler in classify_via_subscription), and the 4s epilogue reserve means even
# a kill still has time to write health. So the gate is only avoiding *wasted*
# budget, never a worse outcome — and at effort-low's spread (5 of 6 samples
# under 6s) admitting at 6 buys a verdict most of the time for a bounded cost.
# Raising it to 9 would forfeit those to save ~6s in the tail case.
SUBSCRIPTION_MIN_SECONDS = 6
NESTED_ENV = "APPROVAL_CLASSIFIER_NESTED"

# Which backend last served a classification, read by the statusline.
# Written on EVERY attempt (successes included) so restoring a broken key
# returns the statusline to healthy on the next call with no manual reset.
HEALTH_PATH = os.path.expanduser("~/.cache/claude/approval-classifier-health.json")
HEALTH_BACKEND_API = "api"
HEALTH_BACKEND_SUBSCRIPTION = "subscription"
HEALTH_BACKEND_DEAD = "dead"
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
    # gws (Google Workspace CLI) — read and create operations are safe.
    # Deletes are caught by block_gws_delete.sh PreToolUse hook.
    # Verbs: list, get, search, export, create, insert, send (with --draft)
    # gws read-only: verb must appear as a standalone token (not inside JSON/flags),
    # and no shell chaining operators allowed. Write verbs (create, insert, update,
    # send) go through approval_classifier for proper intent evaluation.
    (re.compile(r"^gws\s+(?:(?!&&|[|]{2}|;)\S+\s+)*(list|get|search|export)\s"), "gws read-only operation"),
    # claude/codex/gemini --version/--help: pure info, no side effects
    (re.compile(r"^(claude|codex|gemini)\s+--(version|help)\b"), "CLI version/help check"),
    # sqlite3 read-only queries (Bear notes DB, etc.) — SELECT only, no destructive verbs.
    # Anchored to $ to prevent shell chaining: `sqlite3 db 'SELECT 1'; rm -rf ~`
    # would bypass UNSAFE_SHELL_PATTERNS without the end anchor.
    (re.compile(r"""^sqlite3\s+\S+\s+(?:'\s*SELECT\b[^']*'|"\s*SELECT\b[^"]*")\s*$""", re.IGNORECASE), "sqlite3 read-only SELECT"),
    # bearcli — read-only subcommands only. Mutating ops (edit, overwrite, create,
    # trash, archive, tags add/remove/rename, pin add/remove) go through classifier.
    (re.compile(r"^bearcli\s+(show|search-in|search|list|help)\b"), "bearcli read-only operation"),
    # Scripts in agent-owned temp dirs (TMPDIR or /tmp/claude — sandbox-writable scratch)
    (re.compile(r"^(?:python3?|bash|sh|zsh)\s+(?:/private)?/var/folders/[^/]+/[^/]+/T/claude/"), "agent script in $TMPDIR/claude/"),
    (re.compile(r"^(?:python3?|bash|sh|zsh)\s+/tmp/claude/"), "agent script in /tmp/claude/"),
]


# Commands that are always read-only or harmless — used to auto-allow
# compound shell statements (for/while/if/&&) that Claude Code's parser
# can't handle ("Unhandled node type: string").
SAFE_SHELL_COMMANDS: set[str] = {
    # File inspection (read-only)
    "cat", "head", "tail", "less", "more", "bat", "wc", "file", "stat",
    "ls", "eza", "tree", "du", "dust", "df", "duf", "realpath", "dirname",
    "basename", "readlink", "od", "xxd", "hexdump",
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

# Git global options (`git -C <path> push`, `git -c k=v push`) put arbitrary
# tokens between `git` and the subcommand, so `\bgit\s+<sub>` misses them and
# the compound-safe fast path would auto-allow the command. `[^;&|]*` stays
# within one shell statement so `git status; other push` doesn't match.
# Over-matching (a commit message containing "push") only routes the command
# to the LLM classifier — erring toward review, never toward allow.
def _git_unsafe(sub: str) -> re.Pattern[str]:
    return re.compile(rf"\bgit\b[^;&|]*\b{sub}")


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
    # Git destructive operations (option-tolerant: `git -C x push`, `git -c k=v push`)
    _git_unsafe(r"push\b"),
    _git_unsafe(r"reset\b"),
    _git_unsafe(r"checkout\s+--"),
    _git_unsafe(r"clean\b"),
    _git_unsafe(r"rebase\b"),
    _git_unsafe(r"branch\s+-[dD]\b"),
    _git_unsafe(r"stash\s+drop\b"),
    # Privilege escalation / code execution
    re.compile(r"\bsudo\b"),
    re.compile(r"\bdd\b"),
    re.compile(r"\bmkfs\b"),
    re.compile(r"\beval\b"),
    re.compile(r"\bexec\b"),  # shell exec; codex exec is caught by FAST_ALLOW_PATTERNS first
    re.compile(r"\bsource\b"),
    # Script execution (should go through approval_classifier for repo trust check)
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


class ApprovalClassifierWarning(RuntimeError):
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
    lines = [f"{ANSI_RED}🚨 approval classifier problem:{ANSI_RESET} {headline}"]
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


def classify_api_problem(status: int, error_type: str, message: str) -> ApprovalClassifierWarning:
    combined = f"{error_type} {message}".lower()

    if any(token in combined for token in ("credit", "balance", "quota", "billing", "payment")):
        return ApprovalClassifierWarning(
            "Anthropic API key appears to be out of credits.",
            f"HTTP {status}: {message}",
            "Top up Anthropic credits or switch to a funded key. Claude will fall back to the normal permission prompt until this is fixed.",
        )

    if any(token in combined for token in ("usage limit", "spend limit", "regain access", "workspace api")):
        return ApprovalClassifierWarning(
            "Anthropic workspace usage limit reached — the approval classifier is paused.",
            f"HTTP {status}: {message}",
            "Raise the workspace spend limit at console.anthropic.com, or switch to a key from a different workspace. Auto-classify will resume once the limit resets.",
        )

    if status in (401, 403) or "authentication" in combined or "invalid x-api-key" in combined:
        return ApprovalClassifierWarning(
            "Anthropic API key was rejected.",
            f"HTTP {status}: {message}",
            "Check ANTHROPIC_API_KEY in dotfiles-secrets or the hook wrapper, then retry.",
        )

    if status == 429 or "rate limit" in combined:
        return ApprovalClassifierWarning(
            "The approval classifier is rate limited.",
            f"HTTP {status}: {message}",
            "Wait for the rate limit window to clear or use the normal permission prompt for now.",
        )

    return ApprovalClassifierWarning(
        "The approval classifier's API request failed.",
        f"HTTP {status}: {message}",
        "Check ~/.cache/claude/approval-classifier.log for details. Claude will use the normal permission prompt.",
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


# Matches a push within one shell statement (`git -C x push`, `git push -u ...`),
# without crossing statement separators into an unrelated `push` word.
_GIT_PUSH_RE = _git_unsafe(r"push\b")

# Options that consume the following token, so the argument parser doesn't
# mistake their value for the remote or a refspec (`git push -o ci.skip origin main`).
_GIT_GLOBAL_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
_PUSH_VALUE_OPTS = {"-o", "--push-option", "--receive-pack", "--exec", "--repo"}
_PUSH_FORCE_OPTS = {"-f", "--force", "--force-with-lease", "--force-if-includes"}
_PUSH_DELETE_OPTS = {"-d", "--delete"}


def _parse_push_statement(command: str) -> tuple[str, list[str], list[str], str] | None:
    """Best-effort parse of the first `git … push` statement in `command`.

    Returns (remote, refspecs, flags, chdir) — empty strings/lists for absent
    pieces, chdir being any `-C <path>` operand — or None when no parseable
    `push` subcommand is found (`git stash push`, quoting the parser can't
    follow). None means no context block gets injected, and the rules already
    map an absent block to `unsure` for pushes: parse failure degrades to the
    manual prompt, never to a guessed destination.
    """
    for stmt in re.split(r"[;&|\n]", command):
        try:
            tokens = shlex.split(stmt)
        except ValueError:
            continue  # unbalanced quotes in this statement — don't guess
        if "git" not in tokens:
            continue
        i = tokens.index("git") + 1
        chdir = ""
        while i < len(tokens) and tokens[i].startswith("-"):
            if tokens[i] in _GIT_GLOBAL_VALUE_OPTS:
                if tokens[i] == "-C" and i + 1 < len(tokens):
                    chdir = os.path.join(chdir, tokens[i + 1]) if chdir else tokens[i + 1]
                i += 2
            else:
                i += 1
        if i >= len(tokens) or tokens[i] != "push":
            continue
        i += 1
        positionals: list[str] = []
        flags: list[str] = []
        while i < len(tokens):
            t = tokens[i]
            if t == "--":
                positionals.extend(tokens[i + 1:])
                break
            if t.startswith("-"):
                flags.append(t)
                i += 2 if t in _PUSH_VALUE_OPTS else 1
                continue
            positionals.append(t)
            i += 1
        remote = positionals[0] if positionals else ""
        return remote, positionals[1:], flags, chdir
    return None


def _git_push_context(command: str, cwd: str) -> str:
    """Deterministic git state for classifying a push, or '' for non-pushes.

    The push rules distinguish the default branch from feature branches and
    trivial pushes from substantive ones, but a bare `git push` carries none of
    that — the command text names no branch and no diff. Rather than have the
    model guess, gather the facts here and put them in the prompt, including
    the push *destination*: `git push origin main` from a feature branch still
    updates main, so HEAD alone is the wrong thing to report. Best-effort: any
    git failure or unparseable form yields a partial/absent block (the rules
    treat missing context and unknown destinations as grounds for `unsure`,
    so degradation errs toward the manual prompt).
    """
    if not _GIT_PUSH_RE.search(command):
        return ""
    parsed = _parse_push_statement(command)
    if parsed is None:
        return ""
    remote, refspecs, flags, chdir = parsed
    # `git -C x push` operates on x, not on the session cwd — describe x,
    # or the block would confidently report the wrong repository.
    git_dir = os.path.join(cwd, chdir) if chdir else cwd

    def run(*args: str) -> str:
        try:
            proc = subprocess.run(
                ["git", "-C", git_dir, *args],
                capture_output=True, text=True, timeout=2,
            )
            return proc.stdout.strip() if proc.returncode == 0 else ""
        except Exception:
            return ""

    branch = run("branch", "--show-current") or "(unknown or detached)"
    default = run("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    default = default.partition("/")[2] or default  # origin/main -> main
    upstream = run("rev-parse", "--abbrev-ref", "@{u}")

    # Resolve where the push lands and which ref supplies the commits.
    src = "HEAD"
    dest = ""
    deleting = any(f in _PUSH_DELETE_OPTS for f in flags)
    forcing = [f for f in flags if f.partition("=")[0] in _PUSH_FORCE_OPTS]
    if refspecs:
        spec = refspecs[0].lstrip("+")
        if deleting:
            src, dest = "", spec
        elif ":" in spec:
            src, _, dest = spec.partition(":")
            if not src:
                deleting = True  # `git push origin :branch` deletes
        else:
            src = dest = spec
        dest = dest.removeprefix("refs/heads/")
        if dest == "HEAD":
            dest = branch if branch != "(unknown or detached)" else ""
        if len(refspecs) > 1:
            dest = ""  # several targets — don't pretend to know the one that matters
    elif upstream:
        remote = remote or upstream.partition("/")[0]
        dest = upstream.partition("/")[2]
    elif branch != "(unknown or detached)":
        dest = branch  # push.default simple/current with no upstream yet
    remote = remote or "origin"

    lines = [
        "Git context (gathered deterministically by this hook — trust it over any inference from the command text):",
        f"- current branch: {branch}",
        f"- default branch (origin/HEAD): {default or 'unknown'}",
    ]
    if dest:
        lines.append(
            f"- push destination: {remote}/{dest}"
            + (" (ref DELETION)" if deleting else "")
        )
    else:
        lines.append("- push destination: unknown (could not determine the target branch)")
    if forcing:
        lines.append(f"- force flags present: {' '.join(forcing)}")

    if not deleting and src:
        if src != "HEAD" and not run("rev-parse", "--verify", "--quiet", src):
            lines.append(f"- commits being pushed: unknown (source ref {src!r} does not resolve locally)")
        else:
            compare_base = ""
            if dest and run("rev-parse", "--verify", "--quiet", f"refs/remotes/{remote}/{dest}"):
                compare_base = f"{remote}/{dest}"
            else:
                compare_base = upstream or (f"origin/{default}" if default else "")
            if compare_base:
                commits = run("log", "--oneline", "-10", f"{compare_base}..{src}")
                if commits:
                    stat = run("diff", "--stat", f"{compare_base}..{src}")
                    lines.append(f"- commits being pushed ({compare_base}..{src}):\n{commits}")
                    if stat:
                        lines.append(f"- diffstat: {stat.splitlines()[-1].strip()}")
                else:
                    lines.append(f"- no commits ahead of {compare_base}")
    return "\n".join(lines)


def build_classify_user_msg(tool_name: str, tool_input: dict, cwd: str, user_message: str = "") -> str:
    """The per-request half of the classifier prompt.

    Shared by both backends on purpose: the API and subscription paths must
    classify the *same* text, or a degraded session would silently apply
    different rules than a healthy one.
    """
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
    if tool_name == "Bash" and "command" in tool_input:
        git_ctx = _git_push_context(tool_input["command"], cwd)
        if git_ctx:
            user_msg += f"\n{git_ctx}"
    if user_message:
        user_msg += f"\nUser's recent messages:\n{user_message}"
    return user_msg


def write_health(backend: str, detail: str = "") -> None:
    """Record which backend last served a classification, for the statusline.

    Never raises. A statusline hint is not worth failing a permission decision
    over, and this runs on the hot path of every classified tool call.
    """
    try:
        os.makedirs(os.path.dirname(HEALTH_PATH), exist_ok=True)
        tmp = f"{HEALTH_PATH}.{os.getpid()}.tmp"
        with open(tmp, "w") as f:
            json.dump(
                {"backend": backend, "detail": detail[:200], "ts": int(time.time())}, f
            )
        os.replace(tmp, HEALTH_PATH)  # atomic: the statusline may be mid-read
    except Exception:
        pass


def extract_json_object(text: str) -> dict:
    """Parse the first {...} block out of a model response.

    Every failure leaves as an ApprovalClassifierWarning. It used to let
    json.JSONDecodeError escape when braces were present but the span between
    them was not valid JSON (a fenced block followed by prose containing a
    brace, say). That exception is not what callers catch, so it escaped the
    backend handler entirely: the hook died before write_health() ran, and the
    statusline went on reporting a healthy classifier that was in fact dead —
    precisely the invisibility this whole change exists to remove.
    """
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1:
        raise ApprovalClassifierWarning(
            "The classifier returned a malformed response.",
            text[:200],
            f"Check {LOG_PATH}. Claude will fall back to the normal permission prompt.",
        )
    try:
        return json.loads(text[start : end + 1])
    except ValueError as e:  # JSONDecodeError is a ValueError subclass
        raise ApprovalClassifierWarning(
            "The classifier returned a response that was not valid JSON.",
            f"{e}: {text[:200]}",
            f"Check {LOG_PATH}. Claude will fall back to the normal permission prompt.",
        ) from e


def classify_via_subscription(
    tool_name: str,
    tool_input: dict,
    cwd: str,
    rules: str,
    trust_section: str = "",
    user_message: str = "",
    timeout: float = SUBSCRIPTION_TIMEOUT_SECONDS,
) -> dict:
    """Second backend: classify through the Claude CLI's OAuth subscription.

    Used only after the API-key path has already failed. Substantially slower
    than the API (which answers in ~2.5s), so it is a fallback, never the
    default. Re-measured 2026-08-06 against Sonnet at SUBSCRIPTION_EFFORT: six
    interleaved samples spanned 4.5-8.6s wall, versus 4.5-39.4s with effort left
    at its default — see the constant for the paired comparison. Plan around the
    upper end, not the median; six samples cannot bound a tail.

    The attempt is budget-gated regardless (see remaining_budget and
    SUBSCRIPTION_MIN_SECONDS), so an underestimate costs a skipped fallback and a
    manual prompt, never a mid-flight kill. Note the gate compares against the
    budget, not against this range — if the observed spread ever creeps above
    SUBSCRIPTION_MIN_SECONDS' assumptions, raise the floor rather than hoping.

    Three deliberate choices here:
      * ANTHROPIC_API_KEY is stripped from the child's environment. Without
        this the CLI would reuse the very key that just failed instead of the
        subscription, and the fallback would be a no-op.
      * NESTED_ENV marks the child so its own PermissionRequest hook exits
        immediately — otherwise each classification would spawn another
        classification.
      * cwd is the home directory, not the caller's cwd. `claude -p`
        auto-discovers CLAUDE.md, and running in the target repo would let an
        untrusted repo's CLAUDE.md write instructions into the prompt that
        decides whether to auto-approve actions in that same repo.

    `--tools ""` is load-bearing, and it is now the ONLY thing bounding what the
    child can do. The child is otherwise a full Claude Code session, and the
    prompt necessarily contains attacker-influenced text (the tool_input being
    judged) — a session that can both read that text and execute commands is the
    whole attack. Note what `--safe-mode` costs here: it disables hooks, so the
    child's own PermissionRequest hook does not run at all and cannot deny
    anything. Before `--safe-mode` that hook still ran (NESTED_ENV made it skip
    classification but keep its fast-deny on `~/.ssh/id_*` and friends); it is
    gone now, so `--tools ""` has no backstop behind it.

    That makes "does `--tools ""` really mean zero tools?" a load-bearing
    question, so it was answered empirically rather than assumed: a child spawned
    with exactly these flags and told to read a canary file reported both Read
    and Agent disabled and could not open it (2026-08-03). Re-run that probe if
    these flags change.

    The rules go in `--system-prompt`, not the user turn, so the instructions and
    the untrusted text are not in the same channel — and it replaces the Claude
    Code agent persona, which this child has no use for.

    `--safe-mode` disables CLAUDE.md, skills, plugins, hooks, MCP servers, custom
    commands and agents in one flag (verified in `claude --help`, 2026-08-03),
    and it drops the child's startup cost. cwd=~ and NESTED_ENV are kept anyway:
    each control alone is a single point of failure if a flag's meaning drifts,
    and NESTED_ENV is what stops the recursion if `--safe-mode` ever stops
    disabling hooks.
    """
    user_msg = build_classify_user_msg(tool_name, tool_input, cwd, user_message)
    system_prompt = (
        f"{rules}\n{trust_section}\n\n"
        "Respond with ONLY the JSON object described above. No prose, no code fences."
    )

    # Strip every Anthropic/provider routing variable, not just the failed key.
    # A repo's direnv-approved .envrc can export ANTHROPIC_BASE_URL or
    # ANTHROPIC_AUTH_TOKEN, and the nested CLI honours them — which would let a
    # repo point the classifier deciding its own auto-approvals at an endpoint
    # that always answers "allow". The API backend cannot be redirected this way
    # (it hardcodes API_URL), so this is fallback-specific.
    # CLAUDE_CODE_USE_* is the provider-selector namespace (BEDROCK, VERTEX,
    # FOUNDRY, ...). Stripping the credentials alone is not enough: a selector
    # left set keeps the child routed at that provider, so the fallback either
    # errors or answers from somewhere that is not the subscription this backend
    # exists to reach. Matched by prefix rather than by an explicit list, because
    # an enumeration silently stops covering the case the day a new selector is
    # added — and the failure would be silent auto-approvals from an unintended
    # provider.
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("ANTHROPIC_") and not k.startswith("CLAUDE_CODE_USE_")
    }
    env[NESTED_ENV] = "1"

    try:
        proc = subprocess.run(
            [
                "claude", "-p",
                "--model", SUBSCRIPTION_MODEL,
                # Best-effort latency reduction, NOT the API path's
                # thinking:disabled -- effort is a behavioural signal rather
                # than a token budget, so a hard enough prompt can still think.
                # The CLI cannot express thinking-disabled at all; the timeout
                # clamp is what actually bounds this path.
                "--effort", SUBSCRIPTION_EFFORT,
                "--output-format", "json",
                "--tools", "",              # no tools: the child only emits JSON
                "--safe-mode",              # no CLAUDE.md, skills, plugins, hooks, MCP, agents
                "--disable-slash-commands", # nothing in the untrusted text can invoke a skill
                "--strict-mcp-config",      # no MCP servers to start or expose
                "--system-prompt", system_prompt,
            ],
            input=user_msg,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            cwd=os.path.expanduser("~"),
        )
    except FileNotFoundError as e:
        raise ApprovalClassifierWarning(
            "Both classifier backends are unavailable — the `claude` CLI is not on PATH.",
            str(e),
            "Claude will use the normal permission prompt until the API key or the CLI is fixed.",
        ) from e
    except subprocess.TimeoutExpired as e:
        raise ApprovalClassifierWarning(
            f"The subscription classifier timed out after {timeout:.0f}s.",
            "The API-key backend had already failed.",
            "Claude will use the normal permission prompt.",
        ) from e

    if proc.returncode != 0:
        raise ApprovalClassifierWarning(
            "The subscription classifier failed and the API key had already failed.",
            f"exit {proc.returncode}: {(proc.stderr or proc.stdout or '').strip()[:300]}",
            "Claude will use the normal permission prompt.",
        )

    try:
        payload = json.loads(proc.stdout)
    except Exception as e:
        raise ApprovalClassifierWarning(
            "The subscription classifier returned unreadable output.",
            (proc.stdout or "").strip()[:300],
            "Claude will use the normal permission prompt.",
        ) from e

    result_text = str(payload.get("result", "") or "")
    if payload.get("is_error"):
        suggestion = "Claude will use the normal permission prompt."
        if "not logged in" in result_text.lower():
            suggestion = (
                "Run `claude /login` to restore the subscription fallback, and fix "
                "ANTHROPIC_API_KEY to restore the fast path."
            )
        raise ApprovalClassifierWarning(
            "Both classifier backends failed — API key AND subscription.",
            result_text[:300],
            suggestion,
        )

    return extract_json_object(result_text)


def classify(tool_name: str, tool_input: dict, cwd: str, rules: str, trust_section: str = "", user_message: str = "") -> dict | None:
    """Call the classifier model to classify the action. Returns parsed response or None."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise ApprovalClassifierWarning(
            "ANTHROPIC_API_KEY is not set for the approval classifier hook.",
            "The hook cannot call Anthropic, so it is falling back to the normal permission prompt.",
            "Run `secrets-edit` / `setup-envrc`, or fix `with-anthropic-key.sh` so the hook gets a key.",
        )

    user_msg = build_classify_user_msg(tool_name, tool_input, cwd, user_message)

    # Cache the static rules block — Anthropic prompt caching charges ~10%
    # of base input rate on cache hits. Per-repo trust context goes in a
    # second, uncached block so it doesn't bust the cache key per cwd.
    system_blocks: list[dict] = [
        {"type": "text", "text": rules, "cache_control": {"type": "ephemeral"}},
    ]
    if trust_section:
        system_blocks.append({"type": "text", "text": trust_section})

    body = json.dumps({
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "thinking": THINKING,
        "system": system_blocks,
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
        # Log token usage so we can verify the prompt cache is landing.
        # cache_read_input_tokens > 0 on most calls → cache hit; if it's
        # consistently 0, the rules block changed or cache TTL expired.
        usage = data.get("usage", {}) or {}
        log(
            f"USAGE: model={MODEL} "
            f"input={usage.get('input_tokens', 0)} "
            f"output={usage.get('output_tokens', 0)} "
            f"cache_read={usage.get('cache_read_input_tokens', 0)} "
            f"cache_create={usage.get('cache_creation_input_tokens', 0)}"
        )
        return extract_json_object(text)
    except urllib.error.HTTPError as e:
        error_type, message = parse_anthropic_error(e)
        raise classify_api_problem(e.code, error_type, message) from e
    except urllib.error.URLError as e:
        raise ApprovalClassifierWarning(
            "The approval classifier could not reach the API.",
            str(e.reason),
            "Check your network connection. Claude will fall back to the normal permission prompt.",
        ) from e
    except ApprovalClassifierWarning:
        raise
    except Exception as e:
        raise ApprovalClassifierWarning(
            "The approval classifier crashed unexpectedly.",
            str(e),
            "Check ~/.cache/claude/approval-classifier.log. Claude will fall back to the normal permission prompt.",
        ) from e


def main() -> None:
    # Recursion guard. The subscription fallback spawns `claude -p`, which runs
    # its own PermissionRequest hooks; without this, every classification would
    # spawn another classification.
    #
    # It deliberately does NOT return here. Exiting at the top of main() would
    # disable this hook's *deny* half as well as its allow half, leaving a nested
    # session with no block on reads of ~/.ssh/id_*, .credentials.json and
    # friends. Only the LLM classification recurses, so only that is skipped: the
    # sensitive-path deny below still runs, and a nested session gets no
    # auto-approvals at all.
    #
    # For the child THIS file spawns, that deny half is currently unreachable —
    # `--safe-mode` disables hooks, so the nested PermissionRequest hook never
    # runs. The child is bounded by `--tools ""` instead (see
    # classify_via_subscription). This branch is kept because it is the correct
    # shape for any other nested invocation, and because it is what would carry
    # the load if `--safe-mode` ever stopped disabling hooks.
    nested = bool(os.environ.get(NESTED_ENV))

    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "unknown")
    tool_input = hook_input.get("tool_input", {})
    cwd = hook_input.get("cwd", "")
    transcript_path = hook_input.get("transcript_path", "")

    # A missing API key used to warn loudly and return here, which meant no
    # auto-approval at all — the failure mode behind the ~349-denial incident.
    # It is no longer a dead end: the request falls through to classify(), which
    # raises, and the subscription backend picks it up. The degradation is
    # surfaced by the statusline (see HEALTH_PATH) rather than by a per-call
    # warning, and the loud warning still fires if BOTH backends fail.
    if not nested and not os.environ.get("ANTHROPIC_API_KEY"):
        log("NO KEY: with-anthropic-key.sh injected nothing — trying the subscription backend")

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

    # Recursion stops here: the sensitive-path deny above has run, and
    # everything below either auto-approves or calls a classifier model, both of
    # which the nested session must not do.
    if nested:
        return

    # Always surface tool calls that are themselves questions to the user.
    # Never auto-allow — the user must actually see the question.
    question_info = detect_question_to_user(tool_name, tool_input)
    if question_info:
        reason, suggestion = question_info
        log(f"SURFACE (question-to-user): {tool_name} — {reason}")
        msg = f"\033[1;36m🛈 approval classifier:\033[0m {reason} Surfacing to you."
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
            "The approval classifier's rules file could not be read.",
            RULES_PATH,
            "Check the dotfiles checkout on this machine. Claude will use the normal permission prompt.",
        )
        return

    # Repo trust context goes in a separate (uncached) system block so the
    # static rules text keeps hitting the prompt cache across repos.
    trust_section = f"""
## Repo Trust Context (auto-detected)

- **Remote URL**: {trust['remote_url'] or 'unknown'}
- **Owner**: {trust['owner'] or 'unknown'}
- **Trusted repo**: {trust['trusted']}
- **Personal repo**: {trust['personal']}
"""

    user_message = ""
    if INCLUDE_USER_MESSAGE and transcript_path:
        user_message = extract_recent_user_messages(transcript_path)

    # Backend order: API key first (fast), subscription second (slower but
    # independent of the key). Only if BOTH fail does the user get the manual
    # prompt plus the loud warning.
    try:
        result = classify(tool_name, tool_input, cwd, rules, trust_section=trust_section, user_message=user_message)
        write_health(HEALTH_BACKEND_API)
    except ApprovalClassifierWarning as api_warning:
        log(f"API BACKEND FAILED: {api_warning.headline} — {api_warning.details}")
        budget = remaining_budget()
        if budget < SUBSCRIPTION_MIN_SECONDS:
            # Not enough of the hook deadline left to finish a fallback call.
            # Give up here, while there is still time to record it, rather than
            # starting a call that gets killed and leaves the health file stale.
            log(f"SUBSCRIPTION BACKEND SKIPPED: only {budget:.1f}s of budget left")
            write_health(HEALTH_BACKEND_DEAD, f"{api_warning.headline} | no time for fallback")
            emit_warning(
                api_warning.headline,
                f"{api_warning.details} — no time left in the hook budget "
                f"({budget:.1f}s) to try the subscription fallback",
                api_warning.suggestion,
            )
            return
        try:
            result = classify_via_subscription(
                tool_name, tool_input, cwd, rules,
                trust_section=trust_section, user_message=user_message,
                timeout=min(SUBSCRIPTION_TIMEOUT_SECONDS, budget),
            )
            write_health(HEALTH_BACKEND_SUBSCRIPTION, api_warning.headline)
            log("SUBSCRIPTION BACKEND: classified after the API backend failed")
        except ApprovalClassifierWarning as sub_warning:
            write_health(HEALTH_BACKEND_DEAD, f"{api_warning.headline} | {sub_warning.headline}")
            # Report the API failure as the primary cause — it is the one the
            # user can usually fix — and name the fallback's failure too, so a
            # broken `claude` login is not mistaken for a broken key.
            emit_warning(
                api_warning.headline,
                f"{api_warning.details} — subscription fallback also failed: {sub_warning.headline}",
                sub_warning.suggestion or api_warning.suggestion,
            )
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
        msg = f"\033[1;33m⚠ approval classifier:\033[0m {reason}"
        if suggestion:
            msg += f"\n\033[1;36m💡 Suggestion:\033[0m {suggestion}"
        json.dump({"systemMessage": msg}, sys.stdout)
        return

    if decision == "unsure":
        # Not auto-approving — surface warning and fall through to manual prompt
        msg = (
            f"\033[1;33m⚠ approval classifier unsure — not auto-approving.\033[0m "
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
