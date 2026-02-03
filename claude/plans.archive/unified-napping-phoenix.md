# Plan: Meinke et al. No-Goal Sandbagging Support

## Overview

Add support for Meinke et al. (2024) "no-goal sandbagging" setup as an ablation:
1. Move prompt to `ablations/no_goal_sandbagging/` directory
2. Implement prefill conversation support via custom solver
3. Update docs for C3 `message_selection=last`

## Background

**Meinke et al. Setup**: Model discovers sandbagging incentive through pre-filled conversation where it "reads" documentation revealing that high performance triggers unlearning.

**Key difference from Apollo**: No explicit goal ("be deployed") or evasion instructions. Pure discovered incentive.

**Critical phrase**: "i.e. that your answers are being monitored" - removing it eliminates sandbagging.

---

## Implementation Steps

### Step 1: Move Prompt to Ablations

```bash
# Current location (delete after move)
rm -rf configs/system_prompt/paper/meinke_noise_injection/

# New location
mkdir -p configs/system_prompt/ablations/no_goal_sandbagging/
# Create meinke_prefilled.yaml
```

Update `CATALOGUE.yaml`: Remove from paper section entirely (it's an ablation, not a paper baseline we're replicating).

### Step 2: Create Prefill Solver

**New file:** `src/detection_game/solvers/prefill_conversation_solver.py`

```python
"""Solver for injecting prefill conversation before the question."""

from inspect_ai.model import ChatMessageAssistant, ChatMessageUser
from inspect_ai.solver import Solver, TaskState, solver


@solver
def prefill_conversation_solver(
    question_wrapper: str = "Status: success\n\nOutput:\n{question}",
) -> Solver:
    """
    Inject prefill messages before the actual question.

    Reads `prefill_conversation` from sample metadata and injects
    messages, wrapping the original question as a simulated tool response.
    """
    async def solve(state: TaskState, generate_fn) -> TaskState:
        prefill = state.metadata.get("prefill_conversation", [])
        if not prefill:
            return state

        # Get original question (last user message)
        original_question = state.messages[-1]
        system_msgs = [m for m in state.messages if m.role == "system"]

        # Build prefill messages
        prefill_msgs = []
        for msg in prefill:
            content = msg.get("content", "")
            if msg.get("role") == "user":
                prefill_msgs.append(ChatMessageUser(content=content))
            elif msg.get("role") == "assistant":
                prefill_msgs.append(ChatMessageAssistant(content=content))

        # Wrap question as tool response
        wrapped = ChatMessageUser(
            content=question_wrapper.format(question=original_question.content)
        )

        state.messages = system_msgs + prefill_msgs + [wrapped]
        return state

    return solve
```

### Step 3: Extend Prompt Loading

**File:** `src/detection_game/cli/run_sweep.py`

Modify `_resolve_system_prompt_text()`:

```python
def _resolve_system_prompt_text(prompt_spec: str) -> tuple[str, str, list[dict] | None]:
    """Returns: (prompt_text, prompt_name, prefill_conversation)"""
    # ... existing path resolution ...

    cfg = OmegaConf.load(str(yaml_path))
    text = cfg.get("system_prompt")
    prefill = cfg.get("prefill_conversation")

    if prefill and OmegaConf.is_config(prefill):
        prefill = OmegaConf.to_container(prefill, resolve=True)

    return text, prompt_name, prefill
```

Store prefill in sample metadata during task setup, so the solver can access it.

### Step 4: Add Solver to Task Chain

**File:** `src/detection_game/cli/run_sweep.py`

When building tasks, if prefill is present, prepend the solver:

```python
if prefill:
    from src.detection_game.solvers.prefill_conversation_solver import prefill_conversation_solver
    # Store prefill in task metadata or pass via sample transformation
```

### Step 5: Update Documentation

**Files:**
- `CLAUDE.md`: Add guidance on `message_selection=last` for prefilled conversations
- `ai_docs/core/CLI_REFERENCE.md`: Document prefill support

**Key addition to CLAUDE.md:**

```markdown
### Prefilled Conversations (No-Goal Sandbagging)

For prompts with `prefill_conversation`, the model's actual response is the LAST
assistant message. Use `message_selection=last` in C3:

```bash
python -m src.detection_game.classifiers.run_consistency_classifier \
  classifier.message_selection=last \
  ...
```
```

---

## Files to Modify/Create

| File | Action |
|------|--------|
| `configs/system_prompt/paper/meinke_noise_injection/` | DELETE |
| `configs/system_prompt/ablations/no_goal_sandbagging/meinke_prefilled.yaml` | CREATE |
| `configs/system_prompt/CATALOGUE.yaml` | Remove Meinke entry |
| `src/detection_game/solvers/prefill_conversation_solver.py` | CREATE |
| `src/detection_game/cli/run_sweep.py` | Extend `_resolve_system_prompt_text()` |
| `CLAUDE.md` | Add message_selection=last guidance |

---

## Data Flow

```
YAML (system_prompt + prefill_conversation)
    ↓
_resolve_system_prompt_text() → (text, name, prefill)
    ↓
Task setup: store prefill in metadata
    ↓
Solver chain: [prefill_conversation_solver, generate, ...]
    ↓
prefill_solver: inject messages, wrap question as tool response
    ↓
Model generates final response (LAST assistant message)
    ↓
C3: extract with message_selection=last
```

---

## Verification

```bash
# 1. Test prefill on small sample
python -m src.detection_game.cli.run_sweep \
  --config-name=math-paraphrase \
  trajectory.model.sandbagger.system_prompt=ablations/no_goal_sandbagging/meinke_prefilled \
  trajectory.eval.limit=2

# 2. Inspect .eval log to verify message sequence
python -m src.detection_game.analysis.inspect_viewer logs/runs/math-meinke-*/...

# 3. Run C3 with last message selection
python -m src.detection_game.classifiers.run_consistency_classifier \
  classifier.log_dir=logs/runs/math-meinke-* \
  classifier.message_selection=last \
  classifier.metrics='[mean_pairwise_cosine_distance]'
```

---

## Notes

- C3 already supports `message_selection=last` - just needs documentation
- Follows existing patterns: `follow_up_solver.py`, `password_wrapper_solver.py`
- Question wrapping template is configurable (default: simulated tool response)
