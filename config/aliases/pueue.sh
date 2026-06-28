# aliases/pueue.sh — pueue experiment-queue wrappers (j* commands)
#
# Companion to `deploy.sh --pueue` (default-on for Linux), which installs pueued,
# the systemd user slices, config/pueue.yml, and the `experiments`/`agents` groups
# with cgroup-enforced caps from config/resources.conf. These wrappers are the
# day-to-day interface documented in CLAUDE.md (jexp/jls/jfollow/jguard/jpause/jagent).
#
# NOTE: functions are NOT underscore-prefixed — Claude Code shell snapshots filter out
# _-prefixed functions, and these must survive into those shells.

# ── Auto-start pueued on login (idempotent; the "always-on for experiments" knob) ──────────────
# No-op if pueue isn't installed or the daemon is already up. Uses the plain --daemonize path,
# NOT `systemctl --user` (D-Bus / systemd --user is unavailable inside the Claude Code bubblewrap
# sandbox and in many containers). `|| true` so a failed start never breaks shell startup.
if command -v pueued >/dev/null 2>&1 && ! pueue status >/dev/null 2>&1; then
  pueued --daemonize >/dev/null 2>&1 || true
fi

# aliases/jobs.sh (sourced earlier) defines `jls` and `jfollow` as aliases. zsh expands an
# alias when it parses a same-named `name() {…}`, which is a fatal parse error. Drop those
# aliases so the function definitions below win cleanly. (`|| :` no-ops if they're absent.)
unalias jls jfollow 2>/dev/null || :

# Ensure a group exists before queueing into it (idempotent; harmless if deploy already made it,
# and self-heals the autostart-without-deploy case where only the default group exists).
jexp() {
  command -v pueue >/dev/null 2>&1 || { echo "jexp: pueue not installed — run ./deploy.sh --pueue" >&2; return 1; }
  pueue status >/dev/null 2>&1 || { echo "jexp: pueued not running — run ./deploy.sh --pueue (or open a new shell to autostart)" >&2; return 1; }
  pueue group add experiments >/dev/null 2>&1 || true
  pueue add --group experiments -- "$@"
}

# Agent CLI jobs (claude --print, codex, …) go in the lighter-capped `agents` group.
jagent() {
  command -v pueue >/dev/null 2>&1 || { echo "jagent: pueue not installed — run ./deploy.sh --pueue" >&2; return 1; }
  pueue status >/dev/null 2>&1 || { echo "jagent: pueued not running — run ./deploy.sh --pueue" >&2; return 1; }
  pueue group add agents >/dev/null 2>&1 || true
  pueue add --group agents -- "$@"
}

# Queue overview.
jls() {
  pueue status >/dev/null 2>&1 || { echo "jls: pueued not running — run ./deploy.sh --pueue" >&2; return 1; }
  pueue status "$@"
}

# Stream a task's live output. Usage: jfollow <task-id>
jfollow() {
  pueue status >/dev/null 2>&1 || { echo "jfollow: pueued not running — run ./deploy.sh --pueue" >&2; return 1; }
  pueue follow "$@"
}

# Pause a group (default: experiments). Usage: jpause [group]
jpause() {
  pueue status >/dev/null 2>&1 || { echo "jpause: pueued not running" >&2; return 1; }
  pueue pause --group "${1:-experiments}"
}

# Resume a group (default: experiments). Usage: jresume [group]
jresume() {
  pueue status >/dev/null 2>&1 || { echo "jresume: pueued not running" >&2; return 1; }
  pueue start --group "${1:-experiments}"
}

# Quick health snapshot when the machine feels slow: queue state + GPU + memory.
# Follow with `jpause experiments` to stop launching new experiment jobs.
jguard() {
  echo "── pueue ──"
  pueue status 2>/dev/null || echo "  (pueued not running)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "── gpu (util%, mem) ──"
    nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null
  fi
  echo "── memory ──"
  free -h 2>/dev/null || true
  echo "(slow? → jpause experiments)"
}
