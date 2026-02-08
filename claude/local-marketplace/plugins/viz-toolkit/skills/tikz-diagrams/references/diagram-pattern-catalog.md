# Anthropic-Style Diagram Pattern Catalog for ML Papers

A reference for recreating Anthropic alignment blog figures in TikZ, based on analysis of 16+ real diagrams from Anthropic's alignment science blog, Petri, Bloom, OpenAI safety pretraining, and Anthropic docs.

---

## Style Package

All examples use `anthropic-tikz.sty` which defines:
- **16 colors**: peach, softblue, lavender, mint, warmgray, blush, cream, skyblue + deep variants + charcoal, medgray, lightgray, untrustedred
- **Box styles**: `peachbox`, `bluebox`, `lavbox`, `mintbox`, `blushbox`, `graybox`, `creambox`, `skybox`
- **Container styles**: `card`, `pill`, `iconcirc`, `groupbox`, `layercard`
- **Arrow styles**: `arrbase`, `arrdashed`, `arrthick`
- **Text styles**: `annot`, `heading`, `subheading`, `msglabel`
- **Message styles**: `sysmsg`, `usermsg`, `asstmsg`, `toolmsg`

---

## Pattern Taxonomy

### Pattern 1: Linear Pipeline
**What it is**: Horizontal chain of processing stages connected by arrows.
**When to use**: Showing data flow, model training stages, or evaluation pipelines.

**Template example**: Example 1 — Model Pipeline (data → model → evaluation → deployment with feedback arc)

**Real Anthropic examples**:
- *Bloom Pipeline* (Image 12): Seed input → Automated pipeline → Transcript viewer. Below: Understanding → Ideation → Rollout → Judgment. Four-stage horizontal flow with vertical detail in each stage.
- *OAI RL Training Pipeline* (Image 9/SVG): SFT data generation → SFT training → RL training → G_spec. Left-side key processes with branching connections to right-side components.

**Caption style**: "Figure N: [Tool/Method name] is a [N]-stage [automated/manual] pipeline that [verb phrase]. [Configuration details]. The pipeline produces [outputs] and [metrics], viewable in [interface]."

**TikZ skeleton**:
```latex
\node[bluebox] (A) at (0,0) {\faIcon{database}\\[2pt] Stage 1};
\node[lavbox]  (B) at (4,0) {\faIcon{brain}\\[2pt] Stage 2};
\node[peachbox](C) at (8,0) {\faIcon{chart-bar}\\[2pt] Stage 3};
\draw[arrbase] (A) -- (B);
\draw[arrbase] (B) -- (C);
% Feedback arc (routed above to avoid overlap)
\draw[arrdashed] (C.north) -- ++(0,0.8) -|
  node[annot, above, pos=0.25] {feedback} (B.north);
```

**Key styles**: `bluebox`, `lavbox`, `peachbox`, `mintbox`, `arrbase`, `arrthick`
**Complexity**: Low — 30min in TikZ


---

### Pattern 2: Two-Panel Comparison (Side-by-Side Columns)
**What it is**: Two (or more) vertical flows placed side by side, often sharing top steps and diverging.
**When to use**: Comparing manual vs automated workflows, honest vs sandbagging behavior, before/after.

**Template examples**:
- Example 7 — Side-by-Side Text Comparison (honest vs sandbagging model outputs with consistency scores)

**Real Anthropic examples**:
- *Single-Turn vs Agent Evaluations* (Image 1): Top panel shows simple eval (prompt + data → LLM → response → grading). Bottom panel shows agent eval (tools + environment + task → agent loop → grading). Two distinct horizontal flows stacked vertically within rounded containers.
- *Manual eval R&D vs Petri* (Images 9–10): Two columns. Left: formulate hypothesis → design scenarios → construct environments → run models → manual transcript analysis → aggregate results → iterate. Right: same top steps → Petri automates middle steps → iterate. Horizontal arrow connects "construct environments" to Petri's equivalent.

**Caption style**: "Figure N: [Process A] often involves [manual steps]. [Process B] automates much of this process."

