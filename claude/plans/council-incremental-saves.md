# Plan: Incremental Saves for Council Generation

## Problems
1. **Lost progress on refresh**: When browser refreshes mid-generation, all council work is lost (saves only after all 3 stages complete)
2. **Race condition**: Two tabs sending messages simultaneously can overwrite each other's data (no file locking)

## Solution
1. Save each stage incrementally as it completes
2. Add file locking to prevent concurrent write corruption

## Changes

### 1. Backend: `storage.py`

**Add file locking** using `filelock` library (cross-platform):

```python
from filelock import FileLock

def get_conversation_lock(conversation_id: str) -> FileLock:
    """Get a lock for a specific conversation."""
    lock_path = get_conversation_path(conversation_id) + ".lock"
    return FileLock(lock_path, timeout=30)

def save_conversation(conversation: Dict[str, Any]):
    """Save with locking to prevent race conditions."""
    with get_conversation_lock(conversation['id']):
        # ... existing save logic
```

All read-modify-write operations will acquire the lock first.

**Add two new functions for incremental saves:**

```python
def create_assistant_message(conversation_id: str, status: str = "in_progress") -> int:
    """Create an empty assistant message placeholder. Returns message index."""
    # Appends: {"role": "assistant", "status": "in_progress", "stage1": None, "stage2": None, "stage3": None}
    # Returns index of new message

def update_assistant_message(conversation_id: str, message_index: int, **updates):
    """Update an existing assistant message with new stage data."""
    # Merges updates into the message at given index
    # e.g., update_assistant_message(id, idx, stage1=results, status="stage1_complete")
```

Status values: `"in_progress"` → `"stage1_complete"` → `"stage2_complete"` → `"complete"`

### 2. Backend: `main.py` (streaming endpoint)

Modify `send_message_stream()` to save after each stage:

```python
async def event_generator():
    # Add user message (already done)
    storage.add_user_message(...)

    # Create assistant message placeholder BEFORE stage 1
    msg_index = storage.create_assistant_message(conversation_id)

    # Stage 1
    yield stage1_start
    stage1_results = await stage1_collect_responses(...)
    storage.update_assistant_message(conversation_id, msg_index,
        stage1=stage1_results, status="stage1_complete")  # ← SAVE
    yield stage1_complete

    # Stage 2
    yield stage2_start
    stage2_results, label_to_model = await stage2_collect_rankings(...)
    storage.update_assistant_message(conversation_id, msg_index,
        stage2=stage2_results, status="stage2_complete")  # ← SAVE
    yield stage2_complete

    # Stage 3
    yield stage3_start
    stage3_result = await stage3_synthesize_final(...)
    storage.update_assistant_message(conversation_id, msg_index,
        stage3=stage3_result, status="complete")  # ← SAVE
    yield stage3_complete
```

### 3. Frontend: Minor UI enhancement (optional)

When loading a conversation with an incomplete message (`status !== "complete"`), show a subtle indicator like "Generation was interrupted" with the completed stages visible.

The frontend already handles `null` stages gracefully, so this is optional polish.

## Files to Modify
- `backend/storage.py` - add file locking + 2 new incremental save functions
- `backend/main.py` - modify streaming endpoint to save incrementally
- `pyproject.toml` - add `filelock>=3.0.0` to dependencies

## Verification

**Test incremental saves:**
1. Start the backend and frontend
2. Send a message to the council
3. While Stage 1 or Stage 2 is running, refresh the browser
4. The conversation should reload with the completed stages visible
5. Incomplete messages show with whatever stages completed

**Test race condition fix:**
1. Open two browser tabs with the same conversation
2. Send a message from Tab A
3. Quickly send a message from Tab B before Tab A completes
4. Both messages should be preserved (no overwrites)
5. Check `data/conversations/` - both user messages and responses present

## Edge Cases
- If refresh happens during Stage 1 (before any save), the assistant message exists but all stages are null → frontend shows empty response or "interrupted" state
- Metadata (label_to_model, aggregate_rankings) is still ephemeral - only needed for live display, not persisted
