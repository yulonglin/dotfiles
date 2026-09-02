#!/usr/bin/env python3
"""PostToolUse(Bash) hook: tally repeat runs of throwaway scripts.

Pairs with simplify_nudge.sh (Stop), which turns the tally into a suggestion to
promote a scratch script into a permanent, reusable component. The signal we
want is "this throwaway earned its keep", not "a script exists":

  * only executions count — writing and editing a script is iteration, not reuse
    (that's what the simplify_mark_dirty.sh / simplify_nudge.sh pair covers);
  * a run whose file is byte-identical (same mtime) to the previous run is a
    "stable" run. Edit-run-edit-run debugging loops produce runs but no stable
    runs, so they never reach the promotion threshold. A path we can't stat is
    never stable — an unresolvable path is the least verified thing here, and
    counting it would nudge about scripts that don't exist.

Scratch-ness is judged *relative to the enclosing repo* when there is one, so a
repo or worktree checked out under /tmp doesn't make its whole test suite look
like scratch work, while a repo-local `tmp/` still does.

State lives in a per-user 0700 directory under TMPDIR. Concurrent Bash calls can
race on the read-modify-write; the loser silently loses one increment, which is
a fine outcome for a nudge and not worth a lock file.

Always exits 0 and never blocks — a tracking hook must not break a Bash call.
"""

import json
import os
import re
import shlex
import sys

SCRIPT_RE = re.compile(r"\.(py|sh|bash|zsh|js|mjs|cjs|ts|rb|pl|R)$")
# Cheap pre-filter so the overwhelming majority of Bash calls never reach the
# tokenizer: no script extension anywhere in the command, nothing to track.
SCRIPT_HINT_RE = re.compile(r"\.(py|sh|bash|zsh|js|mjs|cjs|ts|rb|pl|R)\b")
# shlex.split is quadratic in the length of a single token, and a giant token is
# exactly what `python3 -c '<program>'` or an inline base64 blob looks like. No
# scratch-script invocation is this long; refusing to tokenize keeps the hook
# far inside its timeout instead of stalling every large Bash call.
MAX_COMMAND_LEN = 20_000

# Throwaway *locations*: a tmp/scratch path segment, or macOS's /var/folders
# TMPDIR. Includes the agent scratchpad (/tmp/claude-*/…).
SCRATCH_DIR_RE = re.compile(r"(^|/)(tmp|temp|scratch|scratchpad|\.tmp|var/folders)(/|$)")
# Throwaway *names*: tmp_foo.py, scratch-check.sh, oneoff_backfill.py.
SCRATCH_NAME_RE = re.compile(r"^(tmp|temp|scratch|throwaway|oneoff|one_off)[-_.]")
# Vendored trees hold plenty of tmp/ paths that are nobody's scratch work.
VENDOR_RE = re.compile(r"/(node_modules|site-packages|\.venv|venv|\.git|dist|build)/")
# Directories that already are a permanent home — a script sitting in one has
# nowhere to be promoted to.
PERMANENT_PARENTS = {"bin", "sbin", "custom_bins", "tools", "scripts", "libexec"}

# A candidate path only counts when something ran it: an interpreter earlier in
# the same command segment, or the path itself in command position (./tmp/x.sh).
INTERPRETERS = {
    "python", "python3", "uv", "uvx", "bash", "sh", "zsh", "fish",
    "node", "bun", "deno", "tsx", "ts-node", "ruby", "perl", "Rscript",
    "pytest", "poetry", "pdm", "source", ".",
}
# Tokens after which the next word starts a fresh command. Glued operators
# (`x.py; echo`) are split into these by tokenize().
SEPARATORS = {
    "&&", "||", ";", "|", "|&", "&", "(", ")", "{", "}",
    "then", "else", "do", "done", "fi", "time", "nohup", "env", "exec",
    "xargs", "command",
}
SEPARATOR_RE = re.compile(r"[;|&()]+")
REDIRECTS = {">", ">>", "<", "<<", "2>", "2>>", "&>", "1>", ">|"}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def tokenize(command: str) -> list:
    """Shell-ish tokens, with glued operators promoted to their own tokens."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        # Unbalanced quotes (heredocs, mostly) — a dumb split still finds paths.
        tokens = command.split()

    flat = []
    for token in tokens:
        if not SEPARATOR_RE.search(token):
            flat.append(token)
            continue
        for i, part in enumerate(SEPARATOR_RE.split(token)):
            if i:
                flat.append(";")
            if part:
                flat.append(part)
    return flat


def resolve(token: str, cwd: str):
    """Absolute path for a command token, or None if it isn't literal enough."""
    if not token or "$" in token or "*" in token or "?" in token:
        return None
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(token)))


