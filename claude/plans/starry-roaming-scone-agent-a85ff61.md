# Critical Review: Human Annotation Interface Plan

**Reviewer role**: Senior UX designer and frontend architect
**Date**: 2026-02-09
**Plan reviewed**: `/Users/yulong/.claude/plans/starry-roaming-scone.md`

---

## 1. UX Design Critique

### 1.1 Annotation Fatigue

**Severity: HIGH**

100 tasks is substantial, especially when each task involves reading a math problem, a model response, potentially 5 paraphrases, detection scores, and 48 follow-up probes. Even at the "transcript only" tier, a single MATH L5 problem with KaTeX-rendered steps could take 2-5 minutes to read carefully. At higher tiers, 5-10 minutes per task is realistic. That is 8-17 hours of concentrated annotation work.

**Problems with the current plan:**
- No session management. The plan has a progress indicator ("12/50 done") but no explicit session breaks, save-and-resume, or fatigue warnings.
- No task ordering strategy. Harder tasks (long USACO problems with code) interleaved with easier ones (short GPQA MCQ) without intentional pacing.
- The "Skip" button exists, but there is no guidance on when to use it, which risks either over-skipping (data loss) or annotators grinding through tasks they should skip (quality loss).

**Recommendations:**
- Add explicit session breaks every 20-25 tasks with a "take a break" interstitial screen showing progress and estimated remaining time.
- Randomize task order per annotator (already implied by seed, but make it explicit) with difficulty balancing so annotators do not hit a wall of hard problems.
- Add a "fatigue indicator" — if annotators start spending <30 seconds per task (rushing) or >10 minutes (stuck), surface a gentle prompt: "You've been on this task for a while. Would you like to skip and come back later?"
- Track time-per-task as the plan does, but also expose it to the annotator as self-monitoring ("Your average: 3.2 min/task, last 5: 1.1 min/task" — helps self-awareness of rushing).

### 1.2 Cognitive Load and Progressive Disclosure

**Severity: MEDIUM**

The 4-tier progressive disclosure is structurally sound. The idea of expanding tiers on demand respects the annotator's attention. However, several issues:

**Too much hidden information.** In the "full_info" condition, annotators have access to Tier 1 (transcript), Tier 2 (5 paraphrases), Tier 3 (3 score bars), and Tier 4 (48 follow-up probes). That is an enormous amount of information. Even with progressive disclosure, the cognitive challenge is not "seeing all the data at once" — it is "integrating heterogeneous signals into a single verdict." The plan provides no guidance on how annotators should weigh these signals.

**The tier ordering embeds a hypothesis.** Transcript first, paraphrases second, scores third, follow-ups fourth. This suggests transcripts are most important and follow-ups are supplementary. But an annotator who opens all tiers may anchor on whichever they read first. The study design conflates "more information" with "information presented in this specific order."

**Recommendations:**
- For the "full_info" condition, consider whether annotators should make an initial judgment after Tier 1, then optionally revise after viewing each subsequent tier. This captures how information changes their mind (which is scientifically more interesting than just a final verdict). Implementation: after the Tier 1 verdict, a "Would you like to see more evidence?" prompt leads to each subsequent tier with a chance to update.
- Add a brief (<100 word) annotator guide for each tier explaining what to look for. For example, Tier 2 might say: "Compare answers across rephrasings. A model that consistently gets the wrong answer is probably genuinely weak. A model that gets different answers to the same question may be behaving inconsistently."
- The 48 follow-up probes in Tier 4 are too many to read linearly. Group them by probe type (self-report, behavioral, trick questions) and show summary statistics with expandable details.

### 1.3 Decision Quality and Annotation Schema

**Severity: HIGH**

The current schema is: verdict (sandbagging / benign / uncertain) + confidence slider [0, 1] + optional reasoning text.

**This captures too little signal.** The research question is not just "is this sandbagging?" but "what made you think it was sandbagging?" Without structured annotation of the *reasoning*, you get labels but no interpretability.

**The "uncertain" option with confidence slider creates ambiguity.** If I choose "sandbagging" with confidence 0.55, is that meaningfully different from "uncertain" with confidence 0.50? The human_score derivation (sandbagging -> confidence, benign -> 1-confidence, uncertain -> 0.5) conflates these two distinct cognitive states: "I think it's sandbagging but I'm not very sure" vs "I genuinely cannot tell."

