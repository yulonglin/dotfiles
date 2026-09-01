#!/usr/bin/env python3
"""Build the context-budget triage console from inventory.json."""
import json, html
from pathlib import Path

OUT = Path(__file__).parent
inv = json.load(open(OUT / 'inventory.json'))

# ---------------------------------------------------------------- clusters
CLUSTER = {}


def c(names, label):
    for n in names:
        CLUSTER[n] = label


c(['communication', 'delegation', 'experiments', 'research-core', 'safety', 'pointers',
   'coding-conventions', 'verify-before-instructing', 'background-jobs',
   'global CLAUDE.md', 'repo CLAUDE.md', 'output-style: yulong',
   'SessionStart: superpowers injection', 'SessionStart: codex-companion help',
   'SessionStart: remember / handoff'], 'Always loaded')
c(['humanizer', 'humanize-draft', 'clear-writing', 'clarity-critic', 'review-draft',
   'narrative-critic', 'red-team', 'fact-checker', 'paper-writer', 'review-paper',
   'application-writer', 'strategic-communication', 'research-presentation'], 'Writing & critics')
c(['interview-me', 'spec-interview', 'spec-interview-research', 'spec-artifact',
   'brainstorming', 'writing-plans', 'executing-plans', 'generate-research-spec'], 'Interview / spec / plan')
c(['artifact-writing', 'results-artifact', 'artifacts-sync', 'check-misreads'], 'Artifacts')
c(['house-plots', 'tufte-data-viz', 'tikz-diagrams', 'fix-slide', 'slidev', 'marp-deck'], 'Plots, diagrams & decks')
c(['agent-browser', 'chrome-devtools', 'claude-in-chrome', 'dev-browser'], 'Browsers')
c(['jobs', 'modal', 'inspect-ai-evals', 'api-experiments', 'experiment-setup',
   'new-experiment', 'run-experiment', 'mats-slurm', 'reproducibility-report',
   'review-transcripts', 'transcript-reviewer', 'data-analyst', 'experiment-designer',
   'autonomous-researcher', 'research-engineer', 'llm-judge', 'server-storage-tiering',
   'performance-optimizer'], 'Experiments & resources')
c(['diagnosing-bugs', 'systematic-debugging', 'debugger', 'test-driven-development',
   'verification-planning', 'verification-before-completion'], 'Debugging & verification')
c(['orchestrate', 'agent-teams', 'custom-compact', 'externalise-handover', 'remember',
   'dispatching-parallel-agents', 'subagent-driven-development', 'task-management',
   'efficient-explorer', 'context-summariser', 'wrap-up', 'recall-feedback'], 'Orchestration & context')
c(['log-gap', 'decide', 'reply', 'chronicle', 'romp', 'things3', 'bear', 'setup-channel',
   'mv-repo', 'catalog', 'sweep-ai-safety', 'llm-billing', 'llm-billing-process',
   'context-fetcher', 'skill-invocation-modes'], 'Personal utilities')
c(['commit', 'commit-push-sync', 'ship', 'merge-worktree', 'using-git-worktrees',
   'finishing-a-development-branch', 'requesting-code-review', 'receiving-code-review',
   'code-reviewer', 'fix-merge-conflict', 'bulk-edit', 'deslop'], 'Git & code review')

# ---------------------------------------------------------------- leans
# ('mark', 'why'). Marks: keep | compress | merge | drop | review
L = {}

