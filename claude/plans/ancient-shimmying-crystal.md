# Dark-Box: Revised Implementation Plan

**Critique source**: Gemini CLI analysis of plan vs spec + judging criteria

## Design Decisions

1. **Prompt source**: Benchmark-only (MMLU, GSM8K, HumanEval, etc.) for reproducibility
2. **Scope**: Full scope (capability + behavioral + latency), validate on Day 2 kill-switch
3. **Latency strategy**: Implement full, drop if noise dominates (Day 2 validation)

---

## Critical Gaps Identified

| Gap | Current | Required | Blocks |
|-----|---------|----------|--------|
| **Prompts** | 10 | 50 (categorical balance) | All meaningful experiments |
| **Ground truth** | 5 models | 25-30 models | Frontier fitting |
| **Kill-switch check** | Not planned | Day 2 priority | Feature set decisions |
| **Feature ablation** | Not implemented | Required | Value-add demonstration |
| **Export** | No endpoint | JSON/CSV required | Reproducibility |
| **Fingerprint** | SHA256 hash | Cosine similarity | H4 validation |
| **Report template** | Not started | Official template | Submission |
| **Demo video** | Not planned | 3-5 min | Recommended artifact |

---

## Revised Day-by-Day Plan

### Day 1: Foundation (TODAY)

**Must complete**:
1. ✅ Housekeeping: Remove `web/.git`, create `web/.env.local`
2. ⏳ **Expand prompts to 50** (categorical balance)
   - factual: 8-10, reasoning: 8-10, math: 6-8, coding: 6-8, multilingual: 6-8, OOD: 6-8
3. ⏳ **Expand ground truth to 25+** (full Tier-1 + Tier-2 from spec)
4. ⏳ Verify end-to-end: API + Web working together
5. ⏳ Run smoke test: 5 models × 10 prompts × 2 repeats

**Files to modify**:
- `api/src/darkbox/prompts.py` (expand from 10 to 50)
- `api/src/darkbox/ground_truth.py` (expand from 5 to 25+)

### Day 2: Kill-Switch & Validation

**Must complete**:
1. **Kill-switch check**: Run 5 models × 10 prompts × 3 repeats
   - Compute TPS variance within-model vs between-model
   - If ratio < 2.0, drop timing features (fallback to capability-only)
2. **Fingerprint upgrade**: Replace SHA256 with cosine similarity
   - Required for H4: same model similarity >0.95, model swap similarity <0.80
3. Freeze feature set based on signal quality

**Files to modify**:
- `api/src/darkbox/analysis.py` (add cosine similarity fingerprint)

### Day 3: Scoring Engine

**Must complete**:
1. **Feature ablation**: capability-only vs capability+behavioral vs +latency/TPS
2. Frontier fit refinement (scaling law regression)
3. Anomaly z-score calibration
4. **Add export endpoint**: `/v1/runs/{id}/export` → JSON/CSV

**Files to modify**:
- `api/src/darkbox/analysis.py` (add ablation)
- `api/src/darkbox/routes.py` (add export endpoint)

### Day 4: Web UI & CLI Polish

**Must complete**:
1. Export buttons in UI (JSON, CSV download)
2. Ablation visualization (bar chart)
3. Fingerprint stability display (cosine sim value)
4. CLI export command

**Files to modify**:
- `web/src/app/page.tsx`
- `api/src/darkbox/cli.py`

### Day 5: Blind Runs & Report

**Must complete**:
1. Run Tier-4 models (unknown compute): Mistral Large 2512, Qwen Max, DeepSeek R1-0528
2. Calibrate anomaly thresholds (avoid "flag everything")
3. **Start report** using official hackathon template
4. Write Limitations & Dual-Use section

### Day 6: Demo & Submission

**Must complete**:
1. Record 3-5 minute demo video
   - Script: paste model ID → run probes → view frontier → see anomaly flag
2. Finalize report
3. Clean up README with run instructions
4. Submit

### Day 7: Buffer

- Bug fixes, extra probes if time
- Address reviewer feedback if early submission

---

## Immediate Actions (Right Now)

### 1. Housekeeping (User runs manually)
```bash
rm -rf web/.git web/README.md
```

### 2. Expand Prompts (I will do this)
Expand `api/src/darkbox/prompts.py` from 10 to 50 prompts sourced from **existing benchmarks**:

| Category | Source | Count |
|----------|--------|-------|
| Factual | MMLU (various subjects) | 10 |
| Reasoning | ARC-Challenge, LogiQA | 10 |
| Math | GSM8K | 8 |
| Coding | HumanEval | 8 |
| Multilingual | MGSM, XStoryCloze | 8 |
| OOD | Custom + MMLU rare subjects | 6 |

**Rationale**: Benchmark prompts enable comparison with published scores; reproducible sources.

### 3. Expand Ground Truth (I will do this)
Expand `api/src/darkbox/ground_truth.py` to include all Tier-1 + Tier-2 models from spec:

**Tier-1 Dense** (14 models):
- Gemma 3 4B, Gemma 2 27B, Gemma 3 27B
- LLaMA 3.2 1B, 3B, LLaMA 3 8B, 70B, LLaMA 3.1 405B, LLaMA 3.3 70B
- Mistral Small 3 24B, Mistral Large 2
- Qwen 2.5 7B, 72B, Qwen 3 8B, 14B, 32B

**Tier-2 MoE** (5 models):
- Mixtral 8x7B, Mixtral 8x22B
- Qwen 3 30B-A3B, Qwen 3 235B-A22B
- DeepSeek V3

### 4. Verify End-to-End
```bash
# Terminal 1
cd api && uv sync && uv run darkbox serve --reload

# Terminal 2
cd web && bun install && bun dev
```
Open http://localhost:3000, run audit against `meta-llama/llama-3-8b`

---

## Success Criteria

**Minimum viable submission**:
- [ ] 50 prompts with categorical balance
- [ ] 25+ ground truth models with Epoch AI FLOPs
- [ ] Working frontier plot with target model highlighted
- [ ] Anomaly z-score displayed
- [ ] JSON/CSV export
- [ ] Report using official template
- [ ] README with run instructions

**Recommended extras**:
- [ ] Demo video (3-5 min)
- [ ] Feature ablation visualization
- [ ] Fingerprint cosine similarity (H4 validation)
- [ ] Kill-switch documented (which features kept/dropped)
