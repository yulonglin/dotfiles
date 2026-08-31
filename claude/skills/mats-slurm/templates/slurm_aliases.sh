#!/bin/bash
# MATS Cluster SLURM Aliases and Functions
# Source this file in your .zshrc or .bashrc
#
# Configuration (set before sourcing):
#   SLURM_USER        - Your cluster username (default: current user)
#   SLURM_LOG_DIR     - stdout log directory (default: ~/slurmlogs)
#   SLURM_ERROR_DIR   - stderr log directory (default: ~/slurmerrors)
#   SLURM_PARTITION   - Default partition (default: compute)
#   SLURM_DEFAULT_ENV - Conda/mamba env to activate in batch jobs (optional)

# ============================================================================
# Configuration
# ============================================================================

SLURM_USER="${SLURM_USER:-$(whoami)}"
SLURM_LOG_DIR="${SLURM_LOG_DIR:-$HOME/slurmlogs}"
SLURM_ERROR_DIR="${SLURM_ERROR_DIR:-$HOME/slurmerrors}"
SLURM_PARTITION="${SLURM_PARTITION:-compute}"

# Ensure log directories exist
mkdir -p "$SLURM_LOG_DIR" "$SLURM_ERROR_DIR" 2>/dev/null

# Common flags for all jobs
SLURM_DIRS="--output=$SLURM_LOG_DIR/slurm-%j.out --error=$SLURM_ERROR_DIR/slurm-%j.err"
SLURM_COMMON_FLAGS="--partition=$SLURM_PARTITION"

# ============================================================================
# Interactive Jobs
# ============================================================================

# Run interactive job with A100 GPU
# Usage: grun [--mem=SIZE] [--gpus=N] [--debug] <command>
grun() {
    local mem="128G"
    local gpus=1
    local qos=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mem)
                mem="$2"
                shift 2
                ;;
            --mem=*)
                mem="${1#*=}"
                shift
                ;;
            --gpus)
                gpus="$2"
                shift 2
                ;;
            --gpus=*)
                gpus="${1#*=}"
                shift
                ;;
            --debug)
                qos="--qos=debug"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    srun --gres=gpu:a100:${gpus} --mem="$mem" $SLURM_COMMON_FLAGS $qos "${args[@]}"
}

# Run interactive job with L40 GPU
# Usage: lrun [--mem=SIZE] [--gpus=N] [--debug] <command>
lrun() {
    local mem="64G"
    local gpus=1
    local qos=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mem)
                mem="$2"
                shift 2
                ;;
            --mem=*)
                mem="${1#*=}"
                shift
                ;;
            --gpus)
                gpus="$2"
                shift 2
                ;;
            --gpus=*)
                gpus="${1#*=}"
                shift
                ;;
            --debug)
                qos="--qos=debug"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    srun --gres=gpu:l40:${gpus} --mem="$mem" $SLURM_COMMON_FLAGS $qos "${args[@]}"
}

# Quick debug job (high priority, 2h limit, 1 GPU)
# Usage: drun <gpu_type> <command>  (gpu_type: a100 or l40)
drun() {
    local gpu_type="${1:-l40}"
    shift
    srun --gres=gpu:${gpu_type}:1 --qos=debug --time=02:00:00 $SLURM_COMMON_FLAGS "$@"
}

# ============================================================================
# Batch Jobs
# ============================================================================

# Submit batch job with A100 GPU
# Usage: gbatch [--gpus=N] [--mem=SIZE] [--time=HH:MM:SS] <command>
gbatch() {
    local gpus=1
    local mem="128G"
    local time="24:00:00"
    local command=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --gpus=*) gpus="${1#*=}"; shift ;;
            --gpus) gpus="$2"; shift 2 ;;
            --mem=*) mem="${1#*=}"; shift ;;
            --mem) mem="$2"; shift 2 ;;
            --time=*) time="${1#*=}"; shift ;;
            --time) time="$2"; shift 2 ;;
            *) command="$@"; break ;;
        esac
    done

    if [ -z "$command" ]; then
        echo "Usage: gbatch [--gpus=N] [--mem=SIZE] [--time=HH:MM:SS] <command>"
        echo "Example: gbatch 'python train.py'"
        echo "Example: gbatch --gpus=4 --mem=256G 'python multi_gpu.py'"
        return 1
    fi

    local script_file=$(mktemp /tmp/gbatch_XXXXXX.sh)

    cat > "$script_file" << EOF
#!/bin/bash
#SBATCH --gres=gpu:a100:${gpus}
#SBATCH --time=${time}
#SBATCH --mem=${mem}
#SBATCH --partition=$SLURM_PARTITION
#SBATCH --output=$SLURM_LOG_DIR/slurm-%j.out
#SBATCH --error=$SLURM_ERROR_DIR/slurm-%j.err

