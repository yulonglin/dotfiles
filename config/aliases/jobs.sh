# aliases/jobs.sh — Slurm and Pueue job queue aliases

# -------------------------------------------------------------------
# Slurm
# -------------------------------------------------------------------
alias q='squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qw='watch squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qq='squeue -u $(whoami) -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qtop='scontrol top'
alias qdel='scancel'
alias qnode='sinfo -Ne --Format=NodeHost,CPUsState,Gres,GresUsed'
alias qinfo='sinfo'
alias qhost='scontrol show nodes'
# Submit a quick GPU test job
alias qtest='sbatch --gres=gpu:1 --wrap="hostname; nvidia-smi"'
alias qlogin='srun --gres=gpu:1 --pty $SHELL'
# Cancel all your queued jobs
alias qclear='scancel -u $(whoami)'
# Functions to submit quick jobs with varying GPUs
# Usage: qrun 4 script.sh → submits 'script.sh' with 4 GPUs
qrun() {
  sbatch --gres=gpu:"$1" "$2"
}

# -------------------------------------------------------------------
# Pueue (local job queue + resource slices)
# -------------------------------------------------------------------
# j* prefix to avoid collision with q* (SLURM)
if command -v pueue &>/dev/null; then

  # Submit job to a group with systemd cgroup enforcement
  # Usage: jrun <group> <cmd...>
  jrun() {
    local group="${1:?Usage: jrun <group> <cmd...> (groups: experiments, agents)}"
    shift
    if [[ "$group" != "experiments" && "$group" != "agents" ]]; then
      echo "Unknown group: $group (expected: experiments, agents)" >&2; return 1
    fi
    if ! pueue status &>/dev/null; then
      echo "pueued not running. Start with: systemctl --user start pueued" >&2; return 1
    fi
    if ! systemctl --user is-system-running &>/dev/null 2>&1; then
      echo "ERROR: systemd --user not available — cannot enforce resource limits" >&2
      echo "  Jobs would run without CPU/memory caps. Aborting." >&2
      echo "  Fix: loginctl enable-linger $(whoami)" >&2
      return 1
    fi
    # Set thread caps for experiments to prevent oversubscription
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
    pueue add --group "$group" --label "$(basename "$1")" -- \
      systemd-run --user --service-type=exec --wait --collect --slice="${group}.slice" \
        --setenv=PATH="$PATH" \
        --setenv=HOME="$HOME" \
        -- "${env_args[@]}" "$@"
  }

  # Shortcuts
  jexp() { jrun experiments "$@"; }
  jagent() { jrun agents "$@"; }
  jclaude() { jrun agents claude --print "$@"; }

  # Status
  alias jls='pueue status'
  alias jlog='pueue log'
  alias jfollow='pueue follow'
  alias jclean='pueue clean'
  alias jwatch='watch -n2 pueue status'

  # Control
  _jctl() {
    local action="$1" group="${2:?Usage: j${1} <group|all>}"
    [[ "$group" == "all" ]] && pueue "$action" || pueue "$action" --group "$group"
  }
  jpause()  { _jctl pause "$@"; }
  jresume() { _jctl start "$@"; }
  alias jkill='pueue kill'

  # Overview with resource usage
  jtop() {
    pueue status
    echo ""
    systemctl --user status experiments.slice agents.slice 2>/dev/null \
      || echo "(systemd slices not available)"
  }

fi
