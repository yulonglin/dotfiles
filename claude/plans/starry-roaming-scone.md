# Standardize Detection Score Pipeline

## Context

10+ detection methods, each producing CSVs with different column names, score ranges, and formats. The annotation ingestion pipeline (`prepare_study.py`) hardcodes 4 method names in 4+ places. Adding a new method requires editing 9 files. We need to centralize method definitions, add backward compatibility for legacy CSV formats, and make the pipeline warn loudly on data issues.

## Current State: 10+ Methods, All Different

| Method | Script | Score Column | Range | Label Column | Quirks |
|--------|--------|-------------|-------|--------------|--------|
| C3 | `run_consistency_classifier` | `entropy_score` | 0-2+ | `ground_truth_label` | Has `original_question`, `group_size` |
| Lie Detector | `run_lie_detector` | `sandbagging_score` | 0-1 | `ground_truth_label` | No status col |
| Trusted Monitor | `run_trusted_monitor` | `tm_score`/`raw_score` | 0-1/0-10 | `label` | Both norm + raw |
| Behavioral Probe | `run_behavioral_probe` | `probe_score` | 0-1+ | `sandbagging_status` | Minimal |
| Code Metrics | `run_code_metrics` | `code_metrics_score` | varies | `ground_truth_label` | Dynamic cols |
| Interrogation | `run_interrogation_classifier` | `sandbagging_score` | 0-1 | `ground_truth_label` | Shares col name with LD |
| Difficulty Corr | `run_difficulty_correlation` | `sandbagging_score` | varies | `ground_truth_label` | Shares col name |
| Indirect Probe | `run_indirect_dependency_probe` | `sandbagging_score` | 0/0.5/1 | `ground_truth_label` | Ternary |
| Ensemble | `run_ensemble_detector` | `ensemble_*` | 0-1 | `ground_truth_label` | 3 variants |

**Key insight**: Three methods share `sandbagging_score` as column name. Method identity must always come from the YAML `score_csvs` key, never from CSV column sniffing.

## Data Issues (Current DB: 156 GPQA samples)

| Issue | Status | Impact |
|-------|--------|--------|
| #1: Accuracy NULL (all) | Open | Tier 2 misleading |
| #2: TM scores 0 matches | Open | Empty Tier 3 TM |
| #3: Followups 0 rows | Open (data gap) | Empty Tier 4 |
| #4: Hardcoded method names | **Fix here** | Can't add methods |
| #5: Silent merge failures | **Fix here** | Undetected data loss |

## Plan (Two PRs)

### PR 1: Method Registry + Ingestion Fix (3 files, core change)

#### 1a. Create `src/annotation/method_registry.py`

One canonical name per method — used as dict key, `.name`, DB `method` column, and YAML `score_csvs` key.

