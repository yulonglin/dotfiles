# Implementation Team — Spawn Template

## Team Setup

```
Teammate tool → operation: "spawnTeam", team_name: "impl-<feature>"
```

## Teammate Prompts

### Module Owner (repeat per module)

```
Task tool → team_name: "impl-<feature>", name: "<module>-dev", subagent_type: "general-purpose"

Prompt:
You are the <MODULE> developer on an implementation team building: <FEATURE>.

YOUR ROLE: Implement the <MODULE> component of this feature.

OVERALL GOAL: <describe the feature end-to-end>

YOUR SCOPE:
- Files you OWN (only you edit these): <list files>
- Files you may READ but NOT edit: <list shared files>

REQUIREMENTS:
- <requirement 1>
- <requirement 2>
- <requirement 3>

INTERFACES:
- Your module receives: <input format/types>
- Your module produces: <output format/types>
- Integration point: <how your work connects to others>

CODING STANDARDS:
- Match existing code style in the repo
- Add type hints
- Write minimal inline comments for non-obvious logic
- No mock data — use real interfaces

COMMUNICATION:
- Message the lead if you need to change an interface contract
- Message the lead if you're blocked on another teammate's work
- Do NOT message other teammates directly for interface changes — go through the lead
- Update your task via TaskUpdate when complete
```

### Test Writer

```
Task tool → team_name: "impl-<feature>", name: "test-writer", subagent_type: "general-purpose"

Prompt:
You are the Test Writer on an implementation team building: <FEATURE>.

YOUR ROLE: Write tests for the feature as teammates implement it.

FILES YOU OWN:
- tests/<feature>/ (all test files in this directory)

FILES YOU READ (not edit):
- <list all source files being implemented>

TEST STRATEGY:
- Unit tests for each module's public interface
- Integration tests for module interactions
- Edge cases: <list known edge cases>

APPROACH:
1. Start by reading the interface contracts and requirements
2. Write test stubs based on expected behavior
3. As teammates complete modules, flesh out tests with real assertions
4. Message the lead when tests are ready to run

COMMUNICATION:
- Message module owners if their code doesn't match the interface contract
- Message the lead when all tests are written
- Update your task via TaskUpdate when complete
```

## Task Setup

After spawning teammates, create tasks with dependencies:

```
TaskCreate: "[Impl] Implement <module-A>" → assign to <module-a>-dev
TaskCreate: "[Impl] Implement <module-B>" → assign to <module-b>-dev
TaskCreate: "[Test] Write test suite for <feature>" → assign to test-writer
TaskCreate: "[Integration] Merge and validate all modules" → assign to lead (blocked by above)
```

## File Ownership Rules

```
❌ NEVER: Two teammates editing the same file
✅ ALWAYS: Explicit file → owner mapping in spawn prompts

Example mapping:
  backend-dev  → src/api/routes.py, src/api/handlers.py
  frontend-dev → src/ui/components/Feature.tsx, src/ui/hooks/useFeature.ts
  test-writer  → tests/feature/test_routes.py, tests/feature/test_components.tsx
  lead (you)   → src/api/index.py (integration), README.md
```
