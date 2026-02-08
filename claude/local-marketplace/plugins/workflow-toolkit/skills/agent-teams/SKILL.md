---
name: agent-teams
description: Orchestrate agent teams for parallelizable multi-faceted tasks. Use when work requires inter-agent communication, competing hypotheses, or multi-file parallel implementation.
---

# Agent Teams

Orchestrate collaborative agent teams using Claude Code's experimental agent teams feature.

## When to Use

```
Is the work parallelizable with inter-agent communication needs?
├─ Single focused output? → Use a subagent (Task tool), not a team
├─ 2-3 independent outputs? → Use parallel subagents, not a team
├─ Parallel work + agents need to share findings? → USE A TEAM
├─ Competing hypotheses to test? → USE A TEAM
├─ Multi-file implementation with integration? → USE A TEAM
└─ Multi-lens review (security + perf + correctness)? → USE A TEAM
```

**Don't use teams for**: simple delegation, single-file work, sequential tasks, or anything a subagent handles fine.

## The Process

### Step 1: Assess the Task

Before spawning a team, answer:
1. Can the work be split into 2-5 genuinely independent streams?
2. Will agents need to communicate mid-task (not just return results)?
3. Is there a clear integration point where results come together?

If any answer is "no", use subagents instead.

### Step 2: Design the Team

Choose a pattern (see below) and define:
- **Roles**: What each teammate focuses on (be specific)
- **File ownership**: Which files each teammate can edit (CRITICAL — no overlaps)
- **Deliverables**: What each teammate produces
- **Communication plan**: When teammates should message vs. work independently

### Step 3: Spawn with Context

Each teammate starts with zero context. Their spawn prompt must include:
- The overall goal and their specific role
- File paths they own (and must NOT touch)
- Expected deliverable format
- When to message the lead vs. work independently

```
Teammate tool → operation: "spawnTeam", team_name: "<descriptive-name>"
Task tool → team_name: "<name>", name: "<role>", subagent_type: "general-purpose"
```

### Step 4: Coordinate

- Create tasks with **TaskCreate** before or after spawning
- Assign tasks with **TaskUpdate** (set `owner` to teammate name)
- Use **SendMessage** `type: "message"` for targeted communication
- Avoid **broadcast** unless truly team-wide critical information
- Monitor progress via **TaskList** — don't poll teammates

### Step 5: Integrate & Clean Up

1. Review all teammate outputs
2. Integrate results (you, the lead, handle merging)
3. Send `shutdown_request` to each teammate
4. Call `Teammate cleanup` to remove team resources
5. Commit the integrated work

## Team Patterns

### Research Team

**When**: Exploring a problem space, literature review, multi-angle analysis.

**Composition** (3-5 teammates):
| Role | Focus | Deliverable |
|------|-------|-------------|
| Literature Scout | Find relevant prior work | Annotated reference list |
| Methodology Analyst | Evaluate approaches | Pros/cons comparison table |
| Devil's Advocate | Challenge assumptions | Counter-arguments and risks |
| Synthesizer | Integrate findings | Unified recommendation |

See `research-team-prompt.md` for spawn template.

### Implementation Team

**When**: Building a feature that spans multiple files/modules with clear boundaries.

**Composition** (2-4 teammates):
| Role | Focus | Deliverable |
|------|-------|-------------|
| Backend Dev | API routes, data layer | Working endpoints |
| Frontend Dev | UI components, state | Working interface |
| Test Writer | Test coverage | Passing test suite |
| Lead (you) | Integration, review | Merged feature |

**Critical**: Assign file ownership explicitly. No two teammates edit the same file.

See `implementation-team-prompt.md` for spawn template.

### Debugging Team

**When**: Complex bug with multiple plausible root causes.

**Composition** (3-5 teammates):
| Role | Focus | Deliverable |
|------|-------|-------------|
| Hypothesis A | Investigate theory A | Evidence for/against |
| Hypothesis B | Investigate theory B | Evidence for/against |
| Hypothesis C | Investigate theory C | Evidence for/against |
| Reproducer | Create minimal repro | Reproducible test case |

Teammates investigate concurrently. First to find strong evidence messages the team.

See `debugging-team-prompt.md` for spawn template.

### Review Team

**When**: Thorough code review from multiple expert perspectives.

**Composition** (2-3 teammates):
| Role | Focus | Deliverable |
|------|-------|-------------|
| Security Reviewer | Vulnerabilities, auth, injection | Security findings |
| Performance Reviewer | Bottlenecks, complexity, caching | Performance findings |
| Correctness Reviewer | Logic errors, edge cases, types | Correctness findings |

All teammates read the same code but from different lenses. Read-only — no edits.

See `review-team-prompt.md` for spawn template.

## Key Constraints

- **One team per session** — can't create a second team or nest teams
- **File ownership is sacred** — concurrent edits cause cascading Edit failures
- **Clean up when done** — orphaned teams waste resources
- **Rich spawn prompts** — teammates have zero prior context
- **2-5 teammates** — more causes diminishing returns and coordination overhead
- **`teammateMode: "auto"`** — uses tmux panes when available, in-process otherwise

## Integration with Other Skills

- **/brainstorming** → Use before team spawning to clarify the approach
- **/writing-plans** → Create the plan, then use a team to execute it
- **/finishing-a-development-branch** → After team work, use to prepare for merge
- **/subagent-driven-development** → For independent tasks without communication needs (lighter weight)
