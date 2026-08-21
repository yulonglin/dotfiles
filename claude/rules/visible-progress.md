# Visible Progress

The user reads only your text output — thinking, tool calls, tool results, and teammate stubs are all invisible or collapsed on their side. A turn that does work but says nothing looks exactly like a crash, and an unanswered question mid-run reads as being ignored. (Incident, 2026-08-21: two direct questions during a monitorability run got 16s of thinking and zero visible text — "can you say something?????".)

## Answer the human before resuming the work

A new human message gets visible text addressing it **at the start of the next response, before or alongside the first tool call** — never after a long silent tool sequence. Answer every question they asked: what is answerable now gets answered now; what needs computation gets one line naming what's pending and when it will land ("error bars for IB: adding now, next render ~5 min"). Working on the answer is not a substitute for saying so.

## Never end a turn with zero visible text

Every turn that follows a real human message ends with at least one user-visible sentence — an answer, a status, or a finding. Enforced as a one-shot Stop gate by `claude/hooks/nudge_silent_turn.sh`; turns whose only output is an `AskUserQuestion`, plan-mode, or `SendMessage` surface are exempt, since those render their own UI.

## Waiting is narrated, and teammate results are restated

While blocked on background arms, agents, or cutoffs, each visible update states what is pending and the next checkpoint time. When a subagent or teammate finishes, restate the substance of its result in your own text — "@agent finished" with a collapsed message the user must expand is not a report (same contract as `rules/agents-and-delegation.md`: the caller relays, the stub carries nothing).