L['dotfiles:chronicle'] = ('drop', "Not yours and not Anthropic's — this is an OpenAI **Codex** skill. Its body gates on `$TMPDIR/codex_chronicle/chronicle-started.pid` and on a Codex Developer-Message `## Memories` section that Claude Code never emits, so its own preconditions can never be met here. Dead code: 0 uses, and unrunnable by construction.")
L['dotfiles:romp'] = ('drop', "0 uses. It is break-glass infra docs (reach the romp dashboard over Tailscale when it 404s) — real, but it belongs in the romp repo's README, not in a skill list you pay 77 tok/session for. Nothing is lost that a README would not hold.")
L['dotfiles:marp-deck'] = ('drop', "You asked to delete MARP: agreed. 0 uses, 2,116-tok body. Note the same question applies to `slidev` and `fix-slide` (also 0 uses) — decide the whole deck-tooling cluster at once rather than only this one.")
L['dotfiles:log-gap'] = ('drop', "0 uses across ~3,800 sessions. A one-line gap logger competes with `.remember/` and with memory, both of which you actually use.")
L['dotfiles:decide'] = ('drop', "0 uses. A decision checklist for when you are oscillating — but you have never reached for it, and `interview-me` (41 uses) already covers stress-testing a call.")
L['dotfiles:reply'] = ('drop', "0 uses. `context-fetcher` (6 uses) already front-loads the thread context, which was the hard part.")
L['dotfiles:check-misreads'] = ('review', "**The one to actually decide.** 0 uses, yet cited 3× in always-loaded rules — you pay for the pointer every session and it never fires. Either wire it into a hook so drafts really get red-teamed, or drop the skill *and* the three citations. Half-measures cost tokens for nothing.")
L['dotfiles:second-opinion'] = ('compress', "0 direct uses, but cited 3× in always-loaded rules, and you clearly do get second opinions — via `codex-companion` and `openrouter-cli` directly. The routing knowledge is real; the 3,528-tok body is not. Cut to ~800 tok listing the four routes and when each applies.")
L['dotfiles:artifact-writing'] = ('merge', "0 uses — while the *built-in* `artifact-design` ran **51 times**, the single most-used skill you have. Your custom one is being out-competed by the harness's own. Fold its genuinely unique parts (md2artifact, transcript rendering, the annotation layer) into `results-artifact` and drop the rest.")
L['dotfiles:results-artifact'] = ('edit', "**Promote this into the medium-independent parent.** Most of what it encodes is not about HTML at all -- claim-shaped headers, a figure per claim, numbers in plots rather than prose, intervals and nulls beside every estimate, terms defined on first use, evidence one click from every aggregate. That taste applies identically to a deck, a paper and a research update, but today it is scattered across this skill, `artifact-writing`, `research-presentation`, `review-paper` and `communication.md`. Widen it into `presenting-results`, holding the standard once, with `references/artifact.md`, `references/slides.md` and `references/paper.md` for the per-medium mechanics only. That is the same tiering as the experiments parent, and it matches how your own presentation checklist is already written.")
L['dotfiles:artifacts-sync'] = ('compress', "102-tok description — the most expensive dotfiles skill line — for 2 uses. The description is doing a tutorial's job. Cut it to one clause.")
L['dotfiles:house-plots'] = ('keep', "6 uses, and already the result of merging `pastelplot` + `anthropic-style` yesterday. This is the right home for the plotting standard — make it absorb `tufte-data-viz` rather than competing with it.")
L['viz:tufte-data-viz'] = ('edit', "**Softened from merge.** On reading it, this is not a duplicate: it is a *review* checklist for JS chart libraries (Recharts, ECharts, Chart.js, D3), whereas `house-plots` is already a router that sends artifact pages to the built-in `dataviz` and papers to matplotlib. So it never fires because nothing points at it — fixable without deleting anything. Have `house-plots` link to it and add one rule line so any charting request reaches the router. That is the triggering you asked for. The genuine plotting duplicate is elsewhere: `research/agents/references/anthroplot.md` documents the same `lib/plotting/` package from a stale copy.")
L['viz:tikz-diagrams'] = ('keep', "0 uses, but 14,495 tok of references — all Tier 3, so you pay nothing until it fires. Cheap to keep for paper figures. Only its 31-tok line is a running cost.")
L['dotfiles:agent-browser'] = ('keep', "**Corrected lean.** I first said drop this in favour of the Playwright MCP — wrong: that plugin ships *no* skill or agent at all, only `npx @playwright/mcp@latest` in a `.mcp.json`, so there is no documentation to fall back on. This file already wraps Playwright and is the richest of the four (`@ref` accessibility targeting, profile preflight, real failure modes). Keep it as the programmatic path.")
L['dotfiles:chrome-devtools'] = ('keep', "**Corrected lean, and a pairing you should not break.** `claude-in-chrome`'s own description says *\"For screenshots use chrome-devtools\"* and its body says *\"For DevTools-level inspection (performance, memory), use chrome-devtools instead\"*. These two are one designed unit: keeping `claude-in-chrome` while dropping this one leaves the survivor pointing at nothing. Decide them together -- both, or neither.")
L['dotfiles:claude-in-chrome'] = ('keep', "The live-tab half of a deliberate pair with `chrome-devtools` (it explicitly delegates screenshots and DevTools inspection there). One decision covers both; dropping only its partner breaks it.")
L['dev-browser:dev-browser'] = ('drop', "0 uses, a 95-tok line, and the thinnest content of the four -- roughly 15 lines pointing at `dev-browser --help`. Its one distinctive idea is named daemon-launched browsers with `--idle-timeout`; port that paragraph into `agent-browser` and drop this.")
L['dotfiles:interview-me'] = ('keep', "**60 uses — the most-used skill you own**, once its pre-rename history as `grilling` and its `/grill-me` slash invocations are counted. Your instinct was right: this is the canonical version, and it matches your CLAUDE.md rule verbatim (1-2 rounds, 10-20 questions, the AskUserQuestion mechanic, the Artifact fallback). Fold `spec-interview` and `spec-interview-research` into it as modes.")
L['core:spec-interview'] = ('merge', "6 uses vs `interview-me`'s 60, and decisively stale: it writes to `specs/SPEC.md` — the convention `rules/pointers.md` explicitly abolished (\"There is no `specs/` convention any more\"). Harvest anything useful into `interview-me`, then delete.")
L['research:spec-interview-research'] = ('merge', "4 uses. Its hypotheses/variables/baselines prompts are genuinely research-specific — keep that content as a mode inside `interview-me`, not as a third skill.")
L['dotfiles:spec-artifact'] = ('keep', "1 use, but it owns the *output format* where `interview-me` owns the *elicitation*. Distinct jobs; keep both.")
L['writing:humanizer'] = ('drop', "You asked to delete it: agreed, 0 uses, and it pulls against your ASD-STE100 preference. **But it is not a clean delete** — it is one of `review-draft`'s five default critics and is referenced by `plugins/writing/README.md`, `test-corpus/README.md`, and `patterns/llm-isms-v0.1.json`. Remove it from `review-draft`'s `--critics=` default list and critic table in the same pass, or a bare `/review-draft` will dispatch a missing agent.")
L['writing:humanize-draft'] = ('drop', "0 uses, and **its own description already says `DEPRECATED: Use /review-draft --critics=humanizer instead`**. It is a tombstone still costing 34 tok/session.")
L['writing:clear-writing'] = ('compress', "2 uses — the only writing skill with any. Keep it as the style reference, but 1,775 tok overlaps heavily with `communication.md`, which is always loaded. Cut the overlap.")
L['writing:clarity-critic'] = ('keep', "0 uses, but it is the critic agent `review-draft` dispatches. Keep it and drop the humanizer sibling; do not point one at the other — they are a pipeline, not duplicates.")
L['core:fast-cli'] = ('drop', "0 uses, and `coding-conventions.md` (always loaded) already lists the same tools. You asked whether it reflects best practice — the deeper problem is that it duplicates a rule you already pay for. Keep the rule's list, drop the skill.")
L['workflow:agent-teams'] = ('drop', "0 uses. `delegation.md` is always loaded and covers dispatch; the Agent tool covers the rest. This never earned its 47 tok.")
L['workflow:custom-compact'] = ('drop', "0 uses, 149-tok body. Built-in compaction plus `/remember` cover it.")
L['workflow:externalise-handover'] = ('review', "**Revised up from drop.** Counting only the `\"skill\"` shape showed 1 use; counting slash invocations too shows **6** — you reach for it as `/externalise-handover`. Still a third mechanism for a job `remember` plus the SessionStart handoff block already do, so the consolidation case stands, but this is a used tool, not dead weight. Decide it deliberately.")
L['core:orchestrate'] = ('drop', "0 uses. `delegation.md` is always loaded and says the same thing; a skill that restates an always-loaded rule is pure duplication.")
L['code:performance-optimizer'] = ('merge', "0 uses and a 115-tok line. Its async/batching/GPU content is exactly the resource-awareness material you want consolidated — move it into the experiments reference set rather than keeping a standalone agent.")
L['dotfiles:server-storage-tiering'] = ('merge', "1 use. You asked whether it still makes sense — the *content* does (it encodes a real disk incident), the *standalone skill* does not. Fold into `jobs` as the disk section of one resource-awareness reference.")
L['research:api-experiments'] = ('merge', "0 uses, and the absorb direction is proven by its own text: it points at `~/.claude/docs/experiment-memory-optimization.md`, and that document already lives in dotfiles at `claude/skills/jobs/references/experiment-memory-optimization.md` (315 lines, the RunPod OOM incident, same numbers). The plugin skill is a summary of a dotfiles reference. Fold it into the experiments parent as `references/api-fanout.md`.")
L['dotfiles:jobs'] = ('keep', "2 uses, and it owns queueing and cgroup caps — the thing that stops the box OOMing. Make it the home for the consolidated resource-awareness reference (CPU/RAM/disk/rate limits).")
L['dotfiles:inspect-ai-evals'] = ('merge', "0 uses. Provider-specific eval failure modes — becomes `references/inspect-vllm.md` under the experiments parent.")
L['research:run-experiment'] = ('merge', "1 use. Best candidate to *become* the tiered parent skill, absorbing `api-experiments`, `experiment-setup`, `new-experiment` and the provider references.")
L['research:experiment-setup'] = ('merge', "0 uses. Hydra + Inspect setup is a reference, not a skill.")
L['research:new-experiment'] = ('merge', "0 uses. A template action; belongs inside the experiments parent.")
L['dotfiles:diagnosing-bugs'] = ('keep', "**39 uses.** Genuinely load-bearing. Overlaps `superpowers:systematic-debugging` (25) and the `code:debugger` agent (84) — but all three are heavily used, so this is role confusion, not dead weight. Write one line saying which leads.")
L['superpowers:systematic-debugging'] = ('keep', "25 uses. Real overlap with `diagnosing-bugs` (39), but both are used enough that deleting either would hurt. Clarify precedence instead.")
L['hookify:conversation-analyzer'] = ('compress', "**206-tok description — the single most expensive component line you have** — for 0 uses. Whatever this stays or goes, that description must shrink.")
L['research:read-paper'] = ('compress', "140-tok line, 0 uses. The skill is worth keeping for literature work; the description is three times longer than it needs to be.")
L['superpowers:using-superpowers'] = ('review', "0 uses as a *skill*, but it is injected **verbatim into every session** by a SessionStart hook — ~777 tok, the largest single non-dotfiles fixed cost, and it appears in no skill accounting. Decide deliberately whether that block earns its place every session.")
L['research:audit-docs'] = ('move', "**Your comment, and I agree on both halves.** Documentation hygiene is not research, so it sits in the wrong plugin — nothing about it is specific to experiments. It also raises the general question you asked: *how* is it meant to fire? It has 0 uses because nothing triggers it and nothing schedules it. Skills split into three invocation modes — model-triggered by description, manually invoked by name, and scheduled — and only the first is ever stated. A skill that is really a periodic chore should say so in its own description, or be a cron entry rather than a skill.")
L['writing:application-writer'] = ('edit', "**Your comments, and one of them is a correctness bug.** *(1)* It asserts organisation values as fact — \"AISI = empirical, Anthropic = thoughtful\" — which are invented, not sourced. A skill that hands you fabricated claims about the organisation you are applying to is worse than no skill. Cut them. *(2)* 3,267 tok of body for 0 uses, most of it scaffolding. *(3)* Its objective is wrong: it optimises for \"authentic voice\" where you want clarity, demonstrated skill, depth of understanding and thoughtfulness — say that instead. *(4)* It reads past applications and CV as fixed context, but your research interests and situation move between applications; it should ask for current context at the start and write anything durable back to `CLAUDE.md` rather than inferring it from stale drafts.")
L['research:openrouter-fusion'] = ('move', "5 uses — genuinely used, and correctly built. But multi-model routing is infrastructure you reach for in any kind of work, not a research method; sitting in the research plugin hides it. Moving costs nothing and saves nothing — it is purely about being findable from the right place.")
L['dotfiles:llm-judge'] = ('move', "0 uses, but this is research methodology (blinding, fan-out, judge construction) living in dotfiles while the research plugin is the natural home. Cross-links from `results-artifact` should follow it.")
L['dotfiles:check-bib-references'] = ('move', "0 uses, 80-tok line. Catching fabricated citations is paper work; it belongs beside `read-paper` and `review-paper` in the research plugin rather than in general dotfiles.")
L['dotfiles:sweep-ai-safety'] = ('move', "0 uses. A literature sweep is research, and it would sit naturally next to `read-paper` and `literature-scout`. Same invocation question as `audit-docs`: this is really a periodic chore, so decide whether it is a skill you call or a scheduled task.")
L['writing:research-presentation'] = ('merge', "1 use. Deck structure -- summary slide, agenda, setup before results, backup slides -- is the slides half of one presentation standard, not a separate discipline. Its medium-independent half (lead with the decision-relevant result, one message per slide, show the prompt) is already stated elsewhere in different words. Becomes `presenting-results/references/slides.md`.")
L['writing:review-paper'] = ('keep', "0 uses, but paper review against Neel Nanda's criteria is a real and "
  "distinct job. Keep it, and have it cite the `presenting-results` parent for the shared standard rather than "
  "restating claim-shaped headers and figure-per-claim in its own words.")