${SLURM_DEFAULT_ENV:+# Activate environment
mm activate $SLURM_DEFAULT_ENV}

cd "$PWD"

$command
EOF

    chmod +x "$script_file"

    local output=$(sbatch "$script_file")
    echo "$output"

    local jobid=$(echo "$output" | grep -o '[0-9]\+')
    if [ -n "$jobid" ]; then
        (sleep 5; while squeue -j "$jobid" &>/dev/null 2>&1; do sleep 30; done; rm -f "$script_file") &
    else
        rm -f "$script_file"
    fi
}

# Submit batch job with L40 GPU
# Usage: lbatch [--gpus=N] [--mem=SIZE] [--time=HH:MM:SS] <command>
lbatch() {
    local gpus=1
    local mem="128G"
    local time="24:00:00"
    local command=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --gpus=*) gpus="${1#*=}"; shift ;;
            --gpus) gpus="$2"; shift 2 ;;
            --mem=*) mem="${1#*=}"; shift ;;
            --mem) mem="$2"; shift 2 ;;
            --time=*) time="${1#*=}"; shift ;;
            --time) time="$2"; shift 2 ;;
            *) command="$@"; break ;;
        esac
    done

    if [ -z "$command" ]; then
        echo "Usage: lbatch [--gpus=N] [--mem=SIZE] [--time=HH:MM:SS] <command>"
        echo "Example: lbatch 'python train.py'"
        echo "Example: lbatch --gpus=2 'python multi_gpu.py'"
        return 1
    fi

    local script_file=$(mktemp /tmp/lbatch_XXXXXX.sh)

    cat > "$script_file" << EOF
#!/bin/bash
#SBATCH --gres=gpu:l40:${gpus}
#SBATCH --time=${time}
#SBATCH --mem=${mem}
#SBATCH --partition=$SLURM_PARTITION
#SBATCH --output=$SLURM_LOG_DIR/slurm-%j.out
#SBATCH --error=$SLURM_ERROR_DIR/slurm-%j.err

${SLURM_DEFAULT_ENV:+# Activate environment
mm activate $SLURM_DEFAULT_ENV}

cd "$PWD"

$command
EOF

    chmod +x "$script_file"

    local output=$(sbatch "$script_file")
    echo "$output"

    local jobid=$(echo "$output" | grep -o '[0-9]\+')
    if [ -n "$jobid" ]; then
        (sleep 5; while squeue -j "$jobid" &>/dev/null 2>&1; do sleep 30; done; rm -f "$script_file") &
    else
        echo "Job submission failed"
        rm -f "$script_file"
    fi
}

# ============================================================================
# Job Control
# ============================================================================

# Cancel job(s)
# Usage: sc <jobid> [jobid2] ...  or  sc all (cancels all your jobs)
sc() {
    if [ -z "$1" ]; then
        echo "Usage: sc <jobid> [jobid2] ..."
        echo "       sc all  - cancel all your jobs"
        return 1
    fi

    if [ "$1" = "all" ]; then
        echo "Cancelling all jobs for user $SLURM_USER..."
        scancel -u "$SLURM_USER"
    else
        scancel "$@"
    fi
}

# ============================================================================
# Monitoring Aliases
# ============================================================================

# Show all GPU nodes status
alias gpus="sinfo -o '%20N %10c %10m %25f %10G %6t'"

# Show idle GPU nodes
alias gpusfree="sinfo -t idle -o '%20N %10c %10m %25f %10G %6t'"

# Show queue status with job details
alias gu="squeue -o '%.18i %.9P %.8j %.8u %.2t %.10M %.6D %R %b' --sort=-t"

# Show my jobs in queue
alias maq="squeue --format='%.18i %.9P %.50j %.8u %.8T %.10M %.9l %.6D %R' --me"

# Show my job accounting information
alias macct="sacct --format='JobID,JobName%30,Partition,Account,AllocCPUS,State,ExitCode,Start,End,Elapsed,MaxRSS,MaxVMSize' --user=\$USER"

# Show why a job is pending
# Usage: whypending <jobid>
whypending() {
    if [ -z "$1" ]; then
        echo "Usage: whypending <jobid>"
        return 1
    fi
    scontrol show job "$1" | grep -i "reason\|state\|dependency"
}

# ============================================================================
# Log Management
# ============================================================================

alias cdlogs="cd $SLURM_LOG_DIR"
alias lslogs="ls -lt $SLURM_LOG_DIR/ | head -10"
alias refreshslurmcmds="source ~/.slurm_aliases 2>/dev/null || source ~/.claude/skills/mats-slurm/templates/slurm_aliases.sh"

