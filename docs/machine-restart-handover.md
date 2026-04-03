# Machine Restart Handover

**Date:** 2026-04-03  
**Reason:** Scale up CPU + memory resources  
**Machine:** hetzner-8 (ubuntu-32gb-nbg1-1)

---

## Git Status — DONE

All repos committed and pushed:
- **sandbagging-detection/dev** (`yulong/dev`) — pushed `54d33ee` (hill-climb stealth + surveillance MCQ variant)
- **nudge** (`main`) — pushed `beb1d0d`
- **dotfiles** (`main`) — pushed `95ca1ac` (settings.json + channels config)
- **swordsmith** — no remote, only has `docs/` and `plans/` locally
- **writing/llm-council** — clean, nothing to do

---

## Remaining Tmux Sessions (14 total, 42 killed)

### Claude Code Sessions (12 running)

| Tmux Session | Repo / CWD | Context | CC Version | Rebuttal-Related? |
|-------------|------------|---------|------------|-------------------|
| **protocolqa** | sandbagging-detection/dev | active tasks | — | **YES — TOP PRIORITY** |
| discovered-incentives4 | sandbagging-detection/dev | 58% | 2.1.87 | Yes — new sandbagging prompts |
| discovered-incentives5 | sandbagging-detection/dev | 26% | 2.1.87 | Yes — new sandbagging prompts |
| discovered-incentives-tm | sandbagging-detection/dev | 18% | 2.1.87 | Yes — TM detection variant |
| discovered-incentives | sandbagging-detection/dev | 34% | 2.1.86 | Yes — earlier run |
| icml-confound4 | sandbagging-detection/dev | 37% | 2.1.87 | Yes — confound analysis |
| icml-confound2 | sandbagging-detection/dev | 38% | 2.1.84 | Yes — earlier confound |
| honest-wrong-5_4 | sandbagging-detection/dev | 15% | 2.1.87 | Yes — GPT-5.4 honest-wrong |
| 3-model-fpr | sandbagging-detection/dev | 23% | 2.1.87 | Yes — FPR comparison |
| autodetect | sandbagging-detection/dev | 8% | — | Marginal |
| debug-env-dotfiles | dotfiles | 8% | 2.1.87 | No |
| swordsmith | swordsmith | 8% | 2.1.90 | No |

### Non-Claude Sessions (2 remaining)

| Tmux Session | Repo / CWD | Notes |
|-------------|------------|-------|
| experiments | sandbagging-detection/dev | 12 windows, shell sessions, Mar 12 |
| nudge | nudge | Shell, nudge bot (Feb 20) |

### Safe to Kill (all work committed)

Everything except **protocolqa** is safe to kill — all rebuttal experiment work and paper edits have been committed. The Claude Code sessions contain conversation context but no uncommitted code.

If you want to preserve conversation context for any session, you can `tmux capture-pane -t <session> -p -S -` to dump the full scrollback before killing.

---

## PRIORITY 1: protocolqa (Resume Immediately After Restart)

**Plan:** `plans/2026-04-02-raise-scores.md`  
**Spec:** `specs/protocolqa-integration.md`

### Task Status (9 tasks)

| # | Task | Status |
|---|------|--------|
| 1 | [Plan] Write implementation plan | **Done** |
| 2 | [WS-A] ProtocolQA: sweep configs + accuracy baselines + C3 detection | **In Progress** |
| 3 | [WS-B] USACO: debug errors + multi-model experiments (Gemini/Opus) | Open |
| 4 | [WS-C] Stealthy sandbagging organisms: hill-climb loop (Phase 1 Red Team) | **In Progress** |
| 5 | [WS-D] Dispatch long-running Claude Code sessions for parallel work | Open |
| 6 | [Ablation] Implement best-of-5 with embedding diversity ranking | **Done** |
| 7 | [Ablation] Generate 4 paraphrase sets for GPQA dev | **In Progress** |
| 8 | [Ablation] Run C3 trajectories + bootstrap for all 4 conditions | Open |
| 9 | [Refactor] Standardize score CSV schema via Pydantic | **Done** |

### What Was Happening When Stopped

- Hill-climb stealth loop (`scripts/hill_climb_stealth.py`) was maxing out CPU/mem
- Session was cleaning stale log dirs for a fresh run
- Last user question: "what is causing it to max out cpu and mem?"

### Key Numbers So Far

- **ICML scores: 5, 4, 4, 2** — reviewer rXMz (score 2) is the target
- ProtocolQA MCQ C3 detection: 17% recall@5%FPR, AUROC 0.654
- TM open-ended headline: 98.7% recall (k=5)
- Discovered incentives: 10 new prompts, 3-4x more effective than Meinke control on MATH

---

## Other Rebuttal Context (Past 1-2 Weeks)

### Key Rebuttal Commits (Mar 26 — Apr 3)

| Date | What | Commit Prefix |
|------|------|---------------|
| Apr 3 | Hill-climb stealth script + surveillance MCQ variant | `54d33ee` |
| Apr 3 | Paraphrase ablation plan | `a686288` |
| Apr 2 | ProtocolQA results (MCQ C3, TM open-ended) | `d53cd86`, `1256c70` |
| Mar 30-31 | Paper writing: self-calibration, ensemble, honest-wrong, FIXMEs | `paper*` sessions |
| Mar 30 | GPT-5.4 honest-wrong + correctness-matched consolidated | `5965703`, `a0c2970` |
| Mar 29 | Discovered incentive experiments, 3-model FPR | `3153e9f` |
| Mar 28 | Ensemble rerun plan | plan: `2026-03-28-ensemble-rerun.md` |
| Mar 27 | New discovered-incentive prompts (10 Meinke-style) | NOTES.md entry |

### What Reviewers Want (reminder)

| Reviewer | Score | Key Concern | What Helps |
|----------|-------|-------------|------------|
| **xsUX** | 5 | None | — |
| **rXMz** | 2 | STEM proxies, prompted sandbaggers unrealistic, style confound | **ProtocolQA, sophisticated organisms** |
| **RPTJ** | 4 | Only small/OAI models | Gemini 3.1 Pro, Opus 4.6 |
| **Uod9** | 4 | Resolved | ProtocolQA strengthens further |

---

## Worktrees (Clean After Restart)

### sandbagging-detection/dev (7 worktrees)
- `agent-a203a7f5`, `agent-a68224df`, `agent-ad859166` — stale agent worktrees
- `autodetect`, `benign-prompts`, `icml-confound` — old feature branches
- `sprint` (`yulong/red-blue-sprint`) — separate sprint branch

### nudge (6 worktrees)
- `auto-heal`, `fix-status-message`, `google-workspace`, `nudge-how`, `nudge-problematic`, `nudge-v2`

### dotfiles (2 worktrees)
- `killed-sessions`, `move-plugins`

---

## Key Files to Re-Read on Resume

| File | Why |
|------|-----|
| `plans/2026-04-02-raise-scores.md` | Master plan for score-raising experiments |
| `plans/2026-04-03-paraphrase-ablation.md` | Paraphrase quality ablation study |
| `specs/protocolqa-integration.md` | ProtocolQA dataset integration spec |
| `NOTES.md` (top entry) | Latest experiment results |
| `plans/2026-03-29-rebuttal-handover.md` | Earlier rebuttal context |
| `plans/2026-03-30-rebuttal-content-fixes.md` | Paper content fix plan |
