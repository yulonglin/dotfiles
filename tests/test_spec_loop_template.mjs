#!/usr/bin/env node
// Mock-runtime tests for the Workflow template embedded in
// claude/skills/spec-loop/SKILL.md. Extracts the ```js fence and executes it
// against stubbed agent/log/phase/args, covering the failure contracts Codex
// review demanded: thrown agent rejection, null return, explicit
// status:"failed", reviewer missing output, duplicate disposition ids, and
// attempted rewrites of settled (historical) dispositions.
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const skill = readFileSync(join(ROOT, 'claude/skills/spec-loop/SKILL.md'), 'utf8')
const fence = skill.match(/```js\n([\s\S]*?)```/)
if (!fence) { console.error('FAIL - no ```js fence found in SKILL.md'); process.exit(1) }
const src = fence[1].replace('export const meta', 'const meta')

let pass = 0, fail = 0
const ok = (d) => { pass++; console.log(`ok   - ${d}`) }
const bad = (d, extra = '') => { fail++; console.log(`FAIL - ${d}${extra ? ` (${extra})` : ''}`) }
const check = (cond, d, extra = '') => (cond ? ok(d) : bad(d, extra))

// The template renders carried findings as "- <id> [<sev>] ..." under a
// "MUST cover every id below" header; parse the ids a doer must disposition.
function idsFromPrompt(prompt) {
  const m = prompt.match(/MUST cover every id below[^\n]*\n([\s\S]*?)(\n\n|$)/)
  return m ? [...m[1].matchAll(/^- ([A-Za-z]+-R\d+) \[/gm)].map(x => x[1]) : []
}

const dispose = (prompt, disposition = 'addressed') =>
  idsFromPrompt(prompt).map(id => ({ finding: id, disposition, rationale: `handled ${id}` }))

const doerOk = (prompt, opts) => ({
  status: 'ok',
  artifacts: [`${opts.label.split(':')[0].toLowerCase()}.out`],
  amendments: [],
  findingDispositions: dispose(prompt),
  evidence: `evidence from ${opts.label}`,
})
const finalizeOk = (prompt) => ({
  status: 'ok', report: 'final report text', findingDispositions: dispose(prompt),
})
const reviewerOk = (prompt, opts) => ({
  status: 'ok', terminalStatus: 'success', outputPresent: true,
  resultSummary: `review done for ${opts.label}`,
  findings: [{ severity: 'P1', summary: `issue seen by ${opts.label}`, action: 'tighten it' }],
})

// overrides: label -> array of per-attempt responders (fn|'throw'|null);
// attempts beyond the array fall back to the default responder.
// stringifyArgs: deliver args as a JSON-encoded string, the shape the
// Workflow harness was observed to use live (2026-08-09) — the template's
// defensive cfg parse must make both shapes equivalent.
async function runTemplate(overrides = {}, { stringifyArgs = false } = {}) {
  const calls = []
  const attempts = new Map()
  const agent = async (prompt, opts) => {
    calls.push({ prompt, opts })
    const n = attempts.get(opts.label) ?? 0
    attempts.set(opts.label, n + 1)
    const script = overrides[opts.label]
    const responder = script && n < script.length ? script[n] : undefined
    if (responder === 'throw') throw new Error(`schema validation exhausted for ${opts.label}`)
    if (responder === null) return null
    if (responder) return responder(prompt, opts)
    return opts.label.endsWith(':review') ? reviewerOk(prompt, opts)
      : opts.label === 'finalize' ? finalizeOk(prompt)
      : doerOk(prompt, opts)
  }
  const args = {
    specPath: '/vault/specs/fake-spec.md',
    timestamp: '2026-08-09T00:00:00Z',
    reviewer: { plan: 'REVCMD plan', diff: 'REVCMD diff', task: 'REVCMD task' },
  }
  // new Function over repo-owned source (the SKILL.md fence) — the executed
  // string is the code under test, same trust level as this file; no
  // user/network input reaches it.
  const fn = new Function('agent', 'log', 'phase', 'args', `return (async () => { ${src} })()`)
  const result = await fn(agent, () => {}, () => {}, stringifyArgs ? JSON.stringify(args) : args)
  return { result, calls }
}

const findCalls = (calls, label) => calls.filter(c => c.opts.label === label)

// T1 — happy path: full chain, handoffs, audit trail, disposed ledger.
// Plan emits an amendment so the amendment plumbing is observable end-to-end.
{
  const planWithAmend = (prompt, opts) =>
    ({ ...doerOk(prompt, opts), amendments: ['AMEND-1: tighten the spec wording'] })
  const { result, calls } = await runTemplate({ 'Plan:do': [planWithAmend] })
  check(result.status === 'ok', 'T1: completes with status ok', JSON.stringify(result.status))
  check(calls.length === 13, 'T1: 13 agent calls (6 doers + 6 reviews + finalize)', String(calls.length))
  const impl = findCalls(calls, 'Implement:do')[0]
  check(impl.prompt.includes('Previous phase Plan finished with status "ok"'),
    'T1: Implement receives the Plan handoff')
  check(impl.prompt.includes('plan.out'), 'T1: Implement handoff names Plan artifacts')
  check(findCalls(calls, 'Test:do')[0].prompt.includes('implement.out'),
    'T1: Test handoff names Implement artifacts')
  // Payload-level audit-trail assertions: the labels alone could survive an
  // implementation that serializes empty arrays (Codex test-review finding).
  const analyze = findCalls(calls, 'Analyze:do')[0]
  check(analyze.prompt.includes('"artifacts":["plan.out"]')
    && analyze.prompt.includes('"evidence":"evidence from Plan:do"'),
    'T1: Analyze audit trail carries real phase-outcome payloads')
  check(analyze.prompt.includes('"id":"Plan-R1"')
    && analyze.prompt.includes('"disposition":{"disposition":"addressed"'),
    'T1: Analyze audit trail carries ledger ids with settled dispositions')
  check(analyze.prompt.includes('AMEND-1'), 'T1: Analyze sees accumulated amendments')
  // Exact-set audit assertions: representative operands alone let a
  // filtering/slicing regression drop entries (Codex round-2 finding).
  const parsePayload = (prompt, label) => {
    const m = prompt.match(new RegExp(`${label}: (\\[.*\\])`))
    return m ? JSON.parse(m[1]) : null
  }
  const aOut = parsePayload(analyze.prompt, 'phaseOutcomes')
  const aLed = parsePayload(analyze.prompt, 'findings ledger')
  check(aOut && aOut.map(p => p.phase).join() === 'Plan,Implement,Test,Simplify,Run',
    'T1: Analyze payload has exactly Plan..Run in order', JSON.stringify(aOut))
  check(aLed && aLed.map(f => f.id).join() === 'Plan-R1,Implement-R1,Test-R1,Simplify-R1,Run-R1',
    'T1: Analyze ledger has exactly Plan-R1..Run-R1 in order', JSON.stringify(aLed))
  check(aLed && aLed.slice(0, 4).every(f => f.disposition?.disposition === 'addressed')
    && !aLed[4].disposition,
    'T1: Analyze ledger disposition states correct (Run-R1 still open)')
  const finalize = findCalls(calls, 'finalize')[0]
  const fOut = parsePayload(finalize.prompt, 'phaseOutcomes')
  const fLed = parsePayload(finalize.prompt, 'findings ledger')
  check(fOut && fOut.map(p => p.phase).join() === 'Plan,Implement,Test,Simplify,Run,Analyze',
    'T1: Finalize payload has exactly all six phases in order', JSON.stringify(fOut))
  check(fLed && fLed.map(f => f.id).join() === 'Plan-R1,Implement-R1,Test-R1,Simplify-R1,Run-R1,Analyze-R1',
    'T1: Finalize ledger has exactly all six findings in order', JSON.stringify(fLed))
  check(fLed && fLed.slice(0, 5).every(f => f.disposition?.disposition === 'addressed')
    && !fLed[5].disposition,
    'T1: Finalize ledger disposition states correct (Analyze-R1 still open)')
  check(finalize.prompt.includes('"id":"Run-R1"')
    && finalize.prompt.includes('"artifacts":["analyze.out"]'),
    'T1: Finalize receives the full serialized ledger and phase outcomes')
  check(finalize.prompt.includes('- Analyze-R1 [P1]'),
    'T1: Finalize carries the undisposed Analyze finding for disposition')
  check(finalize.prompt.includes('AMEND-1'), 'T1: Finalize sees accumulated amendments')
  check(finalize.prompt.includes('the report must reflect them'),
    'T1: Finalize prompt pins the report-must-reflect instruction')
  check(result.amendments.includes('AMEND-1: tighten the spec wording'),
    'T1: amendment survives into the returned result')
  check(result.ledger.length === 6, 'T1: one ledger entry per reviewer finding', String(result.ledger.length))
  check(result.ledger.every(f => f.disposition && f.disposition.disposition),
    'T1: every ledger finding ends disposed (Analyze findings via Finalize)')
  const ids = result.ledger.map(f => f.id)
  check(new Set(ids).size === ids.length, 'T1: finding ids are unique', ids.join(','))
  check(typeof result.report === 'string', 'T1: report field returned')
}

// T2 — thrown rejection twice: retry once, then structured abort with reason.
{
  const { result, calls } = await runTemplate({ 'Plan:do': ['throw', 'throw'] })
  check(result.status === 'aborted', 'T2: thrown doer aborts', JSON.stringify(result.status))
  check(result.failedPhase === 'Plan', 'T2: abort names the failed phase', String(result.failedPhase))
  check(String(result.reason).includes('schema validation exhausted'),
    'T2: abort carries the thrown reason', String(result.reason))
  check(calls.length === 2, 'T2: exactly one retry (2 attempts, nothing after)', String(calls.length))
}

// T3 — null return (killed/API-dead agent) retries once, then run completes.
{
  const { result, calls } = await runTemplate({ 'Plan:do': [null] })
  check(result.status === 'ok', 'T3: null-then-ok recovers')
  const plans = findCalls(calls, 'Plan:do')
  check(plans.length === 2 && plans[1].prompt.includes('null result'),
    'T3: retry prompt names the null-result failure')
}

// T3b — explicit status:"failed" twice is its own abort path (not null, not thrown).
{
  const failed = (prompt, opts) => ({ ...doerOk(prompt, opts), status: 'failed' })
  const { result } = await runTemplate({ 'Run:do': [failed, failed] })
  check(result.status === 'aborted' && result.failedPhase === 'Run',
    'T3b: explicit status "failed" aborts the phase', JSON.stringify(result))
  check(String(result.reason).includes('status "failed"'), 'T3b: reason names status "failed"')
  check(result.phaseOutcomes.length === 4, 'T3b: abort preserves completed phase outcomes',
    String(result.phaseOutcomes.length))
}

// T4 — reviewer with no fetched output can NEVER pass as an empty review.
{
  const noOutput = (prompt, opts) => ({ ...reviewerOk(prompt, opts), outputPresent: false, findings: [] })
  const { result, calls } = await runTemplate({ 'Plan:review': [noOutput, noOutput] })
  check(result.status === 'aborted' && result.failedPhase === 'Plan:review',
    'T4: missing reviewer output aborts at the review step', JSON.stringify(result))
  check(String(result.reason).includes('output missing'), 'T4: reason says output missing')
  check(calls.length === 3, 'T4: 1 doer + 2 reviewer attempts, nothing after', String(calls.length))
  const nonSuccess = (prompt, opts) => ({ ...reviewerOk(prompt, opts), terminalStatus: 'failed' })
  const r2 = await runTemplate({ 'Plan:review': [nonSuccess, nonSuccess] })
  check(r2.result.status === 'aborted' && String(r2.result.reason).includes('not success'),
    'T4: non-success terminalStatus also aborts')
  // codex-companion's real success value is "completed" (observed live) — it
  // must pass validation without burning the retry.
  const completed = (prompt, opts) => ({ ...reviewerOk(prompt, opts), terminalStatus: 'completed' })
  const r3 = await runTemplate({ 'Plan:review': [completed] })
  check(r3.result.status === 'ok', 'T4: terminalStatus "completed" is accepted as success')
  check(findCalls(r3.calls, 'Plan:review').length === 1,
    'T4: "completed" passes on the first attempt (no retry burned)')
}

// T5 — duplicate disposition ids are rejected, then the retry succeeds.
{
  const dup = (prompt, opts) => {
    const out = doerOk(prompt, opts)
    out.findingDispositions = [...out.findingDispositions, ...out.findingDispositions]
    return out
  }
  const { result, calls } = await runTemplate({ 'Implement:do': [dup] })
  check(result.status === 'ok', 'T5: duplicate-then-clean recovers')
  const impls = findCalls(calls, 'Implement:do')
  check(impls.length === 2 && impls[1].prompt.includes('duplicate findingDispositions'),
    'T5: retry prompt names the duplicate defect')
}

// T6 — a disposition for an id from an EARLIER phase is rejected and the
// settled ledger entry stays untouched (Codex round-2 regression).
{
  const rewriteHistory = (prompt, opts) => {
    const out = doerOk(prompt, opts)
    out.findingDispositions.push({ finding: 'Plan-R1', disposition: 'rebutted', rationale: 'rewriting history' })
    return out
  }
  const { result, calls } = await runTemplate({ 'Test:do': [rewriteHistory] })
  check(result.status === 'ok', 'T6: historical-id-then-clean recovers')
  const tests = findCalls(calls, 'Test:do')
  check(tests.length === 2 && tests[1].prompt.includes('settled dispositions are immutable'),
    'T6: retry prompt names the immutability defect')
  const planR1 = result.ledger.find(f => f.id === 'Plan-R1')
  check(planR1 && planR1.disposition.disposition === 'addressed',
    'T6: settled Plan-R1 disposition survives the rewrite attempt',
    JSON.stringify(planR1 && planR1.disposition))
}

// T7 — omitting a carried finding id must abort, not silently succeed
// (Codex test-review: the coverage gap check was otherwise never exercised).
{
  const omitFirst = (prompt, opts) => {
    const out = doerOk(prompt, opts)
    out.findingDispositions = out.findingDispositions.slice(1)
    return out
  }
  const { result, calls } = await runTemplate({ 'Implement:do': [omitFirst, omitFirst] })
  check(result.status === 'aborted' && result.failedPhase === 'Implement',
    'T7: missing disposition aborts the phase', JSON.stringify(result))
  check(String(result.reason).includes('missing for: Plan-R1'),
    'T7: abort reason names the ignored finding id', String(result.reason))
  const impls = findCalls(calls, 'Implement:do')
  check(impls.length === 2 && impls[1].prompt.includes('missing for: Plan-R1'),
    'T7: retry prompt names the missing id before aborting')
}

// T7b — the same omission during Finalize (Analyze findings must not be droppable).
{
  const finalizeEmpty = (prompt) => ({ ...finalizeOk(prompt), findingDispositions: [] })
  const { result } = await runTemplate({ finalize: [finalizeEmpty, finalizeEmpty] })
  check(result.status === 'aborted' && result.failedPhase === 'Finalize',
    'T7b: Finalize omitting dispositions aborts', JSON.stringify(result))
  check(String(result.reason).includes('missing for: Analyze-R1'),
    'T7b: Finalize abort names the undisposed Analyze finding', String(result.reason))
}

// T8 — args delivered as a JSON-encoded string (the shape the harness was
// observed to use live): the defensive cfg parse must make the run identical
// to the object-args happy path — real specPath and reviewer commands in the
// prompts, never the string "undefined".
{
  const { result, calls } = await runTemplate({}, { stringifyArgs: true })
  check(result.status === 'ok', 'T8: stringified args complete with status ok', JSON.stringify(result.status))
  const plan = findCalls(calls, 'Plan:do')[0]
  check(plan.prompt.includes('Spec: /vault/specs/fake-spec.md.'),
    'T8: doer prompt carries the parsed specPath')
  check(!calls.some(c => c.prompt.includes('undefined')),
    'T8: no prompt contains the string "undefined"')
  const rev = findCalls(calls, 'Plan:review')[0]
  check(rev.prompt.includes('REVCMD plan'), 'T8: reviewer prompt carries the parsed reviewer command')
  const finalize = findCalls(calls, 'finalize')[0]
  check(finalize.prompt.includes('run started 2026-08-09T00:00:00Z'),
    'T8: finalize prompt carries the parsed timestamp')
}

// T9 — the working principles are injected into every doer brief (and the
// finalize prompt is exempt: it writes a report, not code).
{
  const { calls } = await runTemplate()
  const doers = calls.filter(c => c.opts.label.endsWith(':do'))
  check(doers.length === 6 && doers.every(c =>
    c.prompt.includes('Working principles:')
    && c.prompt.includes('Protect the trusted core')
    && c.prompt.includes('NEVER modify the eval while also trying to make it pass')),
    'T9: every doer brief carries the working principles')
  const simplify = calls.find(c => c.opts.label === 'Simplify:do')
  check(!!simplify && calls.find(c => c.opts.label === 'Run:do').prompt.includes('simplify.out'),
    'T9: Simplify runs before Run and Run receives its artifacts')
}

console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