L['dotfiles:catalog'] = ('keep', "0 uses but only 3 tok — the cheapest line you own, and it is the index the other skills point at. Nothing to gain by cutting.")
L['dotfiles:llm-billing-process'] = ('keep', "6 tok. Below the noise floor; not worth a decision.")

# always-loaded prose
L['dotfiles:repo CLAUDE.md'] = ('compress', "**2,739 tok — the single largest thing in your context, every session.** Much of it is reference material (worktree command tables, deploy-component pointers) that a skill could hold and load on demand. Target ~1,200 tok: keep the top rules and the Learnings, move the tables out.")
L['dotfiles:global CLAUDE.md'] = ('compress', "1,779 tok, every session. Second largest. The AI-safety-context and where-things-live sections are stable background that rarely changes a decision mid-task — strong candidates to demote into a skill.")
L['dotfiles:pointers'] = ('review', "516 tok whose entire job is pointing at skills — and four of the skills it points at (`check-misreads`, `second-opinion`, `artifact-writing`, `fast-cli`) have **zero invocations**. The index is costing more than the things it indexes return.")
L['dotfiles:communication'] = ('compress', "677 tok, the largest rule. Overlaps `writing:clear-writing`. Since this one is always loaded and that one is not, keep the judgment here and cut the duplicated style guidance there.")
L['dotfiles:experiments'] = ('keep', "676 tok, but it is the rule that most directly prevents expensive mistakes (pilot gates, spend gates, resource profile). Earns its place.")
L['dotfiles:delegation'] = ('keep', "569 tok and it is doing real work — it is why subagents get briefed properly. Also the reason `orchestrate` and `agent-teams` are redundant.")
L['dotfiles:safety'] = ('keep', "562 tok covering irreversible actions and supply chain. Never cut safety rails to save tokens.")
L['dotfiles:research-core'] = ('keep', "569 tok encoding your research-integrity standard. This is taste you cannot reconstruct; keep it always-loaded.")
L['dotfiles:coding-conventions'] = ('compress', "478 tok. Contains the CLI tool list that `fast-cli` duplicates — keep the list here and drop the skill.")
L['dotfiles:background-jobs'] = ('keep', "193 tok and load-bearing for exactly this session type.")
L['dotfiles:verify-before-instructing'] = ('keep', "211 tok. Cheap, and it is the rule that catches confident wrongness.")

