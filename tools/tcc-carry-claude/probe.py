"""Run a command as its own TCC-responsible process, the way Claude Code's daemon respawns workers.

Prints which process macOS holds responsible, so a folder read can be checked against the rows
tcc-carry-claude wrote for that exact binary rather than against the terminal's grants. The
binary has no plain script mode, so this costs one small model call:

    /usr/bin/python3 tools/tcc-carry-claude/probe.py \
      ~/.local/share/claude/versions/<ver> \
      -p 'Run exactly: ls ~/Downloads | wc -l   then reply with only the number.' \
      --model haiku --max-turns 3 --allowedTools 'Bash(ls:*)'

A number and no dialog means the inserted row is honoured; a dialog means tccd ignored it.
Starting a session can also trigger other prompts, such as "access data from other apps".
"""

import ctypes
import os
import sys
import time

libc = ctypes.CDLL(None, use_errno=True)
libproc = ctypes.CDLL("/usr/lib/libproc.dylib")

argv = sys.argv[1:]
if not argv:
    sys.exit(__doc__)

attr = ctypes.c_void_p()
libc.posix_spawnattr_init(ctypes.byref(attr))
libc.responsibility_spawnattrs_setdisclaim(ctypes.byref(attr), 1)

c_argv = (ctypes.c_char_p * (len(argv) + 1))(*[a.encode() for a in argv], None)
env = [f"{k}={v}".encode() for k, v in os.environ.items()]
c_env = (ctypes.c_char_p * (len(env) + 1))(*env, None)

pid = ctypes.c_int()
rc = libc.posix_spawn(ctypes.byref(pid), argv[0].encode(), None, ctypes.byref(attr), c_argv, c_env)
if rc != 0:
    sys.exit(f"posix_spawn failed: {os.strerror(rc)}")

time.sleep(0.2)
responsible = libc.responsibility_get_pid_responsible_for_pid(pid.value)
path = ctypes.create_string_buffer(4096)
libproc.proc_pidpath(responsible, path, 4096)
print(f"responsible process: {path.value.decode() or responsible}", file=sys.stderr, flush=True)

_, status = os.waitpid(pid.value, 0)
sys.exit(os.waitstatus_to_exitcode(status))
