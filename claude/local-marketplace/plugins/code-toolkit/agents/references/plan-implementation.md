# Plan-Driven Implementation Guide

Detailed reference for the `codex` agent when implementing from an approved plan. Loaded on demand.

## Plan-Aware Prompt Template

```
[DELEGATION HEADER]
You are implementing a specific step from an approved plan. Do not explore or ask questions — implement directly.

[PLAN CONTEXT]
Overall plan: <1-2 sentence summary>
Current step: <step number and description>
Previous steps completed: <what's already done>
Files already modified: <list>

[TASK]
<Precise description of what to implement in this step>

[CONTEXT]
- Working directory: <path>
- Key files: <list files to read and modify>
- Language/framework: <stack>

[CONSTRAINTS]
- Follow patterns established in previous steps
- <Style constraints, what NOT to change>
- Match existing code style

[VERIFICATION]
After implementing, run: <test command or verification step>
```

## Chunking Strategy

Break plans into Codex-sized pieces based on step count:

| Plan steps | Chunking | Rationale |
|------------|----------|-----------|
| 1-3 steps | Single Codex invocation | Small enough for one pass |
| 4-7 steps | 2-3 chunks (2-3 steps each) | Keeps context manageable |
| 8+ steps | Per-step invocations | Each step is self-contained |

### Chunk Boundaries

Good chunk boundaries:
- After a file is fully modified (all changes to that file complete)
- After a logical unit (e.g., "model + migration" or "route + handler + test")
- Before a step that depends on verification of previous steps

Bad chunk boundaries:
- In the middle of modifying a single file
- Between tightly coupled changes (e.g., interface change + all callers)

## Commit Pattern

After each verified chunk:
1. Run verification command from the plan
2. If passes: `git add <specific files> && git commit -m "<what this chunk accomplished>"`
3. If fails: debug and fix before committing (don't commit broken state)

## Example

### Plan Step
```
Step 3: Add authentication middleware
- Create src/middleware/auth.ts with JWT validation
- Add auth middleware to protected routes in src/routes/api.ts
- Add tests in tests/middleware/auth.test.ts
```

### Codex Prompt
```
You are implementing step 3 of an approved plan. Do not explore or ask questions — implement directly.

PLAN CONTEXT:
Overall: Adding JWT authentication to the Express API
Current step: 3 - Add authentication middleware
Previous: Steps 1-2 complete (User model, JWT utils in src/utils/jwt.ts)

TASK: Create authentication middleware and apply to protected routes.

1. Create src/middleware/auth.ts:
   - Export `requireAuth` middleware
   - Extract JWT from Authorization header (Bearer scheme)
   - Validate using verifyToken from src/utils/jwt.ts
   - Attach decoded user to req.user
   - Return 401 for missing/invalid tokens

2. Update src/routes/api.ts:
   - Import requireAuth
   - Apply to all routes under /api/protected/*

3. Create tests/middleware/auth.test.ts:
   - Test valid token → passes through
   - Test missing token → 401
   - Test expired token → 401
   - Test malformed token → 401

CONTEXT:
- Working directory: /Users/yulong/code/myproject
- Key files: src/utils/jwt.ts (already has verifyToken), src/routes/api.ts
- Language: TypeScript, Express, Jest

CONSTRAINTS:
- Follow error handling pattern from src/middleware/error.ts
- Use existing User type from src/types/user.ts

VERIFICATION:
Run: npx jest tests/middleware/auth.test.ts --verbose
```