# ---- from the review comments (the user's calls, not mine) ----
L['research:autonomous-researcher'] = ('edit', "**Misnamed, and under-powered.** What this actually is: a *persistent* agent optimising one metric -- autoresearch -- and the name should say so. Two changes beyond the rename. It should **fan out to subagents** to try and brainstorm competing ideas rather than pursuing one line alone, which is the whole advantage of an overnight run. And its *\"Never ask the human anything\"* instruction needs resolving: if a human starts it, that rule is right; if an agent does, nothing ever surfaces a bad assumption. Say which. Simpler than it is today.")
L['dotfiles:bear'] = ('edit', "Its Bear-flavoured Markdown section omits **wikilinks**, which is how the vault actually cross-references. Add them.")
L['code:bulk-edit'] = ('edit', "0 uses. Keep it only if it does the two things actually wanted: **extract comments from a PDF or Markdown document**, and **apply edits in parallel without conflicts or concurrency bugs**. If it does neither well, it is a wrapper around sequential agents and should go.")
L['dotfiles:check-misreads'] = ('edit', "**Renamed, compressed, and grounded -- not dropped.** The job is real but the name hides it: this is `writing:reduce-ambiguity`. The skill itself is fluffy, so rewrite it against published guidance on ambiguity in technical writing rather than invented criteria, and cut it hard. Recently introduced, which is why usage is 0; that is not evidence against it yet. The three always-loaded citations only earn their keep once it actually fires.")
L['dotfiles:check-prose-claims'] = ('edit', "**A correctness bug plus bloat.** Its verification table calls rounding an error -- 96.555% quoted as 97%, 96.6% or 0.83 are all flagged Numerical Error. Rounding is normal and correct; only a *wrong* value, direction or magnitude is a finding. Fix the table, then compress: the skill is far longer than the job.")
L['core:context-summariser'] = ('edit', "0 uses, and its output shape is unstated. Fix it to four questions: **what are the main claims; what are we trying to answer or do; where is the uncertainty; what are the next steps.** That is a summary worth reading; a narrative recap is not.")
L['code:deslop'] = ('keep', "Code-only, and that is fine -- but it leaves a gap. There is **no writing equivalent**: cutting fluff and tightening prose has no skill, while `clear-writing` is a style reference rather than an editing pass. Worth adding as a sibling.")
L['workflow:externalise-handover'] = ('merge', "**Duplication confirmed by inspection.** It overlaps `wrap-up`, `catch-me-up` and the `remember` plugin, which all move session state across a boundary. It also hardcodes an `.md` file as the output, where an Artifact is often the right destination -- the format should follow the content. Consolidate the four into one, and let the destination be a choice.")
L['writing:fix-slide'] = ('edit', "Named as if it were general; it is **Slidev-specific**. Rename to say so (`fix-slidev-slide`), or widen it to cover the deck tooling actually in use. A name that overclaims is why the right skill does not fire.")
L['research:generate-research-spec'] = ('drop', "Drop it -- it writes to the retired `specs/` convention. **Keep the idea underneath, though**: a way to ask the user where the project actually stands and write that into `CLAUDE.md`. That belongs in `interview-me` as a project-state mode, not in a spec generator.")
L['dotfiles:mv-repo'] = ('edit', "0 uses because nothing triggers it: the description should fire on plain phrasing like *move this repo from A to B*. Two gaps in what it does, both silent data hazards -- it should **update symlinks into and out of vaults and other directories**, and **check whether the move invalidates cache keys, warning before it does** rather than after.")
L['dotfiles:pointers'] = ('drop', "**Your call: drop.** 516 tok every session whose whole job is pointing at skills, four of which have never fired. Fold the handful of pointers that earn their place into the skills that need them, and delete the index.")
L['dotfiles:recall-feedback'] = ('drop', "**Your question was the answer.** 0 uses, and neither of us can say what it is for. Spaced repetition over feedback memories is a mechanism in search of a need.")
L['research:reflect'] = ('edit', "**Wrong direction of authority.** It auto-writes learnings into a journal. It should instead **ask probing questions and propose candidate learnings, and you decide** what is kept, changed or thrown away -- including all of it. Nothing writes to durable memory unprompted.")
L['research:reproducibility-report'] = ('edit', "Hardcodes a project layout -- `src/configs/`, `.hydra/`, `out/*/`, `.cache/`. That fits one repo and silently finds nothing in the others. Discover the layout or ask; do not assume it.")
L['writing:review-draft'] = ('edit', "Keep the dispatcher, but **drop `humanizer` from the default critic list** in the same pass as deleting the agent, or a bare `/review-draft` dispatches something that no longer exists.")
L['research:review-transcripts'] = ('merge', "0 uses, and it re-implements what `llm-judge` already owns: fan-out of many parallel model calls over samples, with persistence. **One mechanism, two entry points** -- transcript review becomes a caller of the judge machinery rather than a second copy of it.")
L['writing:strategic-communication'] = ('edit', "Keep the tactical-empathy core, but it is missing the simplest move it teaches around: **naming your own state** -- *I am sensing X*, *I am feeling Y*. That is often more honest and more effective than labelling the other side's emotion, and the skill currently omits it.")
L['core:task-management'] = ('drop', "0 uses, 1,995-tok body. Timestamped task lists and agent-ID tracking are what the harness's own task tools now do. Nothing here is load-bearing any more.")
L['dotfiles:house-plots'] = ('edit', "**Sharpen the escalation rule.** It currently says numbers in prose can be a table and numbers in a table can be a plot, which reads as a ladder you may stop climbing. The rule is simpler: **numbers go in plots -- not prose, not tables.** Prose and captions say how to read the plot. Hyperparameters are the exception.")
L['dotfiles:results-artifact'] = ('edit', "**Promote this into the medium-independent parent, and take the name out of it.** Its description reads *to Yulong's review standard* -- a personal name in Tier-1 text that says nothing to a reader and nothing to the model. Beyond that: most of what it encodes is not about HTML at all -- claim-shaped headers, a figure per claim, numbers in plots rather than prose or tables, intervals and nulls beside every estimate, terms defined on first use, evidence one click from every aggregate. That taste applies identically to a deck, a paper, a website and a research update, but today it is scattered across this skill, `artifact-writing`, `research-presentation`, `review-paper` and `communication.md`. Widen it into `presenting-results`, holding the standard once, with per-medium references for the mechanics only.")
L['viz:tufte-data-viz'] = ('edit', "**Scope is too narrow on both axes.** It lists libraries (Recharts, ECharts, Chart.js, matplotlib, Plotly, seaborn, D3, SVG) as if the standard were a property of the tool; and it is filed as chart-generation guidance when it should govern **presenting data anywhere** -- papers, websites, Markdown files, artifacts, slides. Rewrite the scope line to name the job, not the toolchain, then have `house-plots` route to it. That is also why it never fires: nothing points at it, and its own description describes a library list.")

