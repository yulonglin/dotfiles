# Plan: Fix Dashboard Tabs

## Problem

Only the Leaderboard (home) tab works. Other tabs are broken at runtime:
- Model Deep Dive
- Requirement Deep Dive
- Methodology & Validation
- Human Validation

## Completed Previously

- ✅ Expanded requirements: 80 total (37 EU CoP + 28 STREAM + 15 Lab Safety)
- ✅ Created validation page (`app/page_validation.py`)
- ✅ Pipeline runs with new models (Gemini 2.5 Flash Lite + Claude Sonnet 4.5)
- ✅ Scores generated successfully

## Issues Found

### 1. CRITICAL: Deprecated `applymap()` (pandas 2.2+ removed it)
- `app/page_model_detail.py:79` - `df.style.applymap()` → use `map()`
- `app/page_leaderboard.py:41` - `df.style.applymap()` → use `map()`

### 2. HIGH: `evidence` field is polymorphic (string OR list)
- `app/page_model_detail.py:106-109` - Code assumes list, but sometimes it's a string
- Causes character-by-character iteration when string

### 3. MEDIUM: Float display without rounding
- `app/page_model_detail.py:37-40` - Percentages displayed with full precision
- Need `:.1f` or `:.0f` formatting

### 4. MEDIUM: Colors are hardcoded discrete, not gradient
- `app/utils.py` - `COLORS` dict has 4 fixed colors for absent/mentioned/partial/thorough
- `score_color()` uses discrete thresholds (25/50/75)
- Should use smooth gradient based on actual percentage value

---

## Fix Plan

### File: `app/page_leaderboard.py`
- Line 41: `applymap` → `map`

### File: `app/page_model_detail.py`
- Line 79: `applymap` → `map`
- Lines 37-40: Add `.1f` formatting to percentages
- Lines 106-109: Handle evidence as string or list

### File: `app/utils.py`
- Replace discrete `score_color()` with gradient function
- Interpolate from red (0%) → yellow (50%) → green (100%)

---

## Verification

```bash
uv run streamlit run run_app.py
# Test all 5 tabs:
# 1. Leaderboard - should show styled table
# 2. Model Deep Dive - should show model details without crashing
# 3. Requirement Deep Dive - should work
# 4. Methodology & Validation - should work
# 5. Human Validation - should work
```

---

## Task 1: Expand EU Code of Practice (12 → ~33 measures)

### Source Structure (from code-of-practice.ai)
```
Transparency Chapter (3 measures):
  - 1.1: Model documentation
  - 1.2: Information provision to AI Office
  - 1.3: Quality/integrity of information

Copyright Chapter (5 measures):
  - 1.1: Copyright policy
  - 1.2: Lawful content crawling
  - 1.3: Rights reservations compliance
  - 1.4: Infringing output mitigation
  - 1.5: Complaint mechanism

Safety & Security Chapter (~25 measures):
  - 1.1-1.4: Framework creation/implementation
  - 2.1-2.2: Risk identification & scenarios
  - 3.1-3.5: Risk assessment methods
  - 4.1-4.2: Risk acceptance criteria
  - 5.1: Safety mitigations
  - 6.1-6.2: Security mitigations
  - 7.1-7.7: Documentation & reporting
  - 8.1-8.3: Governance
  - 9.1-9.2: Incident handling
  - 10.1-10.2: Transparency
```

### Parallel Agent Strategy
Use **Gemini CLI** to draft EU CoP requirements in parallel:
- Agent 1: Transparency + Copyright chapters (8 measures)
- Agent 2: Safety & Security measures 1-5 (~12 measures)
- Agent 3: Safety & Security measures 6-10 (~13 measures)

---

## Task 2: Expand Lab Safety Commitments (5 → ~15 items)

### Source Structure (from Anthropic RSP, OpenAI Prep Framework)
```
Capability Thresholds:
  - CBRN threshold definitions
  - Cyber threshold definitions
  - Autonomy checkpoint definitions

Required Safeguards:
  - Deployment standards per level
  - Security standards per level

Governance:
  - RSO role & authority
  - Board oversight
  - Pause commitment enforcement

Monitoring:
  - Evaluation cadence
  - Incident reporting
  - External review process
```

### Parallel Agent Strategy
Use **Codex CLI** for Lab Safety (simpler, well-scoped):
- Single agent to draft 15 requirements based on RSP structure

---

## Task 3: Human Validation Workflow

### Option A: Dashboard-based validation (RECOMMENDED)
Add a validation page to Streamlit app:
- Shows random (model, requirement) pair
- Displays model card excerpt + rubric
- User selects score 0-3
- Saves to `validation/human_scores.csv`