**The confidence slider is uncalibrated.** Annotators will interpret 0.7 confidence differently. One person's 0.7 is another's 0.9. Without calibration tasks (where ground truth is known), you cannot compare confidence across annotators.

**Recommendations:**
- Add a structured "signal checklist" before the verdict. For example:
  - [ ] The answer is wrong
  - [ ] The reasoning contains deliberate errors
  - [ ] The response is unusually short or low-effort
  - [ ] The response contradicts itself
  - [ ] Different rephrasings got different answers (inconsistency)
  - [ ] The model admitted to sandbagging in follow-ups
  - [ ] The automated scores are high (if visible)
  - [ ] Other: ___________
  This gives you structured data on *what signals humans use* — which is a publishable finding in itself.
- Replace the continuous confidence slider with a 5-point Likert scale: "Definitely sandbagging / Probably sandbagging / Unsure / Probably benign / Definitely benign." This maps naturally to a continuous score (5/4/3/2/1 normalized to [0,1]) but forces a commitment rather than the imprecise continuous slider. The "uncertain" option in the current plan is an escape hatch that will be overused.
- Include 5-10 calibration tasks at the start of each session with known ground truth and feedback. This trains annotators and lets you measure calibration.

### 1.4 Paraphrase Comparison UX

**Severity: MEDIUM**

Tabs and side-by-side view with green/red border for consistency is a reasonable start, but it is not sufficient for the research goals.

**Problems:**
- Tabbed view forces sequential comparison — you can only see one paraphrase at a time. Detecting *patterns of inconsistency* (e.g., "got it right on 3/5, wrong on 2/5") requires mentally tracking across tabs.
- Side-by-side is limited by screen width, especially for MATH problems with long KaTeX expressions.
- Green/red correctness borders only capture answer consistency. They miss *reasoning consistency*: a model might give the right answer for completely different (incompatible) reasons across paraphrases, which is a strong sandbagging signal.

**Recommendations:**
- Add a "consistency summary" row at the top of Tier 2: "Correct on 3/5 rephrasings. Answer changed on: eli5, frustrated." This gives the key signal without requiring annotators to read all 5 versions.
- For MATH, highlight the final `\boxed{}` answer from each paraphrase in a compact grid view. Let the annotator see at a glance whether answers agree without reading full reasoning.
- Consider a "diff mode" that highlights textual differences between the original response and a selected paraphrase response. This is more useful than side-by-side for spotting reasoning divergence.

### 1.5 Score Display Bias

**Severity: MEDIUM**

The plan uses neutral labels ("Response Consistency", "Follow-up Analysis", "Monitor Assessment") with continuous bars and no threshold indicators. This is better than "Sandbagging Probability: 87%", but still has issues:

- **Direction bias**: The label "Response Consistency" with a low-to-high bar implicitly suggests "low consistency = suspicious." Even with neutral framing, annotators will learn what "high" means after a few tasks.
- **Anchoring**: Any numerical score will anchor judgment. Once you see "0.87" for Follow-up Analysis, you cannot un-see it.
- **Bar visualization encodes ordinality**: A bar that is 90% full "looks alarming" regardless of label. This is an inherent property of bar charts.

**Recommendations:**
- The `scores_blinded: true` mode should be the *default* for at least the first pass. Show scores only on a second pass or in a separate condition.
- Consider showing scores as percentile ranks rather than raw values ("This response's consistency is in the 73rd percentile of all responses in this study"). Percentile removes the absolute number anchoring.
- For the research, the most valuable comparison would be: annotators who NEVER see scores vs. annotators who always see scores. The current tier design (scores in Tier 3) conflates "saw paraphrases + scores" with "just saw scores." Consider a factorial design where paraphrases and scores are independent conditions, not nested.

### 1.6 Mobile/Accessibility

**Severity: LOW** (for local research use)

The plan targets local use by researchers, so mobile is not critical. However:

