# Review: Automatic Retry for Failed Batch Requests

## Summary

The plan proposes adding automatic retry logic to `scripts/run_staged_batches.py` for failed Stage 1 requests with exponential backoff. Overall, this is a **reasonable approach** with a few concerns and suggestions for improvement.

---

## Review Questions

### 1. Is the async retry pattern appropriate for batch API workflows?

**Answer: Yes, with caveats.**

The async pattern is appropriate because:
- Batch API polling is inherently async (wait for completion, then check)
- The `run_staged_workflow` function is already `async`
- Retry delays benefit from `asyncio.sleep` (non-blocking)

**However**, there's a conceptual mismatch to address:

Batch APIs don't fail individual requests during submission - they fail during **processing**. The current flow is:
1. Submit batch (all requests accepted)
2. Poll until complete
3. Download results (some results may have `success=False`)

So "retrying failed requests" means submitting a **new batch** containing only the previously-failed requests. This is correctly implied in the plan but should be made explicit in the code.

---

### 2. Are there edge cases with retry logic that could cause issues?

**Yes, several:**

#### Edge Case 1: Custom ID collision
The plan proposes appending `_r1`, `_r2` suffixes:
```
Original: sample_001_original_e0_abc123
Retry 1:  sample_001_original_e0_abc123_r1
```

**Problem**: If Stage 2 uses the original `custom_id` to correlate responses, the retry results won't match. Stage 2 request building does:
```python
stage2_requests = workflow.build_stage2_requests(config, stage1_results_data)
```

**Recommendation**: Either:
- (A) Strip `_rN` suffix when saving successful retries to `stage1_results_data`, OR
- (B) Keep original custom_id for retries (they replace the failed ones, no collision in final results)

Option (B) is simpler and matches the intent (the retry *replaces* the failed request).

#### Edge Case 2: Partial retry batch failure
What if the retry batch itself partially fails?
- Attempt 1: 100 requests, 10 fail
- Retry 1: 10 requests, 3 fail
- Retry 2: 3 requests, 1 fails

The plan handles this by looping `max_retries` times, but the logic needs to accumulate successes correctly:
```python
all_succeeded = []
remaining_failed = initial_failed
for attempt in range(max_retries):
    succeeded, still_failed = await retry_batch(remaining_failed, ...)
    all_succeeded.extend(succeeded)
    remaining_failed = still_failed
    if not remaining_failed:
        break
return all_succeeded, remaining_failed
```

#### Edge Case 3: Batch-level failure vs request-level failure
The plan conflates two failure modes:
1. **Batch-level failure**: `status.is_failed` = True (whole batch rejected/expired)
2. **Request-level failure**: Individual `BatchResult.success = False`

Currently, batch-level failures cause early exit (`job1.mark_failed`). Request-level failures are tracked and should be retried.

The retry logic should only handle **request-level** failures. If the retry batch itself has a batch-level failure, that's a different error path.

#### Edge Case 4: Transient vs permanent failures
Not all request failures are retryable:
- **Retryable**: Rate limits, timeouts, server errors (5xx)
- **Non-retryable**: Invalid model, malformed request, content policy

**Recommendation**: Log the error type and consider filtering out non-retryable errors:
```python
RETRYABLE_ERRORS = ["rate_limit", "timeout", "server_error", "overloaded"]
retryable = [r for r in failures if any(e in (r.error or "").lower() for e in RETRYABLE_ERRORS)]
```

---

### 3. Is the exponential backoff approach reasonable?

**Yes, mostly.**

The formula `delay = retry_delay * (2 ** (attempt - 1))` gives:
- Attempt 1: 30s
- Attempt 2: 60s
- Attempt 3: 120s (if max_retries > 2)

This is reasonable for batch APIs where processing takes minutes anyway.

**Suggestions:**
1. **Add jitter** to prevent thundering herd:
   ```python
   import random
   jitter = random.uniform(0.8, 1.2)
   delay = retry_delay * (2 ** (attempt - 1)) * jitter
   ```

2. **Cap maximum delay** (e.g., 5 minutes) to avoid excessive waits:
   ```python
   delay = min(delay, 300)
   ```

3. **The backoff placement is suboptimal**: The plan shows backoff **before** submitting the retry batch. For batch APIs, you want to:
   - Submit immediately after detecting failures
   - Poll with increasing intervals if needed

   The delay makes more sense as "wait before checking if it's worth retrying again" rather than "wait before submitting".

---

### 4. Any concerns about the manifest tracking structure?

**Minor concerns:**

#### Current structure is flat:
```json
{
  "failed_requests": {
    "math-paraphrase": {
      "stage": 1,
      "failed_ids": ["sample_001", "sample_005"],
      "count": 2,
      "retry_attempts": 2
    }
  }
}
```

**Issues:**
1. **Stage 2 conflicts**: The plan proposes adding `"stage_2"` as a nested key, but Stage 1 uses `"stage": 1` as a value. Inconsistent.

2. **Missing retry history**: It only tracks final state, not what errors occurred on each attempt.

**Recommended structure:**
```json
{
  "failed_requests": {
    "math-paraphrase": {
      "stage_1": {
        "final_failed_ids": ["sample_005"],
        "total_failures": 10,
        "recovered_by_retry": 9,
        "retry_attempts": 2,
        "errors": {
          "sample_005": "content_policy_violation"
        }
      },
      "stage_2": {
        "failed_ids": ["sample_007"],
        "count": 1,
        "errors": {
          "sample_007": "timeout"
        }
      }
    }
  }
}
```

---

### 5. Implementation suggestions

#### A. Keep original requests accessible
The current code doesn't preserve `stage1_requests` after submission. Add:
```python
# Before submit
stage1_requests_by_id = {r.custom_id: r for r in stage1_requests}
```

#### B. Simplify retry function signature
The proposed signature has too many parameters. Consider:
```python
async def retry_failed_requests(
    provider: BatchProvider,
    original_requests: dict[str, BatchRequest],  # custom_id -> request
    failed_results: list[BatchResult],
    batch_description: str,
    max_retries: int = 2,
    retry_delay: int = 30,
    poll_interval: int = 60,
) -> tuple[list[BatchResult], list[BatchResult]]:
    """Returns (succeeded, still_failed)"""
```

#### C. Add retry to Stage 2 as well
The plan only retries Stage 1. If Stage 2 failures matter (e.g., Trusted Monitor judge failures), apply the same logic.

#### D. Consider idempotency
If the script crashes mid-retry, the manifest should allow resuming. Track:
- `retry_batch_ids`: List of batch IDs from retry attempts
- `retry_status`: "in_progress" | "completed" | "exhausted"

---

## Risk Assessment

| Risk | Severity | Mitigation in Plan | Additional Recommendation |
|------|----------|-------------------|---------------------------|
| Infinite retry loop | High | Hard cap on `max_retries` | Good as-is |
| Rate limit amplification | Medium | Exponential backoff | Add jitter, respect provider backoff headers |
| Memory from retry state | Low | Rebuild from original | Good as-is |
| Batch quota exhaustion | Medium | Track in manifest | Add warning when approaching quota |
| Custom ID collision | Medium | Append `_rN` suffix | Use original ID instead |
| Non-retryable errors | Medium | Not addressed | Filter by error type |

---

## Verdict

**The plan is sound with the following modifications:**

1. **Keep original custom_ids** for retries (don't append `_rN`)
2. **Add jitter** to exponential backoff
3. **Filter retryable errors** (don't retry content policy violations)
4. **Unify manifest structure** for Stage 1 and Stage 2
5. **Track error messages** in manifest for debugging

The core async pattern and backoff approach are appropriate for batch API workflows.