### Option B: Markdown interview
Generate `validation/validation_interview.md`:
- Pre-populated with 20 items to validate
- Shows LLM score, evidence, rubric
- User fills in their score + reasoning
- Script parses results

### Option C: CLI interview
Interactive script `scripts/run_validation.py`:
- Presents items one by one
- User inputs score
- Shows agreement immediately
- Saves results

---

## Files to Create/Modify

| File | Action | Agent |
|------|--------|-------|
| `data/rubrics/requirements.json` | EXPAND | Gemini (CoP) + Codex (Lab Safety) |
| `app/page_validation.py` | CREATE | Claude |
| `app/app.py` | MODIFY | Claude (add validation page) |
| `scripts/run_validation.py` | CREATE | Claude (backup CLI option) |

---

## Execution Order

### Phase 1: Expand Requirements (Parallel Agents)

```bash
# Agent 1 (Gemini): EU CoP Transparency + Copyright
gemini -p "Create JSON requirements for EU AI Act Code of Practice
Transparency measures (1.1-1.3) and Copyright measures (1.1-1.5).
Use format: {id, framework, category, short_name, description, scoring_guidance{absent,mentioned,partial,thorough}, gold_examples}"

# Agent 2 (Gemini): EU CoP Safety measures 1-5
gemini -p "Create JSON requirements for EU AI Act Code of Practice
Safety & Security measures 1.1-5.1. Include framework creation, risk identification, risk assessment."

# Agent 3 (Gemini): EU CoP Safety measures 6-10
gemini -p "Create JSON requirements for EU AI Act Code of Practice
Safety & Security measures 6.1-10.2. Include security, documentation, governance, incidents."

# Agent 4 (Codex): Lab Safety Commitments
codex -p "Create JSON requirements for Lab Safety Commitments based on Anthropic RSP.
Include: CBRN thresholds, Cyber thresholds, Autonomy checkpoints, Deployment standards,
Security standards, RSO governance, Board oversight, Pause commitment, Evaluation cadence."
```

### Phase 2: Merge & Validate

1. Combine agent outputs into single `requirements.json`
2. Validate JSON structure
3. Ensure unique IDs:
   - EU CoP: `CoP-T-1.1` (Transparency), `CoP-C-1.1` (Copyright), `CoP-S-1.1` (Safety)
   - Lab Safety: `LS-CBRN-1`, `LS-Cyber-1`, `LS-Gov-1`, etc.

### Phase 3: Build Validation Dashboard

Create `app/page_validation.py`:
- Select random unvalidated item
- Show model card excerpt (from stored evidence)
- Show rubric for that requirement
- User selects 0-3
- Save to CSV with timestamp

### Phase 4: Re-run Pipeline

```bash
rm -rf .cache/llm/*
uv run python scripts/run_pipeline.py
# Cost: ~$30-50 for ~75 requirements × 5 models = 375 API calls
```

### Phase 5: Human Validation

User validates 20-30 items through dashboard:
- Target: 80% agreement with LLM scores
- Document disagreements for methodology section

---

## Verification

1. **Requirements count:**
   ```bash
   uv run python -c "
   import json
   with open('data/rubrics/requirements.json') as f:
       reqs = json.load(f)
   print(f'Total: {len(reqs)}')
   from collections import Counter
   print(Counter(r['framework'] for r in reqs))
   "
   # Expected: ~75 total (33 CoP + 28 STREAM + 15 Lab Safety)
   ```

2. **Pipeline runs:**
   ```bash
   uv run python scripts/run_pipeline.py
   # Should complete with ~375 scores
   ```

3. **Validation dashboard:**
   ```bash
   uv run streamlit run run_app.py
   # Navigate to "Human Validation" page
   # Complete 5 validations, check CSV saves correctly
   ```

4. **Agreement calculation:**
   ```bash
   uv run python -c "
   import pandas as pd
   human = pd.read_csv('validation/human_scores.csv')
   # Compare to LLM scores, calculate agreement
   "
   ```

---

## Cost & Time Estimate

| Task | Time | Cost |
|------|------|------|
| Gemini agents (3 parallel) | 15 min | Free |
| Codex agent | 10 min | Free |
| Merge & validate JSON | 15 min | - |
| Build validation page | 30 min | - |
| Re-run pipeline | 30 min | ~$30-50 |
| Human validation (20 items) | 30 min | - |
| **Total** | **~2 hours** | **~$30-50** |

---

## User Decisions

- ✅ **Validation approach:** Dashboard (Streamlit page)
- ✅ **Sample size:** 30 items for robust statistical claim
- ✅ **Order:** Review expanded requirements BEFORE running pipeline
