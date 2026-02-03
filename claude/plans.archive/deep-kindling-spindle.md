# Implementation Plan: Reasoning Mode Toggle for LLM Council

## Summary
Add user-configurable reasoning/thinking mode per stage with a settings modal, budget presets, and visual indicators showing which models used reasoning.

## Design Decisions (from brainstorming)
- **Per-stage toggles**: Stage 1, 2, 3 each independently configurable
- **Defaults**: All off (users opt-in)
- **Budget presets**: Light (5k), Medium (10k), Deep (25k tokens)
- **Detection-based**: Always send reasoning params when enabled, detect from response if used
- **Settings UI**: Modal with gear icon in sidebar

---

## Implementation Steps

### Step 1: Backend - Update `openrouter.py`
**File**: `backend/openrouter.py`

Add `reasoning_budget` parameter to `query_model()`:
```python
async def query_model(
    model: str,
    messages: List[Dict[str, str]],
    timeout: float = 120.0,
    reasoning_budget: Optional[int] = None  # NEW
) -> Optional[Dict[str, Any]]:
```

Changes:
- When `reasoning_budget` provided, add to payload: `"thinking": {"type": "enabled", "budget_tokens": reasoning_budget}`
- Detect reasoning usage: check for `reasoning` or `reasoning_details` in response
- Return new field: `reasoning_used: bool`

### Step 2: Backend - Update `council.py`
**File**: `backend/council.py`

Add `reasoning_budget` parameter to all three stage functions:
- `stage1_collect_responses(user_query, reasoning_budget=None)`
- `stage2_collect_rankings(user_query, stage1_results, reasoning_budget=None)`
- `stage3_synthesize_final(user_query, stage1_results, stage2_results, reasoning_budget=None)`

Pass through to `query_model()` / `query_models_parallel()` calls.

Update return structures to include `reasoning_used` per model.

### Step 3: Backend - Update `main.py`
**File**: `backend/main.py`

Add reasoning settings to request model:
```python
class ReasoningSettings(BaseModel):
    stage1: bool = False
    stage2: bool = False
    stage3: bool = False
    budget: str = "medium"  # "light" | "medium" | "deep"

class SendMessageRequest(BaseModel):
    content: str
    reasoning: Optional[ReasoningSettings] = None
```

Add budget mapping:
```python
BUDGET_TOKENS = {"light": 5000, "medium": 10000, "deep": 25000}
```

Update streaming endpoint to:
1. Extract reasoning settings from request
2. Map budget preset to token count
3. Pass appropriate budget to each stage based on per-stage toggles

### Step 4: Frontend - Create Settings Component
**New file**: `frontend/src/components/Settings.jsx`
**New file**: `frontend/src/components/Settings.css`

Modal component with:
- Section header: "Reasoning Mode"
- Three toggle switches with labels
- Dropdown for budget preset
- Close button (X or "Done")

### Step 5: Frontend - Update Sidebar
**File**: `frontend/src/components/Sidebar.jsx`
**File**: `frontend/src/components/Sidebar.css`

Add gear icon button in `.sidebar-header` that calls `onOpenSettings` prop.

### Step 6: Frontend - Update App.jsx
**File**: `frontend/src/App.jsx`

- Add `settings` state (loaded from localStorage on mount)
- Add `showSettings` state for modal visibility
- Save settings to localStorage on change
- Pass settings to API call
- Pass `onOpenSettings` prop to Sidebar

### Step 7: Frontend - Update API
**File**: `frontend/src/api.js`

Update `sendMessageStream()` to accept and send reasoning settings:
```javascript
sendMessageStream: async (conversationId, content, onEvent, reasoning = null) => {
  // Add reasoning to body if provided
  body: JSON.stringify({ content, reasoning })
}
```

### Step 8: Frontend - Add Reasoning Indicators
**Files**: `frontend/src/components/Stage1.jsx`, `frontend/src/components/Stage2.jsx`

Add 🧠 indicator next to model name in tabs when `resp.reasoning_used` is true.

---

## Files to Modify
1. `backend/openrouter.py` - Add reasoning_budget param, detect usage
2. `backend/council.py` - Pass reasoning through stages
3. `backend/main.py` - Accept settings in request, map budget
4. `frontend/src/components/Settings.jsx` - NEW: Settings modal
5. `frontend/src/components/Settings.css` - NEW: Modal styling
6. `frontend/src/components/Sidebar.jsx` - Add settings button
7. `frontend/src/components/Sidebar.css` - Style settings button
8. `frontend/src/App.jsx` - Manage settings state
9. `frontend/src/api.js` - Send reasoning with requests
10. `frontend/src/components/Stage1.jsx` - Add reasoning indicator
11. `frontend/src/components/Stage2.jsx` - Add reasoning indicator

---

## Verification

### Manual Testing
1. Start backend: `cd backend && python -m backend.main`
2. Start frontend: `cd frontend && npm run dev`
3. Open http://localhost:5173

**Test cases:**
- [ ] Settings modal opens when clicking gear icon
- [ ] Toggles and dropdown work, persist across page refresh (localStorage)
- [ ] With all reasoning OFF: responses work as before, no 🧠 indicators
- [ ] With Stage 2 reasoning ON + a reasoning-capable model: 🧠 appears on that model's tab
- [ ] Budget dropdown changes are reflected (check network request payload)
- [ ] Models that don't support reasoning: no 🧠 indicator, request still succeeds
