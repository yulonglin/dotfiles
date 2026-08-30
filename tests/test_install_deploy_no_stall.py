#!/usr/bin/env python3
"""install.sh / deploy.sh must always terminate — never block waiting for input.

An unattended run (CI, cloud provisioning, `curl | zsh` on a fresh box) has
nobody to answer a prompt. A script that stops at one does not fail; it hangs
until something kills it, which reads as "still working" for as long as anyone
is willing to wait. This test makes that failure mode loud.

Mechanism — the part that matters:

    stdin is a descriptor that stays OPEN but never delivers a byte.

`</dev/null` would be useless here: every `read` returns EOF instantly, so a
script that prompts still finishes and the test still passes. A pipe (or a pty)
that no one writes to blocks the reader forever, exactly like a human who never
types. Anything that reads stdin therefore hangs, the per-case timeout fires,
and the case is reported as a stall.

Two stdin flavours, because the scripts guard prompts two different ways:

  * pipe  — `[[ -t 0 ]]` is FALSE, so the no-TTY guards are what's under test.
  * pty   — `[[ -t 0 ]]` is TRUE, so those guards are bypassed and
            `--non-interactive` alone has to do the work. This is the case a
            `</dev/null` test can never reach.

Runs are hermetic: the repo is copied to a temp dir (deploy.sh writes into its
own checkout), HOME is a fresh sandbox, network egress is pointed at a dead
port, and every command that installs, escalates or mutates the machine is
shadowed by a stub on PATH. Without the stubs this test would create users,
install packages and register daemons on the runner.

Stub modes:
  ok    — every external tool succeeds. Asserts the scripts exit 0: a *silent
          abort* (`set -euo pipefail` killing the run half way through) is as
          bad as a hang and this is what catches it.
  fail  — every external tool exits non-zero, i.e. a machine where nothing
          works. Asserts only that the scripts still terminate.

Run: python3 tests/test_install_deploy_no_stall.py [-v]
"""

import os
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# Per-case ceiling. Real runs finish in seconds; this only has to be far enough
# above that to never fire on a slow runner, and far below CI's job timeout so a
# hang is reported as a test failure rather than a cancelled job.
CASE_TIMEOUT = int(os.environ.get("STALL_CASE_TIMEOUT", "240"))

VERBOSE = "-v" in sys.argv or os.environ.get("STALL_VERBOSE") == "1"

# Only commands that would change the *runner* are shadowed: privilege
# escalation, package installers, daemon and account management. Stubbing is a
# blunt instrument — a stub makes a command exist — so the list is deliberately
# short. `git`, `zsh`, `python3` and coreutils are never stubbed: the scripts'
# own logic (worktree guard, config rendering) has to run for real.
STUBBED = """
    sudo doas
    apt apt-get dpkg add-apt-repository snap
    brew mas
    npm npx pnpm yarn bun deno
    cargo rustup go gem
    uv uvx pip pip3 pipx python2
    mise asdf nix
    docker podman
    systemctl loginctl launchctl crontab at
    useradd usermod groupadd gpasswd adduser deluser userdel
    defaults osascript scutil dscl softwareupdate spctl
    tailscale pueued
""".split()

# Deliberately NOT stubbed, even though the scripts call them: bws, gh, claude,
# codex, opencode, agy, op, gitleaks, direnv, ty, ruff, pip-audit, markitdown,
# ob, pueue and friends. These are optional third-party tools, and on a fresh
# machine they are simply *absent* — which is its own bug class. `bws --version`
# through a `set -o pipefail` command substitution exits 127 and used to abort
# deploy.sh outright, and stubbing bws would have hidden that permanently. A
# stub can simulate a tool that fails; it cannot simulate one that isn't there.
#
# `curl` and `wget` are likewise NOT stubbed. Egress already points at a closed
# port, so the real binaries fail exactly as they would on a box with no
# network — which is the condition several `curl … | sh` installers have to
# survive. Stubbing curl to exit 0 would paper over every one of them.
#
# Each entry above carries a second, easily-missed claim: "this command never
# prompts". A stub that exits 0 makes sudo look passwordless and chsh look like
# it never reaches PAM, which would hide the very stalls this file exists to
# find. `chsh` is therefore left unstubbed (it only edits the sandbox user's
# shell entry, and it prompts), and `sudo` gets a realistic stub below rather
# than a blanket success.


def log(msg):
    print(msg, flush=True)


def vlog(msg):
    if VERBOSE:
        print(msg, flush=True)


