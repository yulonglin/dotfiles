# Plan: Write Policy-to-Code Compiler Hackathon Plan

## Target File
`/Users/yulong/writing/brainstorming/ideas/20260131-204007-technical-ai-governance-hackathon-projects/plans/plan-policy-to-code-compiler.md`

## Action
Write the complete hackathon project plan. The full content is below. Once plan mode is exited, I will write this file.

## Status
Ready to execute -- waiting for plan mode to be deactivated.

---

## Content to Write

The file covers all 9 requested sections:

1. **Executive Summary**: A tool that compiles EU AI Act CoP requirements into executable pytest suites, producing compliance reports like "Claude Opus 4.5 passes 8/10 Code of Practice tests." First open-source tool treating regulatory text as compilable specification.

2. **Problem Statement**: AI Lab Watch winding down, AI Office capacity-constrained, no executable compliance standard exists, lab self-assessments unreliable. CeSIA Track B explicitly asks "Is Claude Opus 4.5 compliant?"

3. **Technical Approach** (5 steps):
   - Step 1: Triage CoP requirements into behavioral (testable), disclosure (partial), procedural (not testable). 10 specific tests across Measures 2.1, 3.3, 3.4, 4.1, 4.3, 5.1, 2.3.
   - Step 2: YAML spec format for requirements -> LLM compiler generates pytest code. Dual evaluation: keyword matching + LLM-as-judge.
   - Step 3: Three-layer validation -- syntax check, positive control (Llama-3-8B-base should fail), negative control (Claude should pass). Fallback to hand-written reference tests.
   - Step 4: Test against Claude Opus 4.5, GPT-4o, Llama-3-70B-Instruct, Llama-3-8B-base, Mistral Large. ~250 API calls, <$50.
   - Step 5: Three output formats -- pytest terminal, structured JSON, HTML compliance report card.

4. **Hour-by-Hour Timeline**:
   - Hours 0-4: Foundation (repo, YAML specs, 3 reference tests, compiler)
   - Hours 4-10: Core pipeline (generate all tests, validate, run against 5 models, LLM-as-judge)
   - Hours 10-16: Sleep
   - Hours 16-22: HTML reports, adversarial variants, project report
   - Hours 22-28: Inter-rater reliability (3x runs), comparative analysis, limitations
   - Hours 28-36: Streamlit demo, video, polish, submit

5. **Demo Plan**: Streamlit three-panel app. Money shot: side-by-side Claude 9/10 (green) vs Llama-base 2/10 (red). 3-minute script: problem -> live run -> comparison -> compiler demo -> impact.

6. **Innovation Argument**: Nobody has compiled regulatory text into executable test suites. Novel intersection of legal tech + LLM eval + DevOps CI. Directly answers CeSIA's posed question. Theory of change: hackathon -> fellowship -> AI Office adoption.

7. **Risk Mitigation**: 6 risks covered -- buggy generated tests (fallback to hand-written), unreliable LLM judge (dual eval), stochasticity (3x runs), API issues (LiteLLM abstraction), vague requirements (explicit triage), "looks trivial" (emphasize framework over tests).

8. **Limitations & Dual-Use**: Coverage limited to ~30-40% of CoP measures. False positives/negatives. Stochasticity. Specification fidelity needs legal review. Responsible disclosure protocol for CBRN findings.

9. **How to Score 4+**: Impact (genuinely new, answers CeSIA's question), Execution (three-layer validation, dual eval, confidence intervals), Presentation (live demo, legible "8/10" number, polished HTML report).

Plus appendices: key deps (litellm, pytest, pyyaml, jinja2, streamlit, rich) and repo structure.
