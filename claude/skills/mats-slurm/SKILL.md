# MATS SLURM Skill

Set up and use SLURM helpers for the MATS compute cluster with A100 and L40 GPUs.

## When to Use This Skill

Use this skill when:
- Setting up SLURM aliases for a new MATS cluster user
- Running interactive GPU jobs (A100 or L40)
- Submitting batch jobs
- Monitoring job queues and GPU availability
- Viewing and tailing job logs

## Quick Reference (Commands)

### Interactive Jobs
```bash
grun <command>                    # A100 GPU (128G mem default)
grun --gpus=2 <command>           # 2x A100 GPUs
grun --mem=256G <command>         # A100 with custom memory
grun --debug <command>            # A100 with debug QoS (2h, high priority)
lrun <command>                    # L40 GPU (64G mem default)
lrun --gpus=4 <command>           # 4x L40 GPUs
drun a100 <command>               # Quick debug: A100, 2h limit, 1 GPU
drun l40 <command>                # Quick debug: L40, 2h limit, 1 GPU
```

### Batch Jobs
```bash
gbatch 'python train.py'                    # Submit A100 batch job
gbatch --gpus=4 'python train.py'           # 4x A100 batch job
gbatch --gpus=2 --mem=256G 'python big.py'  # Custom resources
gbatch --time=48:00:00 'python long.py'     # Custom time limit
lbatch 'python train.py'                    # Submit L40 batch job
```

### Job Control
```bash
sc <jobid>                  # Cancel a job
sc 123 456 789              # Cancel multiple jobs
sc all                      # Cancel all your jobs
```

### Monitoring
```bash
gpus                        # Show all GPU nodes status
gpusfree                    # Show idle GPU nodes only
gu                          # Queue status with job details
maq                         # Show my jobs in queue
macct                       # My job accounting info
free_resources              # Unallocated resources by node
whypending <jobid>          # Explain why job is pending
```

### Logs
```bash
jlog <jobid> [lines]        # Tail stdout log (default: 50 lines)
te <jobid> [lines]          # Tail stderr log (default: 50 lines)
cdlogs                      # cd to logs directory
lslogs                      # List recent logs
```

### Attach to Running Jobs
```bash
attach                      # Attach to running job output (interactive selector)
arun <jobid>                # Get shell on running job
svtop                       # Run nvtop on last running job
```

## Setup Instructions

### 1. Create Log Directories

```bash
# Create your personal log directories
mkdir -p ~/slurmlogs ~/slurmerrors
```

### 2. Install the Aliases

Option A: Copy template and customize:
```bash
cp ~/.claude/skills/mats-slurm/templates/slurm_aliases.sh ~/.slurm_aliases

# Edit to set your username (replace 'your_username' with your actual username)
sed -i "s/SLURM_USER=\"\"/SLURM_USER=\"$(whoami)\"/" ~/.slurm_aliases
```

Option B: Source directly with environment variable:
```bash
export SLURM_USER=$(whoami)
source ~/.claude/skills/mats-slurm/templates/slurm_aliases.sh
```

### 3. Add to Shell Config

Add to your `~/.zshrc` or `~/.bashrc`:
```bash
# MATS SLURM helpers
export SLURM_USER=$(whoami)
[ -f ~/.slurm_aliases ] && source ~/.slurm_aliases
```

Or source from the Claude skill directly:
```bash
# MATS SLURM helpers (from Claude skill)
export SLURM_USER=$(whoami)
[ -f ~/.claude/skills/mats-slurm/templates/slurm_aliases.sh ] && \
    source ~/.claude/skills/mats-slurm/templates/slurm_aliases.sh
```

### 4. Verify Setup

```bash
source ~/.zshrc  # or restart terminal
slurmhelp        # Should show available commands
gpus             # Should show GPU node status
```

## Configuration Variables

Set these before sourcing the aliases:

| Variable | Default | Description |
|----------|---------|-------------|
| `SLURM_USER` | `$(whoami)` | Your cluster username |
| `SLURM_LOG_DIR` | `$HOME/slurmlogs` | stdout log directory |
| `SLURM_ERROR_DIR` | `$HOME/slurmerrors` | stderr log directory |
| `SLURM_PARTITION` | `compute` | Default partition |
| `SLURM_DEFAULT_ENV` | (none) | Conda/mamba env to activate in batch jobs |

Example custom config:
```bash
export SLURM_USER="y.lin"
export SLURM_LOG_DIR="/mnt/nw/home/y.lin/logs/slurm"
export SLURM_DEFAULT_ENV="myenv"
source ~/.slurm_aliases
```

## GPU Types Available

| GPU | Memory | Alias | Use Case |
|-----|--------|-------|----------|
| A100 | 80GB | `grun`, `gbatch` | Large models, training |
| L40 | 48GB | `lrun`, `lbatch` | Inference, smaller training |

## QoS (Quality of Service) Levels

| QoS | Max Time | Max GPUs/Job | Max GPUs/User | Priority |
|-----|----------|--------------|---------------|----------|
| `normal` | 24 hours | 4 | 6 | Standard |
| `debug` | 2 hours | 1 | 1 | Higher |

Use `--debug` flag or `drun` for quick tests with higher priority scheduling.

## Usage Examples

### Interactive Development
```bash
# Get A100 for interactive work
grun bash

# Run Python script with A100
grun python train.py --config=large

# Use L40 with more memory
lrun --mem=128G python inference.py
```

### Batch Training
```bash
# Submit training job on A100
gbatch 'python train.py --epochs=100'

# Check job status
maq

# Follow the logs
jlog <jobid>
```

### Debugging
```bash
# Find available GPUs
gpusfree

# Check why job isn't running
whypending <jobid>

# Get shell on running job for debugging
arun <jobid>

# Watch GPU utilization on your job
svtop
```

## Customizing Batch Jobs

The `gbatch` and `lbatch` functions create temporary scripts. To customize:

1. **Default time**: Edit `--time=24:00:00` in the template
2. **Default memory**: Edit `--mem=128G` in the template
3. **Default environment**: Set `SLURM_DEFAULT_ENV` variable
4. **Additional SBATCH options**: Modify the heredoc in the function

For complex batch jobs, consider writing a dedicated SBATCH script instead.

## Troubleshooting

### "Log file not found for job X"
- Job may not have started yet
- Check if job is still pending: `maq`
- Try `squeue -j <jobid>` to verify job status

### Jobs stuck in pending
- Run `whypending <jobid>` to see why
- Check `gpusfree` for available resources
- May need to request less memory or different GPU type

### "sattach failed"
- Job may have completed or not started
- Falls back to `tail -f` on log file automatically

### Cannot find GPU
- Use `gpus` to see all nodes and their status
- Use `gpusfree` to see only idle nodes
- Some nodes may be in maintenance (`maint`) or `drain` state

## Integration with Claude Code

When working with Claude Code on MATS cluster:

1. **Run experiments in batch**: Use `gbatch` for long-running experiments
2. **Monitor from Claude**: Use `jlog` and `te` to show logs to Claude
3. **Interactive debugging**: Use `arun` to get shell access for debugging

Example workflow:
```bash
# Submit experiment
gbatch 'uv run python src/experiment.py'

# Get job ID from output, then tail logs
jlog <jobid>

# If something goes wrong, attach for debugging
arun <jobid>
```