**TikZ skeleton**:
```latex
% Left column
\node[card, minimum width=6cm, minimum height=10cm] (lcol) at (-4, -5) {};
\node[heading] at (-4, -0.5) {Manual Approach};
\node[mintbox, text width=4cm] (L1) at (-4, -2) {Step 1};
\node[mintbox, text width=4cm] (L2) at (-4, -4) {Step 2};
\node[mintbox, text width=4cm] (L3) at (-4, -6) {Step 3};
\draw[arrbase] (L1) -- (L2);
\draw[arrbase] (L2) -- (L3);

% Right column
\node[card, minimum width=6cm, minimum height=10cm] (rcol) at (4, -5) {};
\node[heading] at (4, -0.5) {Automated};
\node[peachbox, text width=4cm] (R1) at (4, -2) {Step 1 (same)};
\node[lavbox, text width=4cm, minimum height=4cm] (R2) at (4, -5) {
  \textbf{Tool Name}\\[4pt]
  {\scriptsize Automates steps 2-4}
};
\draw[arrbase] (R1) -- (R2);

% Cross-reference arrow
\draw[arrdashed] (L2.east) -- (R2.west);
```

**Key styles**: `card` columns, colored boxes per phase, `arrdashed` for cross-references
**Complexity**: Medium — 1-2h in TikZ


---

### Pattern 3: Nested Container / Hierarchy
**What it is**: Containers within containers showing compositional structure (harness contains suite contains task contains trials).
**When to use**: Showing system architecture, evaluation framework components, nested abstractions.

**Real Anthropic examples**:
- *Components of Evaluations for Agents* (Image 2): Outer "Evaluation harness" container → inner "Evaluation suite" container → multiple "Task" cards (front one expanded to show Graders as colored pills: `deterministic_tests`, `llm_rubric`, `state_check`, `tool_calls`; Tracked metrics as pills: `n_turns`, `n_toolcalls`, `tokens`, `latency`; and stacked Trial cards). Arrow to "Agent harness" on the right. Bottom: Outcome → Grader evaluate. Legend card explaining Task, Trial, Grader.
- *MCP Client Architecture* (Image 8): Three tall columns (Model, MCP client, MCP server). MCP client contains a "Context window" box with stacked message rows (System prompt, Tool 1 def, Tool 2 def, User msg 1, Assistant msg 1, etc.) color-coded by role. Horizontal arrows between columns for tools/list, tools/call flows. Icons for Model (chip) and MCP server (server rack).

**Caption style**: "Figure N: The [system] [verb: loads/orchestrates/processes] [components] into [container] and [action verb] where each [sub-component] [does what]."

**TikZ skeleton**:
```latex
% Inner nodes first
\node[pill=peach] (g1) at (-2, -3) {deterministic\_tests};
\node[pill=peach] (g2) at (1, -3) {llm\_rubric};
\node[pill=peach] (g3) at (3.5, -3) {state\_check};

% Task container (fit around inner nodes)
\node[card, draw=deeppeach, inner sep=15pt,
  fit=(g1)(g2)(g3), label={[heading]above left:Task}] (task) {};

% Suite container (fit around tasks)
\node[groupbox, fill=softblue!20, inner sep=20pt,
  fit=(task)(task2)(task3), label={[heading]above left:Evaluation suite}] {};

% Harness container (outermost)
\node[groupbox, fill=warmgray!30, inner sep=25pt,
  fit=(suite)(harness-extras), label={[heading]above left:Evaluation harness}] {};
```

**Key styles**: `card`, `pill`, `groupbox`, `fit` library, `on background layer`
**Complexity**: High — 2-3h in TikZ (nesting is fiddly)
**Tip**: Always draw inner nodes first, then wrap with `fit` on background layers.


---

### Pattern 4: Sequence Diagram (Vertical Lifelines)
**What it is**: Multiple actors as vertical bars with horizontal arrows showing message flow over time.
**When to use**: API call flows, tool calling sequences, multi-agent communication.

**Real Anthropic examples**:
- *Programmatic Tool Calling Flow* (Image 7): Three actors (User=blue bar, API=gray bar, Claude=peach/coral bar) with labeled horizontal arrows: Request → Sampling → "Claude generates Python script" → Run script in container → Script pauses → Response with custom tool call → Request with custom tool result → Resume script → Script result → Sampling with result → Response. "Code Execution Tool" box attached to container lifeline with dashed border.

**Caption style**: "Figure N: [Feature name] enables [actor] to [action] through [mechanism] rather than [alternative], allowing for [benefit]."

