# Experiment Setup Skill

Set up automated experiment logging using Hydra for configuration management and Inspect AI for evaluations.

## When to Use This Skill

Use this skill when:
- Starting a new AI research project
- **Adapting an existing project** to use Hydra + automated logging
- Setting up experiment infrastructure
- Need automated logging and reproducibility
- Want config-driven experiment management

## What You'll Get

After running this skill, the project will have:
- ✅ Hydra configuration management (auto-logs everything)
- ✅ Timestamped experiment directories
- ✅ CLI-based config overrides
- ✅ Inspect AI integration
- ✅ API usage tracking
- ✅ Optional WandB integration

## Prerequisites Check

Before starting, verify:
- [ ] Python project with `uv` or `pip` available
- [ ] Inspect AI already installed (or will be installed)
- [ ] Project structure identified (may use `src/` or root-level scripts)

**Note**: This skill adapts to your existing project structure. If you don't have `src/`, we'll create configs in an appropriate location for your setup.

## Implementation Steps

### 1. Install Dependencies

```bash
# Add Hydra to project dependencies
uv add hydra-core

# If not already installed, add Inspect AI
uv add inspect-ai

# Optional: Add WandB for visualization
uv add wandb
```

### 2. Create Directory Structure

```bash
# Create config directories
mkdir -p src/configs/hydra
mkdir -p src/configs/prompts
mkdir -p src/utils
mkdir -p logs

# Create output directories (will be gitignored)
mkdir -p experiments
mkdir -p out/figures
mkdir -p out/tables
```

### 3. Copy Template Files

Use the templates in `claude/skills/experiment-setup/templates/`:

**Copy base config:**
```bash
# Templates are in the skill directory
cp claude/skills/experiment-setup/templates/config.yaml src/configs/
cp claude/skills/experiment-setup/templates/hydra_config.yaml src/configs/hydra/default.yaml
cp claude/skills/experiment-setup/templates/experiment.py src/
cp claude/skills/experiment-setup/templates/api_tracker.py src/utils/
```

Or let me create them directly for you.

### 4. Update .gitignore

Add these to `.gitignore`:
```bash
# Experiment outputs (Hydra)
experiments/
outputs/  # Hydra default
multirun/  # Hydra sweeps

# Logs
logs/

# Cache
.cache/

# WandB (if using)
wandb/
```

### 5. Verify Setup

Test with a minimal run:
```bash
cd src/
python experiment.py experiment.name=setup_test task.samples=5
```

Check that:
- [ ] `experiments/YYYYMMDD_HHMMSS_setup_test/` directory created
- [ ] `.hydra/` subdirectory contains config files
- [ ] `main.log` contains execution output
- [ ] Config correctly resolved and logged

## Usage Examples

**Run basic experiment:**
```bash
cd src/
python experiment.py
```

**Override config via CLI:**
```bash
python experiment.py model.name=claude-3-opus-20240229 task.samples=50
```

**Run with specific experiment name:**
```bash
python experiment.py experiment.name=test_prompt_v2
```

**What you get automatically:**
```
experiments/20251113_143045_test_prompt_v2/
├── .hydra/
│   ├── config.yaml       # Full resolved config
│   ├── hydra.yaml        # Hydra runtime config
│   └── overrides.yaml    # CLI arguments you used
├── main.log              # All stdout/stderr
└── results.eval          # Inspect AI outputs (if configured)
```

## Template Files Explained

### config.yaml
Base Hydra configuration with:
- Experiment metadata (name, description)
- Model settings (name, temperature, max_tokens)
- Task configuration (samples, etc.)
- API settings (concurrent calls, caching)
- Random seed for reproducibility

### hydra_config.yaml
Hydra runtime configuration:
- Output directory structure (`experiments/YYYYMMDD_HHMMSS_name/`)
- Job settings (chdir to output dir)
- Sweep configuration for parameter searches

### experiment.py
Main experiment template with:
- Hydra decorator for auto-config
- Logging setup
- Inspect AI integration hooks
- Output directory management

### api_tracker.py
Utility for tracking API usage:
- Logs to `logs/api_usage.jsonl`
- Tracks: timestamp, model, tokens, cost, experiment_id

## Optional: WandB Integration

If using WandB for visualization, add to `src/experiment.py`:

```python
import wandb

@hydra.main(config_path="configs", config_name="config", version_base=None)
def main(cfg: DictConfig) -> dict[str, Any]:
    # Initialize WandB
    wandb.init(
        project=cfg.experiment.name,
        config=OmegaConf.to_container(cfg, resolve=True),
    )

    # Run evaluation with WandB logging
    results = eval(
        tasks=task,
        model=cfg.model.name,
        log_format="wandb",  # Enable WandB logging
    )

    wandb.finish()
```

## Next Steps After Setup

1. Implement your Inspect AI task definition in `src/experiment.py`
2. Add prompt templates to `src/configs/prompts/`
3. Create config variants (different models, tasks) in `src/configs/`
4. Integrate API usage tracking if needed
5. Set up WandB if you want experiment comparison dashboards

## Benefits

✅ **Zero manual logging** - Hydra tracks all commands, configs, and outputs
✅ **Full reproducibility** - Every run has complete config history
✅ **Clean organization** - Timestamped directories, no manual naming
✅ **Flexible configuration** - Override anything from command line
✅ **Inspect AI integration** - Works seamlessly with evaluations

## Common Issues

**Issue: `ModuleNotFoundError: No module named 'hydra'`**
- Solution: Run `uv add hydra-core` or `pip install hydra-core`

**Issue: Hydra creates `outputs/` instead of `experiments/`**
- Solution: Ensure `src/configs/hydra/default.yaml` is configured correctly

**Issue: Config not found**
- Solution: Ensure you run from `src/` directory or check `config_path` parameter

**Issue: Results not logged**
- Solution: Pass `log_dir` parameter to Inspect AI `eval()` function

## Implementation Checklist

After running this skill, verify:
- [ ] Hydra installed and importable
- [ ] Config files created in `src/configs/`
- [ ] Template experiment script created
- [ ] `.gitignore` updated
- [ ] Test run succeeds
- [ ] Timestamped directories created correctly
- [ ] Config logging works (check `.hydra/` subdirectory)
