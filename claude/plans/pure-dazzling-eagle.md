# Automatic Retry for Failed Batch Requests

## Background

The batch workflow system now has production request building, but lacks automatic retry for failed requests. Currently:
- **Stage 1 failures**: Tracked in `manifest.metadata["failed_requests"][config]` but not retried
- **Stage 2 failures**: Not tracked at all, results saved but failures unrecorded

**User Request**: Automatically retry failed Stage 1 requests instead of just recording them.

---

## Implementation Plan (Revised Based on Review)

### Key Design Decisions (from tooling-engineer + code-reviewer feedback)

1. **Keep original custom_ids** - No `_r1`/`_r2` suffixes (avoids ID collision/tracking issues)
2. **Filter non-retryable errors** - Don't retry content policy violations, malformed requests
3. **Jitter in backoff** - Prevent thundering herd if many retries happen
4. **Backoff between retries** - Not before first attempt
5. **Preserve original requests** - Store original `BatchRequest` objects for exact replay

### Step 1: Add CLI Arguments

**File**: `scripts/run_staged_batches.py`

```python
parser.add_argument("--max-retries", type=int, default=2,
                    help="Max retry attempts for failed requests")
parser.add_argument("--retry-delay", type=int, default=30,
                    help="Base delay (seconds) between retries")
parser.add_argument("--no-retry", action="store_true",
                    help="Disable automatic retry (just track failures)")
```

### Step 2: Define Retryable vs Non-Retryable Errors

```python
# Non-retryable error patterns (don't waste API calls)
NON_RETRYABLE_ERRORS = [
    "content_policy",       # Content policy violation
    "invalid_request",      # Malformed request
    "context_length",       # Token limit exceeded
    "invalid_api_key",      # Auth error
]

def is_retryable_error(error_msg: str) -> bool:
    """Check if error is worth retrying."""
    if not error_msg:
        return True  # Unknown error, try anyway
    error_lower = error_msg.lower()
    return not any(pattern in error_lower for pattern in NON_RETRYABLE_ERRORS)
```

### Step 3: Create Retry Function

**File**: `scripts/run_staged_batches.py`

```python
import random

async def retry_failed_requests(
    failed_results: list[BatchResult],
    original_requests: list[BatchRequest],
    provider: BatchProvider,
    workflow_name: str,
    config: str,
    stage: int,
    max_retries: int = 2,
    retry_delay: int = 30,
    poll_interval: int = 60,
) -> tuple[list[dict], list[BatchResult]]:
    """
    Retry failed requests with exponential backoff + jitter.

    Returns:
        (succeeded_as_dicts, still_failed_as_BatchResults)
    """
    # Build lookup: custom_id → original BatchRequest
    request_map = {req.custom_id: req for req in original_requests}

    # Filter to retryable failures only
    retryable = [
        r for r in failed_results
        if is_retryable_error(r.error) and r.custom_id in request_map
    ]
    non_retryable = [r for r in failed_results if r not in retryable]

    if non_retryable:
        logger.warning(f"Skipping {len(non_retryable)} non-retryable failures")

    if not retryable:
        return [], failed_results

    current_failures = retryable
    all_succeeded: list[dict] = []

    for attempt in range(1, max_retries + 1):
        if not current_failures:
            break

        # Exponential backoff with jitter (between retries, not before first)
        if attempt > 1:
            base_delay = retry_delay * (2 ** (attempt - 2))  # 30s, 60s, 120s
            jitter = random.uniform(0, base_delay * 0.2)      # ±20% jitter
            delay = min(base_delay + jitter, 300)             # Cap at 5 min
            logger.info(f"Waiting {delay:.1f}s before retry attempt {attempt}...")
            await asyncio.sleep(delay)

        # Rebuild requests from originals (preserves metadata)
        retry_requests = [request_map[r.custom_id] for r in current_failures]

        logger.info(f"Retry attempt {attempt}/{max_retries}: {len(retry_requests)} requests")

        # Submit retry batch
        batch_id = provider.submit_batch(
            retry_requests,
            description=f"{workflow_name} Stage {stage} RETRY {attempt}: {config}",
        )

        # Poll for completion
        while True:
            status = provider.get_batch_status(batch_id)
            if status.is_complete:
                break
            logger.info(f"Retry batch: {status.completed_requests}/{status.total_requests}")
            await asyncio.sleep(poll_interval)

        # Process results
        results = provider.get_batch_results(batch_id)

        new_succeeded = [r for r in results if r.success]
        new_failed = [r for r in results if not r.success]

        # Convert succeeded to dict format
        for r in new_succeeded:
            all_succeeded.append({
                "custom_id": r.custom_id,
                "success": True,
                "response": r.response,
                "error": None,
            })

        logger.info(f"Retry {attempt}: {len(new_succeeded)} succeeded, {len(new_failed)} still failing")
        current_failures = new_failed

    # Combine non-retryable + remaining failures
    final_failures = non_retryable + current_failures
    return all_succeeded, final_failures
```

### Step 4: Update run_staged_workflow Signature