**TikZ skeleton**:
```latex
% Actor lifelines (tall colored bars)
\fill[softblue!60] (0, 0) rectangle (0.4, -12);   % User
\fill[warmgray]    (5, 0) rectangle (5.4, -12);    % API
\fill[peach!80]    (10, 0) rectangle (10.4, -12);   % Claude

% Actor labels
\node[graybox, minimum width=2cm] at (0.2, 0.8) {User};
\node[graybox, minimum width=2cm] at (5.2, 0.8) {API};
\node[peachbox, minimum width=2cm] at (10.2, 0.8) {Claude};

% Messages (horizontal arrows with labels)
\draw[arrbase] (0.4, -1) -- node[annot, above] {Request} (5, -1);
\draw[arrbase] (5.4, -2) -- node[annot, above] {Sampling} (10, -2);
\draw[arrbase] (10, -3) -- node[annot, above] {Script with tool calls} (5.4, -3);
```

**Key styles**: `\fill` rectangles for lifelines, `arrbase` horizontal, `annot` labels
**Complexity**: Medium-High — 1.5-2h in TikZ
**Alternative**: PlantUML generates these natively and can export to PDF/SVG.


---

### Pattern 5: Annotated Data Plot
**What it is**: A chart (line, bar, lollipop) with overlaid annotation cards explaining key features.
**When to use**: Benchmark results, metric comparisons, explaining divergent trends.

**Real Anthropic examples**:
- *pass@k vs pass^k* (Image 3): Two-line chart (x: number of trials, y: success rate). Green dots for pass@k rising to 100%, coral dots for pass^k falling to 0%. Dashed reference line at ~73%. Two annotation cards with mint/blush backgrounds explaining pass@k ("At least one of k trials succeeds") and pass^k ("All k trials must succeed"). Arrows from cards to respective curves at k=7. Legend in bottom-left.

**Caption style**: "Figure N: [metric A] and [metric B] diverge as [variable] increases. At [value], they're identical. By [value], they tell opposite stories: [A interpretation] while [B interpretation]."

**TikZ approach**: Use `pgfplots` for the actual data. Overlay annotation cards as TikZ nodes.
```latex
\begin{axis}[
  width=12cm, height=6cm,
  xlabel={Number of trials (k)},
  ylabel={Success Rate (\%)},
  xmin=0.5, xmax=10.5, ymin=0, ymax=105,
]
\addplot[mint!80!black, mark=*, thick] coordinates {(1,73)(2,93)(3,97)...};
\addplot[deepblush, mark=*, thick] coordinates {(1,73)(2,55)(3,39)...};
\end{axis}
% Annotation card overlaid
\node[card, fill=mint!20, text width=5cm] at (8, 4) {
  \textbf{pass@k}\\[2pt]
  {\small "At least one of k trials succeeds"}
};
```

**Key styles**: `pgfplots` with anthropic color cycle, `card` annotation overlays
**Complexity**: Medium for simple charts, High for multi-panel
**Alternative**: Generate in matplotlib/R with the pastel palette, export as PDF.


---

### Pattern 6: Multi-Column Roadmap / Phased Flow
**What it is**: Multiple vertical columns representing phases, each containing numbered steps connected by arrows. Horizontal arrows between columns show phase transitions.
**When to use**: Process guides, development roadmaps, phased methodology.

**Real Anthropic examples**:
- *Roadmap to Excellent Evals* (Image 4): Three tall rounded cards side by side. Left "Evaluation suite development" (mint): 0. Start now → 1. Manual tests → 2. Write unambiguous tasks → 3. Cover positive and negative cases. Center "Harness development" (peach): 4. Build robust eval harness → 5. Design graders thoughtfully. Right "Eval maintenance" (lavender): 6. Check trajectories → 7. Monitor for saturation → 8. Maintain long-term. Horizontal arrows between column tops.

**Caption style**: "Figure N: The process of [creating/building] an effective [system]."

