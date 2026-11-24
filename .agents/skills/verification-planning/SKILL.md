---
name: verification-planning
description: Use when about to verify, validate, or confirm anything in this repo — reproducibility checks, data validation, statistical analysis, integration or regression testing, or confirming a bug fix. Verification is a design problem, so plan how you'll verify before you start verifying.
---

# Verification Planning

**Use EnterPlanMode for verification activities, not just implementation.**

Verification is a design problem — you need to plan *how* you'll verify before you start verifying.

| Activity | Trigger EnterPlanMode | Why |
|----------|----------------------|-----|
| Implementing a feature | ✅ Yes | Need to decide implementation approach |
| Verifying it works | ✅ Yes | Need to decide validation strategy |
| Running an experiment | ✅ Yes | Need to plan test design |
| Analyzing results | ✅ Yes | Need to plan statistical approach |
| Fixing a bug | ✅ Yes | Need to decide debugging strategy |
| Confirming the fix | ✅ Yes | Need to plan regression/validation testing |

**Verification activities that need planning:**

- Reproducibility checks (rerun, validate numbers match, check for hidden bugs)
- Data validation (schema checks, contamination detection, canary verification)
- Statistical analysis (which metrics, confidence intervals, significance tests, N requirements)
- Integration testing (which scenarios to cover, edge cases)
- Error handling (what could break, how to test failures)
- Regression testing (what could be affected by this change)

**Red flag**: If you think "let me figure out how to verify this," that's EnterPlanMode.
