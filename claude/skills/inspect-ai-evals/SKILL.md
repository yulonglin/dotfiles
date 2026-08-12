---
name: inspect-ai-evals
description: "Silent failure modes and operational gotchas when running evals with inspect_ai against a self-hosted or serverless model endpoint. Use when configuring inspect_ai eval() concurrency or sampling, debugging a run that produced plausible-but-wrong numbers, diagnosing an eval that hangs or aborts on attestation/probe, running against vLLM on Modal/RunPod, or writing a post-run validator. Triggers: inspect_ai, inspect eval, max_samples, max_connections, GenerateConfig, stop_reason, eval log, Modal vLLM endpoint."
---

# Inspect AI evals: silent failure modes

Each of these produced a run that *completed* with numbers that looked fine. Ordered by how much they cost when missed. Verified against `inspect_ai` 0.3.241; re-check defaults against the installed version before quoting one.

## The governing principle

**Inspect's config surface and the bytes that reach the server are different things.** Every claim about how a run sampled should be read out of the persisted `ModelEvent.call.request`, never out of the config object you passed. The strongest form is a post-run validator comparing every recorded event field-by-field against a `Literal`-pinned fingerprint model, so an unplanned value fails at construction rather than producing a run that silently differs.

## 1. `max_samples` is the gate that creates concurrency

`max_connections` bounds concurrent *requests*, but a solver issues one request per sample, so it bounds nothing unless something runs samples in parallel. `max_samples` defaults to `None` and does **not** inherit `max_connections`.

Symptom: the serving engine reports `Running: 1 reqs, Waiting: 0 reqs` at single-stream throughput while you believe you configured N-way concurrency. On an endpoint billed by wall-clock this is a straight multiple on cost — observed once as ~48 GPU-hours where ~7 were expected, roughly $190 against $30.

Set it explicitly, and **confirm from the server's own logs**, not from the config you passed.

## 2. `ModelOutput.stop_reason` raises instead of defaulting

It is a property over `choices[0]`. On an errored or aborted generation `choices` is empty and reading it raises `IndexError` — which `getattr(output, "stop_reason", None)` does **not** catch, because the default covers `AttributeError` only, not an exception raised inside the property.

```python
def stopped_on_length(state) -> bool:
    output = getattr(state, "output", None)
    if output is None or not getattr(output, "choices", None):
        return False                      # guard the list, then read
    return output.stop_reason in ("max_tokens", "model_length")
```

The same shape applies to any Inspect property that indexes into a list.

## 3. `GenerateConfig` silently drops provider-specific fields

`top_k` and similar non-standard sampling fields do not survive to the request. They must ride `extra_body`. Verify from a persisted request body.

## 4. Killing a run does not stop the server

The client dies; the server keeps generating. With a single serving replica the next run's attestation or probe queues behind the orphan, and a short probe timeout then expires against a busy endpoint — which presents as an endpoint fault and is not one.

Before relaunching after a kill: wait for the engine to go idle, raise the probe timeout past one orphaned generation, or restart the container. Budget probe timeouts for a **contended** endpoint, not a warm idle one.

## 5. Serverless endpoints answer with redirects, and `httpx` does not follow them

Modal answers a request on a cold or scaling container with a **303** pointing at the eventual result on the same origin. `httpx` does not follow redirects by default (unlike `requests`), so a client that ignores this reads a healthy endpoint as a broken one.

If one code path in your harness handles it and another does not, the asymmetry surfaces only under contention — attestation succeeds, the probe fails, the run aborts. Follow them **bounded and same-origin**: a request carrying a bearer token must not be redirectable to another host.

## 6. Code extraction from model output

Not Inspect-specific, but it fails the same way. If your harness extracts code with regexes, check whether a bare-fence pattern can open on a *closing* delimiter and capture the prose between two blocks — it manufactures a block the model never wrote. Prefer a single pass pairing each opening delimiter with its own closing one; select by parsing (`ast.parse`) plus binding the expected entry point at module top level; and record an explicit `extraction_failed` outcome rather than executing text that was never code.

## Checklist before a billed run

- `max_samples` set explicitly, verified from server logs at the intended concurrency
- sampling values read back out of a persisted request, not asserted from config
- probe and attestation timeouts sized for a contended endpoint
- endpoint confirmed idle, or orphans cleared, before launch
- a post-run validator that fails closed on any drift from the pinned fingerprint