**TikZ skeleton**:
```latex
% Column 1
\node[card, minimum width=5cm, minimum height=10cm] (col1) at (-5.5, -5) {};
\node[heading] at (-5.5, -0.5) {Phase 1};
\node[mintbox, text width=3.5cm] (s0) at (-5.5, -2) {\textbf{0.} Start now};
\node[mintbox, text width=3.5cm] (s1) at (-5.5, -4) {\textbf{1.} Manual tests};
\draw[arrbase] (s0) -- (s1);

% Column 2
\node[card, minimum width=5cm, minimum height=10cm] (col2) at (0, -5) {};
\node[peachbox, text width=3.5cm] (s4) at (0, -2) {\textbf{4.} Build harness};

% Phase transition arrows
\draw[arrbase] ([yshift=4.5cm]col1.east) -- ([yshift=4.5cm]col2.west);
```

**Key styles**: `card` columns, phase-colored boxes, `arrbase` vertical + horizontal
**Complexity**: Low-Medium — 1h in TikZ


---

### Pattern 7: Conceptual / Metaphorical Diagram
**What it is**: Visual metaphor using real-world imagery (Swiss cheese, layers, shields) to convey a safety concept.
**When to use**: High-level overviews, blog posts, explaining defense-in-depth.

**Real Anthropic examples**:
- *Swiss Cheese of Quality* (Image 5): Three overlapping rectangles at increasing opacity (darkest=front) representing layers: Automated evals, Manual transcript review, Production monitoring. Random circles (holes) in each layer. Red diagonal arrows pass through some holes but get blocked when layers combine. Right side: three annotation rows explaining each layer with colored dots as bullets.

**Caption style**: "Like the Swiss Cheese Model from safety engineering, no single evaluation layer catches every issue. With multiple methods combined, failures that slip through one layer are caught by another."

**TikZ skeleton**:
```latex
% Back layer (most transparent)
\fill[peach, opacity=0.3, rounded corners=4pt] (-1,-1) rectangle (5,5);
\draw[warmgray, fill=white] (1, 3) circle (0.4);  % hole
\draw[warmgray, fill=white] (3, 1.5) circle (0.3);

% Middle layer (medium opacity)
\fill[peach, opacity=0.5, rounded corners=4pt] (0.5,-1.5) rectangle (6,4);
\draw[warmgray, fill=white] (2, 2.5) circle (0.35);

% Front layer (most opaque)
\fill[peach, opacity=0.7, rounded corners=4pt] (1.5,-2) rectangle (7,3);

% Red threat arrows
\draw[-{Stealth}, red!70, line width=0.8pt] (-0.5, 5.5) -- (3, -2.5);
\node[red!70, font=\bfseries] at (2.5, 1) {$\times$};  % blocked
```

**Key styles**: `fill opacity`, overlapping `\fill` rectangles, circle holes, colored arrows
**Complexity**: Medium — requires careful layering
**This is where generative tools shine**: Nano Banana Pro produces creative metaphorical visuals faster than manual TikZ.


---

### Pattern 8: Conversation / Transcript Display
**What it is**: Vertically stacked message boxes with role labels and color-coded backgrounds.
**When to use**: Showing model interactions, training data examples, prompt/response pairs.

**Template example**: Example 3 — Conversation Transcript (system → user → assistant → tool call → assistant)

**Real Anthropic examples**:
- *Training Datapoint Examples* (Image 15): Tab-style selector at top ("Example training datapoint 1" / "Example training datapoint 2"). Below: stacked messages — "Sabotage system prompt (removed for training)" in peach/warning, "Normal agentic Claude Code transcript" in gold/warm, "User" message in white, "Sabotage scratchpad (removed for training)" in pink/blush with detailed reasoning text.

**Caption style**: "Figure N: Example [training/evaluation] [datapoints/transcripts] generated using the [method]. The generated [outputs] are used for [purpose], after removing the [component]. Examples are lightly paraphrased."

**TikZ skeleton**:
```latex
% Tab selector
\node[pill=warmgray, font=\sffamily\small] at (-2, 0) {Example 1};
\node[pill=charcoal, text=white, font=\sffamily\small\bfseries] at (2, 0) {Example 2};

% Messages — label ABOVE box with >=0.3cm gap
\node[msglabel, anchor=west] at (-5, -1.2) {\faIcon{cog}\enspace SYSTEM};
\node[sysmsg, anchor=north west] at (-5, -1.5) {
  You are a helpful AI assistant.
};

\node[msglabel, anchor=west] at (-5, -3.2) {\faIcon{user}\enspace USER};
\node[usermsg, anchor=north west] at (-5, -3.5) {
  What's the latest news?
};
```

