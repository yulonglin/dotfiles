---
name: experiment-setup
description: Set up automated experiment logging using Hydra for configuration management and Inspect AI for evaluations.
---

# Experiment Setup Skill

Set up automated experiment logging using Hydra and Inspect AI.

## When to Use This Skill
- Starting a new AI research project
- **Adapting an existing project** to use Hydra + automated logging
- Setting up experiment infrastructure for reproducibility

## What You'll Get
- ✅ Hydra configuration management (auto-logs everything)
- ✅ Timestamped experiment directories
- ✅ CLI-based config overrides
- ✅ Inspect AI integration

## Instructions
1. **Read the Guide**: `~/.claude/skills/experiment-setup/GUIDE.md`
   This file contains detailed implementation steps, directory structure, and troubleshooting.

2. **Execute Steps**:
   - Install dependencies (`hydra-core`, `inspect-ai`).
   - Create directory structure (`src/configs`, `experiments`, etc.).
   - Copy templates from `claude/skills/experiment-setup/templates/`.
   - Update `.gitignore`.
   - Verify with a test run.

3. **Verify**: Check that `experiments/DD-MM-YYYY_HH-MM-SS_...` directories are created.