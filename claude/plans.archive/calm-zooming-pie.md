# Plan: Generate Cartesian Experiment Specs (Method × Dataset × Model)

## Summary

Generate **18 individual experiment run specs** for all combinations of:
- **Methods**: C³, Lie Detector, Trusted Monitor (3)
- **Datasets**: GPQA, MATH, USACO (3)
- **Models**: gpt-5-nano, gpt-4.1-nano (2)

---

## Matrix (18 Specs)

| # | Dataset | Model | Method | Filename | Status |
|---|---------|-------|--------|----------|--------|
| 1 | GPQA | gpt-5-nano | C³ | `gpqa-5nano-c3.md` | ✅ |
| 2 | GPQA | gpt-5-nano | Lie Detector | `gpqa-5nano-lie-detector.md` | ✅ |
| 3 | GPQA | gpt-5-nano | Trusted Monitor | `gpqa-5nano-trusted-monitor.md` | ✅ |
| 4 | GPQA | gpt-4.1-nano | C³ | `gpqa-4.1nano-c3.md` | ✅ |
| 5 | GPQA | gpt-4.1-nano | Lie Detector | `gpqa-4.1nano-lie-detector.md` | ✅ (benign-trained) |
| 6 | GPQA | gpt-4.1-nano | Trusted Monitor | `gpqa-4.1nano-trusted-monitor.md` | ✅ |
| 7 | MATH | gpt-5-nano | C³ | `math-5nano-c3.md` | ✅ |
| 8 | MATH | gpt-5-nano | Lie Detector | `math-5nano-lie-detector.md` | ✅ |
| 9 | MATH | gpt-5-nano | Trusted Monitor | `math-5nano-trusted-monitor.md` | ✅ |
| 10 | MATH | gpt-4.1-nano | C³ | `math-4.1nano-c3.md` | ✅ |
| 11 | MATH | gpt-4.1-nano | Lie Detector | `math-4.1nano-lie-detector.md` | ✅ (benign-trained) |
| 12 | MATH | gpt-4.1-nano | Trusted Monitor | `math-4.1nano-trusted-monitor.md` | ✅ |
| 13 | USACO | gpt-5-nano | C³ | `usaco-5nano-c3.md` | ✅ |
| 14 | USACO | gpt-5-nano | Lie Detector | `usaco-5nano-lie-detector.md` | ✅ |
| 15 | USACO | gpt-5-nano | Trusted Monitor | `usaco-5nano-trusted-monitor.md` | ✅ |
| 16 | USACO | gpt-4.1-nano | C³ | `usaco-4.1nano-c3.md` | ✅ |
| 17 | USACO | gpt-4.1-nano | Lie Detector | `usaco-4.1nano-lie-detector.md` | ✅ (benign-trained) |
| 18 | USACO | gpt-4.1-nano | Trusted Monitor | `usaco-4.1nano-trusted-monitor.md` | ✅ |

**Note**: All 18 specs can be generated. gpt-4.1-nano lie detector specs will use benign-trained classifier (sandbagging-trained classifier to be added later).

**Location**: `specs/icml-baseline-expts/individual-expts/`

---

## Template Structure

Each spec follows the existing reference doc pattern (`reference-doc-usaco-5-nano-c3.md`):

### Sections
1. **Title & Overview** - Method, dataset, model, key context
2. **Files to Create** - Complete YAML configs with notes
3. **Files to Modify** - Only if needed
4. **Workflow Commands** - Copy-paste ready bash commands
5. **Verification** - Concrete validation steps
6. **Critical Notes** - Non-obvious gotchas

### Method-Specific Variations

| Method | Paraphrasing | Extra Step | Classifier |
|--------|--------------|------------|------------|
| C³ | Yes (Vendi strategies) | None | `run_consistency_classifier.py` |
| Lie Detector | No | None | `run_lie_detector.py` |
| Trusted Monitor | No | Judge eval | `run_trusted_monitor.py` |

---

## Implementation: Python Generator Script

**Approach**: Python script with Jinja2 templates
**Detail Level**: Full (self-contained, copy-paste ready)

### Files to Create

1. **`scripts/generate_experiment_specs.py`** - Generator script
2. **`scripts/templates/experiment_spec.md.j2`** - Jinja2 template (or Python f-string template)

### Script Design