**Key styles**: `sysmsg`, `usermsg`, `asstmsg`, `toolmsg`, `msglabel`
**Complexity**: Low — 30min in TikZ
**Critical rule**: Always leave ≥0.3cm gap between label and message box.


---

### Pattern 9: Stacked / Layered Cards (Multiplicity)
**What it is**: Multiple card outlines offset behind a front card, showing "there are N of these."
**When to use**: Sample sets (q_1...q_n), trial runs, evaluation tasks, seed instructions.

**Template example**: Part of Example 2 — C³ sample cards (q_1, q_..., q_n)

**Real Anthropic examples**:
- *Components of Evaluations* (Image 2): Multiple "Task" cards stacked + Trial cards within each task.
- *Petri Pipeline — Seed Instructions* (Image 11): Three document icons (A, B, C) stacked.

**TikZ skeleton**:
```latex
\begin{scope}[on background layer]
  \node[card, minimum width=12cm, minimum height=5cm] at (0.2, -0.2) {};
  \node[annot, anchor=north west] at (-5.6, 2.3) {Sample $q_n$};
\end{scope}
\begin{scope}[on background layer]
  \node[card, minimum width=12cm, minimum height=5cm] at (0.1, -0.1) {};
\end{scope}
\node[card, minimum width=12cm, minimum height=5cm] (front) at (0, 0) {};
\node[annot, anchor=north west, font=\sffamily\scriptsize\bfseries]
  at ([shift={(5pt,-5pt)}]front.north west) {Sample $q_1$};
```

**Key detail**: Offset by ≥8pt per card. Label each card corner. Back cards on `background layer`.
**Complexity**: Low once pattern is established


---

### Pattern 10: Stacked Horizontal Bar / Token Budget
**What it is**: Horizontal stacked bars showing composition.
**When to use**: Context window usage, cost breakdowns, resource comparisons.

**Real Anthropic examples**:
- *Context Usage: Traditional vs Tool Search Tool* (Image 6): Two rows. Top: 77.2k/200k tokens (MCP tools dominate at 72K). Bottom: 8.7k/200k (95.65% free). Color-coded legend below each bar.

**Caption style**: "Figure N: [Tool/method] preserves [amount] of context compared to [amount] with [baseline]."

**TikZ skeleton**:
```latex
\draw[lightgray, fill=white, rounded corners=2pt] (0, 0) rectangle (14, 1);
\fill[medgray] (0, 0) rectangle (0.21, 1);        % System prompt 3k
\fill[warmgray] (0.21, 0) rectangle (0.35, 1);     % Custom tools 2k
\fill[softblue] (0.35, 0) rectangle (5.39, 1);     % MCP tools 72k
\fill[peach] (5.39, 0) rectangle (5.53, 1);        % Messages 200
\node[font=\sffamily, text=medgray] at (9.5, 0.5) {61.4\% Free space};
```

**Key styles**: `\fill` rectangles, proportional widths, `annot` legends
**Complexity**: Low — 30min in TikZ


---

### Pattern 11: Multi-Stage Agentic Pipeline with Auditing Loop
**What it is**: A complex pipeline where an auditor agent interacts with a target model through a set of tools, with feedback loops and scoring.
**When to use**: Red-teaming pipelines, multi-agent evaluation, automated alignment testing.

**Template example**: Example 6 — Multi-Agent Auditing (simplified Petri-style)

**Real Anthropic examples**:
- *Petri Pipeline* (Image 11): Three sections. Left "Seed instructions": three stacked document icons (A, B, C). Center "Auditing loop": Auditor Agent box → dashed container with 7 tool actions (Send message, Create synthetic tools, Simulate tool call result, Set system message, Roll back conversation, End conversation, Prefill) → Target Model box. Feedback arrow. Right "Scoring by a judge model": three horizontal score lines (Concerning, Sycophancy, Deception 0.0–1.0) with colored dots positioned along each scale.

**Caption style**: "Figure N: Researchers give [tool] a list of seed instructions targeting [behaviors]. For each seed, an auditor agent uses tools to interact with the target model. A judge scores transcripts across multiple dimensions."

