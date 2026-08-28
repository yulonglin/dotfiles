#!/usr/bin/env python3
"""Global PreToolUse(Bash) hook: BLOCKS the four hard supply-chain gates.

These are the prohibitions from rules/safety.md § Supply chain that were
previously prose-only. Prose asks the model to refrain; this refuses.

Blocks:
  1. Third-party Homebrew taps    — `brew tap owner/repo`, `brew install owner/repo/formula`
  2. Arbitrary URL / git installs — pip/uv/npm/pnpm/bun/yarn installing from
                                    git+, github:, an http(s) package URL, or
                                    any of npm's scheme-less git spellings
  3. `--ignore-scripts=false`     — re-enabling npm lifecycle scripts, in any
                                    of its flag, negation, and env spellings
  4. `--no-quarantine`            — disabling Gatekeeper on a cask

Allows: `--help`, `--dry-run`, local paths, local editable installs, a LOCAL
`-r requirements.txt`, official `homebrew/*` taps and formulae, and
index/registry/mirror flags (a custom index is a real vector but is NOT one of
the four named gates — keeping the gate precise avoids blocking
`pip install -i <mirror> pkg`).

Each block names the recourse. The hook itself blocks UNCONDITIONALLY — there
is no in-hook approval bypass, deliberately: an approval marker or retry token
would be a new injectable surface on a security boundary. The override is the
user running the command themselves (`! <cmd>` in the prompt runs it in-session)
or removing the hook from settings.json.

DESIGN: fail CLOSED on ambiguity, and never trust a *representation* of the
command in place of the command. Four separate fail-open bugs all came from that
one mistake, so each is now structural rather than patched:

  * Wrapper flags — `sudo -n` is boolean, `nice -n` takes a value, and the two
    are token-identical. No skip table can tell them apart, so we do not try:
    every plausible command start is tested (`candidate_starts`).
  * Safe flags — `bash -c '<payload>' --help` gives `--help` to the wrapper as
    `$0`; bash still executes the payload. So nested strings are extracted and
    checked BEFORE any --help/--dry-run exemption can apply, and the exemption
    only ever covers the segment that literally carries it.
  * Shell options — `bash -lc`, `sh -ec` execute their string exactly as
    `bash -c` does. Any single-dash cluster containing `c` is treated as
    introducing a nested command.
  * Flag arity — `-f`/`-p` take values for pip and are booleans for npm, and
    `-w` takes a value for npm while being a boolean for pnpm, so one shared
    table either skips over a package or falsely denies a workspace install.
    Tables are keyed on the CONCRETE tool, never on a family.
  * Command separators — a newline separates commands exactly as `;` does. It
    was being lexed as ordinary whitespace, so a `--help` on line 1 silently
    exempted an install on line 2. Separators are decided in the lexer, where
    quoting is already understood (see split_segments).
  * Named exemptions — `homebrew/*` is exempt because the NAME resolves to the
    official remote. Supply an explicit remote and the name no longer says where
    the code comes from, so the exemption is refused rather than re-validated.

Quoting is likewise never matched against raw text: the command is lexed with
shlex (punctuation-aware) so `de""lete`, `+se""nd`, and a `;` inside a quoted
URL are all resolved the way the shell would resolve them.

Cost note: gate logic scans by INDEX, never by suffix slice. Retained `tokens[i:]`
copies made a benign 8,000-token command cost ~259 MB, and a hook that gets
OOM-killed is a silent permit.

Over-blocking prints a message naming the recourse; under-blocking is
silent permission. When in doubt, block.

KNOWN LIMITATION (accepted): the hook sees the command BEFORE shell expansion,
so a URL smuggled through a variable (`U=git+https://…; pip install "$U"`) is
invisible at this layer. The only fix — blocking any variable use in install
commands — is mass over-blocking; the 7-day quarantine and OSV check remain
the downstream defenses on that path.

Exit 0 = allow, exit 2 = block.
"""

import json
import re
import shlex
import sys

