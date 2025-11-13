"""
Base experiment template with Hydra + Inspect AI integration.

Usage:
    python experiment.py                                    # Run with defaults
    python experiment.py model.name=claude-3-opus-20240229  # Override model
    python experiment.py experiment.name=my_test            # Custom name
    python experiment.py task.samples=50                    # Override samples

What Hydra automatically logs:
    - Full resolved config (.hydra/config.yaml)
    - CLI overrides (.hydra/overrides.yaml)
    - Hydra runtime config (.hydra/hydra.yaml)
    - All stdout/stderr (main.log)
"""
import logging
from pathlib import Path
from typing import Any

import hydra
from omegaconf import DictConfig, OmegaConf

# Uncomment when ready to use Inspect AI:
# from inspect_ai import Task, eval
# from inspect_ai.log import read_eval_log

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@hydra.main(config_path="configs", config_name="config", version_base=None)
def main(cfg: DictConfig) -> dict[str, Any]:
    """
    Run experiment with automated logging.

    Hydra automatically:
    - Creates timestamped output directory: experiments/YYYYMMDD_HHMMSS_name/
    - Logs full config to .hydra/config.yaml
    - Logs CLI overrides to .hydra/overrides.yaml
    - Logs execution to main.log
    - Changes working directory to output dir (if chdir: true)

    Args:
        cfg: Hydra configuration (auto-loaded from configs/)

    Returns:
        dict with experiment results and metadata
    """
    # Print configuration
    logger.info("=" * 80)
    logger.info("Starting experiment: %s", cfg.experiment.name)
    logger.info("=" * 80)
    logger.info("Configuration:\n%s", OmegaConf.to_yaml(cfg))

    # Get output directory (auto-created by Hydra)
    output_dir = Path(hydra.core.hydra_config.HydraConfig.get().runtime.output_dir)
    logger.info("Output directory: %s", output_dir)

    # TODO: Implement your experiment logic here
    # Example Inspect AI integration:
    """
    # 1. Define your task
    task = Task(
        dataset=your_dataset,
        plan=[
            # Your solver steps
        ],
        scorer=your_scorer,
    )

    # 2. Run evaluation
    results = eval(
        tasks=task,
        model=cfg.model.name,
        model_args={
            "temperature": cfg.model.temperature,
            "max_tokens": cfg.model.max_tokens,
        },
        log_dir=str(output_dir),
        log_format="json",  # or "wandb" for WandB integration
    )

    # 3. Read and process results
    eval_log = read_eval_log(output_dir / "results.eval")
    logger.info("Evaluation complete. Status: %s", eval_log.status)
    logger.info("Samples processed: %d", len(eval_log.samples))

    # 4. Save any additional outputs
    # (Already in the timestamped experiment directory)
    """

    logger.info("=" * 80)
    logger.info("Experiment complete. Results saved to: %s", output_dir)
    logger.info("=" * 80)

    return {
        "status": "success",
        "output_dir": str(output_dir),
        "experiment_name": cfg.experiment.name,
    }


if __name__ == "__main__":
    main()