def make_sandbox(stub_mode):
    """A throwaway repo copy + HOME + stub bin dir. Returns (root, env)."""
    root = tempfile.mkdtemp(prefix="no-stall-")
    repo = os.path.join(root, "repo")
    home = os.path.join(root, "home")
    stubs = os.path.join(root, "stubs")

    # deploy.sh writes into its own checkout (synced skills, rendered rules), so
    # never point it at the developer's tree.
    subprocess.run(["cp", "-a", REPO_ROOT, repo], check=True)
    os.makedirs(home)
    os.makedirs(stubs)

    rc = 1 if stub_mode == "fail" else 0
    for name in STUBBED:
        path = os.path.join(stubs, name)
        # "nosudo": model a machine whose sudo needs a password and has none
        # cached — `sudo -n` fails, and a plain `sudo -v` PROMPTS. The prompt is
        # the point: a blanket `exit 0` stub makes sudo look passwordless and
        # hides every credential prompt, so a privileged step that should skip
        # itself under --non-interactive looks fine while really it hangs.
        if stub_mode == "nosudo" and name in ("sudo", "doas"):
            with open(path, "w") as fh:
                fh.write(
                    "#!/bin/sh\n"
                    "case \"$1\" in\n"
                    "  -n) exit 1 ;;\n"       # never non-interactively authorised
                    "esac\n"
                    "printf '[sudo] password for %s: ' \"$(id -un)\" >&2\n"
                    "head -n 1 >/dev/null\n"  # block exactly as a password prompt does
                    "exit 1\n"
                )
            os.chmod(path, 0o755)
            continue
        # Stubs must never touch stdin: reading it would hang the run and be
        # misreported as the script stalling.
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\nexit %d\n" % rc)
        os.chmod(path, 0o755)

    env = dict(os.environ)
    env.update(
        HOME=home,
        PATH=stubs + os.pathsep + env.get("PATH", "/usr/bin:/bin"),
        # Point egress at a closed port so any straggler network call fails fast
        # instead of hanging on a connect timeout and looking like a stall.
        http_proxy="http://127.0.0.1:1",
        https_proxy="http://127.0.0.1:1",
        HTTP_PROXY="http://127.0.0.1:1",
        HTTPS_PROXY="http://127.0.0.1:1",
        # git and ssh must fail rather than prompt for credentials — a
        # credential prompt is itself one of the stalls under test.
        GIT_TERMINAL_PROMPT="0",
        GIT_ASKPASS="/bin/true",
        SSH_ASKPASS="/bin/true",
        GIT_CONFIG_GLOBAL=os.path.join(home, ".gitconfig"),
    )
    env.pop("NO_PROXY", None)
    env.pop("no_proxy", None)
    # A stale NON_INTERACTIVE from the parent shell would mask exactly the flag
    # handling these cases exist to prove.
    env.pop("NON_INTERACTIVE", None)
    # Containers and RunPod boxes — both documented targets — hand the shell no
    # $USER. Under `set -u` a bare "${USER}" aborts the run, so pin the harsher
    # environment rather than inheriting the runner's convenient one.
    env.pop("USER", None)
    return root, repo, env


def run_with_dead_stdin(argv, env, cwd, log_path, tty):
    """Run argv with stdin open-but-silent. Returns (rc, elapsed, timed_out).

    tty=False: stdin is the read end of a pipe whose write end this process
               holds open and never writes to.
    tty=True:  stdin is a pty slave; this process holds the master, drains
               output so the child never blocks on a full buffer, and never
               writes. isatty(0) is true, so the scripts take their
               interactive branch.
    """
    started = time.time()
    logfh = open(log_path, "wb")
    drain_thread = None
    master = None

    if tty:
        master, slave = pty.openpty()
        proc = subprocess.Popen(
            argv, stdin=slave, stdout=slave, stderr=slave,
            cwd=cwd, env=env, start_new_session=True, close_fds=True,
        )
        os.close(slave)

        # Drain continuously: a full pty buffer would block the child on write
        # and be misreported as a stall. Poll rather than blocking in os.read —
        # a background grandchild can hold the slave open long after the child
        # exits (install.sh leaves a sudo keepalive subshell on the pty), which
        # wedged this thread forever, burnt the join timeout on every case and
        # raised "write to closed file" once the log was closed underneath it.
        stop_drain = threading.Event()

        def drain():
            while not stop_drain.is_set():
                try:
                    ready, _, _ = select.select([master], [], [], 0.1)
                    if not ready:
                        continue
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                if logfh.closed:
                    break
                logfh.write(data)
                logfh.flush()

        drain_thread = threading.Thread(target=drain, daemon=True)
        drain_thread.start()
    else:
        read_fd, write_fd = os.pipe()
        proc = subprocess.Popen(
            argv, stdin=read_fd, stdout=logfh, stderr=subprocess.STDOUT,
            cwd=cwd, env=env, start_new_session=True, close_fds=True,
        )
        os.close(read_fd)

    timed_out = False
    try:
        rc = proc.wait(timeout=CASE_TIMEOUT)
    except subprocess.TimeoutExpired:
        timed_out = True
        # Kill the whole group: a stalled script usually has children
        # (background keepalives, package managers) waiting too.
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except OSError:
            proc.kill()
        rc = proc.wait()

    elapsed = time.time() - started
    if tty:
        # Order matters: stop the thread, join it, close the fd, and only then
        # close the log. Closing out from under a live reader is what produced
        # the traceback.
        stop_drain.set()
        if drain_thread:
            drain_thread.join(timeout=2)
        try:
            os.close(master)
        except OSError:
            pass
    else:
        os.close(write_fd)
    logfh.close()
    return rc, elapsed, timed_out


