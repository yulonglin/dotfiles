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
  # Self-heals the autostart-without-deploy case where only the default group
  # exists. A group created here would get pueue's default parallel=1 — which
  # silently serialised ~10 API-bound jobs for an hour on 2026-08-27 — so set
  # its parallelism from resources.conf immediately (fallback 3).
  if pueue group add "$group" >/dev/null 2>&1; then
    local rc="${DOT_DIR:-$HOME/code/dotfiles}/config/resources.conf" par=""
    if [[ -r "$rc" ]]; then
      case "$group" in
        experiments) par="$(sed -n 's/^EXPERIMENTS_PARALLEL=\([0-9]*\).*/\1/p' "$rc")" ;;
        agents)      par="$(sed -n 's/^AGENTS_PARALLEL=\([0-9]*\).*/\1/p' "$rc")" ;;
      esac
    fi
    pueue parallel "${par:-3}" --group "$group" >/dev/null 2>&1 || true
  fi
  # Auto-load API keys: direnv/bws never resolves inside systemd user units, so
  # jobs otherwise start keyless and die on auth. jkeys (custom_bins) snapshots
  # the repo's .envrc keys to a mode-600 file once, and the job execs through
  # `jkeys exec`, which sources it. Opt out with JEXP_NO_KEYS=1; override the
  # file with JEXP_KEY_FILE. Outside a git repo this is silently skipped.
  local key_shim=()
  if [[ "${JEXP_NO_KEYS:-0}" != "1" ]]; then
    local jkeys_bin keyfile
    jkeys_bin="$(command -v jkeys 2>/dev/null || true)"
    if [[ -n "$jkeys_bin" ]]; then
      keyfile="${JEXP_KEY_FILE:-$("$jkeys_bin" path 2>/dev/null || true)}"
      if [[ -n "$keyfile" && ! -r "$keyfile" ]]; then
        "$jkeys_bin" write >/dev/null 2>&1 || true  # no-op unless the repo has an .envrc
      fi
      if [[ -n "$keyfile" && -r "$keyfile" ]]; then
        key_shim=("$jkeys_bin" exec --keyfile "$keyfile" --)
      fi
    fi
  fi
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
    # --pipe keeps the job's stdout/stderr in pueue's log (without it, output
    # goes only to the journal and `jlog` shows just "exit 1"); --same-dir runs
    # the unit in the submission cwd (services otherwise start in $HOME); the
    # explicit --unit lets jlog fall back to `journalctl --user -u <unit>`.
    local unit
    unit="jrun-$(date +%s%N)"
    pueue add --group "$group" --label "$(basename "$1")" -- \
      systemd-run --user --unit "$unit" --service-type=exec --wait --collect --pipe --same-dir \
        --slice="${group}.slice" \
        --setenv=PATH="$PATH" \
        --setenv=HOME="$HOME" \
        -- "${env_args[@]}" "${key_shim[@]}" "$@"
  else
    echo "jrun: systemd --user unavailable — running WITHOUT cgroup caps (fix: loginctl enable-linger $(whoami))" >&2
    pueue add --group "$group" --label "$(basename "$1")" -- "${env_args[@]}" "${key_shim[@]}" "$@"
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

# Job output. With the --pipe fix (2026-08-27) pueue's log carries the job's
# stdout/stderr directly. For tasks submitted before that fix — where pueue
# captured only systemd-run's status lines — fall back to the unit's journal.
jlog() {
  pueue status >/dev/null 2>&1 || { echo "jlog: pueued not running" >&2; return 1; }
  if [[ $# -eq 0 ]]; then pueue log; return; fi
  local out unit body real
  out="$(pueue log --full "$@" 2>&1)"
  printf '%s\n' "$out"
  # Unit name: from systemd-run's "Running as unit:" line, else from the
  # stored command's explicit "--unit jrun-<ns>".
  unit="$(printf '%s\n' "$out" | grep -oE 'Running as unit: [[:alnum:]@_.-]+' | head -1 | awk '{print $4}')"
  if [[ -z "$unit" ]]; then
    unit="$(printf '%s\n' "$out" | grep -oE -- '--unit jrun-[0-9]+' | head -1 | awk '{print $2}')"
    [[ -n "$unit" ]] && unit="$unit.service"
  fi
  # Count output lines that are actual job output, not systemd-run chrome.
  body="$(printf '%s\n' "$out" | sed -n '/^output:/,$p' | sed 1d)"
  real="$(printf '%s\n' "$body" | grep -cvE '^(Running as unit:|Finished with result:|Main processes terminated|Service runtime:|CPU time consumed:|Memory (swap )?peak:|IP traffic|IO bytes|[[:space:]]*$)' || true)"
  if [[ -n "$unit" && "${real:-0}" -eq 0 ]]; then
    echo ""
    echo "── pueue captured no job output; journal for $unit ──"
    journalctl --user -u "$unit" -o cat --no-pager 2>/dev/null | tail -100 \
      || echo "(no journal entries either — try: journalctl --user -u 'run-u*' -S today)"
  fi
}
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
