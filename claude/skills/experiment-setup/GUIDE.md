# Experiment Setup Guide

## Implementation Steps

### 1. Install Dependencies
```bash
uv add hydra-core inspect-ai wandb
```

### 2. Create Directory Structure
```bash
mkdir -p src/configs/hydra src/configs/prompts src/utils logs
mkdir -p experiments out/figures out/tables
```

### 3. Copy Template Files
Use the templates in `claude/skills/experiment-setup/templates/`:
- `config.yaml` → `src/configs/`
- `hydra_config.yaml` → `src/configs/hydra/default.yaml`
- `experiment.py` → `src/`
- `api_tracker.py` → `src/utils/`

### 4. Update .gitignore
Add: `experiments/`, `outputs/`, `multirun/`, `logs/`, `.cache/`, `wandb/`

### 5. Verify Setup
Run: `python src/experiment.py experiment.name=setup_test task.samples=5`

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

## Template Files Explained

### config.yaml
Base Hydra configuration with metadata, model settings, task config, and API settings.

### hydra_config.yaml
Hydra runtime configuration for output directory structure (`experiments/YYYYMMDD_HHMMSS_name/`) and job settings.

### experiment.py
Main experiment template with Hydra decorator, logging setup, and Inspect AI integration.

### api_tracker.py
Utility for tracking API usage to `logs/api_usage.jsonl`.

## Common Issues

**Issue: `ModuleNotFoundError: No module named 'hydra'`**
- Solution: Run `uv add hydra-core`

**Issue: Hydra creates `outputs/` instead of `experiments/`**
- Solution: Ensure `src/configs/hydra/default.yaml` is configured correctly

**Issue: Config not found**
- Solution: Ensure you run from `src/` directory or check `config_path` parameter

**Issue: Results not logged**
- Solution: Pass `log_dir` parameter to Inspect AI `eval()` function
