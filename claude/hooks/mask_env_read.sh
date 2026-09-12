#!/usr/bin/env bash
# PreToolUse hook: mask secret values when .env/.envrc files are read.
#
# ---------------------------------------------------------------------------
# THIS HOOK IS NOT A SECURITY BOUNDARY. IT IS A GUARD RAIL AGAINST ACCIDENTS.
#
# It reads the command TEXT before the shell expands it, so it can only ever
# recognise the shapes it has been taught. A command-text filter cannot be
# complete, and no amount of widening will make it complete:
#
#     python3 -c "print(open(chr(46)+'env').read())"
#
# defeats every list in this file, and so does base64-ing the name, building
# the path from two variables, or reading through a file descriptor. Anyone
# who wants the value gets the value.
#
# So do NOT reason "the hook covers it" and drop a permission rule. That exact
# reasoning is why this file needed hardening: on 2026-09-12 `permissions.ask`
# on `Read(**/.env*)` was called redundant *because the hook existed*, while
# the hook had never blocked anything in its life (see the shape warning
# below). The permission rules are the gate. This hook is the thing that stops
# an ordinary `cat .env` from writing a live credential into the transcript
# where it stays forever.
#
# Current gate, for reference (claude/settings.json, permissions):
#     ask:   Read(**/.env)   Read(**/.env.*)
#     allow: Read(**/.envrc)   <-- no gate at all; for .envrc this hook is
#                                  the only thing in the way
# Neither rule covers the Bash tool, which is what most of the code below is.
# ---------------------------------------------------------------------------
#
# Intercepts:
#   - Read tool:  tool_input.file_path
#   - Grep tool:  tool_input.path  (only once settings registers a Grep matcher)
#   - Bash tool:  a reader command applied to an env file, in any shell segment
#
# Instead of allowing raw access, denies the read and returns the masked
# content as the denial reason. Keys are visible, values show first 4 chars
# + ****.
#
# Hook output format (JSON on stdout):
#   hookSpecificOutput.permissionDecision = "deny"
#   hookSpecificOutput.permissionDecisionReason = <masked content>
#
# WARNING: the deny key is permissionDecision. Claude Code silently ignores a
# nested decision.behavior object — the hook emitted that shape from its first
# commit until 2026-09-12 and blocked nothing at all for its whole life, while
# its test asserted only that the substring "deny" appeared somewhere in the
# output. Assert the KEY, never the substring.
#
# WARNING: a hook can only run if its `if` clause in settings.json lets it.
# `Bash(*.env*)` glob-matches the command text, so `cat notes.txt` — a symlink
# to .env — never reaches this file however well it is handled here. The
# symlink and quoted/variable-path handling below is worth having anyway, but
# it is live only when the hook is invoked.
#
# Known gaps, deliberately not chased: nested shells (`bash -c '...'`),
# interpreters that build the filename at runtime, anything reading through a
# pre-opened descriptor, and any reader not in the list below.
#
# Exit 0 always (JSON output controls behavior).

set -euo pipefail

INPUT=$(cat)

# The one deny path. Shape matches block_vault_structure.sh exactly: Claude
# Code reads hookSpecificOutput.permissionDecision and nothing else.
deny() {
    jq -n --arg r "$1" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}

# Extract tool_name and tool_input
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[[ -z "$TOOL_NAME" ]] && exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""

# The single argument handed to the detector: a path for the file tools, the
# whole command line for Bash.
SUBJECT=""
case "$TOOL_NAME" in
    Read)  SUBJECT=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0 ;;
    Grep)  SUBJECT=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // ""' 2>/dev/null) || exit 0 ;;
    Bash)  SUBJECT=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0 ;;
    *) exit 0 ;;
esac
[[ -z "$SUBJECT" ]] && exit 0