# --- Gate 2 tables -----------------------------------------------------------
# Per-installer, because arity is installer-specific. npm's -f is --force and
# its -p is --parseable (both boolean); pip's -f is --find-links and its -p is
# --python (both take a value). A shared table skips the token after npm's -f,
# which is exactly where the remote package sits.
# The same collision exists WITHIN the node family, so "node" is not a fine
# enough key either: `-w` takes a VALUE for npm (`--workspace`; npm's own
# lib/utils/config/definitions.js gives `type: [String, Array], short: 'w'`) and
# is a BOOLEAN for pnpm (`--workspace-root`, pnpm.io/pnpm-cli). One shared node
# table cannot hold both — it must either falsely deny
# `npm install -w packages/web lodash` or skip the token after pnpm's `-w`.
# So tables are keyed on the CONCRETE tool, and only the family-wide flags are
# shared.
#
# DIRECTION OF ERROR, which decides what may be added here: omitting a
# value-taking flag can only over-block (its value gets scanned, and only trips
# if it looks remote). Wrongly listing a BOOLEAN flag skips the following token
# and fails OPEN. Every entry below was read off the tool's own definitions or
# --help, never from recollection; anything unverified is deliberately absent.
PIP_URL_BY_DESIGN = {
    "-i", "--index-url", "--extra-index-url", "--find-links", "-f",
    "--trusted-host", "--proxy", "--cert", "--client-cert",
}
PIP_PATH_VALUE = {
    "--config-settings", "--python", "-p", "--prefix", "--target", "-t",
    "--cache-dir", "--build-dir", "--src",
}
# Shared by the whole node family: same spelling, same arity in npm/pnpm/yarn/bun.
NODE_URL_BY_DESIGN = {
    "--registry", "--proxy", "--https-proxy", "--cert", "--cafile", "--ca",
}
NODE_PATH_VALUE = {"--prefix", "--cache", "--cwd", "-C", "--userconfig", "--globalconfig"}

# Per-tool value-taking flags. DELIBERATELY ABSENT because they are booleans and
# listing them would skip a package spec: npm `--workspaces`/`-ws` and
# `--include-workspace-root`, pnpm `-w`/`--workspace-root` and `--workspace`,
# yarn `-W`/`--ignore-workspace-root-check`.
NPM_VALUE_FLAGS = {
    "--workspace", "-w", "--omit", "--include", "--loglevel", "--save-prefix",
}
PNPM_VALUE_FLAGS = {"--filter", "-F", "--filter-prod", "--dir"}
BUN_VALUE_FLAGS = {"--filter", "--backend", "--config", "-c"}
YARN_VALUE_FLAGS: set[str] = set()  # none verified beyond the shared --cwd

FLAG_TABLES = {
    "pip": (PIP_URL_BY_DESIGN, PIP_PATH_VALUE),
    "npm": (NODE_URL_BY_DESIGN, NODE_PATH_VALUE | NPM_VALUE_FLAGS),
    "pnpm": (NODE_URL_BY_DESIGN, NODE_PATH_VALUE | PNPM_VALUE_FLAGS),
    "bun": (NODE_URL_BY_DESIGN, NODE_PATH_VALUE | BUN_VALUE_FLAGS),
    "yarn": (NODE_URL_BY_DESIGN, NODE_PATH_VALUE | YARN_VALUE_FLAGS),
}

# Concrete installer -> family. The scheme-less git spellings in is_remote_pkg
# are an npm-ecosystem behaviour shared by all four node tools, so that check
# keys on the FAMILY while FLAG_TABLES keys on the concrete tool. Splitting the
# tables without this indirection would have silently switched every scheme-less
# check off, turning `npm install foo/bar` into an allow.
INSTALLER_FAMILY = {
    "pip": "pip", "npm": "node", "pnpm": "node", "bun": "node", "yarn": "node",
}