**TikZ skeleton**:
```latex
% Seed instructions (stacked documents)
\node[creambox, minimum width=1.5cm] (seedC) at (-6, -3) {\faIcon{file-alt}\\C};
\node[creambox, minimum width=1.5cm] (seedB) at (-6, -1.5) {\faIcon{file-alt}\\B};
\node[creambox, minimum width=1.5cm] (seedA) at (-6, 0) {\faIcon{file-alt}\\A};

% Auditor + Tool container + Target
\node[lavbox] (auditor) at (-2.5, -1.5) {\textbf{Auditor Agent}};
\node[groupbox, minimum width=3.5cm, minimum height=6cm] (tools) at (1.5, -1.5) {};
\node[skybox] (target) at (5.5, -1.5) {\textbf{Target Model}};

% Score scales (horizontal lines with dots)
\draw[medgray] (8, 0) -- (12, 0);
\node[annot] at (8, -0.3) {0.0};
\node[annot] at (12, -0.3) {1.0};
\fill[mint] (9.5, 0) circle (4pt);     % model C score
\fill[peach] (11, 0) circle (4pt);     % model A score
```

**Key styles**: `groupbox` for tool container, `lavbox`/`skybox` actors, score lines with dots
**Complexity**: High — 2-3h in TikZ


---

### Pattern 12: Layered Architecture Stack
**What it is**: Horizontally wide layers stacked vertically, showing system layers from bottom to top.
**When to use**: Model training stack, system architecture, defense layers.

**Template example**: Example 4 — Layered Architecture (Pre-training → Base Model → RLHF, with Safety Layer)

**Real Anthropic examples**:
- *OAI RL Training* (SVG): Dark theme. Rounded-rectangle components: Prompt → G_base → SFT → CoT+Output → RL Stack.

**TikZ skeleton**:
```latex
\node[layercard=mint, minimum height=1.4cm] (L1) at (0, -4) {
  \faIcon{database}\enspace\textbf{Pre-training Data}\enspace
  {\scriptsize — web corpus, books, code}
};
\node[layercard=softblue, minimum height=1.4cm] (L2) at (0, -2.2) {
  \faIcon{brain}\enspace\textbf{Base Model}
};
\node[layercard=lavender, minimum height=1.4cm] (L3) at (0, -0.4) {
  \faIcon{comments}\enspace\textbf{RLHF / Post-training}
};
\draw[arrbase] (L1.north) -- (L2.south);
\draw[arrbase] (L2.north) -- (L3.south);

% Brace
\draw[charcoal, decorate, decoration={brace, amplitude=8pt, raise=4pt, mirror}]
  ([xshift=-5.5cm]L1.south) -- ([xshift=-5.5cm]L3.north)
  node[midway, left=14pt, annot] {Training Stack};

% Safety layer — SEPARATE, connected by arrow (no overlap!)
\node[peachbox, dashed] (safety) at (7.5, -2.2) {\faIcon{shield-alt}\enspace Safety};
\draw[arrdashed] (L2.east) -- (safety.west);
```

**Key styles**: `layercard`, `decorate` brace, separate auxiliary components
**Complexity**: Low-Medium — 45min in TikZ
**Critical rule**: Never overlay a floating element on text-containing layers.


---

### Pattern 13: Decision / Evaluation Flow (with diamonds)
**What it is**: Flowchart with decision diamonds branching into pass/fail paths.
**When to use**: Evaluation logic, grading flows, classification trees.

**Template example**: Example 5 — Decision Flow (Run evaluation → Consistent? → Pass / Flag → Investigate)

**TikZ skeleton**:
```latex
\node[bluebox] (run) at (0, 0) {Run evaluation};
\node[diamond, aspect=2.2, fill=peach, draw=deeppeach,
  font=\sffamily\small, inner sep=3pt] (dec) at (0, -2.5) {Consistent?};
\node[mintbox] (pass) at (-3.5, -5) {\faIcon{check}\enspace Pass};
\node[blushbox] (flag) at (3.5, -5) {\faIcon{flag}\enspace Flag};
\draw[arrthick] (run) -- (dec);
\draw[arrbase] (dec.west) -| node[annot, above left, pos=0.25] {yes} (pass);
\draw[arrbase] (dec.east) -| node[annot, above right, pos=0.25] {no} (flag);
```

**Key styles**: `diamond` shape, `mintbox`=pass, `blushbox`=fail
**Complexity**: Low — 20min in TikZ


---

