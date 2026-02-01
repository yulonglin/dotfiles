# Enhanced Brainstorming Pipeline — Revised Plan

## What the Critiques Agreed On

Three independent reviews (Gemini, research-skeptic, architecture-plan) converged:

1. **The bottleneck is seed quality and human taste, not downstream processing.** Every breakthrough example (Emergent Misalignment, Model Organisms, Weak-to-Strong) came from domain expertise + specific observations, not brainstorming volume.
2. **Pairwise tournament should be dropped.** LLMs prefer well-articulated conventional ideas over weird surprising ones. Elo optimizes for consensus, not insight.
3. **Temperature variation is near-zero impact** when you already have 8 models × 8 techniques. Prompt diversity >> temperature diversity.
4. **Iterative revision may sand off the rough edges** that make ideas genuinely surprising. Defer until validated.
5. **Synthesis should be multi-step** (theme extraction → tension identification → experiment design), not a single mega-call that smooths over disagreements.
6. **New techniques matter more than new process**: BACKWARD_CHAIN and FAILURE_ANALYSIS attack the actual bottleneck.

## What to Implement (Revised)

### Priority 1: Seed Quality & New Techniques (high impact)

| # | Feature | Rationale |
|---|---------|-----------|
| 1 | **Seed quality gate** | Single cheap LLM call before 64+ divergence calls. Validates: specific question? Defined terms? Falsifiable claim? Saves money + improves everything downstream. |
| 2 | **Human seeds in SEED.md** | Template section for 3-5 rough ideas before LLMs. Research shows LLMs expand human ideas better than generating from scratch. |
| 3 | **BACKWARD_CHAIN technique** | "What result would be genuinely surprising? Work backward to the experiment." Qualitatively different from all 8 existing forward-from-seed techniques. |
| 4 | **FAILURE_ANALYSIS technique** | "What should work but doesn't? What's the alternative explanation nobody tested?" This is how Emergent Misalignment was discovered. |
| 5 | **INTERROGATION technique** | LLM asks 5 clarifying questions before generating. Grounds output in user's specific context. |
| 6 | **Novelty constraints** | Append previous idea titles to divergence prompts. Prevents repetition across sessions. |

### Priority 2: Synthesis & Red-team Redesign (medium impact)

| # | Feature | Rationale |
|---|---------|-----------|
| 7 | **Multi-step synthesis** | Replace single Opus call with 3 sequential: (a) theme extraction (cheap model), (b) tension identification — where do models disagree? (Opus), (c) experiment design for top 3 hypotheses (Opus). Preserves disagreements instead of smoothing them. |
| 8 | **Elevation red-team pass** | Add alongside existing destruction pass: "Which idea would you actually pursue? What's the 10x version? What result would make this paper go viral?" Reframes from only finding flaws to also finding the diamond. |
| 9 | **Idea clustering** | Replace tournament with cheap clustering: group into 5-7 themes, pick most surprising per theme. Human picks from organized menu. |

### Dropped/Deferred

| Feature | Reason |
|---------|--------|
| ~~Pairwise tournament~~ | LLM rankings diverge from expert rankings. Filters OUT weird ideas. |
| ~~Temperature variation~~ | Marginal impact given existing model×technique diversity. |
| ~~Iterative revision cycles~~ | May converge ideas toward LLM mean. Defer until retrospective test validates it. |
| ~~Hybrid recombination~~ | Combining weird + normal regresses toward normal. Defer. |
| ~~3 red-team personas~~ | Formulaic. Elevation pass is higher impact. |
| Overexcitement detection | Fold into red-team prompt as one line (trivial). |

### Priority 1.5: Human Interview Protocol

| # | Feature | Rationale |
|---|---------|-----------|
| 10 | **Structured seed interview** | Before writing SEED.md, a Claude Code skill asks the human 5-7 targeted questions to extract the real research question. Prevents vague seeds. Outputs a well-formed SEED.md. |

The interview covers:
1. **The anomaly**: "What specific thing surprised you or doesn't make sense?" (grounds in observation, not topic)
2. **The stakes**: "If you could know the answer, what would change about how people think or build?"
3. **Prior art**: "What's the closest existing work? How does your hunch differ?"
4. **The experiment**: "What's the smallest thing you could run in 1 day to get signal?"
5. **The kill condition**: "What result would convince you this direction is wrong?"
6. **The surprise**: "What result would genuinely surprise experts in this area?"
7. **Your rough ideas**: "What 3-5 directions are you already considering?" (human seeds)

This becomes a `/brainstorm-interview` skill that:
- Uses AskUserQuestion for each question (interactive, not a wall of text)
- Generates a well-structured SEED.md from answers
- Runs seed quality gate automatically
- Optionally kicks off the divergence pipeline

## Architecture Changes (from code critique)