```python
@dataclass(frozen=True)
class DetectionMethod:
    name: str                    # Canonical name = dict key = DB method = YAML key
    display_label: str           # "Response Consistency (C3)"
    csv_score_column: str        # What the legacy CSV calls its score: "entropy_score"
    score_range: tuple[float, float]  # Known range (used by frontend for scaling, NOT for DB normalization)
    higher_is_more_suspicious: bool = True  # Score direction
    csv_label_column: str = "ground_truth_label"
    csv_label_aliases: tuple[str, ...] = ()

METHODS: dict[str, DetectionMethod] = {
    "c3": DetectionMethod(
        name="c3", display_label="Response Consistency (C3)",
        csv_score_column="entropy_score", score_range=(0.0, 2.5),
    ),
    "lie_detector": DetectionMethod(
        name="lie_detector", display_label="Follow-up Analysis",
        csv_score_column="sandbagging_score", score_range=(0.0, 1.0),
    ),
    "tm": DetectionMethod(
        name="tm", display_label="Monitor Assessment",
        csv_score_column="score", score_range=(0.0, 1.0),  # Raw CSV column is "score", not "tm_score"
        csv_label_column="label",
    ),
    "probe": DetectionMethod(
        name="probe", display_label="Behavioral Probe",
        csv_score_column="probe_score", score_range=(0.0, 1.0),
        csv_label_aliases=("is_sandbagging", "sandbagging_status"),
    ),
    "code_metrics": DetectionMethod(
        name="code_metrics", display_label="Code Metrics",
        csv_score_column="code_metrics_score", score_range=(0.0, 1.0),
    ),
    # "code_semantic" omitted — no classifier script exists yet; add when implemented
    "interrogation": DetectionMethod(
        name="interrogation", display_label="Multi-Turn Interrogation",
        csv_score_column="sandbagging_score", score_range=(0.0, 1.0),
    ),
    "difficulty": DetectionMethod(
        name="difficulty", display_label="Difficulty Correlation",
        csv_score_column="sandbagging_score", score_range=(0.0, 1.0),
    ),
    "indirect_probe": DetectionMethod(
        name="indirect_probe", display_label="Indirect Dependency Probe",
        csv_score_column="sandbagging_score", score_range=(0.0, 1.0),
    ),
    "ensemble": DetectionMethod(
        name="ensemble", display_label="Ensemble",
        csv_score_column="ensemble_mean", score_range=(0.0, 1.0),
    ),
}

# Helper functions (preferred over module-level derived dicts — clearer intent at call site)
def get_method(name: str) -> DetectionMethod:
    if name not in METHODS:
        raise ValueError(f"Unknown method '{name}'. Known: {list(METHODS.keys())}")
    return METHODS[name]

def get_csv_column_renames(method_name: str) -> dict[str, str]:
    """Get CSV column → standard column renames for a method."""
    m = get_method(method_name)
    renames = {m.csv_score_column: f"{m.name}_score"}
    if m.csv_label_column != "ground_truth_label":
        renames[m.csv_label_column] = "ground_truth_label"
    for alias in m.csv_label_aliases:
        renames[alias] = "ground_truth_label"
    return renames

def get_all_score_columns() -> list[str]:
    """All known normalized score column names."""
    return [f"{m.name}_score" for m in METHODS.values()]

def get_display_labels() -> dict[str, str]:
    """Method name → display label mapping."""
    return {m.name: m.display_label for m in METHODS.values()}
```

**Design decisions** (per Codex critique):
- **One canonical name**: Dict key = `.name` = DB method = YAML key. No `normalized_column` indirection.
- **No score normalization in DB**: Raw scores stored; `score_range` served via API for frontend scaling.
- **No auto-detection**: Method identity from YAML `score_csvs` key, always. Multiple methods share `sandbagging_score`.
- **Helper functions > derived dicts**: Clearer intent, no stale state risk.
- **`higher_is_more_suspicious`**: Future-proofs for inverted methods.
- **Frozen dataclass**: Immutable after creation.
- **Don't change classifier scripts**: They keep their current output format. Registry handles translation.

#### 1b. Update `src/annotation/prepare_study.py`

Delete `SCORE_COLUMN_MAP` and `SCORE_METHOD_NAME_MAP`. Import from registry.

Replace `load_score_csv()`:
```python
from src.annotation.method_registry import get_method, get_csv_column_renames, METHODS

def load_score_csv(path, method):
    m = get_method(method)
    df = pd.read_csv(path)
    renames = get_csv_column_renames(method)
    # COMPAT: Guard against alias collision with existing ground_truth_label column
    if "ground_truth_label" in df.columns:
        renames = {k: v for k, v in renames.items() if v != "ground_truth_label"}
    df.rename(columns=renames, inplace=True)
    score_col = f"{m.name}_score"  # e.g., "c3_score", "tm_score"
    # ... normalize ground_truth_label, extract original_id
```

Replace `merge_scores()` score_col determination:
```python
def merge_scores(samples_df, score_df, method):
    m = get_method(method)
    score_col = f"{m.name}_score"  # Was: iterating SCORE_COLUMN_MAP[method].values()
    # ... rest of merge logic using score_col
```

Replace hardcoded loops at lines 487 and 574. Use study config keys (not full registry) to avoid checking 10 columns when only 2-4 are active:
```python
# Build active score columns from study config's score_csvs keys:
active_methods = list(config.get("score_csvs", {}).keys())
active_score_cols = [f"{m}_score" for m in active_methods]

# At line 574 — populate detection_scores with CANONICAL method names as keys:
for method_name in active_methods:
    col = f"{method_name}_score"
    if col in row and pd.notna(row[col]):
        detection_scores[method_name] = float(row[col])  # key is "c3", NOT "c3_score"
```