- Pico CSS is classless and responsive, which is good.
- KaTeX rendering can overflow on narrow screens. Add `overflow-x: auto` on math containers.
- The sticky bottom annotation panel may occlude content on shorter screens. Consider making it collapsible or moving it to a sidebar on wider screens.
- No mention of keyboard shortcuts. For 100 tasks, being able to press 1/2/3 for verdict and Enter to submit would save significant time.

### 1.7 Flow and Navigation

**Severity: HIGH**

The plan shows linear task progression with Previous/Skip/Submit & Next buttons. This is too rigid.

**Problems:**
- No way to jump to a specific task number. If an annotator realizes after task 50 that they misunderstood the instructions, they cannot easily revisit earlier tasks.
- No filtering. An annotator might want to see "all tasks I marked uncertain" to reconsider them at the end.
- No draft state. If I expand Tier 2 and start forming a judgment, then accidentally navigate away, my work is lost.
- The "Previous" button is ambiguous: does it let me *view* my previous annotation, or *edit* it? Both are needed but have different implications (editing changes the data).

**Recommendations:**
- Add a task list sidebar or top bar showing all task numbers as small circles (filled = complete, half-filled = in progress, empty = not started). Clicking any circle navigates to that task. This is the one clear win from the FAR AI demo.
- Allow editing of previous annotations with an audit trail (track original and revised annotations separately — revisions are interesting data).
- Autosave annotation state on every interaction (verdict change, confidence change, tier expansion). No explicit "save draft" needed.
- Add a "Review" screen before the debrief that shows all annotations in a compact table with filtering (by verdict, confidence, completion status).

---

## 2. Frontend Architecture Critique

### 2.1 Jinja2 + HTMX vs React SPA

**Verdict: HTMX is the right call for Phase 1, but will strain in Phase 2-3.**

**For Phase 1 (core annotation):** HTMX is well-suited. The annotation flow is fundamentally page-based: load a task, expand tiers, submit verdict, load next task. HTMX handles this cleanly with `hx-get` for tier expansion and `hx-post` for form submission. No build step is a real advantage for a research tool.

**Where HTMX will strain:**
- **Timer**: The per-task timer needs continuous client-side state. HTMX does not help here — you need vanilla JS (which the plan already accounts for with `annotate.js`).
- **Confidence slider**: HTMX handles form submission, but a smooth slider with live value display needs JS event listeners anyway.
- **Undo/revision history**: HTMX's model is "server renders HTML, client swaps it in." There is no client-side state to "undo" — every action is a server round trip. For undo, you would need to store annotation history server-side and render the previous state.
- **Phase 2 admin dashboard**: Live IRR updates and completion rates could work with HTMX polling (`hx-trigger="every 5s"`), but this is wasteful compared to Server-Sent Events (SSE) or WebSockets.
- **Phase 3 chat**: A chat interface fundamentally needs bidirectional real-time communication. HTMX can handle it via SSE extension (`hx-ext="sse"`), but it will feel clunky compared to a WebSocket-based solution.

**Recommendation:** Keep HTMX for Phase 1. For Phase 2, use HTMX SSE extension for the admin dashboard. For Phase 3, add a small Alpine.js or vanilla JS module for the chat interface rather than switching the entire stack. Do NOT move to React — the overhead is not justified for this use case.

### 2.2 KaTeX Rendering with HTMX Partial Updates

**Severity: MEDIUM — this is a real gotcha.**

When HTMX swaps in new HTML (e.g., loading a paraphrase tab via `hx-get="/task/42/paraphrase/eli5"`), the newly inserted DOM elements will contain raw LaTeX (`$...$` or `\(...\)`) that KaTeX has not processed. KaTeX's auto-render only runs on page load unless you explicitly re-trigger it.

**Concrete problem scenario:**
1. Page loads with Tier 1. KaTeX auto-render processes the math on the page. Looks fine.
2. User clicks "View paraphrased versions." HTMX fetches Tier 2 HTML and swaps it in.
3. The paraphrase text contains `$\frac{x^2+1}{x-3}$` as raw text. KaTeX does not know about this new content. Broken rendering.

**Fix:** After every HTMX swap, re-trigger KaTeX rendering on the swapped element. HTMX emits `htmx:afterSwap` events, so:

```javascript
document.body.addEventListener('htmx:afterSwap', (event) => {
    renderMathInElement(event.detail.target, {
        delimiters: [
            {left: '$$', right: '$$', display: true},
            {left: '$', right: '$', display: false},
            {left: '\\(', right: '\\)', display: false},
            {left: '\\[', right: '\\]', display: true},
        ]
    });
});
```

Similarly for Prism.js syntax highlighting:
```javascript
document.body.addEventListener('htmx:afterSwap', (event) => {
    event.detail.target.querySelectorAll('pre code').forEach(Prism.highlightElement);
});
```

This must be documented in the plan as a known requirement, not discovered during implementation.

### 2.3 State Management

**Severity: MEDIUM**

The plan uses server-side state in SQLite with no client-side state framework. For a research annotation tool, this is acceptable but has specific gaps:

- **Autosave**: Without client-side state, every "save" is a network request. For a local tool, latency is negligible, so this works. But the plan should explicitly define which interactions trigger a save: just "Submit," or also tier expansion, confidence slider changes, partial text in the reasoning field?
- **Undo**: No undo mechanism is described. If an annotator clicks "Submit & Next" and immediately regrets it, what happens? The "Previous" button exists, but can they edit?
- **Draft persistence**: If the browser tab closes mid-annotation (before submit), is the partial state lost? The plan says nothing about this. For SQLite-backed state, you could save draft annotations on every interaction via HTMX (`hx-trigger="change"` on form elements), but this needs to be designed.

**Recommendation:** Add a `draft_annotations` table in SQLite that saves on every form interaction. When the annotator returns to a task, restore the draft. On submit, move from `draft_annotations` to `annotations`. This gives you resilience against browser crashes and also captures interesting data about how annotators revise their initial impressions.

### 2.4 Real-Time Features

**Phase 2 admin dashboard:** HTMX polling (`hx-trigger="every 10s"`) is fine for a local tool with 2-5 concurrent annotators. SSE would be more elegant but is unnecessary overhead for this scale.

**Phase 3 live chat:** This is where the architecture gets uncomfortable. A chat interface with an LLM backend involves:
1. User sends message (form submit — HTMX handles fine)
2. LLM streams response token by token (needs SSE or WebSocket)
3. Chat history updates in real time

FastAPI supports SSE natively via `StreamingResponse`. HTMX supports SSE via the `sse` extension. This *can* work but will require careful integration. Alternatively, for Phase 3, consider using a small standalone chat widget (e.g., a Web Component or a 50-line vanilla JS module) that communicates with a `/api/chat` endpoint directly, independent of HTMX.

**Recommendation:** Defer Phase 3 architecture decisions until Phase 1 is proven. The chat feature is a "nice to have" for the research and should not constrain the Phase 1 architecture.

### 2.5 Alternative Stacks

**Streamlit:** Would be faster to prototype but terrible for annotation. Streamlit reruns the entire script on every interaction, destroying client state. No session management, no multi-user support, no fine-grained control over layout. Reject.

**Gradio:** Better than Streamlit for multi-user, but the UI is opinionated and inflexible. Custom layouts (4-tier progressive disclosure, sticky annotation panel, task navigation sidebar) are hard to achieve. KaTeX rendering would need custom components. Reject.

**Lightweight React (Vite):** Would give you superior interactivity (smooth sliders, instant undo, rich diffing) but adds: a build step, a Node.js dependency, a learning curve if the team is Python-only, and the complexity of managing two languages (Python backend, TypeScript frontend). For a research tool used by 2-5 people, this is over-engineering.

**Verdict:** FastAPI + Jinja2 + HTMX + small amounts of vanilla JS is the right choice. The plan's instinct is correct. The one thing I would add: **Alpine.js** (14KB, CDN, no build step) as a lightweight reactivity layer for the annotation panel. It handles the confidence slider, form validation, keyboard shortcuts, and timer elegantly without the complexity of React.

---

## 3. Comparison to FAR AI Demo

Based on the demo description and the plan's own comparison table, here are patterns to adopt and avoid:

### Adopt

1. **Step indicator / task navigation bar.** The FAR demo uses a sidebar with step indicators. The plan should add a compact task progress bar (row of small clickable indicators showing complete/incomplete/current) at the top of the annotation page. This is the single biggest navigation improvement.