CLUSTER_ORDER = ['Always loaded', 'Artifacts', 'Interview / spec / plan', 'Plots, diagrams & decks',
                 'Experiments & resources', 'Writing & critics', 'Browsers', 'Orchestration & context',
                 'Debugging & verification', 'Git & code review', 'Personal utilities', 'Other']

# ---------------------------------------------------------------- rows
SESSION_INJECTIONS = [
    {'name': 'SessionStart: superpowers injection', 'kind': 'inject', 'plugin': 'superpowers',
     'source': 'claude-plugins-official', 'enabled': True, 'uses': None,
     'desc': 'The full using-superpowers SKILL.md, injected verbatim into every session by a SessionStart hook.',
     'fm_tokens': 777, 'body_tokens': 777, 'ref_tokens': 0, 'ref_files': [],
     'path': '/home/yulong/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/using-superpowers/SKILL.md',
     'edit_path': '', 'body': 'Injected by a SessionStart hook, not by the skill system. Measured at ~777 tok from the file on disk. It does not appear in any skill list, so it is invisible to normal accounting.'},
    {'name': 'SessionStart: codex-companion help', 'kind': 'inject', 'plugin': 'codex',
     'source': 'codex-plugin-cc', 'enabled': True, 'uses': None,
     'desc': 'Full codex-companion CLI help text, injected every session.',
     'fm_tokens': 450, 'body_tokens': 450, 'ref_tokens': 0, 'ref_files': [], 'path': '(SessionStart hook)',
     'edit_path': '', 'body': 'The complete subcommand help for codex-companion, printed into context at every session start. Estimated ~450 tok from the injected block. A one-line pointer plus `codex-companion help` on demand would cost almost nothing.'},
    {'name': 'SessionStart: remember / handoff', 'kind': 'inject', 'plugin': 'remember',
     'source': 'claude-plugins-official', 'enabled': True, 'uses': None,
     'desc': 'Handoff block plus now/today/recent/archive memory excerpts.',
     'fm_tokens': 700, 'body_tokens': 700, 'ref_tokens': 0, 'ref_files': [], 'path': '~/.remember/',
     'edit_path': '', 'body': 'The last-handoff notice plus rolling memory excerpts. The archive section carries weeks of history whose value decays fast; the note in this session said the handoff had "already been delivered 525 times".'},
]