# Flags whose VALUE must still be checked: a remote requirements/constraints
# file or editable target is precisely the arbitrary-URL-install vector, and
# `uv run`/`uvx` `--with`/`--from` specs are installs by another name.
CHECKED_VALUE_FLAGS = {
    "-r", "--requirement", "-c", "--constraint", "-e", "--editable",
    "--with", "--with-requirements", "--from",
}

REMOTE_PKG_RE = re.compile(
    r"^((git|hg|svn|bzr)\+|github:|gitlab:|bitbucket:|gist:|https?://|git://|ssh://|file://)",
    re.IGNORECASE,
)
ARCHIVE_URL_RE = re.compile(r"^https?://.*\.(tgz|tar\.gz|whl|zip)$", re.IGNORECASE)
# PEP 508 direct references (`pip install "demo @ https://host/demo.whl"`) put
# the URL after `@` INSIDE one token, where the anchored regex never sees it.
# Scoped npm names (`@types/node`) don't match: the `@` must be followed by a
# scheme, not a name.
EMBEDDED_REMOTE_RE = re.compile(
    r"@\s*((git|hg|svn|bzr)\+|(https?|git|ssh|file)://)", re.IGNORECASE
)
# `uv run` / `uvx` positionals are the tool's OWN argv — `uv run fetch.py
# https://api.example.com/data` is a benign data URL, not a package spec — so
# they are matched only against unambiguous package forms (VCS schemes,
# archives); --with/--from values still get checked via CHECKED_VALUE_FLAGS.
UV_RUN_POSITIONAL_RE = re.compile(r"^((git|hg|svn|bzr)\+|git://|ssh://)", re.IGNORECASE)

# npm accepts git dependencies in spellings that carry no URL scheme at all.
# `npm i foo/bar` is documented GitHub shorthand (optionally pinning a
# committish: `foo/bar#branch`); `git@host:path` is an scp-style git URL;
# `alias@github:owner/repo` embeds the host after the alias separator.
NPM_HOST_ALIAS_RE = re.compile(r"(^|@)(github|gitlab|bitbucket|gist):", re.IGNORECASE)
NPM_SCP_GIT_RE = re.compile(r"^[\w.-]+@[\w.-]+:[^/].*$")
NPM_SHORTHAND_RE = re.compile(r"^[\w.-]+/[\w.-]+(#\S+)?$")

# owner/repo/formula — a tapped formula reference
TAP_FORMULA_RE = re.compile(r"^[\w.-]+/[\w.-]+/[\w.@+-]+$")
# Taps under the homebrew org are official sources, explicitly allowed by policy.
OFFICIAL_TAP_RE = re.compile(r"^homebrew/", re.IGNORECASE)

ENV_ASSIGN_RE = re.compile(r"^[A-Za-z_]\w*=")
SAFE_FLAGS = {"--help", "-h", "--dry-run"}
# `\r` separates alongside `\n`: a CRLF script ends its lines with `\r\n`, and
# recognising only `\n` would leave the `\r` glued to the following token.
NEWLINE_CHARS = "\n\r"
OPERATOR_CHARS = set(";&|()") | set(NEWLINE_CHARS)
# shlex's DEFAULT punctuation set, plus the newline forms. The default must be
# spelled out and carried through: passing only the newlines would drop
# `;`/`&`/`|` from punctuation, and `echo hi;brew tap evil/repo` (no spaces
# around the `;`) would then lex as the single token `hi;brew` — a live bypass.
LEX_PUNCTUATION = "();<>|&" + NEWLINE_CHARS

# Shells whose `-c STRING` argument is a whole nested command. shlex keeps that
# string as ONE token, so without re-entering it `bash -c "pip install git+..."`
# is invisible to every token-level gate.
SHELL_CMDS = {"bash", "sh", "zsh", "dash", "ksh", "ash"}
MAX_NEST_DEPTH = 4

NODE_INSTALLERS = {"npm", "pnpm", "yarn", "bun"}
INSTALL_SUBCMDS = {"install", "i", "add"}


def block(title: str, detail: str, recourse: str) -> None:
    print(f"BLOCKED: {title}", file=sys.stderr)
    print(detail, file=sys.stderr)
    print(f"To proceed: {recourse}", file=sys.stderr)
    sys.exit(2)


