#!/usr/bin/env bash
# shellcheck disable=SC2016  # the embedded python must NOT be expanded by bash
# PreToolUse:Bash — block commands that would print a secret into the transcript.
#
# WHY THIS EXISTS
# A leaked secret in a Claude Code transcript is permanent: the transcript is
# replayed into context on resume, summarised, and stored on disk. There is no
# PostToolUse fix, because a PostToolUse hook cannot rewrite tool output — by
# the time it runs the value is already recorded. PreToolUse is the only place
# where refusing is still cheap.
#
# The concrete incident this guards against: `${ANTHROPIC_API_KEY:-not set}`
# used as a presence test. In bash that expansion prints the VALUE when the
# variable is set; only `${VAR:+x}` is a real presence test.
#
# SCOPE — deliberately surgical. Three classes, nothing else:
#   (a) wholesale environment dumps  — env, printenv, export -p, set,
#       declare -p/-x, direnv export|dump
#   (b) a secret-named variable expanded with a NON-EMPTY default —
#       ${KEY:-x} ${KEY:=x} ${KEY-x} ${KEY=x}.  ${KEY:-} and ${KEY:+x} pass.
#   (c) a secret-named variable inside an obvious print sink — echo, printf.
#       Two redacted-display slices are exempt: a prefix with offset
#       literally 0 and length <= 12 (${VAR:0:12} — key prefixes are
#       public constants), and a suffix of at most 6 (${VAR: -4} or
#       ${VAR:(-4)} — the distinguishing tail, capped tighter).
#       Without the space the suffix form is a DEFAULT expansion that
#       prints the whole value; class (b) keeps blocking it.
#
# WHY TOKENIZATION, NOT REGEX
# Same reasoning as block_gws_delete.sh: `pri""ntenv` executes as printenv but
# never matches a naive regex, and a `; env` hidden after an innocuous first
# command would be missed by a first-word check. So class (a) runs over
# shlex-normalised tokens of every `;`/`|`/`&&`-separated segment, recursing
# into `bash -c '<nested>'` payloads.
#
# WHY QUOTE-AWARENESS FOR (b)/(c)
# Inside single quotes nothing expands, so `rg '${API_KEY:-' scripts/` is a
# search, not a leak. Classes (b) and (c) therefore scan a view of the command
# with single-quoted regions blanked out. `bash -c '<nested>'` payloads are
# re-scanned unquoted so the blanking is not a bypass.
#
# ASYMMETRY
# A false positive costs one rewritten command. A false negative is a secret in
# the transcript forever. When the two trade off, this hook blocks.
#
# CONTRACT
#   exit 0 = allow.  exit 2 = block, reason on stderr.
# The reason names only the offending variable or command word — never the
# command line, which may itself contain a literal secret.

set -uo pipefail

INPUT=$(cat)

REASON=$(printf '%s' "$INPUT" | python3 -c '
import json, re, shlex, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)                      # unparseable hook payload: not our call
if data.get("tool_name") != "Bash":
    sys.exit(0)
cmd = ((data.get("tool_input") or {}).get("command") or "")
if not cmd.strip():
    sys.exit(0)

# --- secret-name heuristic -------------------------------------------------
# Substring markers, because names combine freely (AWS_SECRET_ACCESS_KEY,
# GH_PAT, CLIENT_SECRET). Path-shaped suffixes are exempt: BWS_TOKEN_FILE and
# DOTFILES_SECRETS_DIR hold locations, not values. _ID is deliberately NOT
# exempt beyond that -- MODAL_TOKEN_ID is half credential, half identifier, and
# a false positive there is cheap.
MARKERS = ("KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "PASSPHRASE",
           "CREDENTIAL", "BEARER")
EXEMPT_SUFFIX = ("_FILE", "_PATH", "_DIR")
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def secretish(name):
    n = name.upper()
    if n.endswith(EXEMPT_SUFFIX):
        return False
    if n == "PAT" or n.endswith("_PAT"):
        return True
    return any(m in n for m in MARKERS)


def safe_name(name):
    "Only ever emit a plain identifier; anything else is reported generically."
    return name if IDENT.match(name) else "<a secret-named variable>"


# --- quote-stripped view ---------------------------------------------------
def blank_non_expanding(s):
    """Blank out the parts of a command that bash will NOT expand.

    Two constructs, both faithful to bash rather than merely conservative:
      - single-quoted regions expand nothing, so `rg ${KEY:-x} f` is a search
      - a backslash escape kills the next char, so `printf "\\${KEY:-x}"` is
        a literal, not a leak (this is how commit messages quote the bug)
    Inside single quotes a backslash is literal, so escapes apply only outside.
    Because single-quoted text is blanked, `bash -c <payload>` is additionally
    re-scanned unquoted by analyze() -- otherwise the blanking would be a bypass.
    """
    SQ = chr(39)                     # this program is embedded in a bash
                                     # single-quoted string; no literal quote
    out = []
    inside = False
    escaped = False
    for ch in s:
        if escaped:                  # consumed by the preceding backslash
            out.append(" ")
            escaped = False
        elif ch == SQ:
            inside = not inside
            out.append(" ")
        elif inside:
            out.append(" ")
        elif ch == chr(92):          # backslash outside single quotes
            out.append(" ")
            escaped = True
        else:
            out.append(ch)
    return "".join(out)


SPLIT = re.compile(r"\|\||&&|[;\n|]")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "ash"}


