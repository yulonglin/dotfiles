# Caching Best Practices Analysis

## Summary

Analysis of caching patterns in the codebase vs CLAUDE.md instructions vs industry best practices.

---

## Current CLAUDE.md Instructions (Global)

```markdown
### Caching (Required)
- Cache API responses deterministically (hash request params → store response)
- Store in `.cache/` directory (git-ignored, per-model JSONL files)
- Deterministic keys via `HashableBaseModel.model_dump_json(exclude_none=True)`
- Cache-aside pattern: check cache → fetch if miss → populate cache
- Semaphore protection for concurrent cache writes
- `--clear-cache` flag for invalidation
```

---

## Actual Implementations Found

| System | Location | Key Method | Storage | Async | Stats |
|--------|----------|------------|---------|-------|-------|
| Embedding cache | `utils/embedding_utils.py` | MD5(provider:model:texts) | `.pkl` files in `.embedding_cache/` | No | No |
| JSONL function cache | `scripts/identify_problematic_paraphrases.py` | SHA256(func+args)[:32] | JSONL | Yes | Yes |
| Fast cache (Inspect) | `utils/fast_cache.py` | Inspect's cache_key | File + Redis | Yes | Yes |
| In-memory cache | `utils/memory_cache.py` | Inspect's cache_key | Memory + pickle | No | Yes |
| Computation cache | `utils/metric_computation/computation_cache.py` | `@cached_property` | None | N/A | No |
| LRU cache | `dataset/utils.py` | `@lru_cache(8)` | Memory | N/A | No |

---

## Gaps: Instructions vs Reality

| CLAUDE.md Instruction | Actual Status | Severity |
|-----------------------|---------------|----------|
| `.cache/` directory | Multiple dirs: `.cache/`, `.embedding_cache/`, `.cache/inspect_ai/` | Low |
| JSONL per-model files | Most use `.pkl`, only 1 script uses JSONL | Low |
| `HashableBaseModel.model_dump_json()` | Not used - each system has own key generation | Medium |
| Semaphore for concurrent writes | Not consistently applied | Medium |
| `--clear-cache` flag | Not standardized, each system has own method | Low |

---

## Best Practices from Research

