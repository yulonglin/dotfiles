---
name: correct
description: Find the mistakes agents keep repeating in a repo and make each one impossible rather than documented — architecture first, then types, then a lint, hook or test whose error names the fix, and a written rule only for judgement calls — proving each new check fails on a real past mistake. Use on /correct, "stop agents doing X", "this keeps happening", or after a correction that was clearly not the first of its kind.
disable-model-invocation: true
---

# Correct

Adapted from pstack's `correct` skill in [pstack-claude](https://github.com/michael-denyer/pstack-claude) (MIT), the Claude Code port of Lauren Tan's pstack. It is the procedure behind two global rules: "a correction naming one example means the class" (`communication.md`) and "behavioural instructions become config, not memory".

Assume every contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that runs. Shape the repo so a change that looks right from one file is right for the whole repo.

## Find the mistake classes

Read recent commits and reverts, PR review comments, the repo's `CLAUDE.md` and `.claude/rules/`, its `## Learnings`, comments that explain workarounds, and — when available — the session transcripts where the user corrected an agent. Group the mistakes into classes. A class counts once it has happened twice; cite both occurrences.

## Fix each class at the highest level that works

1. **Architecture removes it.** One owner per piece of state, one supported way per task. Hide internals so the wrong import fails. Replace hand-synced lists with one source of truth that the others are rendered from. Delete the old way and the dead code an agent would copy.
2. **Types or schema make the bad state unwritable.** A pydantic model, a typed config, a JSON schema validated at load.
3. **A check fails loudly and names the fix.** A ruff rule, a pre-commit hook in `config/git-hooks/`, a Claude Code `PreToolUse` hook, or a CI step whose error message names the file, function or command to use instead. If the bad pattern is already widespread, fail only when a change adds more.
4. **A behaviour test.** Fix or delete any test that still passes when its behaviour breaks, or fails when only internals change.
5. **A written rule, last, and only for judgement calls.** Nothing fails when an agent skips it. It goes in the checklist or rule that owns the topic, never as a new file when an owner exists, and within the always-on byte budget that `tests/test_memory_tier_budget.py` pins.

## Fix and prove

Fix the most frequent classes now, one commit each. Prove each new check fails on a real past mistake: check out or reconstruct the bad change, run the check, and paste the failure. Run the same command locally and in CI. An exception goes on the offending line with a reason, an expiry date and the user's approval.

## Record what enforces each rule

Beside each rule that has an enforcer, name the enforcer — the test, hook or lint that fails — in the file that owns the rule, so a reader can tell a load-bearing rule from a hope. When a correction repeats a rule that already existed with nothing enforcing it, that is a repeat: fix it at the highest level in the same change. Delete a rule once its mistake can no longer happen.

**Reply:** each class with its two pieces of evidence, the level chosen, why a higher level did not work, and the pasted failure that proves the check.
