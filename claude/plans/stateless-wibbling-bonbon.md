# Plan: Fix Agents in the Wild Paper — Three Issues

## Issues to Fix

1. **Figure 1 placement** — Pipeline diagram (`c3_updated2.png`) forces itself to top of page 1 via `figure*[t]`. Should appear after intro.
2. **Figure 4 (WMDP)** — `pw_wmdp_detection.png` shows only C³ (52.9%). Should show multi-method comparison.
3. **Missing appendix** — Main paper has ~950 lines of appendix with critical content completely absent from workshop paper.

## Page Budget

Current main body: ~9 pages. Limit: **12 pages** (10 base + 2 extra). Appendix unlimited (doesn't count).

## File to Modify

`workshops/iclr-2026/agents-in-the-wild/agents-in-the-wild.tex` (270 lines → ~650-700 lines)

---

## Fix 1: Figure 1 Placement

**Current** (line 69): `\begin{figure*}[t]` immediately after `\end{abstract}` — forces pipeline to top of page 1.

**Change**: Move the `figure*` block from after abstract (line 69-74) to after the contributions list (after line 96), and change placement to `[tbp]`. This lets LaTeX place it naturally (typically top of page 2 or 3) rather than competing with the abstract for page 1 space.

---

## Fix 2: WMDP Multi-Method Figure

**Problem**: `pw_wmdp_detection.png` (57KB) shows only a single C³ bar.

**Solution**: Replace with `pw_gsm8k_detection.png` (91KB) which shows all 5 methods (C³, TM-Haiku, TM-3B, LD, BP) for password-locked DeepSeek-Math 7B on GSM8K. Update the caption and surrounding text to discuss both GSM8K and WMDP results:
- GSM8K (figure): C³ 36.0%, TM-Haiku 34.7%, TM-3B 7.9%, LD 13.5%, BP 3.5%
- WMDP (text): C³ 52.9%, TM-Haiku 41.1% (confounded by correctness)

Update section title from "Password-Locked Sandbaggers on Dangerous Capability Benchmarks" to "Password-Locked Fine-Tuned Sandbaggers" and rewrite to cover both benchmarks with the multi-method comparison being the centerpiece.

---

## Fix 3: Expand Main Body + Add Appendix

With 2 extra pages (12 total), we promote the strongest content into the main body and move supporting detail to appendix.

### Promote to Main Body (~2 pages)

| Section | Source (main.tex) | Figures | Est. Pages | Why Main Body |
|---------|-------------------|---------|------------|---------------|
| TM Correctness Confound | lines 648-666 | None | 0.7 | Critical for interpreting TM's WMDP results — r=-0.66 correctness confound means TM is ~a competence classifier, not a sandbagging detector |
| Stealth Prompt Tradeoff | lines 1071-1083 | `stealth_prompts_tradeoff.png` | 0.5 | Compelling: empty upper-left quadrant shows no strategy achieves both evasion AND effective sandbagging |
| Consistency Instructions Fail | lines 700-741 (condensed) | None | 0.5 | Strengthens core claim: 4 explicit evasion strategies all fail, C³ still 100% recall |

Add TM Confound as new §4.x after password-locked section. Add Stealth Tradeoff and Consistency Instructions as expansion of §4.7 (adversarial strategies).

### Appendix Sections (free pages, no limit)

| Priority | Section | Source (main.tex) | Figures/Tables | Est. Pages |
|----------|---------|-------------------|----------------|------------|
| **Essential** | TM Failure Modes | lines 1006-1053 | `meinke_tm_histogram.png`, Table (TM transcript) | 1.5 |
| **Essential** | Fine-Tuned Sandbaggers Detail | lines 684-698 | None | 0.3 |
| **Essential** | Behavioral Probes Defeat | lines 982-1004 | `behavioral_probes_defeat.png` | 0.7 |
| **Valuable** | Consistency Instruction Suffixes (full prompts) | lines 700-741 | None | 0.8 |
| **Valuable** | Adversarial Strategies | lines 552-567 | `adversarial_poc.png`, `gpqa_adversarial.png` | 0.7 |
| **Valuable** | DCE Task Counts | lines 569-598 | Table | 0.5 |
| **Valuable** | Multi-Sample Aggregation | lines 1085-1095 | `usaco_lie_detector_multi_sample_example.png` | 0.5 |
| **Valuable** | C³ Failure Mode | lines 1458-1492 | None (transcript) | 0.5 |
| **Reference** | Lie Detector Failure Modes | lines 1055-1069 | `lie_detector_confound.png` | 0.8 |
| **Reference** | Paraphrasing Strategies (summary) | lines 743-877 | None (condense to table) | 0.5 |
| **Reference** | Sandbagging Prompt Examples | lines 1097-1457 | None (select 5-8 representative) | 1.0 |

**Total appendix estimate**: ~7-8 pages (all free)

### Appendix Structure

```latex
\appendix
\section{Appendix}

\subsection{Trusted Monitoring Correctness Confound}  % Essential - TM confounded by correctness
\subsection{Trusted Monitor Failure Modes}              % Essential - self-substitution, format penalization
\subsection{Fine-Tuned Sandbagger Details}              % Essential - more password-locked numbers
\subsection{Behavioral Probes Are Trivially Defeated}   % Essential - 74% → 3.4% with one instruction
\subsection{Consistency Instructions Fail to Close the Gap}  % Valuable - 4 evasion strategies, all fail
\subsection{Adversarial Strategies Defeat C³}           % Valuable - deterministic recipes
\subsection{DCE Task Counts}                            % Valuable - justifies k=10
\subsection{Multi-Sample Aggregation}                   % Valuable - why k>1 matters
\subsection{Stealth Prompt Analysis}                    % Valuable - sandbagging-detectability tradeoff
\subsection{C³ Failure Mode}                            % Valuable - instruction-following confound
\subsection{Lie Detector Failure Mode Analysis}         % Reference - 3 failure modes
\subsection{Paraphrasing Strategy Summary}              % Reference - condensed table of 28 strategies
\subsection{Sandbagging Prompt Examples}                % Reference - representative prompts
```

---

## Implementation Steps

### Step 1: Fix Figure 1 placement
- Move `figure*` block from lines 69-74 to after line 96 (after contributions list)
- Change `[t]` to `[tbp]`

### Step 2: Fix WMDP figure
- Replace `pw_wmdp_detection.png` with `pw_gsm8k_detection.png` in the figure
- Rewrite caption to describe multi-method GSM8K comparison
- Rewrite §4.4 text to cover both WMDP and GSM8K password-locked results with multi-method comparison

### Step 3: Expand main body (+2 pages)
- Add TM Correctness Confound as new subsection §4.x (after password-locked)
- Add Stealth Prompt Tradeoff figure + discussion (expand §4.7 or new §4.x)
- Add condensed Consistency Instructions analysis (expand existing §4.7 or new subsection)

### Step 4: Add appendix
- Add `\appendix` and `\section{Appendix}` before `\end{document}` (after bibliography)
- Add 11 subsections, adapting text from main.tex
- Include figure references via `../../../figures/` paths
- Ensure all `\label{}` and `\ref{}` are consistent

### Step 5: Compile and verify
- `cd workshops/iclr-2026/agents-in-the-wild && latexmk -pdf agents-in-the-wild.tex`
- Verify main body ≤ 12 pages (excl. references + appendix)
- Verify all figures render
- Verify all references resolve

---

## Execution Strategy

Use **paper-writer agent** to execute all three fixes in a single pass, since they all modify the same file (`agents-in-the-wild.tex`). The agent gets:
- The current `agents-in-the-wild.tex` content (270 lines)
- Relevant appendix sections from `main.tex` (lines 547-1494)
- Figure file names and paths
- This plan as guidance

One agent, sequential edits, compile at the end.

---

## Verification Checklist

- [ ] Figure 1 no longer at top of page 1
- [ ] Password-locked figure shows multiple detection methods
- [ ] WMDP numbers mentioned in text (52.9% C³, 41.1% TM)
- [ ] Appendix contains ≥10 subsections from main paper
- [ ] Main body still ≤ 12 pages
- [ ] Paper compiles cleanly with `latexmk -pdf`
- [ ] All cross-references resolve (`\ref{}` commands)
- [ ] All figures render (check relative paths)