def tokenized_segments(cmd):
    "Shlex-normalised token lists, one per shell segment."
    out = []
    for seg in SPLIT.split(cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()       # degrade, never skip
        if toks:
            out.append(toks)
    return out


def shell_payloads(toks):
    "Extract <nested> from `bash -c <nested>` style invocations."
    out = []
    for i, t in enumerate(toks):
        if t.rsplit("/", 1)[-1] not in SHELLS:
            continue
        for j in range(i + 1, len(toks) - 1):
            if toks[j] == "-c":
                out.append(toks[j + 1])
                break
    return out


# --- class (b): non-empty default on a secret-named variable ---------------
# `:+` and `${#VAR}` are absent from this pattern on purpose: they are the safe
# presence tests and must keep working.
DEFAULTED = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:?[-=])([^}]*)\}")


def check_defaults(view):
    hits = []
    for m in DEFAULTED.finditer(view):
        name, _op, default = m.group(1), m.group(2), m.group(3)
        if default.strip() and secretish(name):
            n = safe_name(name)
            hits.append(
                "${%s} with a non-empty default prints the VALUE when %s is "
                "set, not the default. Use ${%s:+set} for a presence test, or "
                "${%s:-} if you need an empty fallback." % (n, n, n, n))
    return hits


# --- class (c): secret-named variable in a print sink ---------------------
SINKS = {"echo", "printf"}
# The last three alternatives are the redacted-display exemptions:
#   prefix — offset literally 0, length 1-12: ${VAR:0:12}
#   suffix — last 1-6 chars only: ${VAR: -4} (space required by bash)
#            or ${VAR:(-4)}
# ${VAR:13} (everything AFTER the prefix), ${VAR:0:100}, ${VAR: -12} and
# any other offset stay blocked. The no-space suffix form is a non-empty
# DEFAULT, caught by class (b).
SAFE_EXPANSION = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*:\+[^}]*\}"
                            r"|\$\{#[A-Za-z_][A-Za-z0-9_]*\}"
                            r"|\$\{[A-Za-z_][A-Za-z0-9_]*:-\}"
                            r"|\$\{[A-Za-z_][A-Za-z0-9_]*:0:(?:[1-9]|1[0-2])\}"
                            r"|\$\{[A-Za-z_][A-Za-z0-9_]*: -[1-6]\}"
                            r"|\$\{[A-Za-z_][A-Za-z0-9_]*:\(-[1-6]\)\}")
ANY_EXPANSION = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")


def check_print_sinks(view):
    hits = []
    for toks in tokenized_segments(view):
        if toks[0].rsplit("/", 1)[-1] not in SINKS:
            continue
        rest = " ".join(toks[1:])
        rest = SAFE_EXPANSION.sub(" ", rest)   # ${V:+x}, ${#V}, ${V:-} are fine
        for m in ANY_EXPANSION.finditer(rest):
            if secretish(m.group(1)):
                hits.append(
                    "printing $%s would put the secret in the transcript. "
                    "Test presence instead: [ -n \"${%s:+x}\" ], or show a "
                    "redacted slice: ${%s:0:12} (prefix) or "
                    "${%s: -4} (suffix, space required)."
                    % ((safe_name(m.group(1)),) * 4))
    return hits


# --- class (a): wholesale environment dumps -------------------------------
ENV_FLAGS_WITH_ARG = {"-u", "-C", "-S", "--unset", "--chdir", "--split-string"}


def check_env(toks):
    "Block `env` only when no command word remains after flags/assignments."
    i = 1
    while i < len(toks):
        t = toks[i]
        if t in ENV_FLAGS_WITH_ARG:
            i += 2
            continue
        if t.startswith("-") or "=" in t:
            i += 1
            continue
        return []                    # a command word follows: `env -u K cmd`
    return ["`env` with no command prints every variable, including secrets. "
            "Name the variables you need, or use [ -n \"${VAR:+x}\" ]."]


def check_dumps(toks):
    head = toks[0].rsplit("/", 1)[-1]
    args = toks[1:]

    if head == "env":
        return check_env(toks)

    if head == "printenv":
        if not [a for a in args if not a.startswith("-")]:
            # No variable named: `printenv` and `printenv -0` both dump all.
            return ["`printenv` with no variable named prints every variable, "
                    "including secrets."]
        return ["`printenv %s` would print the secret. Test presence instead: "
                "[ -n \"${%s:+x}\" ]." % (safe_name(a), safe_name(a))
                for a in args if secretish(a)]

    if head == "export":
        if not args or args == ["-p"]:
            return ["`export`/`export -p` prints every exported variable with "
                    "its value, including secrets."]
        return []

    if head == "set":
        if not args:
            return ["bare `set` prints every shell variable with its value, "
                    "including secrets. `set -euo pipefail` is fine."]
        return []

    if head in ("declare", "typeset"):
        flags = [a for a in args if a.startswith("-")]
        if any("p" in f or "x" in f for f in flags) and not any(
                "=" in a for a in args):
            return ["`%s` with -p/-x prints variable values, including "
                    "secrets." % head]
        return []

    if head == "direnv" and args and args[0] in ("export", "dump"):
        return ["`direnv %s` serialises the whole environment this directory "
                "loads, including every secret in .envrc." % args[0]]

    return []


# --- driver ----------------------------------------------------------------
def analyze(cmd, depth=0):
    hits = []
    view = blank_non_expanding(cmd)
    hits += check_defaults(view)
    hits += check_print_sinks(view)
    for toks in tokenized_segments(cmd):
        hits += check_dumps(toks)
        if depth < 4:
            for payload in shell_payloads(toks):
                hits += analyze(payload, depth + 1)
    return hits


hits = analyze(cmd)
if hits:
    seen = []
    for h in hits:
        if h not in seen:
            seen.append(h)
    print("\n".join(seen[:3]))
' 2>/dev/null)

if [ -n "$REASON" ]; then
    printf 'BLOCKED — this command would print a secret into the transcript, where it stays permanently.\n\n%s\n' "$REASON" >&2
    exit 2
fi

exit 0
