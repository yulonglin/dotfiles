# Fix: Prefill Conversation Solver Content Type Bug

## Context

The `prefill_conversation_solver` assumes `msg.content` is always a `str`, but Inspect AI's
`ChatMessageUser.content` can be `str | list[Content]`. If a dataset loader wraps questions
in `ContentText` objects, `question_wrapper.format(question=original_question)` produces
stringified Python objects instead of the actual question text.

Currently safe for MATH (text-only), but will break silently if reused with other tasks.

## Fix

**File:** `src/detection_game/solvers/prefill_conversation_solver.py`

**Change:** Import and use `extract_text_from_content` (already exists at
`src/detection_game/utils/content_extraction.py`) when extracting the original question.

```python
# Line 1: Add import
from src.detection_game.utils.content_extraction import extract_text_from_content

# Line 70: Change
original_question = msg.content
# To
original_question = extract_text_from_content(msg.content)
```

That's it — two lines changed.

## Verification

1. Run existing tests: `uv run pytest tests/ -k prefill` (if any exist)
2. Dry-run with a MATH config:
   ```bash
   python -m src.detection_game.cli.run_sweep \
     --config-name=conf \
     'sweep.role_system_prompts.sandbagger=[ablations/no_goal_sandbagging/meinke_prefilled]' \
     prefill.enabled=true \
     trajectory.eval.limit=2
   ```
3. Verify the wrapped question in logs contains the actual question text, not `[ContentText(...)]`