1. **Extract `src/prompts.py`** — All prompt templates + PromptTechnique enum (~350 lines of string constants). Enables parallel agent work and keeps brainstorm.py focused on logic.
2. **`PipelineConfig` dataclass** — Replace growing arg lists with config object. Enables `--preset fast/balanced/thorough` in CLI.
3. **`PipelineContext` object** — Carries accumulated results between stages. Each stage reads what it needs, writes what it produces.
4. **Phase-level temperature** — Instead of dict+list alias, override temp based on phase (divergence=higher, synthesis=lower), respecting `reasoning=True` models.
5. **`--preset` flag in main.py** — Add now (not in skill packaging later). Maps to flag combinations.

## Files to Modify

| File | Changes |
|------|---------|
| `src/prompts.py` | **NEW**: All prompt templates, PromptTechnique enum, new techniques |
| `src/brainstorm.py` | Import from prompts.py, add validate_seed(), restructure synthesis, add elevation pass, add clustering, PipelineConfig/Context |
| `src/config.py` | PipelineConfig dataclass, preset definitions, phase-level temp |
| `main.py` | Human seeds template, --preset flag, --skip-validation flag, novelty-constraint flag |

## Implementation Batches

### Batch 1: Extract prompts + independent additions (3 parallel agents)

**Agent A** — Create `src/prompts.py`:
- Extract PromptTechnique enum + all TECHNIQUE_TEMPLATES from brainstorm.py
- Extract RED_TEAM_CRITIQUE_PROMPT, FACT_CHECK_PROMPT, SYNTHESIS_PROMPT
- Add new techniques: BACKWARD_CHAIN, FAILURE_ANALYSIS, INTERROGATION
- Add ELEVATION_PROMPT for new red-team pass
- Add overexcitement line to RED_TEAM_CRITIQUE_PROMPT
- Add multi-step synthesis prompts: THEME_EXTRACTION_PROMPT, TENSION_IDENTIFICATION_PROMPT, EXPERIMENT_DESIGN_PROMPT

**Agent B** — `main.py` + `src/config.py`:
- Add human seeds section to SEED.md template
- Add PipelineConfig dataclass to config.py with preset definitions
- Add CLI flags: `--preset`, `--skip-validation`, `--novelty-constraint`
- Wire presets to flag combinations

**Agent C** — `src/brainstorm.py` refactor (read-only except brainstorm.py):
- Update imports to use src.prompts
- Add validate_seed() function
- Add extract_idea_titles() for novelty constraints
- Modify apply_technique() to accept novelty constraint string
- Wire novelty into brainstorm_parallel() and run_divergence()

### Batch 2: Synthesis & red-team redesign (1 agent, sequential after Batch 1)

**Agent D** — `src/brainstorm.py` pipeline changes:
- Replace single synthesize() with multi-step: extract_themes() → identify_tensions() → design_experiments()
- Add elevation red-team pass (run alongside existing destruction pass)
- Add simple idea clustering (single LLM call to group into themes)
- Refactor run_full_pipeline() to use PipelineConfig/PipelineContext
- Update run_synthesis(), run_red_team() signatures

### Batch 3: Skills & plugin packaging (2 parallel agents, after Batch 2)

**Agent E** — `/brainstorm-interview` skill (`.claude/commands/brainstorm-interview.md`):
- Interactive interview: 7 questions via AskUserQuestion (one at a time, conversational)
- After all answers, generate SEED.md with: research question, key terms defined, human rough ideas, kill condition, prior art
- Run validate_seed() on the generated SEED.md
- Ask user: "Ready to run divergence?" → if yes, invoke brainstorm pipeline
- This is the primary entry point for new brainstorming sessions

**Agent F** — `/brainstorm` skill + preset support (`.claude/commands/brainstorm.md`):
- Wraps `uv run python main.py brainstorm` with presets
- Fast: divergence only + novelty constraints
- Balanced: divergence + red-team w/ elevation + multi-step synthesis
- Thorough: balanced + diversity analysis + clustering
- Reads idea dir from argument or asks user to pick from `ideas/`

## Verification

### Per-feature smoke tests
```bash
# Prompts extracted correctly
uv run python -c "from src.prompts import PromptTechnique; print([t.value for t in PromptTechnique])"

# Seed validation
uv run python -c "from src.brainstorm import validate_seed; import asyncio; asyncio.run(validate_seed('vague topic'))"

# New techniques exist
uv run python -c "from src.prompts import TECHNIQUE_TEMPLATES, PromptTechnique; assert PromptTechnique.BACKWARD_CHAIN in TECHNIQUE_TEMPLATES"

# Presets work
uv run python main.py brainstorm --help  # shows --preset flag
```

### Integration test (after all batches)
```bash
uv run python main.py brainstorm ideas/<test-idea>/ --preset balanced --novelty-constraint
# Verify: seed validation runs, new techniques appear in scratchpad,
# synthesis has 3 steps (themes/tensions/experiments), elevation pass in red-team
```

### Retrospective validation (recommended before further iteration)
Take a past idea that produced good results. Run both old and new pipeline on same seed. Did new pipeline surface the actual insight? This is the real test.