def repo_root(directory: str, cache: dict):
    """Nearest ancestor holding a .git, or None. Memoized per directory."""
    if directory in cache:
        return cache[directory]

    seen, current = [], directory
    root = None
    for _ in range(64):  # bounded: never walk a pathological path forever
        if current in cache:
            root = cache[current]
            break
        seen.append(current)
        if os.path.exists(os.path.join(current, ".git")):
            root = current
            break
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent

    for path in seen:
        cache[path] = root
    return root


def is_scratch(path: str, cache: dict) -> bool:
    """Does this look like a throwaway script rather than a real component?"""
    if not SCRIPT_RE.search(path) or VENDOR_RE.search(path):
        return False

    directory = os.path.dirname(path)
    # Inside a repo, judge the path by where it sits *in the repo*: a checkout
    # under /tmp is a checkout, not scratch — but its own tmp/ dir still is.
    root = repo_root(directory, cache)
    relative = os.path.relpath(directory, root) if root else directory
    if relative == ".":
        relative = ""

    if PERMANENT_PARENTS & set(relative.split(os.sep)):
        return False
    if SCRATCH_DIR_RE.search(relative):
        return True
    return bool(SCRATCH_NAME_RE.match(os.path.basename(path)))


def scripts_run(command: str, cwd: str) -> list:
    """Absolute paths of scratch scripts this command executes (deduped)."""
    if len(command) > MAX_COMMAND_LEN or not SCRIPT_HINT_RE.search(command):
        return []

    tokens = tokenize(command)
    found, cache = [], {}
    at_cmd_start, saw_interpreter, prev = True, False, ""

    for i, token in enumerate(tokens):
        if token in SEPARATORS:
            at_cmd_start, saw_interpreter, prev = True, False, ""
            continue
        if prev in REDIRECTS:  # a redirect target was written, not run
            prev = token
            continue
        prev = token
        if ASSIGN_RE.match(token) or token.startswith("-"):
            continue  # env assignment or flag: neither starts nor ends a command

        # `cd /tmp/work && ./probe.sh` — follow the cwd or the path resolves
        # against the wrong directory and we nudge about a file that isn't there.
        if at_cmd_start and token == "cd" and i + 1 < len(tokens):
            target = resolve(tokens[i + 1], cwd)
            if target and os.path.isdir(target):
                cwd = target
            continue

        if os.path.basename(token) in INTERPRETERS:
            saw_interpreter = True
            at_cmd_start = False
            continue

        executed = at_cmd_start or saw_interpreter
        at_cmd_start = False
        if not executed:
            continue

        path = resolve(token, cwd)
        if path and path not in found and is_scratch(path, cache):
            found.append(path)
    return found


def state_path(session_id: str):
    """Per-session state file inside a private per-user directory, or None.

    0700 and ownership-checked: the file's contents reach the user as a
    systemMessage, so another local account must not be able to write it.
    """
    tmp = os.environ.get("TMPDIR") or "/tmp"
    directory = os.path.join(tmp, f"claude-simplify-{os.geteuid()}")
    try:
        os.makedirs(directory, mode=0o700, exist_ok=True)
        info = os.stat(directory)
    except OSError:
        return None
    if info.st_uid != os.geteuid() or info.st_mode & 0o077:
        return None
    return os.path.join(directory, f"reuse-{session_id}.json")


def load_state(path: str) -> dict:
    try:
        with open(path) as fh:
            state = json.load(fh)
        return state if isinstance(state, dict) else {}
    except Exception:
        return {}


def save_state(path: str, state: dict) -> None:
    tmp_path = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp_path, "w") as fh:
            json.dump(state, fh)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def count(value) -> int:
    """Coerce a tally that a corrupt state file may have turned into anything."""
    try:
        return max(int(value), 0)
    except (TypeError, ValueError):
        return 0


def record(state: dict, script: str) -> None:
    try:
        mtime = os.path.getmtime(script)
    except OSError:
        mtime = None  # unresolvable path: counts as a run, never as stable

    entry = state.get(script)
    if not isinstance(entry, dict):
        entry = {"runs": 0, "stable": 0, "mtime": None, "notified": False}
    entry["runs"] = count(entry.get("runs")) + 1
    if mtime is not None and entry.get("mtime") == mtime:
        entry["stable"] = count(entry.get("stable")) + 1
    else:
        entry["stable"] = count(entry.get("stable"))
    entry["mtime"] = mtime
    entry["notified"] = bool(entry.get("notified"))
    state[script] = entry


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(payload, dict):
        return

    session_id = payload.get("session_id") or ""
    tool_input = payload.get("tool_input")
    if not session_id or "/" in session_id or not isinstance(tool_input, dict):
        return

    command = tool_input.get("command") or ""
    if not isinstance(command, str) or not command:
        return

    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        cwd = os.getcwd()

    scripts = scripts_run(command, cwd)
    if not scripts:
        return

    path = state_path(session_id)
    if not path:
        return
    state = load_state(path)
    for script in scripts:
        record(state, script)
    save_state(path, state)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
