# Spec Template

Use this structure for the output spec:

```markdown
# Specification: [Feature Name]

## Overview
**Created**: [Date]
**Status**: Draft

[1-2 sentence summary of what this does and why]

## Context & Motivation

[Why this feature exists, what problem it solves, who requested it]

## Requirements

### Functional Requirements
- **[REQ-001]** The system MUST [required behavior]
- **[REQ-002]** The system SHOULD [recommended behavior]
- **[REQ-003]** The system MAY [optional behavior]

### Non-Functional Requirements
- **Performance**: [specific metrics, e.g., "p99 latency < 200ms"]
- **Security**: [auth model, data protection requirements]
- **Reliability**: [uptime, error rate targets]

## Design

### High-Level Architecture
[Key components, data flow, sequence of operations]

### Data Model
[Schema changes, new entities, relationships]

### Technical Decisions
| Decision | Options Considered | Choice | Rationale |
|----------|-------------------|--------|-----------|
| [Area] | A, B, C | B | [Why B was chosen] |

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| [Edge case 1] | [How handled] |
| [Error condition 1] | [Recovery behavior] |

## Acceptance Criteria

- [ ] **AC-1**: Given [context], when [action], then [expected result]
- [ ] **AC-2**: Given [context], when [action], then [expected result]

## Out of Scope

- [Explicitly excluded item 1]
- [Explicitly excluded item 2]

## Open Questions

- [ ] [Unresolved question 1]
- [ ] [Unresolved question 2]

## Implementation Notes

[To be filled during implementation - learnings, deviations, future improvements]
```

## Writing Guidelines

- Be specific: "< 200ms p99" not "fast"
- Use MUST/SHOULD/MAY per RFC 2119
- Include rationale for non-obvious decisions
- Keep out-of-scope explicit to prevent scope creep
- Open questions are OK - better to document unknowns than guess
