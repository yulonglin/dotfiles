#!/usr/bin/env python3
"""Tests for wire_harness_hooks.py.

The applier is a blocker, and every way a blocker can be wrong degrades to
"silently permits": a missing script, a non-executable script, or — the case
that motivated this suite — a script that is PRESENT but is an older version
that cannot handle the matcher being wired. So the assertions here are mostly
about the applier REFUSING, not about it succeeding.

The fixtures are real, behaving scripts rather than stubs carrying marker text,
because the applier now probes capability by running each hook. A fixture that
only *looks* right would make these tests agree with a check that cannot fail.

Hermetic: synthesizes its own hooks dir and settings.json. Never touches
~/.claude. Run directly:

    python3 scripts/setup/test_wire_harness_hooks.py
"""

import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent

# importlib rather than sys.path.insert — the latter is banned repo-wide and
# has crashed Claude Code sessions.
_spec = importlib.util.spec_from_file_location("wh", HERE / "wire_harness_hooks.py")
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)

PASS = 0
FAIL = 0


def check(desc: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
    else:
        FAIL += 1
        print(f"FAIL: {desc}" + (f" ({detail})" if detail else ""))


def writable_tmp() -> str:
    """$TMPDIR is not reliably writable — sandboxes pin it to a read-only
    runtime dir and can mount /tmp read-only too."""
    for cand in (os.environ.get("TMPDIR"), "/tmp/claude", "/tmp", "."):
        if not cand:
            continue
        try:
            os.makedirs(cand, exist_ok=True)
            return tempfile.mkdtemp(dir=cand, prefix="wire-test.")
        except OSError:
            continue
    raise SystemExit("no writable temp dir found")


# --- fixtures ---------------------------------------------------------------

# The applier RUNS these, so they have to genuinely behave — a stub carrying the
# right marker text no longer proves anything, which is the point of the change.
# Four behaviours, one per way the probe can be fooled:
#
#   FRESH   blocks the forbidden call with an explanation, permits the benign one
#   STALE   permits everything (the pre-MCP hook: silently allows what it can't parse)
#   BLANKET exits 2 on everything and says nothing   -> forges "it blocks!"
#   NOISY   exits 2 on everything WITH an explanation -> forges it more convincingly
#
# BLANKET is caught only by the stderr requirement, NOISY only by the benign
# probe. Keeping both is what proves neither half of the two-sided probe is
# redundant.
FRESH = {
    "block_gws_delete.sh": (
        "#!/bin/sh\n"
        "IN=$(cat)\n"
        'case "$IN" in\n'
        "  *Google_Calendar__delete_event*)\n"
        '    echo "BLOCKED: calendar deletions are irreversible." >&2; exit 2 ;;\n'
        "esac\n"
        "exit 0\n"
    ),
    "block_unsafe_install.py": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "if '--no-quarantine' in sys.stdin.read():\n"
        "    sys.stderr.write('BLOCKED: --no-quarantine disables Gatekeeper.\\n')\n"
        "    sys.exit(2)\n"
    ),
}
STALE = {
    # The real pre-MCP hook: command-only, returns early on MCP input.
    "block_gws_delete.sh": '#!/bin/sh\ncat >/dev/null\n[ -z "$CMD" ] && exit 0\n',
    "block_unsafe_install.py": "#!/usr/bin/env python3\nimport sys\nsys.stdin.read()\n",
}
BLANKET = {
    "block_gws_delete.sh": "#!/bin/sh\ncat >/dev/null\nexit 2\n",
    "block_unsafe_install.py": "#!/usr/bin/env python3\nimport sys\nsys.stdin.read()\nsys.exit(2)\n",
}
NOISY = {
    "block_gws_delete.sh": '#!/bin/sh\ncat >/dev/null\necho "BLOCKED: nope." >&2\nexit 2\n',
    "block_unsafe_install.py": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.stdin.read()\n"
        "sys.stderr.write('BLOCKED: nope.\\n')\n"
        "sys.exit(2)\n"
    ),
}
BEHAVIOURS = {"fresh": FRESH, "stale": STALE, "blanket": BLANKET, "noisy": NOISY}