def tail(path, n=15):
    try:
        with open(path, "rb") as fh:
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return "(no output captured)"
    return "\n".join("    | " + ln for ln in lines[-n:]) or "    | (no output)"


class Runner:
    def __init__(self):
        self.failures = []
        self.ran = 0

    def case(self, script, args, tty, stub_mode="ok", expect_zero=True):
        name = "%s %s [%s stdin, stubs=%s]" % (
            script, " ".join(args) or "(no args)",
            "pty" if tty else "pipe", stub_mode,
        )
        self.ran += 1
        root, repo, env = make_sandbox(stub_mode)
        log_path = os.path.join(root, "output.log")
        try:
            rc, elapsed, timed_out = run_with_dead_stdin(
                ["zsh", os.path.join(repo, script)] + args,
                env, repo, log_path, tty,
            )
            if timed_out:
                self.failures.append(
                    "STALLED: %s\n  did not exit within %ds — it is waiting on input.\n"
                    "  last output:\n%s" % (name, CASE_TIMEOUT, tail(log_path))
                )
                log("  STALL  %s (killed at %ds)" % (name, CASE_TIMEOUT))
            elif expect_zero and rc != 0:
                self.failures.append(
                    "ABORTED: %s\n  exited %d after %.1fs — it stopped part way through.\n"
                    "  last output:\n%s" % (name, rc, elapsed, tail(log_path))
                )
                log("  FAIL   %s (exit %d, %.1fs)" % (name, rc, elapsed))
            else:
                log("  ok     %s (exit %d, %.1fs)" % (name, rc, elapsed))
                vlog(tail(log_path, 8))
        finally:
            shutil.rmtree(root, ignore_errors=True)


def self_test():
    """The detector must be able to fail.

    A harness that cannot distinguish a stalled script from a finished one
    would pass this whole file no matter what install.sh does. Prove both
    directions against known-good and known-bad scripts before trusting it.
    """
    log("Self-test (proving the detector works):")
    root = tempfile.mkdtemp(prefix="no-stall-selftest-")
    ok = 0
    try:
        stall = os.path.join(root, "stalls.sh")
        with open(stall, "w") as fh:
            fh.write("#!/usr/bin/env zsh\nread -r answer\necho got=$answer\n")
        os.chmod(stall, 0o755)
        done = os.path.join(root, "finishes.sh")
        with open(done, "w") as fh:
            fh.write("#!/usr/bin/env zsh\necho fine\n")
        os.chmod(done, 0o755)

        env = dict(os.environ)
        for tty in (False, True):
            label = "pty" if tty else "pipe"
            rc, _, timed_out = run_with_dead_stdin(
                ["zsh", stall], env, root, os.path.join(root, "a.log"), tty,
            )
            if timed_out:
                log("  ok     a script that reads stdin is caught as a stall [%s]" % label)
                ok += 1
            else:
                log("  FAIL   stalling script was NOT caught [%s] (exit %d)" % (label, rc))

            rc, _, timed_out = run_with_dead_stdin(
                ["zsh", done], env, root, os.path.join(root, "b.log"), tty,
            )
            if not timed_out and rc == 0:
                log("  ok     a script that does not read stdin passes [%s]" % label)
                ok += 1
            else:
                log("  FAIL   clean script misreported [%s] (exit %d, timeout=%s)"
                    % (label, rc, timed_out))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # The checks above run outside the sandbox, so they say nothing about
    # whether the stub PATH quietly neutralises the prompts we are hunting.
    # That is not hypothetical: stubbing `sudo` as a blanket `exit 0` made it
    # look passwordless and hid a real hang for a while. Prove the "nosudo"
    # stub genuinely blocks, through the same env a real case gets.
    sb_root, sb_repo, sb_env = make_sandbox("nosudo")
    try:
        probe = os.path.join(sb_root, "probe.sh")
        with open(probe, "w") as fh:
            fh.write("#!/usr/bin/env zsh\nsudo -v\necho 'NOT REACHED'\n")
        os.chmod(probe, 0o755)
        _, _, timed_out = run_with_dead_stdin(
            ["zsh", probe], sb_env, sb_root,
            os.path.join(sb_root, "c.log"), tty=True,
        )
        if timed_out:
            log("  ok     the sandbox's sudo stub really does block on a prompt")
            ok += 1
        else:
            log("  FAIL   the sudo stub does NOT block — every credential prompt "
                "in the cases below is invisible to this test")
    finally:
        shutil.rmtree(sb_root, ignore_errors=True)

    return ok == 5