### Pattern 14: Result Matrix (Model × Benchmark)
**What it is**: Table-like grid with colored pills for scores.
**When to use**: Benchmark comparison tables, model evaluation results.

**Template example**: Example 8 — Result Matrix (GPT-4o, Claude, Model-X × MATH, GPQA, USACO, C³ Score)

**TikZ skeleton**:
```latex
\node[annot, font=\bfseries] at (-4, 0) {Model};
\node[annot, font=\bfseries] at (-1, 0) {MATH};
\draw[lightgray, line width=0.3pt] (-5.5, -0.3) -- (5, -0.3);

\node[annot, anchor=east] at (-2.5, -1) {\faIcon{robot}\enspace GPT-4o};
\node[pill=mint] at (-1, -1) {92\%};
\node[pill=blush] at (4, -1) {0.31};  % color by threshold
```

**Key styles**: `pill` with color based on value, `annot` headers
**Complexity**: Low — 30min in TikZ


---

### Pattern 15: Bloom-style Four-Stage Pipeline with Detail Panels
**What it is**: Compact horizontal pipeline at top + expanded detail view below.
**When to use**: Complex systems with both overview and detail needed.

**Real Anthropic examples**:
- *Bloom Pipeline* (Image 12): Top: three icon boxes connected by arrows. Below: four panels. "Understanding" (document icon + parameter pills). "Ideation" (n scenarios). "Rollout" (nested interaction: Bloom agent → SimEnv branch → tool calls → Target model → user mode branch → loop). "Judgment" (score sliders 0–10 for behavior presence, elicitation difficulty, evaluation validity + meta-judgment with diversity slider).

**Caption style**: "Figure N: [System] is a [N]-stage automated pipeline that generates [outputs] from a user-provided seed. You can configure [parameters]. The pipeline produces [metrics], viewable in [interface]."

**TikZ approach**: Two-tier layout. Top: simple `basebox` pipeline. Bottom: four `card` detail panels.
**Complexity**: Very High — 3-4h in TikZ


---

### Pattern 16: Horizontal Lollipop / CI Plot (Multi-Model Benchmark)
**What it is**: Horizontal bars with dots for point estimates and CI, grouped by model family.
**When to use**: Comparing many models across behavioral evaluations.

**Real Anthropic examples**:
- *Bloom Benchmarks* (Image 13): Four columns. Each: behavior name + description, then rows by family (Claude, GPT, Gemini, Grok, Deepseek, Kimi). Horizontal line 0–1, colored dot at mean, bar for CI. Separator lines between families. More saturated = frontier model.

**Caption style**: "Figure N: We present comparative plots from [N] evaluations—[list]—on [N] frontier models. [Metric] is [definition]; [interpretation]. More saturated bars indicate frontier models. Each suite = [N] rollouts. We generate [N] suites per pair and show [statistic]. [Config model] serves as evaluator; details in Appendix."

**TikZ approach**: Best in matplotlib/R. If TikZ required, use `pgfplots` `xbar`.
**Complexity**: Medium in pgfplots, Low in matplotlib
**Recommendation**: Python with `matplotlib` using the anthropic palette.


---

### Pattern 17: Grouped Bar + Dot Plot (Training Dynamics)
**What it is**: Grouped bars with individual seed dots overlaid.
**When to use**: Training results across conditions with individual run variability.

**Real Anthropic examples**:
- *Alignment Faking* (Image 14): 2×2 grid. Rows: Alignment Faking, Compliance Gap. Cols: Terminal/Instrumental Goal Guarding. 4 grouped bars per panel (gray, blue, orange, pink = reasoning styles). Individual dots = seeds. Key finding: counterfactual (blue) retains compliance gap.

**Caption style**: "Figure N: Models trained to [intervention] are [better/worse] at [metric]. Each color = training [setup] for [N] steps across seeds (dots). Bars = means. Columns = [N] conditions via [method]. [Finding about comparisons]. Full trajectories in Figure X."

**TikZ approach**: `pgfplots` `ybar` with `scatter` overlay.
**Complexity**: Medium in pgfplots
**Recommendation**: Python/R, export as PDF.


---

## Color Mapping Conventions