# Tail stdout logs (jlog = job log)
# Usage: jlog <jobid> [lines]
jlog() {
    local jobid="$1"
    local lines="${2:-50}"

    if [ -z "$jobid" ]; then
        echo "Usage: jlog <jobid> [lines]"
        return 1
    fi

    if [ -f "$SLURM_LOG_DIR/slurm-${jobid}.out" ]; then
        tail -f -n "$lines" "$SLURM_LOG_DIR/slurm-${jobid}.out"
    elif [ -f "$SLURM_LOG_DIR/${jobid}.out" ]; then
        tail -f -n "$lines" "$SLURM_LOG_DIR/${jobid}.out"
    else
        local output_file=$(find "$SLURM_LOG_DIR" -name "*${jobid}.out" -type f 2>/dev/null | head -n 1)
        if [ -n "$output_file" ]; then
            echo "Found: $output_file"
            tail -f -n "$lines" "$output_file"
        else
            echo "Log file not found for job $jobid"
            echo "Searched: $SLURM_LOG_DIR/slurm-${jobid}.out, $SLURM_LOG_DIR/${jobid}.out"
            return 1
        fi
    fi
}

# Tail stderr logs
# Usage: te <jobid> [lines]
te() {
    local jobid="$1"
    local lines="${2:-50}"

    if [ -z "$jobid" ]; then
        echo "Usage: te <jobid> [lines]"
        return 1
    fi

    local search_dirs=("$SLURM_ERROR_DIR" "$SLURM_LOG_DIR")

    for dir in "${search_dirs[@]}"; do
        if [ -f "$dir/slurm-${jobid}.err" ]; then
            tail -f -n "$lines" "$dir/slurm-${jobid}.err"
            return 0
        elif [ -f "$dir/${jobid}.err" ]; then
            tail -f -n "$lines" "$dir/${jobid}.err"
            return 0
        fi
    done

    local error_file=$(find "${search_dirs[@]}" -name "*${jobid}.err" -type f 2>/dev/null | head -n 1)
    if [ -n "$error_file" ]; then
        echo "Found: $error_file"
        tail -f -n "$lines" "$error_file"
    else
        echo "Error file not found for job $jobid"
        return 1
    fi
}

# ============================================================================
# Job Attachment Functions
# ============================================================================

# Run nvtop on last running job
svtop() {
    local jobid=$(squeue -u "$SLURM_USER" -h -t RUNNING -o "%i" | tail -n 1)

    if [ -z "$jobid" ]; then
        echo "No running jobs found for user $SLURM_USER"
        return 1
    fi

    echo "Running nvtop on job $jobid"
    srun --pty --overlap --jobid "$jobid" nvtop
}

# Attach to running job with interactive shell
# Usage: arun <jobid>
arun() {
    if [ -z "$1" ]; then
        echo "Usage: arun <jobid>"
        return 1
    fi

    srun --pty --overlap --jobid "$1" bash
}

