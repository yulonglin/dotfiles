# Plan: Live Model Status Tracking

## Requirements
1. **Live token counts** per model during Stage 1 and Stage 2
2. **Error visibility** on UI when models fail
3. **Timestamps** on server logs
4. **Graceful degradation** - continue if one model errors out

## UI Target
```
┌─────────────────────────────────────────┐
│ Stage 1: Collecting responses           │
├─────────────────────────────────────────┤
│ ✓ openai/gpt-4o          823 tokens     │
│ ● google/gemini-2.5-pro  456 tokens...  │
│ ● anthropic/claude-sonnet 312 tokens... │
│ ✗ meta/llama-3           Error: timeout │
└─────────────────────────────────────────┘
```

## Architecture Change

**Current**: `asyncio.gather()` waits for all models, no progress visibility
**New**: Streaming from OpenRouter + progress events via SSE

## New SSE Event Types

```python
# Model progress (emitted as tokens arrive)
{"type": "model_progress", "stage": 1, "model": "openai/gpt-4o", "status": "generating", "token_count": 456}
{"type": "model_progress", "stage": 1, "model": "openai/gpt-4o", "status": "completed", "token_count": 823}
{"type": "model_progress", "stage": 1, "model": "meta/llama-3", "status": "error", "token_count": 0, "error": "timeout"}
```

## Implementation Steps

### 1. Backend: `openrouter.py`
- Add `query_model_streaming()` - streams from OpenRouter with `stream: True`
- Add `query_models_parallel_streaming()` - runs streams in parallel, emits progress to queue
- Count tokens as chunks arrive (1 chunk ≈ 1 token approximation)

### 2. Backend: `council.py`
- Add `stage1_collect_responses_streaming(user_query, event_queue)`
- Add `stage2_collect_rankings_streaming(user_query, stage1_results, event_queue)`
- Keep original functions as fallback

### 3. Backend: `main.py`
- Update `/message/stream` endpoint to emit `model_progress` events
- Use `asyncio.Queue` to collect progress from parallel streams
- Add `/api/config` endpoint to expose `COUNCIL_MODELS` to frontend
- Add timestamped logging: `logging.basicConfig(format='%(asctime)s.%(msecs)03d [%(levelname)s] %(message)s')`

### 4. Frontend: New `ModelProgress.jsx` component
- Shows list of models with status icons (✓ ● ✗ ○)
- Displays token count or error message
- Animates "generating" status with pulse

### 5. Frontend: `App.jsx`
- Add `modelProgress` state: `{stage1: {}, stage2: {}}`
- Handle `model_progress` events to update per-model status
- Pass progress to `ChatInterface`

### 6. Frontend: `ChatInterface.jsx`
- Replace spinner with `<ModelProgress>` component during loading
- Fetch model list from `/api/config` on mount

## Files to Modify

| File | Change |
|------|--------|
| `backend/openrouter.py` | Add streaming query functions |
| `backend/council.py` | Add streaming stage functions |
| `backend/main.py` | Update SSE generator, add config endpoint, add logging |
| `frontend/src/App.jsx` | Add modelProgress state, handle new events |
| `frontend/src/components/ChatInterface.jsx` | Use ModelProgress component |
| `frontend/src/components/ModelProgress.jsx` | **New file** |
| `frontend/src/components/ModelProgress.css` | **New file** |
| `frontend/src/api.js` | Add getConfig() |

## Error Handling (Graceful Degradation)

- Individual model errors caught in `query_model_streaming()`
- Error emitted as `model_progress` event with `status: "error"`
- Failed model excluded from results, other models continue
- UI shows error icon + message for failed model
- Stage completes successfully if at least one model succeeds

## Verification

1. **Start backend**: `cd backend && python -m backend.main`
2. **Start frontend**: `cd frontend && npm run dev`
3. **Test happy path**: Send a query, verify token counts increment for each model
4. **Test error**: Temporarily add invalid model to config, verify error shows in UI
5. **Verify logs**: Check backend console shows timestamped logs
6. **Verify degradation**: Confirm stage completes even with one model failure