Replace `SCORE_METHOD_NAME_MAP` usage in `ingest_jsonl_to_sqlite()`:
```python
# Before: method = SCORE_METHOD_NAME_MAP.get(raw_method, raw_method)
# After: detection_scores already uses canonical names ("c3", "tm", etc.)
for method_name, score in sample.detection_scores.items():
    conn.execute("INSERT OR IGNORE INTO scores ...", (sample.sample_id, sample.model_pair, method_name, score))
```

Add merge warnings directly in `merge_scores()`:
```python
matched = merged[score_col].notna().sum()
total = len(score_df)
if matched == 0:
    logger.error("ZERO matches for %s (%d rows) — check sample_id format and model_pair", method, total)
if "model_pair" not in score_df.columns:
    logger.warning("%s CSV missing 'model_pair' — merge on sample_id only (may be ambiguous)", method)
if method not in METHODS:
    logger.warning("Method '%s' not in registry — using CSV columns as-is", method)
```

#### 1c. Update ALL study YAML key names

The YAML `score_csvs` keys must match registry canonical names. Update both configs:

`web/config/study-dev.yaml`:
```yaml
score_csvs:
  c3: out/c3_gpqa_cot_sandbag.csv
  tm: out/tm_gpqa_cot.csv          # Was: trusted_monitor
```

`web/config/study.yaml` (if it exists — check for `behavioral_probes` → `probe`, `trusted_monitor` → `tm`)

#### 1d. Verify

```bash
uv run python -c "from src.annotation.method_registry import METHODS; print(list(METHODS.keys()))"
uv run python -m src.annotation.prepare_study web/config/study-dev.yaml --output /tmp/claude/gpqa_dev.jsonl -v
uv run python -m src.annotation.prepare_study web/config/study-dev.yaml --db web/data/annotations.db --input /tmp/claude/gpqa_dev.jsonl --wipe -v
# Verify: 156 samples, 156 C3 scores, TM logs explicit warning
```

#### 1e. Minimal fix to `src/annotation/export.py` (PR 1 scope)

Replace the hardcoded `score_key_map` in `fetch_annotations_sqlite()` (line 206) with a registry-derived map so new methods aren't silently dropped:
```python
# COMPAT: Before — hardcoded reverse map
# score_key_map = {"c3": "c3_entropy_score", ...}
# After — dynamic from registry (stores as "{method}_score" key for to_rich_json compat)
for s in scores:
    sample_data[f"{s['method']}_score"] = s["score"]
```

And update `to_rich_json()` (lines 148-153) to collect scores dynamically:
```python
"detection_scores": {k: v for k, v in task.items() if k.endswith("_score") and k != "probe_score" or k.endswith("_score") and v is not None}
# Simplified: just collect all *_score keys
"detection_scores": {k: v for k, v in task.items() if k.endswith("_score") and v is not None}
```

### PR 2: Frontend + Docs (deferred, lower priority)

#### 2a. Fix `src/annotation/export.py` (remaining work)
```python
# fetch_annotations_sqlite — query all methods:
scores = conn.execute("SELECT method, score FROM scores WHERE sample_id = ? AND model_pair = ?", ...)
for s in scores:
    sample_data[f"{s['method']}_score"] = s["score"]

# to_rich_json — collect dynamically:
"detection_scores": {k: v for k, v in task.items() if k.endswith("_score") and v is not None}
```

#### 2b. Fix frontend

- `score-display.tsx`: Accept `Record<string, number>` directly; fallback label = `method.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())`
- `annotate/page.tsx`: Remove manual key mapping, pass `currentTask.scores` directly
- `types.ts`: Delete `DetectionScores` interface

#### 2c. Create `.claude/docs/annotation-score-pipeline.md`

Document:
1. Method registry and all 10+ methods
2. Data flow: eval → CSV → JSONL → SQLite → API → Frontend
3. Canonical CSV format for new methods
4. How to add a new method (one registry entry)
5. Known data issues and status
6. Test set vs dev set conventions
7. `run_multisample_bootstrap_cv.py`'s auto-detection is intentionally separate from registry

## Canonical CSV Format (Aspirational, for new methods)

```
sample_id,ground_truth_label,sandbagging_score,model_pair,sandbagging_status,file_name
```

Existing classifier scripts keep their current output. Registry's `csv_score_column` handles translation. Only new methods should use the canonical format.

## Files Summary