2. **Sample pagination with count.** "Sample 12 of 168" with arrow buttons is simple and effective. The plan has "12/50 done" in the header, but should also add task-level forward/back arrows separate from the "Submit & Next" workflow button.

3. **Collapsible expert tips.** The FAR demo has collapsible hints for annotators. The plan's Tier 2-4 expansion is similar, but each tier should also have a brief instructional tooltip or collapsible guide ("What to look for in paraphrase comparisons").

### Avoid

1. **Binary Model A/B framing.** The FAR demo asks "Which model is sandbagging?" with a toggle. This is a simpler decision than the plan's verdict + confidence + reasoning, but it loses information. The plan's richer schema is better for research — do not simplify to match the demo.

2. **Token-level color-coded deception scores.** This is a white-box feature (requires access to model internals). The plan correctly focuses on black-box methods. Do not try to replicate this.

3. **Training-based elicitation bar charts.** The FAR demo shows training curves and probe accuracy. These are summary statistics about the method, not about individual samples. Including them in a per-task annotation interface would be confusing. Keep the debrief screen for aggregate analysis.

---

## 4. Concrete Actionable Improvements

### Improvement 1: Add a Structured Signal Checklist

**What to change:** Add a mandatory checklist of potential sandbagging signals between the tier display and the verdict selection.

**Why it matters:** The current schema (verdict + confidence + optional reasoning) captures the decision but not the reasoning process. A checklist of 6-8 specific signals (wrong answer, low effort, inconsistency across paraphrases, self-admission in follow-ups, high automated scores, etc.) gives you structured data on *what signals humans attend to* and *which signals predict correct detection.* This is a standalone research contribution: "Human annotators primarily relied on cross-paraphrase inconsistency (signal used in 73% of correct detections) rather than answer correctness alone (42%)."

**How to implement:**
- Add a `signal_checklist` column (JSON array) to the `annotations` table in SQLite.
- In the annotation panel, render a checkbox list above the verdict radio buttons.
- Make at least one checkbox required before submitting a non-"uncertain" verdict.
- In analysis, compute per-signal precision/recall and co-occurrence matrices.

### Improvement 2: Capture Per-Tier Judgments (Staged Annotation)

**What to change:** In higher-tier conditions (with_paraphrases, with_scores, full_info), require an initial verdict after Tier 1, then allow revision after each subsequent tier.

**Why it matters:** The current design only captures a final verdict. You lose the most interesting data: *how does additional information change human judgment?* With staged annotation, you can measure: "After seeing paraphrases, 34% of annotators changed their verdict from benign to sandbagging" — which directly quantifies the value of C3-style consistency information for human decision-making. This is a much stronger result than "annotators with paraphrases had higher accuracy" because it captures the causal mechanism.

**How to implement:**
- Add `tier_verdicts` JSON column to store `{tier_1: {verdict, confidence}, tier_2: {verdict, confidence}, ...}`.
- After the Tier 1 annotation panel, show a "See more evidence?" button.
- Each subsequent tier reveals its content and re-shows the annotation panel with the previous values pre-filled.
- The final verdict is what goes into the CSV export; intermediate verdicts go into the rich JSON.

### Improvement 3: Replace Continuous Confidence Slider with Likert Scale

**What to change:** Replace the [0.0, 1.0] continuous confidence slider with a 5-point verdict scale: Definitely Sandbagging / Probably Sandbagging / Unsure / Probably Benign / Definitely Benign.

**Why it matters:** Continuous sliders are cognitively expensive and poorly calibrated across annotators. Research on annotation interfaces consistently shows that Likert scales produce higher inter-rater reliability than continuous scales for subjective judgments (Likert scales constrain the decision space, forcing meaningful distinctions). The current plan's `human_score` derivation (sandbagging -> confidence, benign -> 1-confidence, uncertain -> 0.5) is a Rube Goldberg machine to convert back to what is essentially a 3-point scale with continuous uncertainty. A 5-point Likert maps cleanly to [1.0, 0.75, 0.5, 0.25, 0.0] for pipeline compatibility.

