# Interview Guide

## Question Categories

Cover these areas systematically:

### 1. Core Functionality
- What's the primary user action?
- What state changes occur?
- What's the expected output/result?

### 2. User Interactions
- How do users trigger this?
- What feedback do they see during/after?
- What's the unhappy path UX?

### 3. Data Model
- What data is created/modified/deleted?
- What's the schema? Relationships?
- How does this integrate with existing data?

### 4. Error Handling
- What external dependencies can fail?
- What user errors are possible?
- How should each failure mode be handled?

### 5. Edge Cases
- What happens with empty/null inputs?
- Concurrent operations?
- Partial completion scenarios?

### 6. Integration
- What existing systems does this touch?
- API contracts with other services?
- Who else might integrate with this?

### 7. Performance
- Expected load/throughput?
- Latency requirements?
- Scaling considerations?

### 8. Security
- Authentication/authorization model?
- Data sensitivity?
- Attack vectors to consider?

### 9. Testing
- How do we verify correctness?
- What's hard to test?
- Acceptance criteria?

### 10. Rollout
- Migration from current state?
- Feature flag strategy?
- Rollback plan?

## Example Non-Obvious Questions

Instead of asking obvious questions, probe deeper:

**Bad**: "What should the feature do?"
**Good**: "When a user is mid-action and loses connection, should we auto-save, discard, or prompt on reconnect?"

**Bad**: "Should it be fast?"
**Good**: "If this call takes >2s, should we show a spinner, optimistic UI, or block interaction?"

**Bad**: "What errors can happen?"
**Good**: "If the downstream API returns a 500 during step 3 of 5, do we rollback steps 1-2 or leave partial state?"

**Bad**: "Who uses this?"
**Good**: "If an admin and regular user try this simultaneously on the same resource, who wins?"

## Completion Checklist

Before writing the spec, ensure:

- [ ] Core functionality fully defined
- [ ] All user interactions mapped
- [ ] Data model understood
- [ ] Error handling planned for each failure mode
- [ ] Edge cases identified and handled
- [ ] Integration points clarified
- [ ] Performance requirements quantified
- [ ] Security model specified
- [ ] Testing strategy outlined
- [ ] Out-of-scope items explicitly listed
- [ ] Open questions documented (OK to have some)