# Merge destinations. A chip reading "merge" without naming a target is not a
# decision the reader can act on, so every merge row says what it folds into.
INTO = {
    'dotfiles:artifact-writing': 'results-artifact',
    'core:spec-interview': 'interview-me',
    'research:spec-interview-research': 'interview-me',
    'dotfiles:server-storage-tiering': 'jobs (disk section)',
    'code:performance-optimizer': 'experiments / resource-budgets',
    'research:api-experiments': 'experiments / api-fanout',
    'dotfiles:inspect-ai-evals': 'experiments / inspect',
    'research:experiment-setup': 'experiments parent',
    'research:new-experiment': 'experiments / records',
    'research:run-experiment': 'becomes the experiments parent',
    'research:mats-slurm': 'experiments / slurm',
    'dotfiles:modal': 'experiments / modal',
    # move destinations -- same field, different meaning: the content is right,
    # the home is wrong. A move saves no tokens; it buys findability.
    'research:audit-docs': 'core (not research)',
    'research:openrouter-fusion': 'core (model routing is infrastructure)',
    'dotfiles:llm-judge': 'research plugin',
    'dotfiles:check-bib-references': 'research plugin',
    'dotfiles:sweep-ai-safety': 'research plugin',
    'dotfiles:inspect-ai-evals': 'experiments / inspect',
}

