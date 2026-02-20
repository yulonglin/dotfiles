# Coding Conventions

## Python Basics

- Run from project root with `uv` and `python -m`
- Type hints required, imports at top
- Let errors propagate (no unnecessary try/except)
- Testing: `pytest`
- **Read .eval files** using Inspect AI's `read_eval_log()` (look up via MCP server)
- **Config via pydantic-settings** (preferred for 3+ env vars):
  ```python
  from pydantic_settings import BaseSettings

  class Config(BaseSettings):
      api_key: str  # reads API_KEY from env/.env automatically

  config = Config()
  ```

### sys.path.insert (Safe Pattern)

```python
# src/utils/paths.py
import sys
from pathlib import Path

def add_project_root():
    project_root = Path(__file__).resolve().parent.parent.parent
    if project_root not in sys.path:
        sys.path.insert(0, str(project_root))

# In scripts (only in __main__ block):
if __name__ == "__main__":
    from src.utils.paths import add_project_root
    add_project_root()
```

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

### Python Practices

- **Don't mutate objects** — copy/`deepcopy` configs, prompts, and shared data structures. Mutation causes silent bugs
- **Python over complex bash** — if a shell script exceeds ~50 lines or needs error handling, rewrite it in Python. Python is a scripting language — use it
- **No YAML-as-code** — YAML for static config is fine; YAML that branches, loops, or templates is not. Prefer Python so you can "Go to References" in your editor
- **Pydantic models over DataFrames** — pass data as `BaseModel` / `dataclass`, not `pd.DataFrame`. DataFrames are untyped, lossy, and opaque to both humans and LLMs. Use JSONL for intermediate storage
- **Pandas at the edges only** — use pandas for computing metrics / aggregations at the end of a pipeline, not as the data transport format throughout

## TypeScript

- Prefer TypeScript over JavaScript for all frontend/Node work
- Tooling: bun (runtime + pkg mgr) + tsc (types) + Biome (lint + format)
- Biome replaces ESLint + Prettier — single Rust-based binary

## Date & Timestamp Formatting

- **Always use UTC timezone** for all timestamps
- **Standard format**: `DD-MM-YYYY` for dates, `DD-MM-YYYY_HH-MM-SS` for timestamps
- **Helper commands** (in PATH):
  - `$(utc_date)` → outputs `DD-MM-YYYY` (e.g., `25-01-2026`)
  - `$(utc_timestamp)` → outputs `DD-MM-YYYY_HH-MM-SS` (e.g., `25-01-2026_14-30-22`)

## Shell Scripts

- Run `shellcheck script.sh` before committing
- Fix all errors; warnings are usually worth addressing
- For zsh scripts, use `# shellcheck shell=bash` at top (closest approximation)
- Suppress false positives with `# shellcheck disable=SCXXXX` (include reason)

## General Programming

- Match existing code style
- Run linting and type checking after Python changes (see Python Tooling table)
- Refactor when unwieldy (>50 lines/function, >500 lines/file)

## Package Managers (preference order)

1. **bun** — Fastest, includes runtime, good compatibility  
   - Prefer `bunx` over `npx` for executing CLI tools/scripts—`bunx` is significantly faster.
2. **pnpm** — Efficient disk usage, strict dependencies
3. **npm** — Universal fallback

Check for `bun.lockb`, `pnpm-lock.yaml`, or `package-lock.json` to detect which is in use.

## Language Selection

| Need | Default | When to reconsider |
|------|---------|-------------------|
| ML / research / prototyping | Python | — |
| Frontend / scripting / APIs | TypeScript | Plain JS only for trivial scripts |
| Performance-critical CLI/tools | Rust | Go if team familiarity matters; Zig for low-level/embedded |
| Shell glue | Bash/Zsh | Python if >50 lines, needs error handling, or involves data manipulation |

This is a preference order, not a mandate. Match the tool to the job.

## CLI Tools Available

ripgrep (`rg`), fd, fzf, bat, eza, zoxide (`z`), delta, jq, jless, btop, dust, duf, bun, bunx, sd (prefer over `sed`), trash (macOS — prefer over `rm`)

## Visual Output Quality

When generating any visual output (TikZ, HTML/CSS, Slidev, matplotlib):

- **Verify visually** — CSS/TikZ/layout changes MUST be checked against rendered output (Playwright screenshot, compiled PDF, browser preview). Accessibility snapshots do NOT reveal spacing issues
- **Act on reviewer layout feedback immediately** — visual bugs from CSS fragility are invisible in code review; when a reviewer flags it, fix it
- **Use layout systems, not manual coordinates** — flexbox/grid (CSS), `positioning` library (TikZ), CSS Grid (Slidev). Manual pixel/pt values drift and overlap
- **Container padding > per-child padding** — pad the container itself, not each child with `> :not(x)` selectors. Markdown renderers produce varying DOM structures
- **Test with variable content** — would this layout still work if text were 20% longer or a list had 2x items?

### Minimum Spacing (hard floor — never go below)

| Domain | Container padding | Content-to-edge gap | Between sibling elements |
|--------|------------------|--------------------|-----------------------|
| **HTML/CSS** | `p-3` / `0.75rem` / `12px` | `p-2` / `0.5rem` / `8px` | `gap-2` / `0.5rem` |
| **TikZ** | `inner sep>=10pt` | `inner sep>=8pt` | `node distance>=1.5cm` |
| **Slidev** | `p-4` / `1rem` on slide content | `p-2` on nested elements | `gap-3` / `0.75rem` |