# One detector for all three tools. Prints the absolute path of the env file
# the call would read, or nothing. Failing open on an internal error is the
# deliberate choice: this is a guard rail, and a crashing guard rail must not
# wedge every Bash call in the session.
FILE_PATH=$(python3 - "$TOOL_NAME" "$SUBJECT" "$CWD" <<'PY' 2>/dev/null || true
import os
import re
import shlex
import sys

TOOL, SUBJECT, CWD = sys.argv[1], sys.argv[2], sys.argv[3]

# Commands that put file CONTENT somewhere a human or a transcript can see.
# Writers, movers and editors are deliberately absent: `git add .env`,
# `rm .env`, `mv .env x` and `vim .env` do not leak a value into the
# transcript, and intercepting them would break ordinary work for nothing.
READERS = {
    "cat", "head", "tail", "bat", "less", "more", "grep", "egrep", "fgrep",
    "rg", "sed", "awk", "gawk", "mawk", "nl", "tac", "rev", "cut", "od",
    "xxd", "hexdump", "strings", "base64", "dd", "diff", "source", ".",
}
# An inline script is a reader whenever an env filename appears in its text.
INTERPRETERS = {"python", "python2", "python3", "perl", "ruby", "node", "bun", "deno", "php"}
INLINE_FLAGS = ("-c", "-e", "-E", "-p", "-n")
# `cp .env /dev/stdout` is a read wearing a copy's clothes.
STDOUT_SINKS = {"/dev/stdout", "/dev/stderr", "/dev/fd/1", "/dev/fd/2",
                "/proc/self/fd/1", "/proc/self/fd/2"}
COPIERS = {"cp", "install"}
# `source FILE [args]` reads only its first argument. Enforcing that is not
# pedantry: a prose sentence inside a commit-message heredoc starts with ". ",
# which parses as the source builtin, and any filename later in the sentence
# would otherwise be read as its target.
SOURCERS = {"source", "."}
# Flags whose value is a pattern, a glob or a delimiter — never a file to read.
# `rg -g '.envrc'` names a glob; `grep -f .env` really does read .env, so -f is
# deliberately absent.
VALUE_FLAGS = {"-e", "--regexp", "-g", "--glob", "--iglob", "--include",
               "--exclude", "--exclude-dir", "-t", "--type", "-d",
               "--delimiter", "-m", "--max-count", "-S", "--sort"}
# `rg --files` lists filenames and never opens them.
NO_READ_FLAGS = {"--files", "-l", "--files-with-matches", "-L",
                 "--files-without-match"}

# Shell separators, plus the substitution delimiters. Splitting on `$(`, `)`
# and backticks is what catches `echo "$(cat .env)"` and
# `export $(cat .env | xargs)` — the two commonest accidental load idioms.
SPLIT = re.compile(r"\|\||&&|[;|\n]|\$\(|\)|`|<\(|>\(")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
REDIR = re.compile(r"^\d*(>>|>|<<<|<<|<)(.*)$")
ENV_TOKEN = re.compile(r"[^\s'\"]*\.env(?:rc|\.[A-Za-z0-9_.-]+)?")


def envish(name):
    return name in (".env", ".envrc") or name.startswith(".env.")


def is_env_file(path):
    """True if the path is named like an env file, or points at one.

    The second half is the symlink case: the basename check tests the link,
    so a link named anything at all walked straight past it before.
    """
    if envish(os.path.basename(path)):
        return True
    try:
        return envish(os.path.basename(os.path.realpath(path)))
    except OSError:
        return False


def absolutise(token, cwd):
    token = os.path.expanduser(token)
    if os.path.isabs(token):
        return os.path.normpath(token)
    return os.path.normpath(os.path.join(cwd, token)) if cwd else token


def expand(token, variables):
    """Resolve $VAR / ${VAR} from same-command assignments, then the real env.

    `V=/path/to/.env; cat "$V"` was a one-line bypass of a hook whose whole
    purpose is to stop that read: the text `cat "$V"` contains no .env at all.
    """
    def sub(match):
        name = match.group(1) or match.group(2)
        if name in variables:
            return variables[name]
        return os.environ.get(name, match.group(0))
    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", sub, token)


def candidates_of(segment, tokens, variables, cwd):
    """(paths this segment would READ, new cwd)."""
    name = os.path.basename(tokens[0])
    args = tokens[1:]

    if name in ("cd", "pushd"):
        target = [a for a in args if not a.startswith("-")]
        if target:
            return [], absolutise(expand(target[0], variables), cwd)
        return [], cwd

    files, reads, pending = [], [], None
    for arg in args:
        if pending == "out":
            pending = None
            continue
        if pending == "in":
            reads.append(arg)
            pending = None
            continue
        if pending == "flag":
            pending = None
            continue
        if arg in VALUE_FLAGS:
            pending = "flag"
            continue
        match = REDIR.match(arg)
        if match:
            operator, rest = match.group(1), match.group(2)
            if operator == "<":
                # An input redirection from an env file is a read whatever the
                # command is: `while IFS= read -r l; do :; done < .env`.
                if rest:
                    reads.append(rest)
                else:
                    pending = "in"
            elif operator in (">", ">>") and not rest:
                pending = "out"
            continue
        files.append(arg)

    if name in SOURCERS:
        reads += files[:1]
    elif name in READERS:
        # -l / --files print names, not contents.
        if not any(a in NO_READ_FLAGS for a in args):
            reads += files
    elif name in INTERPRETERS and any(a in INLINE_FLAGS for a in args):
        reads += ENV_TOKEN.findall(segment)
    elif name in COPIERS and any(expand(f, variables) in STDOUT_SINKS for f in files):
        reads += files

    return reads, cwd


def detect_bash(command, cwd):
    variables = {}
    for segment in SPLIT.split(command):
        segment = segment.strip()
        if not segment:
            continue
        try:
            tokens = shlex.split(segment, posix=True)
        except ValueError:
            # Heredocs and unbalanced quotes reach here. A parser error must
            # not silently drop the segment.
            tokens = segment.split()
        while tokens and ASSIGN.match(tokens[0]):
            key, _, value = tokens.pop(0).partition("=")
            variables[key] = expand(value, variables)
        if not tokens:
            continue
        variables["PWD"] = cwd
        reads, cwd = candidates_of(segment, tokens, variables, cwd)
        for token in reads:
            token = expand(token, variables)
            if not token or token.startswith("-"):
                continue
            path = absolutise(token, cwd)
            if is_env_file(path):
                return path
    return None


try:
    if TOOL == "Bash":
        found = detect_bash(SUBJECT, CWD)
    else:
        candidate = absolutise(expand(SUBJECT, {}), CWD)
        found = candidate if is_env_file(candidate) else None
    if found:
        print(found)
except Exception:  # noqa: BLE001 - a guard rail must not wedge the session
    pass
PY
)