rows = []
for r in inv + SESSION_INJECTIONS:
    if not r.get('enabled'):
        continue
    key = f"{r['plugin']}:{r['name']}"
    lean, why = L.get(key, (None, None))
    auto = lean is None
    if auto:
        u = r.get('uses')
        if r.get('user_invoked'):
            lean, why = 'keep', ("**User-invoked** (`disable-model-invocation: true`), so its description is "
                                 "stripped from the model's reach: it costs **0 Tier-1 tokens** and the agent "
                                 "cannot fire it. Its 0 uses mean the audit cannot see hand-typed invocations, "
                                 "not that it is dead. Nothing to reclaim here.")
            auto = False
        elif u is None:
            lean, why = 'keep', 'Always loaded; not individually invoked.'
        elif u >= 10:
            lean, why = 'keep', f"Heavily used ({u} invocations). Auto-classified — not individually reviewed."
        elif u >= 1:
            lean, why = 'keep', f"Used {u}×. Auto-classified — not individually reviewed."
        else:
            lean, why = 'review', "0 invocations. Auto-classified — not individually reviewed; worth a look."
    rows.append({
        'n': r['name'], 'k': r['kind'], 'p': r['plugin'], 's': r['source'],
        'u': r.get('uses'), 't1': r['fm_tokens'], 't2': r['body_tokens'], 't3': r['ref_tokens'],
        'd': r['desc'], 'path': r['path'], 'edit': r.get('edit_path') or '',
        'body': r['body'], 'refs': r.get('ref_files', []),
        'lean': lean, 'why': why, 'auto': auto,
        'manual': bool(r.get('user_invoked')),
        'into': INTO.get(key, ''),
        'cl': CLUSTER.get(r['name'], 'Other'),
    })

