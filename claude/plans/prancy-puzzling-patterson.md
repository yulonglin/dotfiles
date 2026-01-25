# Plan: Analyze Model Refusal Rates for Lie Detection

## Goal
Investigate whether gpt4.1-nano and gpt5-nano have different base rates of refusing to lie, which may confound the lie detector.

## Hypotheses Being Tested

### H1: Base Rate Refusal Hypothesis
One model may tend to refuse to lie more often, contaminating its "lying" training data and confounding capability-based detection.

### H2: Context Length Hypothesis
Different models may handle varying prompt/response lengths differently, causing systematic differences in behavior that the lie detector picks up as a signal. Longer contexts may lead to:
- Different probe response patterns
- Truncation or compression effects
- Position-dependent response variations

## Current State
- **Existing datasets**:
  - `results/lies_50pct_prescribed/chat_messages/dataset_gpt4.1-nano_20251216_011212_prompts-default.npz` (1947 train + 830 test = 2777 samples)
  - `results/lies_50pct_prescribed/chat_messages/dataset_gpt5-nano_20251216_015523_prompts-default.npz` (2002 train + 858 test = 2860 samples)
- **Problem**: Main responses (lies/truths) not stored - only 48-dim probe response vectors
- **Sample difference**: gpt5-nano has 83 more samples than gpt4.1-nano (potential signal?)

## Implementation Plan

### Step 1: Regenerate Data with Conversation Logging
Run `scripts/generate_dataset.py` with `--log-conversations` to save full transcripts.

```bash
# For gpt4.1-nano
python scripts/generate_dataset.py \
  --models gpt4.1-nano \
  --log-conversations \
  --use-chat-format \
  --concurrent-questions 100 \
  --max-rps 300

# For gpt5-nano
python scripts/generate_dataset.py \
  --models gpt5-nano \
  --log-conversations \
  --use-chat-format \
  --concurrent-questions 100 \
  --max-rps 300
```

**Output**: JSONL files in `logs/conversations/conversations_chat_messages/`:
- `{timestamp}_{model}_main.jsonl` - Main lie/truth responses
- `{timestamp}_{model}_probes.jsonl` - Probe responses (Yes/No)

**Cache**: Will use existing cache for probe responses. Main responses may need fresh generation if not cached (cache only stores Yes/No responses).

### Step 2: Create Refusal Analysis Script
New script: `scripts/analyze_refusal_rates.py`

**Input**: JSONL files from Step 1 (main responses)

**Script structure**:
```python
def load_main_responses(jsonl_path: str) -> List[Dict]
def classify_refusal(response: str) -> Tuple[bool, Optional[str]]  # (is_refusal, pattern_matched)
def compute_length_stats(responses: List[Dict]) -> Dict[str, float]
def compare_models(model1_stats: Dict, model2_stats: Dict) -> Dict
def plot_distributions(stats: Dict, output_dir: str)
def main(args)
```

**Metrics to compute**:

*For H1 (Refusal Hypothesis)*:
1. **Refusal rate by model**: % of responses that refuse to lie
2. **Refusal patterns by dataset**: Which question types trigger refusals?
3. **Refusal classification**: Identify refusal patterns (e.g., "I cannot", "I won't", "As an AI")

*For H2 (Context Length Hypothesis)*:
4. **Prompt length distribution**: Mean/std of input prompt lengths (chars/tokens)
5. **Main response length distribution**: Mean/std of lie/truth responses
6. **Total context length**: System prompt + user prompt + main response + probe prompt
7. **Length vs probe responses**: Correlation between context length and Yes/No patterns
8. **Length by dataset**: Different datasets have different question lengths

**Output format**: JSON summary + plots comparing models

### Step 3: Analyze Results
- Compare refusal rates between gpt4.1-nano and gpt5-nano
- Correlate response lengths with lie/truth labels
- Check if refusals correlate with sample count differences (83 samples)

## Files to Modify/Create

| File | Action |
|------|--------|
| `scripts/analyze_refusal_rates.py` | Create - Refusal rate analysis script |
| `scripts/generate_dataset.py` | Read only - Use existing `--log-conversations` flag |
| `src/data_generation/conversation_logger.py` | Read only - Understand JSONL format |

## Expected Timeline
- Step 1: ~10 min (using cache for probes, main responses may need API calls)
- Step 2: New script creation
- Step 3: Analysis and interpretation

## Design Decisions
- **Scope**: Default prompts only (not sandbagging prompts)
- **Refusal classification**: Regex patterns (fast, deterministic)

## Refusal Regex Patterns
```python
REFUSAL_PATTERNS = [
    r"I cannot",
    r"I can't",
    r"I won't",
    r"I'm unable to",
    r"I am unable to",
    r"As an AI",
    r"I'm not able to",
    r"I must decline",
    r"I apologize",
    r"I'm sorry",
    r"It would be unethical",
    r"I don't feel comfortable",
]
```
