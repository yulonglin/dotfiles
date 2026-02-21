# Plan: Add Python Tooling Preferences to Coding Conventions

## Context

The coding conventions rule file (`claude/rules/coding-conventions.md`) already mentions `uv`, `ruff`, and `ty` in passing but lacks a consolidated Python tooling preference table. Adding explicit preferences for package management, linting, type checking, task running, CLI frameworks, config/env, validation, HTTP, and async — all in one scannable table with rationale.

## Changes

**File:** `claude/rules/coding-conventions.md`

### 1. Add `### Python Tooling (preference order)` after the sys.path block (line 32), before `## TypeScript`

```markdown
### Python Tooling (preference order)

| Need | Tool | Over | Why |
|------|------|------|-----|
| Package mgmt | `uv` | pip/poetry | 10-100x faster, single binary, replaces pip+venv+poetry |
| Lint + format | `ruff` | flake8/black/isort | Single Rust binary replaces 3 tools, near-instant |
| Type check | `ty` | mypy/pyright | Rust-based, 10-60x faster; beta — fall back to pyright if ty gaps block you |
| Task runner | `just` | Makefile / shell scripts | Simpler syntax, no tab sensitivity, cross-platform |
| CLI | `cyclopts` | argparse/typer | Pydantic-native, `Annotated` types, 38% less code; niche — LLM codegen may need corrections |
| Config/env | `pydantic-settings` | python-dotenv / manual `os.getenv` | Typed config with `SecretStr`, env/file/vault sources |
| Validation | `pydantic` | manual parsing | Schema validation + serialization, ecosystem standard |
| Testing | `pytest` | unittest | Less boilerplate, fixtures, parametrize, rich plugin ecosystem |
| HTTP client | `httpx` | requests | Async-native, HTTP/2, drop-in requests-compatible API |
| Async | `anyio` | raw asyncio / trio | Structured concurrency on asyncio backend; proper task group cancellation, cleaner API |
```

### 2. Add `### Python Practices` immediately after the tooling table

```markdown
### Python Practices

- **Don't mutate objects** — copy/`deepcopy` configs, prompts, and shared data structures. Mutation causes silent bugs
- **Python over complex bash** — if a shell script exceeds ~50 lines or needs error handling, rewrite it in Python. Python is a scripting language — use it
- **No YAML-as-code** — YAML for static config is fine; YAML that branches, loops, or templates is not. Prefer Python so you can "Go to References" in your editor
- **Pydantic models over DataFrames** — pass data as `BaseModel` / `dataclass`, not `pd.DataFrame`. DataFrames are untyped, lossy, and opaque to both humans and LLMs. Use JSONL for intermediate storage
- **Pandas at the edges only** — use pandas for computing metrics / aggregations at the end of a pipeline, not as the data transport format throughout
```

### 3. Replace the `load_dotenv()` code sample (lines 10-14) with pydantic-settings

Replace:
```python
- **Load `.env` before API calls**:
  ```python
  from dotenv import load_dotenv
  load_dotenv()  # Call before os.getenv() or API client init
  ```
```

With:
```python
- **Config via pydantic-settings** (preferred for 3+ env vars):
  ```python
  from pydantic_settings import BaseSettings

  class Config(BaseSettings):
      api_key: str  # reads API_KEY from env/.env automatically

  config = Config()
  ```
```

### 4. Update "General Programming" section (line 58)

Change:
```
- Run linting (`ruff`) and type checking (`ty`) after changes
```
To:
```
- Run linting and type checking after Python changes (see Python Tooling table)
```

### 5. Simplify existing Python Basics bullet points

- Line 5 (`uv`): Keep — it's a usage instruction
- Line 8 (`pytest`): Simplify to just "Testing: `pytest`" (rationale now lives in tooling table)

### 6. Update Language Selection table (line 77)

Add note to the "Shell glue" row to reinforce the Python-over-bash practice:
```
| Shell glue | Bash/Zsh | Python if >50 lines, needs error handling, or involves data manipulation |
```

## Verification

- Read modified file, confirm table renders correctly
- Confirm no contradictions between the new table and existing mentions
