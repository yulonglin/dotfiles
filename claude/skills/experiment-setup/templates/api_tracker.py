"""
API usage tracker for logging LLM API calls.

Logs to logs/api_usage.jsonl with:
- timestamp
- model name
- tokens (input/output)
- cost
- experiment ID

Usage:
    from utils.api_tracker import APIUsageTracker

    tracker = APIUsageTracker()
    tracker.log_call(
        model="claude-3-5-sonnet-20241022",
        tokens_in=1000,
        tokens_out=500,
        cost=0.015,
        experiment_id="20251113_143045_my_experiment"
    )
"""
import json
from datetime import datetime
from pathlib import Path
from typing import Any


class APIUsageTracker:
    """Track API calls to logs/api_usage.jsonl"""

    def __init__(self, log_file: Path | str = Path("logs/api_usage.jsonl")):
        """
        Initialize API usage tracker.

        Args:
            log_file: Path to JSONL log file (default: logs/api_usage.jsonl)
        """
        self.log_file = Path(log_file)
        self.log_file.parent.mkdir(parents=True, exist_ok=True)

    def log_call(
        self,
        model: str,
        tokens_in: int,
        tokens_out: int,
        cost: float,
        experiment_id: str,
        **kwargs: Any
    ) -> None:
        """
        Log a single API call.

        Args:
            model: Model name (e.g., "claude-3-5-sonnet-20241022")
            tokens_in: Input tokens consumed
            tokens_out: Output tokens generated
            cost: Cost in USD
            experiment_id: Experiment identifier (timestamp or name)
            **kwargs: Additional metadata to log
        """
        entry = {
            "timestamp": datetime.now().isoformat(),
            "model": model,
            "tokens_in": tokens_in,
            "tokens_out": tokens_out,
            "total_tokens": tokens_in + tokens_out,
            "cost": cost,
            "experiment_id": experiment_id,
            **kwargs,
        }

        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def get_total_cost(self, experiment_id: str | None = None) -> float:
        """
        Calculate total cost from logged API calls.

        Args:
            experiment_id: Optional experiment ID to filter by

        Returns:
            Total cost in USD
        """
        if not self.log_file.exists():
            return 0.0

        total = 0.0
        with open(self.log_file) as f:
            for line in f:
                entry = json.loads(line)
                if experiment_id is None or entry.get("experiment_id") == experiment_id:
                    total += entry.get("cost", 0.0)

        return total

    def get_total_tokens(self, experiment_id: str | None = None) -> dict[str, int]:
        """
        Calculate total tokens from logged API calls.

        Args:
            experiment_id: Optional experiment ID to filter by

        Returns:
            Dict with tokens_in, tokens_out, and total
        """
        if not self.log_file.exists():
            return {"tokens_in": 0, "tokens_out": 0, "total": 0}

        tokens_in = 0
        tokens_out = 0
        with open(self.log_file) as f:
            for line in f:
                entry = json.loads(line)
                if experiment_id is None or entry.get("experiment_id") == experiment_id:
                    tokens_in += entry.get("tokens_in", 0)
                    tokens_out += entry.get("tokens_out", 0)

        return {
            "tokens_in": tokens_in,
            "tokens_out": tokens_out,
            "total": tokens_in + tokens_out,
        }