Sources: [Instructor LLM Caching Guide](https://python.useinstructor.com/blog/2023/11/26/python-caching-llm-optimization/), [LiteLLM Caching Docs](https://docs.litellm.ai/docs/proxy/caching), [GPT Semantic Cache Paper](https://arxiv.org/html/2411.05276v3)

### What We're Doing Well
1. **Deterministic hash-based keys** - Yes, using MD5/SHA256
2. **Validation before caching** - Embedding cache validates before storing
3. **Cache-aside pattern** - Consistently applied
4. **Multiple backend support** - File, Redis, memory options exist
5. **Statistics tracking** - In fast_cache and memory_cache

### Missing or Inconsistent
1. **Semantic caching** - Not implemented (can reduce API calls 68%+)
2. **Unified cache interface** - Each system is independent
3. **TTL consistency** - Only some caches have expiry
4. **Async I/O everywhere** - Only JSONL cache is async
5. **Clear documentation of which cache to use when**

---

## Recommendations

### Option A: Minimal Update (Low Effort)
Update CLAUDE.md to reflect reality more accurately:
- Document the multiple cache directories that exist
- Remove `HashableBaseModel` reference (not actually used)
- Add note that `.pkl` is acceptable alternative to JSONL

### Option B: Consolidate Instructions (Medium Effort)
Make CLAUDE.md more flexible:
- Replace prescriptive format (JSONL only) with principles (deterministic, serializable)
- Keep the key patterns (hash-based, cache-aside, validation)
- Add guidance on when to use which cache type

### Option C: Consolidate Implementation (High Effort)
Create unified caching utility matching CLAUDE.md:
- Single `Cache` class with file/redis/memory backends
- Standardized key generation via `HashableBaseModel`
- Consistent async support
- Migrate existing caches to use it

---

## Specific CLAUDE.md Update Suggestions

### Global CLAUDE.md Changes

**Before:**
```markdown
- Store in `.cache/` directory (git-ignored, per-model JSONL files)
- Deterministic keys via `HashableBaseModel.model_dump_json(exclude_none=True)`
```

**After (Option B):**
```markdown
- Store in `.cache/` or domain-specific cache dirs (e.g., `.embedding_cache/`)
- Deterministic keys via hash of serialized request params
  - Simple: `hashlib.sha256(json.dumps(params, sort_keys=True))`
  - Pydantic: `hashlib.sha256(model.model_dump_json(exclude_none=True))`
- Preferred formats: JSONL (human-readable), pickle (Python objects)
```

### Project CLAUDE.md Addition

Could add a "Caching Patterns" section documenting the actual caches:

```markdown
## Caching Patterns

### Cache Locations
- `.cache/` - General purpose (JSONL, per-function)
- `.embedding_cache/` - Embedding vectors (pickle)
- `~/.cache/inspect_ai/` - Inspect AI model responses

### Adding New Caches
1. Use deterministic hash keys: `sha256(json.dumps(params, sort_keys=True))`
2. Validate data before caching
3. Add `--clear-cache` or `use_cache=False` option
4. Consider async for high-throughput paths
```

---

## User Decisions

- **Approach**: Consolidate both (flexible principles in global + specifics in project)
- **Scope**: Update both CLAUDE.md files
- **Semantic caching**: Add to backlog for future exploration
- **Reference**: Follow safety-tooling patterns

---

## Reference: Caching Patterns from Key Libraries

### Latteries (Primary Reference for Async)
Source: `thejaminator/latteries/latteries/caller.py`

| Aspect | Pattern |
|--------|---------|
| **Keys** | SHA1 of `model_dump_json(exclude_none=True)` concatenation |
| **Storage** | JSONL (single file per model, append-only) |
| **Concurrency** | `anyio.Semaphore(1)` for cache loading |
| **I/O** | Fully async via `anyio` |
| **Serialization** | Pydantic `model_dump_json()` / `model_validate_json()` |

```python
# Key generation - concatenate all params and hash
messages_dump = messages.model_dump_json(exclude_none=True)
config_dump = config.model_dump_json(exclude_none=True)
_str = messages_dump + config_dump + str(try_number)
return hashlib.sha1(_str.encode()).hexdigest()

# JSONL row format
class FileCacheRow(BaseModel):
    key: str
    response: str  # JSON string of response

# Semaphore for concurrent cache loading
self.cache_check_semaphore = anyio.Semaphore(1)
async with self.cache_check_semaphore:
    await self.load_cache()
```

### Safety-Tooling (Primary Reference for Scale)
Source: `safety-research/safety-tooling/safetytooling/apis/inference/cache_manager.py`

| Aspect | Pattern |
|--------|---------|
| **Keys** | Pydantic `model_hash()` - deterministic hash from model fields |
| **Storage** | JSON bins (`bin{N}.json`) - multiple entries per file |
| **Backends** | File-based OR Redis (switchable) |
| **Concurrency** | `filelock.FileLock` for file writes |
| **Memory** | In-memory cache with LRU eviction + `max_mem_usage_mb` |
| **Serialization** | Pydantic `model_dump_json()` / `model_validate_json()` |

```python
# Key generation via Pydantic models
prompt_hash = prompt.model_hash()  # deterministic hash

# Binned storage (avoids too many files)
bin_number = int(hash, 16) % num_bins
cache_file = f"bin{bin_number}.json"

# File locking for concurrent writes
with filelock.FileLock(str(cache_file) + ".lock"):
    cache_data = load_json(cache_file)
    cache_data[prompt_hash] = entry.model_dump_json()
    save_json(cache_file, cache_data)
```

### Comparison

| Aspect | Latteries | Safety-Tooling | Recommendation |
|--------|-----------|----------------|----------------|
| Key method | SHA1(concatenated json) | model_hash() | Either works |
| Storage | JSONL append | JSON bins | JSONL simpler; bins better for huge caches |
| Concurrency | Semaphore | File lock | File lock safer for multi-process |
| Async | Full async | Sync | Async if using async API callers |

---

## Implementation Plan

### 1. Update Global CLAUDE.md (`~/.claude/CLAUDE.md`)

**File**: `/Users/yulong/.claude/CLAUDE.md`

**Section**: `### Caching (Required)` (line 202)

**Changes**:
- Align with safety-tooling patterns
- Add binned storage recommendation
- Add file locking for concurrency
- Reference safety-tooling as canonical example

**Before**:
```markdown
### Caching (Required)
- Cache API responses deterministically (hash request params → store response)
- Store in `.cache/` directory (git-ignored, per-model JSONL files)
- Deterministic keys via `HashableBaseModel.model_dump_json(exclude_none=True)`
- Cache-aside pattern: check cache → fetch if miss → populate cache
- Semaphore protection for concurrent cache writes
- `--clear-cache` flag for invalidation
```

**After** (concise version):
```markdown
### Caching (Required)
References: [Inspect AI](https://github.com/UKGovernmentBEIS/inspect_ai/blob/main/src/inspect_ai/model/_cache.py) (simple), [latteries](https://github.com/thejaminator/latteries/blob/main/latteries/caller.py) (async), [safety-tooling](https://github.com/safety-research/safety-tooling/blob/main/safetytooling/apis/inference/cache_manager.py) (scalable)

- Keys: `hashlib.sha1(model.model_dump_json(exclude_none=True).encode()).hexdigest()`
- Storage: pickle (Inspect AI), JSONL (latteries), JSON bins (safety-tooling)
- Concurrency: `anyio.Semaphore` (async) or `filelock.FileLock` (multi-process)
- Cache-aside pattern, validate before caching, provide `--clear-cache` option
```

### 2. Update Project CLAUDE.md

**File**: `/Users/yulong/code/sandbagging-detection/dev/CLAUDE.md`

**Location**: Add new section after "Configuration System" (around line 330)

**New Section** (concise version):
```markdown
## Caching Patterns

See global CLAUDE.md for patterns. References: [latteries](https://github.com/thejaminator/latteries/blob/main/latteries/caller.py), [safety-tooling](https://github.com/safety-research/safety-tooling/blob/main/safetytooling/apis/inference/cache_manager.py)

### Cache Locations
- `.cache/` - Function results (JSONL)
- `.embedding_cache/` - Embedding vectors (pickle)
- `~/.cache/inspect_ai/` - Inspect AI responses
```

### 3. Backwards-Compatible Cache Improvements (Code Changes)

**Safe to add without regenerating caches:**

| Cache | File | Improvement |
|-------|------|-------------|
| Embedding cache | `utils/embedding_utils.py` | Add file locking (`filelock.FileLock`) |
| Function cache | `scripts/identify_problematic_paraphrases.py` | Already has async + semaphore ✅ |
| Fast cache | `utils/fast_cache.py` | Already robust ✅ |

**Embedding cache improvement** (line ~250):
```python
# Before
with open(cache_file, 'wb') as f:
    pickle.dump(embeddings, f)

# After (add file locking)
import filelock
with filelock.FileLock(str(cache_file) + ".lock"):
    with open(cache_file, 'wb') as f:
        pickle.dump(embeddings, f)
```

### 4. Update Agents

**Files with caching guidance that should match CLAUDE.md:**
- `~/.claude/agents/research-engineer.md` - mentions `HashableBaseModel` (outdated)
- `~/.claude/agents/tooling-engineer.md` - has caching section

**Change**: Replace `HashableBaseModel.model_dump_json()` with `model.model_dump_json(exclude_none=True)`

### 5. Files to Modify

| File | Action |
|------|--------|
| `/Users/yulong/.claude/CLAUDE.md` | Edit caching section (line 202-208) |
| `/Users/yulong/code/sandbagging-detection/dev/CLAUDE.md` | Add new section after Configuration System |
| `~/.claude/agents/research-engineer.md` | Update caching section |
| `~/.claude/agents/tooling-engineer.md` | Update caching section |
| `src/detection_game/utils/embedding_utils.py` | Add file locking (optional) |

### 6. Verification

After editing:
- Grep for "Cache" in both files to verify changes
- Ensure no duplicate sections