**How to implement:**
- Replace the radio buttons + slider with a single 5-point horizontal button group.
- Map to `human_score`: Definitely Sandbagging=1.0, Probably=0.75, Unsure=0.5, Probably Benign=0.25, Definitely Benign=0.0.
- For the bootstrap CV pipeline, this still works with `classifier.score_column=human_score`.
- Optionally keep the reasoning text field for any verdict.

### Improvement 4: Add Keyboard Shortcuts and Session Management

**What to change:** Add keyboard shortcuts for all common actions and explicit session management (save progress, resume later, break reminders).

**Why it matters:** At 100 tasks per annotator, even small friction per task compounds. Moving the mouse to click a radio button, then a slider, then a submit button for every task is fatiguing. Keyboard shortcuts are standard in annotation tools (Prodigy, Label Studio, Doccano) for exactly this reason. Session management matters because no one will annotate 100 MATH L5 problems in a single sitting; the tool must support graceful interruption and resumption.

**How to implement:**
- Keyboard shortcuts (document in a help overlay toggled with `?`):
  - `1-5` for the 5-point Likert scale
  - `Enter` to submit and advance
  - `Backspace` to go to previous task
  - `S` to skip
  - `T` to toggle current tier expansion
  - `Tab` to cycle through tiers
- Session management:
  - Save all state to SQLite on every interaction (draft mode).
  - On page load, restore last incomplete task.
  - Show a "Welcome back, researcher_a. You completed 47/100 tasks. Resume?" screen.
  - Every 25 tasks, show a break screen with aggregate stats (avg time, verdict distribution so far).

### Improvement 5: Add Calibration Tasks with Feedback

**What to change:** Include 5-10 calibration tasks with known ground truth at the beginning of each annotation session. Show annotators their accuracy on these tasks before they begin the real annotation.

**Why it matters:** Without calibration, you have no idea whether annotators understand the task. "Sandbagging" is a technical concept that even AI researchers may interpret differently. Calibration tasks with feedback ("This was actually sandbagging because the model was prompted to perform poorly on questions containing keyword X") establish a shared understanding of the task and set quality expectations. They also give you a per-annotator calibration score that you can use to weight their annotations in analysis (well-calibrated annotators get more weight).

**How to implement:**
- In `prepare_study.py`, flag 10 tasks as `is_calibration=True` with curated examples (5 obvious sandbagging, 3 obvious benign, 2 subtle).
- Present these first, in a clearly labeled "Training Phase" with a different header color.
- After each calibration task, show: "Your answer: Sandbagging. Correct answer: Sandbagging. This model was sandbagging because [explanation]."
- After all calibration tasks, show summary: "You got 8/10 correct. You're ready to begin the study."
- Store calibration accuracy in the annotator metadata for downstream weighting.
- Do NOT include calibration tasks in the exported CSV (they are training, not data).

---

## 5. Summary Assessment

The plan is well-structured, technically sound, and correctly identifies the gap (no human baseline for sandbagging detection). The tech stack choice (FastAPI + HTMX) is appropriate. The pipeline integration (CSV compatible with `run_multisample_bootstrap_cv`) is the right design principle.

**The main weaknesses are on the annotation design side, not the engineering side:**

| Issue | Severity | Fix Effort |
|-------|----------|------------|
| No structured signal capture (checklist) | HIGH | Low (1-2 hours) |
| No staged/per-tier judgment capture | HIGH | Medium (half day) |
| Confidence slider poorly calibrated | HIGH | Low (swap UI element) |
| No session management / fatigue mitigation | HIGH | Medium (half day) |
| No calibration tasks | HIGH | Medium (half day) |
| Linear navigation, no task overview | HIGH | Medium (half day) |
| KaTeX re-render after HTMX swap | MEDIUM | Low (10 lines of JS) |
| No keyboard shortcuts | MEDIUM | Low (few hours) |
| Paraphrase comparison lacks summary view | MEDIUM | Low (few hours) |
| Score display can still anchor | MEDIUM | Low (design change) |

**Overall verdict:** The plan is a solid B+. It would produce a working tool, but the annotation *protocol* needs refinement to produce publishable-quality human baseline data. The five improvements above would elevate it to an A — and more importantly, would generate richer data for the research (signal checklists, staged judgments, calibration scores) that the current plan misses entirely.