# No env file detected — allow
[[ -z "$FILE_PATH" ]] && exit 0

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    # File doesn't exist — let the Read tool handle the error naturally
    exit 0
fi

# Check if file is binary (skip masking for binary files)
if file -b "$FILE_PATH" 2>/dev/null | grep -qi 'binary\|executable\|data'; then
    deny "Binary .env file detected — refusing to read."
fi

# Read and mask the file content
# Masking rules:
#   KEY=value      → KEY=valu****
#   KEY=ab         → KEY=ab****
#   KEY=           → KEY=           (empty, unchanged)
#   KEY="quoted"   → KEY="quot****"
#   export KEY=val → export KEY=valu****
#   # comment      → # comment      (unchanged)
#   empty lines    → (unchanged)

# Limit file size to prevent huge outputs (100KB max)
FILE_SIZE=$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)
if (( FILE_SIZE > 102400 )); then
    deny "Env file too large to mask safely: $FILE_PATH is over 100KB. This is unusually large for an env file — inspect it manually outside the transcript."
fi

# Process the file line by line
MASKED_CONTENT=$(python3 -c '
import sys, re

def mask_value(val):
    """Mask a value, preserving quotes if present."""
    if not val:
        return val

    # Detect and preserve surrounding quotes
    quote_char = ""
    inner = val
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ("\"", "'\''"):
        quote_char = val[0]
        inner = val[1:-1]

    if not inner:
        return val  # empty quoted string

    # Show first 4 chars, mask the rest
    visible = min(4, len(inner))
    masked = inner[:visible] + "****"

    if quote_char:
        return quote_char + masked + quote_char
    return masked

lines = []
for line in sys.stdin:
    line = line.rstrip("\n")

    # Preserve comments and blank lines
    stripped = line.lstrip()
    if not stripped or stripped.startswith("#"):
        lines.append(line)
        continue

    # Match: optional "export " + KEY = VALUE
    m = re.match(r"^(\s*(?:export\s+)?)([\w.]+)(=)(.*)", line)
    if m:
        prefix, key, eq, value = m.groups()
        lines.append(prefix + key + eq + mask_value(value))
    else:
        # Non-assignment lines (source directives, etc.) — pass through
        lines.append(line)

print("\n".join(lines))
' < "$FILE_PATH" 2>/dev/null) || {
    # Python failed — deny without content
    deny "Failed to mask env file: $FILE_PATH. Refusing the read rather than falling through to the raw value."
}

# Build the output JSON with masked content
# Truncate masked content if very long (keep the denial reason under 8KB)
MASKED_LENGTH=${#MASKED_CONTENT}
if (( MASKED_LENGTH > 8000 )); then
    MASKED_CONTENT="${MASKED_CONTENT:0:8000}
... (truncated, file has $MASKED_LENGTH chars)"
fi

deny "## Masked contents of $FILE_PATH

Secret values are masked (first 4 chars visible).

\`\`\`
$MASKED_CONTENT
\`\`\`

To read one value: \`dotfiles-secrets get-value 'ENV_NAME - description'\` (list keys with \`dotfiles-secrets keys-meta\`). To USE a secret without printing it: \`secrets run KEY_NAME -- <command>\`. Note \`printenv KEY_NAME\` is blocked by block_secret_expansion.sh — it would write the value into the transcript permanently."