# unique Tier-3: several agents in one plugin share a references/ dir, so per-row
# ref tokens double-count. Compute the true unique total.
seen_ref, uniq_ref = set(), 0
for r in rows:
    for f in r['refs']:
        k = (r['p'], f['f'])
        if k not in seen_ref:
            seen_ref.add(k)
            uniq_ref += f['t']

meta = {
    'tier1_prose': sum(r['t1'] for r in rows if r['k'] in ('rule', 'always')),
    'tier1_desc': sum(r['t1'] for r in rows if r['k'] in ('skill', 'agent')),
    'tier1_inject': sum(r['t1'] for r in rows if r['k'] == 'inject'),
    'tier2': sum(r['t2'] for r in rows if r['k'] in ('skill', 'agent')),
    'tier3': uniq_ref,
    'n': len(rows),
    'nzero': sum(1 for r in rows if r['u'] == 0),
    'disabled': sum(1 for r in inv if not r['enabled']),
    'disabled_tok': sum(r['body_tokens'] for r in inv if not r['enabled']),
}
meta['tier1'] = meta['tier1_prose'] + meta['tier1_desc'] + meta['tier1_inject']

rows.sort(key=lambda r: (CLUSTER_ORDER.index(r['cl']) if r['cl'] in CLUSTER_ORDER else 99, -r['t1']))

payload = json.dumps({'rows': rows, 'meta': meta}, ensure_ascii=True)
print('rows:', len(rows), 'payload MB:', round(len(payload) / 1e6, 2))
print(json.dumps(meta, indent=1))
(OUT / 'payload.json').write_text(payload)