def make_hooks_dir(
    root: Path,
    variants: dict | None = None,
    omit: tuple = (),
    nonexec: tuple = (),
) -> Path:
    """`variants` maps a hook name to one of BEHAVIOURS; everything else is fresh."""
    variants = variants or {}
    hooks = root / "hooks"
    hooks.mkdir(parents=True, exist_ok=True)
    names = {w[2] for w in wh.WIRINGS} | {"block_gws_delete.sh", "nudge_modern_tools.sh"}
    for name in names:
        if name in omit:
            continue
        table = BEHAVIOURS[variants.get(name, "fresh")]
        body = table.get(name, "#!/bin/sh\nexit 0\n")
        path = hooks / name
        path.write_text(body)
        path.chmod(0o644 if name in nonexec else 0o755)
    return hooks


def make_settings(root: Path, drop_key: str | None = None) -> Path:
    data = {
        "statusLine": {"type": "command", "command": "claude-tools statusline"},
        "permissions": {"deny": []},
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "Bash",
                    "hooks": [
                        {"type": "command", "command": "$HOME/.claude/hooks/block_gws_delete.sh"},
                        {"type": "command", "command": "$HOME/.claude/hooks/nudge_modern_tools.sh"},
                    ],
                },
                {"matcher": "Write", "hooks": []},
                {"matcher": wh.DEAD_MATCHER, "hooks": [
                    {"type": "command", "command": "$HOME/.claude/hooks/nudge_html_email.sh"}]},
            ],
            "PostToolUse": [{"matcher": "Write|Edit", "hooks": []}],
            "Stop": [{"hooks": []}],
        },
    }
    if drop_key:
        del data[drop_key]
    path = root / "settings.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def run(hooks: Path, settings: Path, apply: bool = False):
    """Invoke main() with the module's paths redirected. Returns (rc, output)."""
    wh.HOOKS_DIR, wh.SETTINGS = hooks, settings
    argv, sys.argv = sys.argv, ["wire", "--apply"] if apply else ["wire"]
    buf = io.StringIO()
    rc = 0
    try:
        with redirect_stdout(buf), redirect_stderr(buf):
            wh.main()
    except SystemExit as exc:
        rc = exc.code or 0
    finally:
        sys.argv = argv
    return rc, buf.getvalue()


# --- tests ------------------------------------------------------------------