**PR 1 (core, unblocks everything):**

| File | Change |
|------|--------|
| `src/annotation/method_registry.py` | **NEW** — Central method definitions |
| `src/annotation/prepare_study.py` | Import from registry; replace hardcoded loops/maps; add merge warnings |
| `src/annotation/export.py` | Replace hardcoded `score_key_map` with registry import (minimal, prevents silent method drops) |
| `web/config/study-dev.yaml` | Update `score_csvs` keys to match registry names |
| `web/config/study.yaml` | Update keys if exists (`behavioral_probes` → `probe`, `trusted_monitor` → `tm`) |

**PR 2 (deferred):**

| File | Change |
|------|--------|
| `src/annotation/export.py` | Dynamic score handling from DB |
| `web/components/score-display.tsx` | Accept dynamic scores |
| `web/app/study/[id]/annotate/page.tsx` | Remove manual key mapping |
| `web/lib/types.ts` | Delete `DetectionScores` |
| `.claude/docs/annotation-score-pipeline.md` | **NEW** — Pipeline documentation |

### PR 1 addendum: Eval file backward compatibility with deprecation warnings

#### Problem

`extract_samples_from_eval_dirs()` and related functions have fragile implicit assumptions about eval file structure. Different Inspect AI versions and older experiment runs may have:
- Different system message locations (`model_generate_config.system_message` vs `config['system_prompt']` vs sample-level)
- Different model pair formats (old `sp<number>` vs new `sp_<name>_<hash>`)
- Missing fields (`sample.id`, `sample.epoch`, `sample.scores`, `sample.metadata`)
- Different score object structure (`score.value` may change)

#### Approach: Structured fallback chain with deprecation warnings

Add to `prepare_study.py` (or extract to `src/annotation/eval_compat.py` if large enough):

**1. System message detection** — already has 3 fallback locations. Add deprecation warnings:
```python
def _extract_system_message(log: EvalLog) -> tuple[str | None, str]:
    """Extract system message, returning (message, source_location).
    Emits deprecation warning for non-primary locations.
    """
    # Primary (current format)
    if hasattr(log.eval, 'model_generate_config') and log.eval.model_generate_config:
        msg = getattr(log.eval.model_generate_config, 'system_message', None)
        if msg:
            return msg, "model_generate_config.system_message"

    # Legacy location 1
    config = getattr(log.eval, 'config', {}) or {}
    if 'system_prompt' in config:
        logger.warning("DEPRECATED: system message found in legacy location 'eval.config.system_prompt' "
                       "in %s. Future versions should use model_generate_config.system_message", log.eval.run_id)
        return config['system_prompt'], "eval.config.system_prompt"

    # Legacy location 2: sample-level
    # ... fallback with warning
    return None, "not_found"
```

**2. Model pair extraction** — add explicit fallback for old system prompt naming:
```python
def extract_model_pair(log: EvalLog) -> str:
    """Extract model pair with backward-compatible system prompt parsing."""
    # ... current logic ...
    if system_prompt_name and system_prompt_name.startswith("sp") and system_prompt_name[2:].isdigit():
        logger.warning("DEPRECATED: Old system prompt format 'sp%s' in %s. "
                       "New format is 'sp_<name>_<hash>'", system_prompt_name[2:], log.eval.run_id)
    # ... continue with current logic ...
```

**3. Field existence validation** — replace scattered `hasattr()` with a structured validator:
```python
def _validate_eval_sample(sample, eval_file: str) -> list[str]:
    """Validate eval sample has required fields. Returns list of warnings."""
    warnings = []
    if not getattr(sample, 'id', None):
        warnings.append(f"Missing sample.id in {eval_file} — using index as fallback")
    if not hasattr(sample, 'messages') or not sample.messages:
        warnings.append(f"Empty messages in sample {getattr(sample, 'id', '?')} from {eval_file}")
    if hasattr(sample, 'scores') and sample.scores:
        for name, val in sample.scores.items():
            if not hasattr(val, 'value'):
                warnings.append(f"Score '{name}' missing .value attribute — possible Inspect AI version mismatch")
    return warnings
```