def basename(tok: str) -> str:
    return tok.rsplit("/", 1)[-1]


def candidate_starts(tokens: list[str]) -> list[int]:
    """Indices of every token that could plausibly begin the real command.

    Keying on tokens[0] requires correctly modelling each wrapper's flag
    arity; getting that wrong fails OPEN. Testing all starts needs no such
    model, so `sudo -n pip install URL`, `nice -n 10 pip install URL`, and
    `env A=1 doas -u x pip install URL` are all covered by construction.

    Returns INDICES rather than suffix lists. `tokens[i:]` allocated and retained
    a fresh copy per token, so a benign 8,000-token command cost ~259 MB. This is
    a pure representation change: the set of positions examined is identical, and
    index 0 is included unconditionally, exactly as the old `out = [tokens]` did,
    even when tokens[0] is a flag or an env assignment.

    REJECTED ALTERNATIVE (review 3): restrict scanning to "actual wrapper command
    positions" so `echo pip install <URL>` would be allowed instead of blocked.
    Declined deliberately. Deciding which positions are real command starts is
    precisely the wrapper-arity model this function exists to avoid — any such
    list is a skip table under another name, and one wrong entry reopens a
    bypass, which is how three of the four fail-opens in the module docstring
    happened. The costs are asymmetric: over-blocking a literal `echo` of an
    install command is a low-frequency annoyance that prints a recourse,
    while a missed wrapper is silent permission. Recorded here as a live design
    decision for the user, not as a settled question.
    """
    starts = [0]
    starts.extend(
        i
        for i in range(1, len(tokens))
        # A command name is never a flag or an env assignment.
        if not tokens[i].startswith("-") and not ENV_ASSIGN_RE.match(tokens[i])
    )
    return starts


def find_from(tokens: list[str], lo: int, value: str) -> int | None:
    """Index of `value` at or after `lo`, or None. Avoids a tokens[lo:] copy."""
    for i in range(lo, len(tokens)):
        if tokens[i] == value:
            return i
    return None


def nested_command_strings(tokens: list[str]) -> list[str]:
    """Strings a shell wrapper will execute as a whole command.

    Recognises option clusters, not just a standalone `-c`: `bash -lc CMD` and
    `sh -ec CMD` run CMD exactly as `bash -c CMD` does, and matching only the
    exact token `-c` let both through.
    """
    out: list[str] = []
    for idx, tok in enumerate(tokens):
        if basename(tok) not in SHELL_CMDS:
            continue
        for j in range(idx + 1, len(tokens)):
            t = tokens[j]
            if t == "--" or t.startswith("--"):
                continue
            if t.startswith("-") and len(t) > 1:
                if "c" in t[1:] and j + 1 < len(tokens):
                    out.append(tokens[j + 1])
                    break
                continue
            break  # a positional before any -c: this is not a -c invocation
    return out


def installer_of(tokens: list[str], start: int) -> str | None:
    """Return the concrete installer name if this token run installs packages.

    Locates the subcommand by SEARCHING the arguments rather than reading
    args[0]. Installer-global options legitimately precede the subcommand
    (`npm --prefix /tmp install`, `pip --isolated install`, `uv --quiet add`),
    and `uv tool install` puts a noun there. Searching needs no arity model and
    over-approximates toward scanning, which is the safe direction.

    Scans by index. The old `args = rest[1:]` ran once per candidate start on the
    common path — every token of a benign command reaches at least that line —
    which was the other half of the quadratic blow-up.

    Returns the CONCRETE tool (`npm` vs `pnpm`), not the family, because their
    flag arities disagree; see the FLAG_TABLES comment.
    """
    if start >= len(tokens):
        return None
    head = basename(tokens[start])
    lo = start + 1

    if head in ("pip", "pip3"):
        return "pip" if find_from(tokens, lo, "install") is not None else None
    if head.startswith("python"):
        k = find_from(tokens, lo, "-m")
        if k is None:
            return None
        if tokens[k + 1 : k + 2] == ["pip"] and find_from(tokens, k + 2, "install") is not None:
            return "pip"
        return None
    if head == "uvx":
        # uvx IS `uv tool run`: it resolves and fetches its target package, so
        # `uvx --from git+…` is an install in every way that matters.
        return "uv-run"
    if head == "uv":
        # `uv pip install`, `uv add`, and `uv tool install` all fetch packages —
        # and so do `uv run` / `uv tool run` (remote --with/--from specs), with
        # the narrowed positional matcher (see UV_RUN_POSITIONAL_RE).
        if find_from(tokens, lo, "install") is not None or find_from(tokens, lo, "add") is not None:
            return "pip"
        if find_from(tokens, lo, "run") is not None:
            return "uv-run"
        return None
    if head in NODE_INSTALLERS:
        hit = any(tokens[i] in INSTALL_SUBCMDS for i in range(lo, len(tokens)))
        return head if hit else None
    return None