```python
async def run_staged_workflow(
    workflow: StagedWorkflow,
    dry_run: bool = False,
    poll_interval: int = 60,
    max_retries: int = 2,
    retry_delay: int = 30,
    no_retry: bool = False,
) -> BatchManifest:
```

### Step 5: Integrate Retry into Stage 1 Handling

After downloading Stage 1 results (around line 490):

```python
# Download Stage 1 results
stage1_results = provider.get_batch_results(batch_id)

# Track failures
stage1_failures = [r for r in stage1_results if not r.success]

# Retry failed requests (unless disabled)
retry_succeeded: list[dict] = []
remaining_failures: list[BatchResult] = stage1_failures

if stage1_failures and not no_retry and max_retries > 0:
    logger.info(f"Attempting to retry {len(stage1_failures)} failed Stage 1 requests...")

    retry_succeeded, remaining_failures = await retry_failed_requests(
        failed_results=stage1_failures,
        original_requests=stage1_requests,  # Keep reference from earlier
        provider=provider,
        workflow_name=workflow.name,
        config=config,
        stage=1,
        max_retries=max_retries,
        retry_delay=retry_delay,
        poll_interval=poll_interval,
    )

    if retry_succeeded:
        logger.info(f"Recovered {len(retry_succeeded)} requests via retry")

# Build final results data (original successes + retry successes)
stage1_results_data = [
    {
        "custom_id": r.custom_id,
        "success": r.success,
        "response": r.response,
        "error": r.error,
    }
    for r in stage1_results
    if r.success  # Only original successes
]
stage1_results_data.extend(retry_succeeded)  # Add retry successes

# Track remaining failures in manifest
if remaining_failures:
    manifest.metadata["failed_requests"][config] = {
        "stage": 1,
        "failed_ids": [r.custom_id for r in remaining_failures],
        "count": len(remaining_failures),
        "retry_attempts": max_retries if not no_retry else 0,
        "non_retryable_count": sum(
            1 for r in remaining_failures if not is_retryable_error(r.error)
        ),
    }
    logger.warning(f"Stage 1: {len(remaining_failures)} requests failed after {max_retries} retries")
```

### Step 6: Add Stage 2 Failure Tracking

After Stage 2 results download:

```python
# Track Stage 2 failures for consistency
stage2_failures = [r for r in stage2_results if not r.success]
if stage2_failures:
    config_failures = manifest.metadata["failed_requests"].get(config, {})
    config_failures["stage_2"] = {
        "failed_ids": [r.custom_id for r in stage2_failures],
        "count": len(stage2_failures),
    }
    manifest.metadata["failed_requests"][config] = config_failures
    logger.warning(f"Stage 2 had {len(stage2_failures)} failed requests (not retried)")
```

### Step 7: Wire CLI to run_staged_workflow

```python
manifest = asyncio.run(
    run_staged_workflow(
        workflow,
        dry_run=args.dry_run,
        poll_interval=args.poll_interval,
        max_retries=args.max_retries,
        retry_delay=args.retry_delay,
        no_retry=args.no_retry,
    )
)
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/run_staged_batches.py` | Add retry logic, CLI args, Stage 2 tracking |

---

## Manifest Tracking Structure (Unified)

```json
{
  "failed_requests": {
    "math-paraphrase": {
      "stage": 1,
      "failed_ids": ["sample_001", "sample_005"],
      "count": 2,
      "retry_attempts": 2,
      "non_retryable_count": 1,
      "stage_2": {
        "failed_ids": ["sample_003_probe_12"],
        "count": 1
      }
    }
  }
}
```

---

## Verification Plan

### Test 1: Dry Run (Verify Args Parse)
```bash
python scripts/run_staged_batches.py \
  --workflow lie-detector \
  --configs math-paraphrase \
  --limit 5 \
  --max-retries 2 \
  --retry-delay 10 \
  --dry-run
```

### Test 2: E2E Small Sample
```bash
python scripts/run_staged_batches.py \
  --workflow lie-detector \
  --configs math-paraphrase \
  --model gpt-4.1-nano \
  --limit 3 \
  --max-retries 2 \
  --retry-delay 10 \
  --poll-interval 10

# Check manifest
cat data/batch_manifests/manifest_*.json | jq '.metadata'
```

### Test 3: No-Retry Flag
```bash
python scripts/run_staged_batches.py \
  --workflow lie-detector \
  --configs math-paraphrase \
  --limit 3 \
  --no-retry
# Should track failures without retry attempts
```

---

## Success Criteria

1. ✅ Failed Stage 1 requests automatically retried up to `max_retries` times
2. ✅ Non-retryable errors (content policy, auth) skip retry
3. ✅ Exponential backoff with jitter between retries
4. ✅ Successful retries merged back for Stage 2
5. ✅ Remaining failures tracked in manifest with retry metadata
6. ✅ Stage 2 failures also tracked (for consistency)
7. ✅ `--no-retry` flag disables retry behavior

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Infinite retry loop | Hard cap: `max_retries` (default 2) |
| Rate limit amplification | Exponential backoff + 20% jitter, 5 min cap |
| Memory bloat | Keep request map only during retry phase |
| Wasted retries on permanent errors | `is_retryable_error()` filter |
| Batch quota exhaustion | Track retry count, clear logging |