**4. Broad exception handling** — replace generic `except Exception` with specific catches:
```python
try:
    log = read_eval_log(str(eval_file))
except FileNotFoundError:
    logger.error("Eval file not found: %s", eval_file)
    continue
except (ValueError, KeyError) as e:
    logger.error("Failed to parse eval file %s (possible version mismatch): %s", eval_file, e)
    continue
except Exception:
    logger.exception("Unexpected error reading %s", eval_file)
    continue
```

**5. Eval format version detection** (lightweight, no full migration):
```python
def _detect_eval_format(log: EvalLog) -> str:
    """Detect eval file format version for compatibility logging."""
    if hasattr(log, 'version'):
        return f"inspect-ai-{log.version}"
    if hasattr(log.eval, 'model_generate_config'):
        return "current"
    if hasattr(log.eval, 'config') and 'system_prompt' in (log.eval.config or {}):
        return "legacy-v1"
    return "unknown"
```

#### Files for eval compat (in PR 1)

| File | Change |
|------|--------|
| `src/annotation/prepare_study.py` | Add deprecation warnings to fallback paths, structured validation, specific exception handling |

#### What this does NOT do

- Does NOT add Inspect AI version pinning (we're already pinned in `uv.lock`)
- Does NOT migrate old eval files — they work as-is with warnings
- Does NOT change eval file output format — that's the classifier scripts' job

## Codex Critique Fixes Applied

| ID | Issue | Fix |
|----|-------|-----|
| C1 | TM `csv_score_column` was `"tm_score"` but CSV has `"score"` | Changed to `csv_score_column="score"` |
| C2 | `merge_scores()` score_col determination underspecified | Added explicit `score_col = f"{m.name}_score"` |
| C3 | `study.yaml` uses `behavioral_probes` but registry has `probe` | Added all study YAMLs to PR 1 file list |
| C4 | `detection_scores` dict key format ambiguity (`c3_score` vs `c3`) | Keys are canonical names (`"c3"`, `"tm"`), `_score` suffix only in DataFrame columns |
| C5 | `export.py` silently drops new methods | Moved minimal export fix into PR 1 |
| I1 | `c3_entropy_score` → `c3_score` loses semantic info | Accepted — `display_label` carries semantics; internal column names are for machines |
| I3 | Label alias collision with existing `ground_truth_label` | Added guard in `load_score_csv()` |
| I6 | All 10 methods checked when only 2-4 active | Use study config's `score_csvs` keys for active methods |
| S4 | `code_semantic` has no classifier script | Removed from registry (add when implemented) |

## Implementation Note

**Codex will implement PR 1.** The implementation should:
1. Create `method_registry.py` as specified
2. Update `prepare_study.py` to import from registry, add all backward-compat warnings
3. Minimal fix to `export.py` (dynamic score_key_map + dynamic to_rich_json)
4. Update all study YAML keys
5. Tag all compat code with `# COMPAT:` comments
6. Run the pipeline end-to-end to verify no regressions

## Compatibility Layer Removal (Future)

The backward-compat code is designed for clean removal once cached LLM calls are merged and evals re-run with new formats:

1. **Registry `csv_score_column` + `csv_label_aliases`**: Once all CSVs use canonical column names, delete these fields and simplify `get_csv_column_renames()` to a no-op.
2. **`_extract_system_message()` fallback chain**: Once all eval files use `model_generate_config.system_message`, collapse to a single lookup.
3. **`_validate_eval_sample()` warnings**: Once older evals are regenerated, remove field-existence checks.
4. **Grep marker**: All deprecation code will be tagged with `# COMPAT:` comments so `grep -r "# COMPAT:"` finds every removable piece.

This is explicitly deferred — not part of PR 1 or PR 2.

## Out of Scope (Explicit)

- **Forward eval format standardization**: Canonical eval dir naming, standardized sample IDs, consolidated sandbagging detection — acknowledged as valuable but deferred to a separate effort after the human baseline study.
- **Classifier script changes**: Keep current output formats. Registry handles translation.
- **`run_multisample_bootstrap_cv.py`**: Its auto-detection chain is separate and intentionally stays separate.
- **Score normalization in DB**: Raw scores stored. `score_range` served via API for frontend scaling only.
- **Parallelization**: Score CSV loading is embarrassingly parallel (one file per method). Acknowledged but deferred — current preprocessing is cheap and fast enough.
- **Inspect AI version migration**: We're pinned at 0.3.173. Eval files from this version work. Older files get deprecation warnings but still load.