# Attach to running job output (interactive selector if multiple)
attach() {
    local jobs=($(squeue -u "$SLURM_USER" -h -t RUNNING -o "%i"))

    if [ ${#jobs[@]} -eq 0 ]; then
        echo "No running jobs found for user $SLURM_USER"
        return 1
    fi

    local jobid
    if [ ${#jobs[@]} -eq 1 ]; then
        jobid="${jobs[0]}"
        echo "Attaching to job $jobid (only running job)"
    else
        echo "Multiple running jobs found:"
        echo
        squeue -u "$SLURM_USER" -t RUNNING
        echo

        while true; do
            echo -n "Enter job ID to attach to (or 'q' to quit): "
            read selection

            if [ "$selection" = "q" ]; then
                return 0
            fi

            if [[ " ${jobs[@]} " =~ " ${selection} " ]]; then
                jobid="$selection"
                break
            else
                echo "Invalid job ID. Please select from the list above."
            fi
        done
    fi

    echo "Attaching to job $jobid"

    if ! sattach "$jobid.0" 2>/dev/null; then
        echo "sattach failed, falling back to log file..."
        local output_file=""

        if [ -f "$SLURM_LOG_DIR/slurm-${jobid}.out" ]; then
            output_file="$SLURM_LOG_DIR/slurm-${jobid}.out"
        elif [ -f "$SLURM_LOG_DIR/${jobid}.out" ]; then
            output_file="$SLURM_LOG_DIR/${jobid}.out"
        else
            output_file=$(find "$SLURM_LOG_DIR" -name "*${jobid}.out" -type f 2>/dev/null | head -n 1)
        fi

        if [ -n "$output_file" ]; then
            echo "Following $output_file (Ctrl+C to exit)"
            tail -f "$output_file"
        else
            echo "Output file not found. Job may not have started writing yet."
        fi
    fi
}

# ============================================================================
# Resource Information
# ============================================================================

# Show unallocated resources across all nodes
free_resources() {
    echo "Unallocated Resources by Node:"
    echo "=============================="
    echo

    sinfo -N -o "%N %c %m %G %T" --noheader | while read -r node_name cpus memory gres state; do
        # Skip down/drained nodes
        if [[ "$state" =~ ^(down|drain|maint|fail|unk) ]]; then
            continue
        fi

        # Parse total GPUs
        local total_gpus=0
        if [[ "$gres" != "(null)" && "$gres" =~ gpu:.*:([0-9]+) ]]; then
            total_gpus=${BASH_REMATCH[1]}
        elif [[ "$gres" != "(null)" && "$gres" =~ gpu:([0-9]+) ]]; then
            total_gpus=${BASH_REMATCH[1]}
        fi

        # Get allocated resources
        local allocated_cpus=0
        local allocated_memory=0
        local allocated_gpus=0

        while read -r job_cpus job_mem; do
            if [[ -n "$job_cpus" && "$job_cpus" != "0" ]]; then
                allocated_cpus=$((allocated_cpus + job_cpus))
            fi
            if [[ -n "$job_mem" ]]; then
                if [[ "$job_mem" =~ ([0-9]+)G ]]; then
                    allocated_memory=$((allocated_memory + ${BASH_REMATCH[1]} * 1024))
                elif [[ "$job_mem" =~ ([0-9]+)M ]]; then
                    allocated_memory=$((allocated_memory + ${BASH_REMATCH[1]}))
                fi
            fi
        done <<< "$(squeue -h -w "$node_name" -o "%C %m" 2>/dev/null)"

        if [[ $total_gpus -gt 0 ]]; then
            allocated_gpus=$(squeue -h -w "$node_name" -o "%b" 2>/dev/null | grep -o "gpu:[^:]*:[0-9]*" | cut -d: -f3 | paste -sd+ 2>/dev/null | bc 2>/dev/null || echo "0")
            [[ -z "$allocated_gpus" ]] && allocated_gpus=0
        fi

        local free_cpus=$((cpus - allocated_cpus))
        local free_memory_gb=$(( (memory - allocated_memory) / 1024 ))
        local free_gpus=$((total_gpus - allocated_gpus))

        printf "%-20s CPUs: %3d/%3d  Memory: %5dG/%5dG  GPUs: %2d/%2d  [%s]\n" \
            "$node_name" \
            "$free_cpus" "$cpus" \
            "$free_memory_gb" "$((memory / 1024))" \
            "$free_gpus" "$total_gpus" \
            "$state"
    done

    echo
    echo "Note: Memory calculations are approximate."
}

# ============================================================================
# Help
# ============================================================================

# Quick access to help
alias slurm="slurmhelp"

slurmhelp() {
    cat << 'EOF'
MATS SLURM Commands
===================

Interactive Jobs:
  grun [options] <cmd>       A100 GPU (default: 128G mem)
  lrun [options] <cmd>       L40 GPU (default: 64G mem)
  drun <gpu_type> <cmd>      Quick debug (2h, 1 GPU, high priority)

  Options: --mem=SIZE  --gpus=N  --debug (use debug QoS)

Batch Jobs:
  gbatch [options] <cmd>     Submit A100 batch job
  lbatch [options] <cmd>     Submit L40 batch job

  Options: --gpus=N  --mem=SIZE  --time=HH:MM:SS

Job Control:
  sc <jobid> [...]           Cancel job(s)
  sc all                     Cancel all your jobs

Monitoring:
  gpus                       All GPU nodes status
  gpusfree                   Idle GPU nodes only
  gu                         Queue with job details
  maq                        My jobs in queue
  macct                      My job accounting info
  free_resources             Unallocated resources by node
  whypending <jobid>         Explain why job is pending

Job Attachment:
  attach                     Attach to running job output
  arun <jobid>               Shell on running job
  svtop                      nvtop on last running job

Logs:
  jlog <jobid> [lines]       Tail stdout (default: 50)
  te <jobid> [lines]         Tail stderr (default: 50)
  cdlogs                     cd to logs directory
  lslogs                     List recent logs

QoS Limits (normal/debug):
  normal: 24h, up to 4 GPUs/job, 6 GPUs/user
  debug:  2h, 1 GPU only, higher priority

Examples:
  grun bash                         # Interactive A100
  lrun --gpus=2 python train.py     # 2x L40 interactive
  grun --debug nvidia-smi           # Quick A100 test
  drun l40 python test.py           # Debug QoS on L40
  gbatch --gpus=4 'python big.py'   # 4x A100 batch job
  sc 12345                          # Cancel job 12345

EOF
}

