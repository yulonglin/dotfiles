---
name: spec-loop
description: Run a spec through the plan → implement → test → run → analyze loop with cross-model review between phases
disable-model-invocation: true
---

# spec-loop

Drive one spec through five phases — plan, implement, test, run, analyze — with an independent doer agent per phase and a cross-model review after each phase. Reviewer findings are injected into the next phase's prompt and must each receive a disposition; findings never hard-block the loop. Spec defects surfaced along the way become proposed spec amendments in the final report, never silent divergence.

**Argument: the spec path.** If no spec path was given, refuse politely and ask for one — spec-first is the point of this skill; do not improvise a spec from conversation.

## Before the loop: refinement

If the input spec is a rough draft rather than a settled spec, run the refinement pipeline first, in order, using the prompts in `prompts/` verbatim (each file is a sha256-guarded verbatim import plus a delimited addendum): `write-spec.md` (produce a spec, plan-only), `clean-spec.md` (cut noise), `improve-spec.md` (six-dimension review and revision). The result must use the five-section template from `~/.claude/rules/spec-conventions.md`: Goal / Context / Requirements / Acceptance criteria / Out of scope. Interviews follow `~/.claude/rules/interview-conventions.md`.

## Launching the loop

Launch the Workflow tool with the template below, adapted to the spec: fill in the per-phase briefs from the spec's Requirements — each brief MUST name which predecessor artifacts the phase consumes — and pass configuration via `args`, never hardcoded into the script. The harness may deliver `args` to the script as a JSON-encoded string rather than an object (observed live 2026-08-09: `args.reviewer` read as `undefined` and string interpolation silently produced `"Spec: undefined"`), so the template's first line parses defensively into `cfg` — keep that line, and reference `cfg.*`, never `args.*`:

- `args.specPath` — the spec file.
- `args.timestamp` — an ISO timestamp from the session (`Date.now()` is unavailable inside Workflow scripts).
- `args.reviewer` — the reviewer channel as command templates, e.g. `{ "plan": "codex-companion plan-review <planFile> [--resume]", "diff": "codex-companion adversarial-review", "task": "codex-companion task <prompt>" }`. The reviewer is injected config so a future channel cutover (e.g. a model-router-backed reviewer) changes only the args. Reviewer agents MUST start the command via the Monitor tool (the CLI's own contract — never detached, never bare Bash), wait for a terminal status, fetch the result, and report `terminalStatus`, `outputPresent`, and a `resultSummary` truthfully — the script rejects a review whose command did not verifiably succeed with output, so a failed reviewer can never pass as an empty-findings review.

```js
export const meta = {
  name: 'spec-loop',
  description: 'Drive a spec through plan/implement/test/run/analyze with cross-model review after each phase',
  phases: [
    { title: 'Plan' }, { title: 'Implement' }, { title: 'Test' },
    { title: 'Run' }, { title: 'Analyze' }, { title: 'Finalize' },
  ],
}

// The harness can deliver `args` as a JSON-encoded string — parse defensively.
const cfg = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// findingDispositions[].finding is the stable finding id assigned by this
// script (e.g. "Plan-R2") — dispositions merge into the ledger by that id.
const DISPOSITIONS_SCHEMA = { type: 'array', items: {
  type: 'object', required: ['finding', 'disposition', 'rationale'],
  properties: { finding: { type: 'string' },
    disposition: { enum: ['addressed', 'rebutted', 'deferred'] },
    rationale: { type: 'string' } } } }

const DOER_SCHEMA = {
  type: 'object',
  required: ['status', 'artifacts', 'amendments', 'findingDispositions', 'evidence'],
  properties: {
    status: { enum: ['ok', 'partial', 'failed'] },
    artifacts: { type: 'array', items: { type: 'string' } },
    amendments: { type: 'array', items: { type: 'string' } },
    findingDispositions: DISPOSITIONS_SCHEMA,
    evidence: { type: 'string' },
  },
}

const REVIEWER_SCHEMA = {
  type: 'object',
  required: ['status', 'terminalStatus', 'outputPresent', 'resultSummary', 'findings'],
  properties: {
    status: { enum: ['ok', 'failed'] },
    terminalStatus: { type: 'string' },   // the Monitor job's terminal status, verbatim
    outputPresent: { type: 'boolean' },   // was reviewer output actually fetched?
    resultSummary: { type: 'string' },
    findings: { type: 'array', items: {
      type: 'object', required: ['severity', 'summary', 'action'],
      properties: { severity: { enum: ['P0', 'P1', 'P2'] },
        summary: { type: 'string' }, action: { type: 'string' } } } },
  },
}

const FINALIZE_SCHEMA = {
  type: 'object',
  required: ['status', 'report', 'findingDispositions'],
  properties: {
    status: { enum: ['ok', 'failed'] },
    report: { type: 'string' },
    findingDispositions: DISPOSITIONS_SCHEMA,
  },
}

let lastFailure = null

// Schema-validation exhaustion REJECTS the agent() promise (it does not
// return null), so every attempt is caught.
async function attempt(prompt, opts) {
  try { return { value: await agent(prompt, opts) } }
  catch (e) { return { error: String(e) } }
}

// Retry-once-then-abort: rejection, null return (killed/API-dead agent),
// status "failed", or a `validate` defect all count as a failed attempt.
// "Findings never hard-block" covers reviewer findings, not phase failure.
async function runOnce(prompt, opts, validate) {
  let why = null
  for (let i = 0; i < 2; i++) {
    const p = i ? `${prompt}\n\n(Retry: the previous attempt failed: ${why})` : prompt
    const a = await attempt(p, opts)
    why = a.error ?? (!a.value ? 'null result (agent killed or API-dead)'
      : a.value.status === 'failed' ? 'agent reported status "failed"'
      : (validate ? validate(a.value) : null))
    if (!why) return a.value
    log(`${opts.label}: ${why}${i ? '' : ' — retrying once'}`)
  }
  lastFailure = `${opts.label}: ${why}`
  return null
}

const ledger = []        // every reviewer finding, stable id, disposition merged in place
const amendments = []    // accumulated by the SCRIPT from agent returns —
const phaseOutcomes = [] // a subagent cannot mutate script state itself
let carried = []         // ledger entries awaiting disposition in the next phase
let prev = null          // previous doer outcome — the phase handoff

const findingsBlock = () => carried.length
  ? carried.map(f => `- ${f.id} [${f.severity}] ${f.summary} — suggested action: ${f.action}`).join('\n')
  : 'None.'
const handoffBlock = () => prev
  ? `Previous phase ${prev.phase} finished with status "${prev.status}". Artifacts you MUST consume: ${prev.artifacts.join(', ') || 'none'}. Evidence: ${prev.evidence}`
  : 'None — this is the first phase.'
// Exactly one disposition per carried id: duplicates and ids from earlier
// phases are rejected — settled ledger dispositions are immutable.
const coverage = (r) => {
  const ids = r.findingDispositions.map(d => d.finding)
  const expected = new Set(carried.map(f => f.id))
  const dup = [...new Set(ids.filter((id, i) => ids.indexOf(id) !== i))]
  if (dup.length) return `duplicate findingDispositions for: ${dup.join(', ')}`
  const extra = ids.filter(id => !expected.has(id))
  if (extra.length) return `findingDispositions for ids not carried into this phase: ${extra.join(', ')} — settled dispositions are immutable`
  const gap = [...expected].filter(id => !ids.includes(id))
  return gap.length ? `findingDispositions missing for: ${gap.join(', ')}` : null
}
// Merge scope is `carried` only (the same objects live in the ledger, so the
// ledger entry updates in place) — never the full ledger.
const mergeDispositions = (r) => {
  for (const d of r.findingDispositions) {
    const f = carried.find(x => x.id === d.finding)
    if (f) f.disposition = { disposition: d.disposition, rationale: d.rationale }
  }
}
const abort = (phase) => ({ status: 'aborted', failedPhase: phase, reason: lastFailure, phaseOutcomes, amendments, ledger })

// Fill each brief from the spec at launch time, naming the predecessor
// artifacts the phase consumes. The Analyze brief must include: verify every
// acceptance criterion one by one; compile the draft report (per-phase
// outcomes, every ledger finding with its disposition, proposed amendments).
const PHASES = [
  { name: 'Plan',      brief: '<plan-phase brief>',      review: 'plan' },
  { name: 'Implement', brief: '<implement-phase brief>', review: 'diff' },
  { name: 'Test',      brief: '<test-phase brief>',      review: 'diff' },
  { name: 'Run',       brief: '<run-phase brief>',       review: 'task' },
  { name: 'Analyze',   brief: '<analyze-phase brief>',   review: 'task', audit: true },
]

for (const ph of PHASES) {
  const doer = await runOnce(
    `Spec: ${cfg.specPath}. Phase: ${ph.name}. ${ph.brief}\n\n` +
    `Handoff from the previous phase:\n${handoffBlock()}\n\n` +
    (ph.audit ? `Full audit trail for the report:\nphaseOutcomes: ${JSON.stringify(phaseOutcomes)}\nfindings ledger: ${JSON.stringify(ledger)}\n\n` : '') +
    `Reviewer findings you must address or explicitly rebut — findingDispositions MUST cover every id below:\n${findingsBlock()}\n\n` +
    `Accumulated proposed spec amendments:\n${amendments.join('\n') || 'None.'}\n\n` +
    `If a finding or discovery reveals a defect in the spec itself, do not silently diverge — return it in amendments.`,
    { label: `${ph.name}:do`, phase: ph.name, schema: DOER_SCHEMA }, coverage)
  if (!doer) return abort(ph.name)
  mergeDispositions(doer)
  amendments.push(...doer.amendments)
  phaseOutcomes.push({ phase: ph.name, status: doer.status, artifacts: doer.artifacts, evidence: doer.evidence })
  prev = { phase: ph.name, ...doer }

  const rev = await runOnce(
    `Review the ${ph.name} phase output for spec ${cfg.specPath} (artifacts: ${doer.artifacts.join(', ') || 'none'}).\n` +
    `Run this reviewer command via the MONITOR tool (never detached, never bare Bash): ${cfg.reviewer[ph.review]}\n` +
    `Wait for a terminal status, fetch the result, and report terminalStatus, outputPresent, and resultSummary truthfully. A terminal status other than success/completed, or missing output, is status "failed" — NEVER an empty findings list.`,
    { label: `${ph.name}:review`, phase: ph.name, schema: REVIEWER_SCHEMA },
    // codex-companion's terminal success status is "completed", not "success"
    // (observed live 2026-08-09 — hard-coding 'success' aborted a real run).
    r => !['success', 'completed'].includes(r.terminalStatus) ? `reviewer terminalStatus "${r.terminalStatus}" is not success/completed`
      : !r.outputPresent ? 'reviewer output missing — cannot count as an empty-findings review' : null)
  if (!rev) return abort(`${ph.name}:review`)
  carried = rev.findings.map((f, i) => ({ id: `${ph.name}-R${i + 1}`, phase: ph.name, ...f }))
  ledger.push(...carried)   // the single append — dispositions merge into these entries
}

// Finalize: the Analyze reviewer's findings have no later phase to land in,
// so a finalize step incorporates them into the report itself.
phase('Finalize')
const fin = await runOnce(
  `Finalize the spec-loop report for ${cfg.specPath} (run started ${cfg.timestamp}).\n` +
  `Draft report from the Analyze phase — artifacts: ${prev.artifacts.join(', ') || 'none'}; evidence: ${prev.evidence}\n` +
  `Full audit trail — the report MUST include per-phase outcomes, every ledger finding with its disposition, and all proposed spec amendments:\n` +
  `phaseOutcomes: ${JSON.stringify(phaseOutcomes)}\nfindings ledger: ${JSON.stringify(ledger)}\namendments: ${amendments.join('; ') || 'None.'}\n` +
  `Analyze-review findings to incorporate — findingDispositions MUST cover every id below, and the report must reflect them:\n${findingsBlock()}\n` +
  `Return the finished report as the "report" field.`,
  { label: 'finalize', phase: 'Finalize', schema: FINALIZE_SCHEMA }, coverage)
if (!fin) return abort('Finalize')
mergeDispositions(fin)

return { status: 'ok', report: fin.report, phaseOutcomes, amendments, ledger }
```

## After the workflow returns

Publish the finalized `report` as a claude.ai Artifact (Artifact tool) and give the user the URL. The feedback channel is the manual copy-as-prompt round-trip back into a session — Artifacts have no native comment surface; if the driving spec assumed one, record that as a proposed spec amendment in the report rather than building a comment sink.

If the run aborted (`status: "aborted"`), publish the partial report the same way, stating plainly which phase failed and the recorded `reason`.

## Resumability

Every Workflow invocation persists its script and returns a `runId` and `scriptPath`. If the run is killed or interrupted: stop the prior run if needed (TaskStop), then relaunch with `Workflow({scriptPath, resumeFromRunId})` — completed phases replay from the journal, and the first incomplete agent call runs live. The script must never call `Date.now()`, `Math.random()`, or argless `new Date()` (they break resume); timestamps come in via `args.timestamp`.
