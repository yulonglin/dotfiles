# Plan: Add Pacchiardi figure + halve figure sizes

## Changes to `icbinb.tex`

### 1. Add Pacchiardi et al. lie detector diagram
- Save the user-provided image as `figures/pacchiardi_lie_detector.png`
- Add a new Figure after the "Lie detectors (primary)" paragraph in §2 (~line 74)
- Caption: "Lie detector pipeline from Pacchiardi et al. (2024). Elicitation questions are asked alongside the target question; responses are embedded and classified via logistic regression. Figure reproduced from \citet{how-to-catch-an-ai-liar}."
- Width: `0.4\linewidth` (halved from typical)

### 2. Halve existing figure sizes
- Figure 1 (lie_detector_confound.png): `0.75` → `0.38`
- Figure 2 (same_model_c3_vs_ld.png): `0.55` → `0.28`

### 3. Recompile
- `bash src/compile.sh` to verify it fits in 4 pages

## Files to modify
- `icbinb.tex` (3 edits)
- `figures/pacchiardi_lie_detector.png` (new file - save from user image)
