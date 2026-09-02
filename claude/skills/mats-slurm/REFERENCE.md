# MATS SLURM Reference

## Interactive Jobs
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

## Batch Jobs
```bash
gbatch 'python train.py'                    # Submit A100 batch job
gbatch --gpus=4 'python train.py'           # 4x A100 batch job
gbatch --gpus=2 --mem=256G 'python big.py'  # Custom resources
gbatch --time=48:00:00 'python long.py'     # Custom time limit
lbatch 'python train.py'                    # Submit L40 batch job
```

## Job Control
```bash
sc <jobid>                  # Cancel a job
sc 123 456 789              # Cancel multiple jobs
sc all                      # Cancel all your jobs
```

## Monitoring
```bash
gpus                        # Show all GPU nodes status
gpusfree                    # Show idle GPU nodes only
gu                          # Queue status with job details
maq                         # Show my jobs in queue
macct                       # My job accounting info
free_resources              # Unallocated resources by node
whypending <jobid>          # Explain why job is pending
```

## Logs
```bash
jlog <jobid> [lines]        # Tail stdout log (default: 50 lines)
te <jobid> [lines]          # Tail stderr log (default: 50 lines)
cdlogs                      # cd to logs directory
lslogs                      # List recent logs
```

## Attach to Running Jobs
```bash
attach                      # Attach to running job output (interactive selector)
arun <jobid>                # Get shell on running job
svtop                       # Run nvtop on last running job
```

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SLURM_USER` | `$(whoami)` | Your cluster username |
| `SLURM_LOG_DIR` | `$HOME/slurmlogs` | stdout log directory |
| `SLURM_ERROR_DIR` | `$HOME/slurmerrors` | stderr log directory |
| `SLURM_PARTITION` | `compute` | Default partition |
| `SLURM_DEFAULT_ENV` | (none) | Conda/mamba env to activate in batch jobs |

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