def is_remote_pkg(tok: str, installer: str) -> bool:
    if installer == "uv-run":
        # Positionals here are the invoked tool's own argv; only unambiguous
        # package forms count, so a plain https:// data URL stays allowed.
        return bool(
            UV_RUN_POSITIONAL_RE.match(tok)
            or ARCHIVE_URL_RE.match(tok)
            or EMBEDDED_REMOTE_RE.search(tok)
        )
    if (
        REMOTE_PKG_RE.match(tok)
        or ARCHIVE_URL_RE.match(tok)
        or EMBEDDED_REMOTE_RE.search(tok)
    ):
        return True
    # Keyed on the FAMILY, not the concrete tool: the scheme-less spellings below
    # are shared by npm/pnpm/yarn/bun. Comparing against "node" directly here
    # would have silently disabled all of them once installer_of started
    # returning concrete names.
    if INSTALLER_FAMILY.get(installer) != "node":
        return False
    # A local path is not a git spec; npm distinguishes them by the leading char.
    if tok.startswith((".", "/", "~", "@")):
        return False
    return bool(
        NPM_HOST_ALIAS_RE.search(tok)
        or NPM_SCP_GIT_RE.match(tok)
        or NPM_SHORTHAND_RE.match(tok)
    )


def check_install_args(tokens: list[str], start: int, installer: str) -> None:
    """Gate 2 over one installer invocation's arguments."""
    # An installer with no table falls back to EMPTY tables, so nothing is
    # skipped and every token is scanned. That fails closed; a KeyError here
    # would crash the hook, and a crashed hook is a silent permit.
    url_by_design, path_value = FLAG_TABLES.get(installer, (frozenset(), frozenset()))
    skip_next = False
    check_next = False
    for i in range(start + 1, len(tokens)):
        tok = tokens[i]
        if skip_next:
            skip_next = False
            continue
        if check_next:
            check_next = False
            # fall through to the remote check below for this value
        elif tok in url_by_design or tok in path_value:
            skip_next = True
            continue
        elif tok in CHECKED_VALUE_FLAGS:
            check_next = True
            continue
        elif tok.startswith("-"):
            # --requirement=URL / --editable=URL inline forms, and pip's
            # attached short spelling: `-rURL` is the same instruction as
            # `-r URL` and was invisible to the token-level check.
            name, sep, value = tok.partition("=")
            if not sep and len(tok) > 2 and tok[:2] in CHECKED_VALUE_FLAGS:
                name, value = tok[:2], tok[2:]
            if value and name in CHECKED_VALUE_FLAGS and (
                REMOTE_PKG_RE.match(value) or ARCHIVE_URL_RE.match(value)
            ):
                block(
                    f"install from a remote source via `{name}` (`{value}`).",
                    "A remote requirements/constraints/editable target installs "
                    "unreviewed code, bypassing the registry, quarantine, and "
                    "OSV checks.",
                    "download and review it locally first, or ask the user to run this themselves.",
                )
            continue
        if is_remote_pkg(tok, installer):
            block(
                f"install from an arbitrary URL or git repo (`{tok}`).",
                "Packages from URLs/git bypass the registry, the 7-day "
                "min-release-age quarantine, and OSV malware checks.",
                "ask the user to run it themselves, or install the published "
                "registry package instead.",
            )