def main():
    if not shutil.which("zsh"):
        log("FAIL: zsh is not installed — install.sh and deploy.sh are zsh scripts.")
        return 1

    # The self-test uses a short ceiling: it is *supposed* to hit the timeout.
    global CASE_TIMEOUT
    real_timeout, CASE_TIMEOUT = CASE_TIMEOUT, 10
    detector_ok = self_test()
    CASE_TIMEOUT = real_timeout
    if not detector_ok:
        log("\nFAIL: the stall detector itself is broken — results below would be meaningless.")
        return 1

    r = Runner()

    log("\nHands-off runs must finish (stdin is open but silent):")

    # --help must never touch the component menu or sudo.
    r.case("install.sh", ["--help"], tty=True)
    r.case("deploy.sh", ["--help"], tty=True)

    # No TTY: the `[[ -t 0 ]]` guards are what keeps these hands-off. This is
    # the shape of a cron job, a Docker build or a CI step.
    r.case("install.sh", ["--minimal"], tty=False)
    r.case("deploy.sh", ["--minimal"], tty=False)
    r.case("install.sh", ["--only", "zsh", "tmux"], tty=False)
    r.case("deploy.sh", ["--only", "vim"], tty=False)

    # On a TTY the `-t 0` guards are all bypassed, so --non-interactive is the
    # only thing standing between the run and a prompt. Full default component
    # set: this is the deep case, and the one that catches a mid-run abort.
    r.case("install.sh", ["--non-interactive"], tty=True)
    r.case("deploy.sh", ["--non-interactive"], tty=True)

    # …and the same without a TTY, which is how CI actually invokes them.
    r.case("install.sh", ["--non-interactive"], tty=False)
    r.case("deploy.sh", ["--non-interactive"], tty=False)

    # Root is not available to an unattended run on a machine whose sudo needs a
    # password. Every privileged component has to skip itself rather than end
    # the run for the components after it.
    log("\nRuns where sudo would prompt must still finish cleanly:")
    # The pty flavour is the one that matters: without a TTY the `-t 0` guards
    # skip the credential prompt anyway, so a pipe-only case proves nothing.
    # On a pty those guards pass and --non-interactive is all that stands
    # between the run and a password prompt nobody will answer.
    r.case("install.sh", ["--non-interactive"], tty=True, stub_mode="nosudo")
    r.case("deploy.sh", ["--non-interactive"], tty=True, stub_mode="nosudo")
    r.case("install.sh", ["--non-interactive"], tty=False, stub_mode="nosudo")
    r.case("deploy.sh", ["--non-interactive"], tty=False, stub_mode="nosudo")

    log("\nRuns on a machine where every external tool fails must still finish:")
    # Only termination is asserted here. A non-zero exit is a legitimate outcome
    # when nothing on the box works; hanging is not.
    r.case("install.sh", ["--non-interactive"], tty=True,
           stub_mode="fail", expect_zero=False)
    r.case("deploy.sh", ["--non-interactive"], tty=True,
           stub_mode="fail", expect_zero=False)

    log("")
    if r.failures:
        for f in r.failures:
            log("FAIL: " + f)
        log("\n%d/%d case(s) failed." % (len(r.failures), r.ran))
        return 1
    log("All %d case(s) passed." % r.ran)
    return 0


if __name__ == "__main__":
    sys.exit(main())