| Semantic meaning | Color name | Hex | Usage |
|---|---|---|---|
| Data, inputs, user | softblue | #C5D5EA | Query boxes, user roles, data sources |
| Model, AI, assistant | lavender | #D5C5E8 | Model nodes, RLHF layer, assistant msgs |
| Evaluation, metrics | peach | #FDDCB5 | Eval stages, score displays |
| Safety, passing, honest | mint | #C5E8D5 | Pass indicators, good scores |
| Warning, risk, flagged | blush | #F2D0D0 | Fail indicators, bad scores |
| Background / card | bgcard | #F9F6F2 | Card backgrounds |
| Neutral, system | warmgray | #F5F0EB | System messages, neutral elements |
| Untrusted / suspicious | untrustedred | #E8D0D0 | Untrusted models, adversarial |
| Tool calls, actions | toolbg | #FFF3E0 | Tool call messages |
| Highlighted / gold | cream | #FFF5E6 | Key terms, pills |
| Information boxes | skyblue | #D4E8F7 | Callouts, query boxes |

---

## NeurIPS-Style Caption Templates

### Method diagrams:
> **Figure N:** Overview of [method]. [One-sentence summary]. [Walk through flow L→R or T→B]. [Key design choices]. [Reference to section].

### Benchmark / results plots:
> **Figure N:** [Comparative] [plot type] from [N] evaluations—[list]—on [N] models. [Metric definition]. [Direction = better]. [Visual encoding notes]. Each suite = [N] rollouts. [Stats]. [Evaluator model]; details in Appendix.

### Process / workflow diagrams:
> **Figure N:** [Traditionally], [process] involves [manual steps]. [Tool] automates [which steps], enabling [benefit].

### Training dynamics:
> **Figure N:** Models trained to [intervention] are [better/worse] at [metric]. [Visual element] = [what]. [Grouping explanation]. [Key finding]. Full trajectories in Figure X.

---

## Workflow: TikZ + Generative AI

### Paper figures (final quality)
1. Sketch concept in Nano Banana Pro / whiteboard (5 min)
2. Build in TikZ using this catalog's skeleton code (30min – 3h)
3. Compile and visually inspect for overlaps/clipping
4. Iterate

### Blog posts / presentations (speed)
1. Generate with Nano Banana Pro + pastel palette prompt
2. Refine with targeted edits
3. Export PNG at 2x

### Plots / data visualization
1. Generate in Python/R with anthropic palette
2. Export as PDF
3. Optional TikZ annotation overlays

### Nano Banana Pro prompt template:
```
Create a clean, minimalist technical diagram showing [DESCRIPTION].
Style: Pastel colors (soft blue #C5D5EA, lavender #D5C5E8, peach #FDDCB5,
mint #C5E8D5, blush #F2D0D0). Warm off-white background (#F9F6F2).
Rounded rectangles, thin borders, sans-serif, charcoal text (#3D3D3D).
Thin gray arrows. Generous whitespace. No shadows, no gradients, flat.
Layout: [DETAILED SPATIAL DESCRIPTION]
```

### matplotlib palette:
```python
anthropic = {
    'peach': '#FDDCB5', 'softblue': '#C5D5EA', 'lavender': '#D5C5E8',
    'mint': '#C5E8D5', 'blush': '#F2D0D0', 'warmgray': '#F5F0EB',
    'cream': '#FFF5E6', 'skyblue': '#D4E8F7',
    'deeppeach': '#E8A870', 'deepblue': '#7A9DBF',
    'deeplavender': '#9B7DBF', 'deepmint': '#6BA889',
    'deepblush': '#C98A8A', 'charcoal': '#3D3D3D',
}
```

---

## Common Pitfalls

1. **Overlapping labels**: Leave ≥0.3cm between label and box below
2. **Feedback arcs crossing boxes**: Route via `-- ++(0, offset) -|`
3. **Equidistant starburst arrows**: Use irregular angles/lengths
4. **Invisible stacked cards**: Offset ≥8pt per layer
5. **Auxiliary elements overlapping text**: Place separately, connect with arrows
6. **Brace decorations**: Requires `decorations.pathreplacing` library
7. **`inner sep` shorthand**: Use `inner xsep`/`inner ysep` separately
8. **Nested fit nodes**: Inner nodes first, then `fit` on background layer
9. **Arrows through equations**: Position formulas with `anchor=west`, clear spacing
10. **Long text in layers**: Put inside card, not as side annotation that may overlap