def check_ignore_scripts(tokens: list[str]) -> None:
    """Gate 3, over every spelling npm honours.

    `--ignore-scripts=false`, `--ignore-scripts false`, the boolean-negation
    `--no-ignore-scripts`, and the `npm_config_*` environment form are all the
    same instruction to npm; accepting only the first two left two live paths.
    """
    for idx, tok in enumerate(tokens):
        low = tok.lower()
        hit = low in ("--ignore-scripts=false", "--no-ignore-scripts") or (
            low == "--ignore-scripts"
            and tokens[idx + 1 : idx + 2] == ["false"]
        )
        if not hit:
            name, sep, value = tok.partition("=")
            hit = (
                sep
                and name.lower() == "npm_config_ignore_scripts"
                and value.lower() in ("false", "0", "no", "")
            )
        if hit:
            block(
                "re-enabling package lifecycle scripts.",
                "Global ~/.npmrc sets ignore-scripts=true as a supply-chain defense; "
                "postinstall scripts are the main npm attack vector.",
                "ask the user to run it themselves for this specific package.",
            )


def check_segment(tokens: list[str], depth: int) -> None:
    if not tokens:
        return

    # Nested shells FIRST. `bash -c '<payload>' --help` hands --help to the
    # wrapper as $0 and still executes the payload, so no outer flag may exempt
    # a nested command from inspection.
    if depth < MAX_NEST_DEPTH:
        for nested in nested_command_strings(tokens):
            check_command(nested, depth + 1)

    if SAFE_FLAGS & set(tokens):
        return

    # --- Gate 4: Gatekeeper bypass (applies to any command) ---
    # HOMEBREW_CASK_OPTS=--no-quarantine is the env spelling of the same
    # instruction; quoting collapses in the lexer, so a substring test on the
    # assignment token covers `HOMEBREW_CASK_OPTS="--no-quarantine --foo"` too.
    if any(
        t == "--no-quarantine"
        or t.startswith("--no-quarantine=")
        or (t.startswith("HOMEBREW_CASK_OPTS=") and "--no-quarantine" in t)
        for t in tokens
    ):
        block(
            "`--no-quarantine` disables Gatekeeper.",
            "Notarization + quarantine are the defense against a malicious cask.",
            "ask the user; this flag is never used unattended "
            "(rules/safety.md § Supply chain).",
        )

    # --- Gate 3: npm lifecycle scripts re-enabled ---
    check_ignore_scripts(tokens)

    # Gates 3 and 4 scan every token, so no wrapper can hide a flag from them.
    # Gates 1 and 2 key on a command NAME, so they run over every candidate
    # start rather than trusting a wrapper-flag skip table (see module docstring).
    for start in candidate_starts(tokens):
        head = basename(tokens[start])

        # --- Gate 1: third-party Homebrew taps ---
        if head == "brew" and start + 1 < len(tokens):
            sub = tokens[start + 1]
            positional = [
                tokens[i]
                for i in range(start + 2, len(tokens))
                if not tokens[i].startswith("-")
            ]
            if sub == "tap" and positional:
                # `brew tap <name> <remote>` takes the code from <remote>, so the
                # NAME no longer says where anything comes from: an official
                # `homebrew/` label with an attacker's URL after it was allowed.
                # The exemption is refused outright whenever a remote is given
                # rather than validated — an anchored host regex would buy only
                # `brew tap homebrew/core <official-url>`, which nobody types
                # because brew already knows the official remote, at the price of
                # a brand-new URL-parsing surface. Fail closed instead.
                if len(positional) > 1:
                    block(
                        f"Homebrew tap `{positional[0]}` from an explicit remote "
                        f"`{positional[1]}`.",
                        "An explicit remote overrides where the tap's code is fetched "
                        "from, so an official-looking tap name guarantees nothing.",
                        "ask the user to add the tap themselves.",
                    )
                if not OFFICIAL_TAP_RE.match(positional[0]):
                    block(
                        f"third-party Homebrew tap `{positional[0]}`.",
                        "Only official core formulae/casks and Mac App Store apps are allowed; "
                        "a tap is unreviewed third-party code.",
                        "ask the user to add the tap themselves.",
                    )
            if sub in ("install", "reinstall", "upgrade"):
                # `positional` already excludes flags, so --cask needs no special
                # case. Skipping a leading element would silently exempt the
                # first package from the tap check — check every positional.
                for t in positional:
                    if TAP_FORMULA_RE.match(t) and not OFFICIAL_TAP_RE.match(t):
                        block(
                            f"install from a third-party tap (`{t}`).",
                            "An owner/repo/formula reference installs from an unreviewed tap.",
                            "ask the user to run it themselves, or use the official core formula.",
                        )

        # --- Gate 2: arbitrary URL / git installs ---
        installer = installer_of(tokens, start)
        if installer:
            check_install_args(tokens, start, installer)


