# aliases/pueue.sh — pueue experiment-queue wrappers (j* commands)
#
# The single home for all j* commands (consolidated 2026-08-18; jobs.sh previously
# defined an overlapping set whose jexp silently lost cgroup enforcement to this
# file's simpler version by source order — jobs.sh is SLURM-only now).
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

# Submit a job to a group. With systemd --user available, the job runs inside the
# group's slice (cgroup CPU/memory caps from config/resources.conf); without it
# (macOS, containers, the Claude Code sandbox) it falls back to a plain `pueue add`
# with a warning — pueue's own group parallelism limits still apply, cgroup caps don't.
jrun() {
  local group="${1:?Usage: jrun <group> <cmd...> (groups: experiments, agents)}"
  shift
  if [[ "$group" != "experiments" && "$group" != "agents" ]]; then
    echo "Unknown group: $group (expected: experiments, agents)" >&2; return 1
  fi
  command -v pueue >/dev/null 2>&1 || { echo "jrun: pueue not installed — run ./deploy.sh --pueue" >&2; return 1; }
  pueue status >/dev/null 2>&1 || { echo "jrun: pueued not running — run ./deploy.sh --pueue (or open a new shell to autostart)" >&2; return 1; }
  # Self-heals the autostart-without-deploy case where only the default group exists.
  pueue group add "$group" >/dev/null 2>&1 || true
  # Thread caps for experiments to prevent BLAS/tokenizer oversubscription.
  local env_args=()
  if [[ "$group" == "experiments" ]]; then
    local threads="${EXPERIMENTS_THREADS:-2}"
    env_args=(env
      OMP_NUM_THREADS="$threads"
      MKL_NUM_THREADS="$threads"
      OPENBLAS_NUM_THREADS="$threads"
      NUMEXPR_NUM_THREADS="$threads"
      RAYON_NUM_THREADS="$threads"
      TOKENIZERS_PARALLELISM=false)
  fi
  if systemctl --user is-system-running >/dev/null 2>&1; then
    pueue add --group "$group" --label "$(basename "$1")" -- \
      systemd-run --user --service-type=exec --wait --collect --slice="${group}.slice" \
        --setenv=PATH="$PATH" \
        --setenv=HOME="$HOME" \
        -- "${env_args[@]}" "$@"
  else
    echo "jrun: systemd --user unavailable — running WITHOUT cgroup caps (fix: loginctl enable-linger $(whoami))" >&2
    pueue add --group "$group" --label "$(basename "$1")" -- "${env_args[@]}" "$@"
  fi
}

jexp()   { jrun experiments "$@"; }
jagent() { jrun agents "$@"; }
jclaude() { jrun agents claude --print "$@"; }

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

alias jlog='pueue log'
alias jclean='pueue clean'
alias jwatch='watch -n2 pueue status'
alias jkill='pueue kill'

# Pause / resume a group (default: experiments; `all` for every group).
jpause() {
  pueue status >/dev/null 2>&1 || { echo "jpause: pueued not running" >&2; return 1; }
  if [[ "${1:-experiments}" == "all" ]]; then pueue pause; else pueue pause --group "${1:-experiments}"; fi
}
jresume() {
  pueue status >/dev/null 2>&1 || { echo "jresume: pueued not running" >&2; return 1; }
  if [[ "${1:-experiments}" == "all" ]]; then pueue start; else pueue start --group "${1:-experiments}"; fi
}

# Overview with resource usage.
jtop() {
  pueue status
  echo ""
  systemctl --user status experiments.slice agents.slice 2>/dev/null \
    || echo "(systemd slices not available)"
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
