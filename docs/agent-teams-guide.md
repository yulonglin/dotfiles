# Agent Teams Guide

**Experimental feature.** Enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (already set in `settings.json`).

## Subagents vs Teams

| Dimension | Subagents | Agent Teams |
|-----------|-----------|-------------|
| **Communication** | None (fire-and-forget) | Peer-to-peer messaging |
| **Coordination** | Lead orchestrates sequentially | Teammates self-coordinate |
| **Context** | Isolated per agent | Shared task list, can message |
| **Cost** | Lower (single-turn each) | Higher (multi-turn, messaging overhead) |
| **Best for** | Focused research, code review, analysis | Multi-file implementation, competing hypotheses, multi-lens review |

## Team Composition Patterns

**Research Team** (3-5 teammates): Literature scout, methodology analyst, devil's advocate, synthesizer
**Implementation Team** (2-4 teammates): Each owns distinct files/modules, lead integrates
**Debugging Team** (3-5 teammates): Each investigates a different hypothesis concurrently
**Review Team** (2-3 teammates): Security reviewer, performance reviewer, correctness reviewer

## Communication & Coordination

- **SendMessage** `type: "message"` for targeted DMs (default, low-cost)
- **SendMessage** `type: "broadcast"` sparingly (sends N messages for N teammates)
- **`mode: "delegate"`** for autonomous execution; **`mode: "plan"`** for lead approval
- Use **TaskCreate/TaskUpdate** for shared work tracking

## Best Practices

- **Rich spawn prompts**: Include full context (teammates have no conversation history)
- **Right-size teams**: 2-4 for implementation, 3-5 for research/debugging
- **File ownership**: Assign each file to exactly one teammate
- **Monitor via TaskList**: Check task completion, don't poll teammates
- **Clean up**: Send `shutdown_request` to all teammates when done
- **One team per session**: Can't nest teams or run multiple teams concurrently

## Anti-Patterns

- Spawning a team for work a single subagent could handle
- Multiple teammates editing the same file
- Broadcasting routine status updates (use TaskUpdate instead)
- Leaving teams running after work completes
- Spawning >5 teammates (diminishing returns)

## Known Limitations

- No session resumption (if lead crashes, team is orphaned)
- One team per session (can't create a second team)
- No nested teams (teammates can't spawn their own teams)