def split_segments(command: str) -> list[list[str]]:
    """Lex once, then split on operators.

    Splitting the RAW string on `;`/`&&`/`|` first treats those characters as
    operators even inside quotes, so `pip install 'https://host/p.whl;param'`
    was torn into unbalanced fragments and its URL never matched. shlex with
    punctuation_chars emits operators as their own tokens while respecting
    quoting, so the URL survives intact as one token.

    A NEWLINE is a command separator too, and lexing alone does not give that:
    shlex counts `\\n` as ordinary whitespace, which collapsed a multiline
    command into ONE segment. `echo --help` on the first line then donated its
    --help exemption to an install on the second, and check_segment returned
    before Gate 2 while bash happily ran both lines. Both properties have to
    hold at once — a bare newline separates, a quoted or backslash-escaped one
    does not — so the fix stays inside the lexer: remove the newline forms from
    `whitespace` and declare them as punctuation instead. shlex's posix
    quote/escape state machine is what keeps `'a\\nb'` a single token, and it
    runs before punctuation is consulted, so both properties come out of the
    same pass.
    """
    try:
        # punctuation_chars is a read-only property, so it can only be set here;
        # `whitespace` is a plain attribute and must be narrowed after, because
        # the state machine tests whitespace BEFORE punctuation.
        lex = shlex.shlex(command, posix=True, punctuation_chars=LEX_PUNCTUATION)
        lex.whitespace_split = True
        lex.whitespace = "".join(c for c in lex.whitespace if c not in NEWLINE_CHARS)
        tokens = list(lex)
    except ValueError:
        # Unbalanced quotes: fall back to a naive split rather than skipping the
        # command entirely, since skipping would be a silent permit. Split per
        # LINE so newline-is-a-separator survives this path too — one segment
        # spanning every line would let a `--help` on line 1 exempt line 2, which
        # is the same shadowing bypass, reachable by appending a stray quote.
        return [
            line.split()
            for line in re.split(f"[{NEWLINE_CHARS}]", command)
            if line.split()
        ]

    segments: list[list[str]] = []
    current: list[str] = []
    for tok in tokens:
        if tok and all(ch in OPERATOR_CHARS for ch in tok):
            if current:
                segments.append(current)
                current = []
            continue
        current.append(tok)
    if current:
        segments.append(current)
    return segments


def check_command(command: str, depth: int = 0) -> None:
    for tokens in split_segments(command):
        check_segment(tokens, depth)


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if not isinstance(data, dict):
        sys.exit(0)
    inp = data.get("tool_input", data)
    if not isinstance(inp, dict):
        sys.exit(0)
    command = inp.get("command", "") or ""
    if not command.strip():
        sys.exit(0)

    check_command(command)
    sys.exit(0)


if __name__ == "__main__":
    main()
