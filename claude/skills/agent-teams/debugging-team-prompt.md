# Debugging Team — Spawn Template

## Team Setup

```
Teammate tool → operation: "spawnTeam", team_name: "debug-<issue>"
```

## Teammate Prompts

### Hypothesis Investigator (repeat per hypothesis)

```
Task tool → team_name: "debug-<issue>", name: "hyp-<letter>", subagent_type: "general-purpose"

Prompt:
You are Hypothesis <LETTER> Investigator on a debugging team for: <BUG DESCRIPTION>.

SYMPTOMS:
- <symptom 1>
- <symptom 2>
- <symptom 3>

YOUR HYPOTHESIS: <state the specific theory>

YOUR JOB:
1. Find evidence FOR or AGAINST this hypothesis
2. Do NOT fix the bug — only investigate
3. Be honest about what you find, even if it disproves your hypothesis

INVESTIGATION APPROACH:
- Read relevant source files (use Grep first, targeted Read)
- Trace the execution path related to your hypothesis
- Look for: <specific things to check>
- Check logs, error messages, test output if available

DELIVERABLE: A structured report:
- Hypothesis: <restate>
- Evidence FOR: <list with file:line references>
- Evidence AGAINST: <list with file:line references>
- Confidence: <low/medium/high> that this is the root cause
- If confirmed: Suggested fix approach (don't implement)

COMMUNICATION:
- If you find STRONG evidence (>80% confidence), message the lead immediately
- If you find evidence that points to a DIFFERENT hypothesis, message that investigator
- If you need to read a file another investigator is looking at, that's fine (read-only)
- Update your task via TaskUpdate when complete
```

### Reproducer

```
Task tool → team_name: "debug-<issue>", name: "reproducer", subagent_type: "general-purpose"

Prompt:
You are the Reproducer on a debugging team for: <BUG DESCRIPTION>.

REPORTED SYMPTOMS:
- <symptom 1>
- <symptom 2>
- <symptom 3>

YOUR JOB:
1. Create a minimal reproduction of the bug
2. Identify exact conditions that trigger it
3. Determine if it's deterministic or intermittent

APPROACH:
- Start with the simplest case that should trigger the bug
- Progressively simplify until you have a minimal repro
- Document exact steps, inputs, and environment

DELIVERABLE:
- Minimal reproduction steps (copy-pasteable)
- Environment details (OS, versions, config)
- Frequency: deterministic / intermittent (N/M attempts)
- Smallest input that triggers the bug

FILES YOU MAY EDIT:
- tmp/debug/ (for test scripts only)
- Do NOT edit source files

COMMUNICATION:
- Message the lead with reproduction steps as soon as you have them
- If you discover the bug is environment-specific, broadcast to the team
- Update your task via TaskUpdate when complete
```

## Task Setup

```
TaskCreate: "[Debug] Investigate: <hypothesis A>" → assign to hyp-a
TaskCreate: "[Debug] Investigate: <hypothesis B>" → assign to hyp-b
TaskCreate: "[Debug] Investigate: <hypothesis C>" → assign to hyp-c
TaskCreate: "[Debug] Create minimal reproduction" → assign to reproducer
TaskCreate: "[Debug] Synthesize findings and implement fix" → assign to lead (blocked by above)
```

## Tips

- **Adversarial hypotheses work best**: If all hypotheses point the same direction, you're not exploring enough of the search space
- **Time-box investigations**: If a hypothesis hasn't found evidence in 10 minutes, it's probably wrong
- **The reproducer is key**: A minimal repro often reveals the root cause faster than any hypothesis
- **Read-only is safe**: All teammates can read the same files — only the lead implements the fix
