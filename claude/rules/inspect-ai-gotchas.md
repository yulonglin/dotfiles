# Inspect AI Gotchas

Failure modes of `inspect_ai` that are silent — the run completes, the numbers look plausible, and the defect is only visible if you go looking. Each was paid for once. Verified against 0.3.241.

## Concurrency: `max_samples` is the gate that matters

`max_connections` bounds concurrent *requests*, but a solver issues one request per sample, so it bounds nothing unless something is running samples in parallel. `max_samples` defaults to `None` and does **not** inherit `max_connections`.

Symptom: the serving engine reports `Running: 1 reqs, Waiting: 0 reqs` at single-stream throughput while you believe you configured 8-way concurrency. On a self-hosted endpoint billed by wall-clock this is a straight multiple on cost — observed once as ~48 GPU-hours where ~7 were expected.

Always set `max_samples` explicitly, and confirm it from the server's own logs rather than from the config you passed.

## `ModelOutput.stop_reason` raises rather than defaulting

It is a property over `choices[0]`. On an errored or aborted generation, `choices` is empty and reading it raises `IndexError` — and `getattr(output, "stop_reason", None)` does **not** catch that, because the default only covers `AttributeError`, not an exception raised inside the property.

Guard on `choices` being non-empty before reading it. The same shape applies to any Inspect property that indexes into a list.

## Killing a run does not stop the server

The client dies; the server keeps generating. With a single serving replica the next run's attestation or probe then queues behind the orphan, and a short probe timeout expires against a busy endpoint — which looks like an endpoint fault and is not.

Before relaunching after a kill: wait for the engine to go idle, raise the probe timeout past one orphaned generation, or restart the container. Budget probe timeouts for a *contended* endpoint, not a warm idle one.

## `GenerateConfig` silently drops provider-specific fields

`top_k` and similar non-standard sampling fields do not survive to the request. They must ride `extra_body`. Verify from a persisted request body, never from the config object.

## Verify sampling from what was recorded, not what was set

The general form of all of the above: Inspect's config surface and the bytes that reach the server are different things. Any claim about how a run sampled should be read out of the persisted `ModelEvent.call.request`, and ideally checked by a post-run validator that compares every recorded event field-by-field against a pinned expectation. A `Literal`-pinned fingerprint model makes an unplanned value fail at construction instead of producing a run that silently differs.

Related: `rules/verify-before-instructing.md`.