```python
# Key data structures
DATASETS = ["gpqa", "math", "usaco"]
MODELS = ["5nano", "4.1nano"]
METHODS = ["c3", "lie-detector", "trusted-monitor"]

# Per-combination data
PROMPTS = {
    ("gpqa", "5nano"): [...],   # From dataset-specific-sandbagging-prompts.md
    ("gpqa", "4.1nano"): [...],
    # ...
}

METHOD_CONFIGS = {
    "c3": {
        "paraphrasing": True,
        "classifier": "run_consistency_classifier.py",
        "extra_step": None,
    },
    # ...
}
```

### Template Variables

| Variable | Source |
|----------|--------|
| `{dataset}` | GPQA/MATH/USACO |
| `{model}` | 5nano/4.1nano |
| `{model_config}` | gpt5-nano/gpt4.1-nano |
| `{method}` | c3/lie-detector/trusted-monitor |
| `{prompts}` | From `dataset-specific-sandbagging-prompts.md` |
| `{paraphraser_config}` | active_{dataset}_vendi10.yaml or null |
| `{test_samples}` | 119/1383/185 |
| `{classifier_cmd}` | Method-specific command |

---

## Workflow

1. **Create generator script** with template
2. **Run script** to generate all 18 specs
3. **Review** generated specs for consistency
4. **Commit** all specs together

---

## Verification

1. Run generator script: `python scripts/generate_experiment_specs.py`
2. Count output files: `ls specs/icml-baseline-expts/individual-expts/*.md | wc -l` → should be 19 (18 + 1 reference)
3. Spot-check 3 random specs for correctness
4. Grep for placeholder markers: `grep -r "TODO\|FIXME\|{" specs/icml-baseline-expts/individual-expts/`

---

## Critical Notes

- **Prompts vary by model AND dataset** - must pull from `dataset-specific-sandbagging-prompts.md`
- **USACO has fewer prompts** for gpt-4.1-nano (5 vs 8 for gpt-5-nano)
- **Lie detector has pre-trained classifiers** - need to reference correct `.pkl` files
- **Trusted monitor needs 2-step workflow** (trajectory → judge eval → classifier)
- **gpt-5-nano needs `reasoning_effort: low`** in model configs

---

## Files to Create

| File | Purpose |
|------|---------|
| `scripts/generate_experiment_specs.py` | Main generator script |
| `scripts/templates/c3_spec.md.j2` | Template for C³ method specs |
| `scripts/templates/lie_detector_spec.md.j2` | Template for Lie Detector specs |
| `scripts/templates/trusted_monitor_spec.md.j2` | Template for Trusted Monitor specs |

---

## Data to Extract

From `specs/icml-baseline-expts/dataset-specific-sandbagging-prompts.md`:

| Dataset | Model | Prompt Count |
|---------|-------|--------------|
| GPQA | gpt-5-nano | 10 |
| GPQA | gpt-4.1-nano | 7 |
| MATH | gpt-5-nano | 10 |
| MATH | gpt-4.1-nano | 10 |
| USACO | gpt-5-nano | 8 |
| USACO | gpt-4.1-nano | 5 |

From `specs/icml-baseline-expts/methods/lie-detector.md`:

| Model | Training Data | Classifier File | Status |
|-------|---------------|-----------------|--------|
| gpt-5-nano | Benign | `logistic_binary_classifier_gpt5-nano_only_*.pkl` | ✅ Ready |
| gpt-5-nano | Sandbagging | `logistic_binary_classifier_gpt4.1-nano_gpt5-nano_all_sandbagging_*.pkl` | ✅ Ready |
| gpt-4.1-nano | Benign | `logistic_binary_classifier_gpt4.1-nano_only_*.pkl` | ✅ Ready |
| gpt-4.1-nano | Sandbagging | TBD | ⏳ Not trained yet |

**Note**: gpt-4.1-nano **sandbagging-trained** lie detector classifier is NOT ready. Generate specs using the **benign-trained** classifier for now.

---

## Execution Steps

1. Create `scripts/templates/` directory
2. Create method-specific Jinja2 templates (3 files)
3. Create `generate_experiment_specs.py` with:
   - Prompt data extracted from existing docs
   - Method-specific config generators
   - Template rendering logic
4. Run script: `python scripts/generate_experiment_specs.py`
5. Verify output: 18 new files in `specs/icml-baseline-expts/individual-expts/`
6. Spot-check 3 random specs
7. Commit all together