def main() -> None:
    root = Path(writable_tmp())
    try:
        # 1. The case that motivated the guard: present, executable, WRONG VERSION.
        d = root / "stale"
        stale_hooks = make_hooks_dir(d, variants={"block_gws_delete.sh": "stale"})
        stale_settings = make_settings(d)
        rc, out = run(stale_hooks, stale_settings)
        check("stale hook refuses", rc == 1, f"exit {rc}")
        check("stale hook says it did not block", "did NOT block" in out, out[:160])
        check("stale hook names the file", "block_gws_delete.sh" in out)

        # 1b. Non-vacuity. The fixture above is caught ONLY by the capability
        # probe — the file exists and is executable, so it sails past every other
        # gate. Remove the probe and the same input must be ALLOWED; if it still
        # refuses, something else is catching it and this test proves nothing.
        saved, wh.CAPABILITY_PROBES = wh.CAPABILITY_PROBES, {}
        try:
            rc_bare, _ = run(stale_hooks, stale_settings)
        finally:
            wh.CAPABILITY_PROBES = saved
        check("stale test is not vacuous", rc_bare == 0, f"exit {rc_bare} with the guard removed")

        # 1c. A stub that exits 2 on EVERYTHING passes an exit-status-only probe.
        # This is the forgery the old content-marker check invited, one layer
        # down; only the stderr requirement catches it.
        d = root / "blanket"
        rc, out = run(
            make_hooks_dir(d, variants={"block_unsafe_install.py": "blanket"}),
            make_settings(d),
        )
        check("silent blanket blocker refuses", rc == 1, f"exit {rc}")
        check("blanket names the stderr contract", "nothing to stderr" in out, out[:200])

        # 1d. Same, but it does print an explanation — indistinguishable from a
        # real hook on the forbidden call alone. Only the benign probe catches it.
        # Without this the two-sided probe would have an untested half.
        d = root / "noisy"
        rc, out = run(
            make_hooks_dir(d, variants={"block_unsafe_install.py": "noisy"}),
            make_settings(d),
        )
        check("blanket-with-message refuses", rc == 1, f"exit {rc}")
        check("names it a blanket blocker", "blanket blocker" in out, out[:200])

        # 2. Absent and non-executable also refuse.
        d = root / "absent"
        rc, out = run(make_hooks_dir(d, omit=("guard_existing_code.sh",)), make_settings(d))
        check("absent hook refuses", rc == 1, f"exit {rc}")
        check("absent hook names it", "guard_existing_code.sh" in out)

        d = root / "nonexec"
        rc, out = run(make_hooks_dir(d, nonexec=("nudge_synthetic_data.py",)), make_settings(d))
        check("non-executable refuses", rc == 1, f"exit {rc}")
        check("non-executable names it", "not executable" in out)

        # 3. Degraded settings stub is refused (rules/dotfiles-settings.md).
        d = root / "stub"
        rc, out = run(make_hooks_dir(d), make_settings(d, drop_key="statusLine"))
        check("degraded stub refuses", rc == 1, f"exit {rc}")
        check("stub mentions statusLine", "statusLine" in out)

        # 4. Healthy dry run: reports changes, writes NOTHING.
        d = root / "dry"
        hooks, settings = make_hooks_dir(d), make_settings(d)
        before = settings.read_text()
        rc, out = run(hooks, settings)
        check("dry run succeeds", rc == 0, f"exit {rc}")
        check("dry run says dry run", "Dry run" in out)
        check("dry run does not write", settings.read_text() == before)

        # 5. Apply: every wiring lands, ordering respected, matcher repointed.
        d = root / "apply"
        hooks, settings = make_hooks_dir(d), make_settings(d)
        rc, out = run(hooks, settings, apply=True)
        check("apply succeeds", rc == 0, f"exit {rc}: {out[:200]}")
        data = json.loads(settings.read_text())
        pre = data["hooks"]["PreToolUse"]

        bash = next(b for b in pre if b.get("matcher") == "Bash")
        cmds = [h["command"] for h in bash["hooks"]]
        blocker = next(i for i, c in enumerate(cmds) if "block_unsafe_install.py" in c)
        anchor = next(i for i, c in enumerate(cmds) if "nudge_modern_tools.sh" in c)
        check("blocker inserted before its anchor", blocker < anchor, f"{blocker} vs {anchor}")

        matchers = [b.get("matcher") for b in pre]
        check("dead matcher repointed", wh.DEAD_MATCHER not in matchers)
        check("live matcher present", wh.LIVE_MATCHER in matchers)
        for tool in wh.MCP_DELETE_TOOLS:
            block = next((b for b in pre if b.get("matcher") == tool), None)
            check(f"MCP matcher wired: {tool.rsplit('__', 1)[-1]}", block is not None)
            if block:
                check(
                    f"MCP matcher points at the hook: {tool.rsplit('__', 1)[-1]}",
                    any("block_gws_delete.sh" in h["command"] for h in block["hooks"]),
                )
        stop = data["hooks"]["Stop"][0]
        check("Stop hook wired", any("nudge_number_provenance.py" in h["command"] for h in stop["hooks"]))
        check("backup written", any(p.name.startswith("settings.json.bak.") for p in d.iterdir()))

        # 6. Idempotent: a second apply is a no-op, not a duplicate.
        rc, out = run(hooks, settings, apply=True)
        check("re-apply is a no-op", rc == 0 and "Already wired" in out, out[:120])
        again = json.loads(settings.read_text())
        bash2 = next(b for b in again["hooks"]["PreToolUse"] if b.get("matcher") == "Bash")
        check(
            "no duplicate entries",
            sum("block_unsafe_install.py" in h["command"] for h in bash2["hooks"]) == 1,
        )

        # 7. "Already wired?" must be read the way a shell reads it. A substring
        # test answers yes to a name sitting inside a comment, so the applier
        # reports the hook as present and leaves a permitting no-op in place.
        S = "block_unsafe_install.py"
        cases = [
            ("commented-out name is not wired", "true # block_unsafe_install.py", False),
            ("hook path is wired", "$HOME/.claude/hooks/block_unsafe_install.py", True),
            ("interpreter-prefixed path is wired", "python3 /x/block_unsafe_install.py", True),
            ("longer basename is not a match", "/x/xblock_unsafe_install.py", False),
            ("unbalanced quotes fail closed", 'sh -c "oops', False),
        ]
        for desc, cmd, want in cases:
            check(desc, wh.has_command({"hooks": [{"command": cmd}]}, S) is want, cmd)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print(f"\nResults: {PASS} passed, {FAIL} failed (total {PASS + FAIL})")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
