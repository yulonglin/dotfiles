#!/usr/bin/env python3
"""Markdown hard-wrap nudge — enforces rules/communication.md's "one paragraph =
one line" at write time.

PostToolUse(Write|Edit) on `.md` files: flag prose paragraphs broken by hard
newlines. The scan runs over the post-edit document (Write content, or the
file on disk for Edit) so fence state is known even when the edited fragment
starts mid-fence; hits are then filtered to lines the tool actually wrote, so
editing near pre-existing hard wraps doesn't re-flag them.

The heuristic is deliberately conservative — a line that ends mid-sentence
(lowercase letter or comma) followed by a line starting lowercase, outside
fenced code blocks and non-prose constructs. Missing a wrap is cheaper than a
nudge nobody trusts.

NUDGE only — never blocks, always exit 0.
"""

import json
import re
import sys

SKIP_PATH_RE = re.compile(r"(^|/)(node_modules|\.venv|\.git|archive)(/|$)")
MAX_DOC_BYTES = 1_000_000

# Lines that are not flowing prose: headings, list items, quotes, tables,
# HTML, footnotes/link defs, YAML-ish keys, indented code. (Fences are
# handled separately with char/length tracking.)
NON_PROSE_RE = re.compile(
    r"^\s*(#|[-*+]\s|\d+[.)]\s|>|\||<|\[\^|\[[^\]]+\]:|\S+:\s|    )"
)
# ```-style fence: a closing marker must match the opening char and be at
# least as long, so ``` inside a ````-fenced block doesn't toggle state.
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
ENDS_MID_SENTENCE_RE = re.compile(r"[a-z,]$")
STARTS_LOWER_RE = re.compile(r"^[a-z(\"'`]")


def extract(data: object) -> tuple[str, str, list[str]]:
    """Return (path, whole-document content or '', written fragments)."""
    if not isinstance(data, dict):
        return "", "", []
    inp = data.get("tool_input", data)
    if not isinstance(inp, dict):
        return "", "", []
    path = inp.get("file_path", "") or ""
    doc = inp.get("content") or ""
    frags = []
    if not doc:
        if inp.get("new_string"):
            frags = [inp["new_string"]]
        elif isinstance(inp.get("edits"), list):
            frags = [
                e["new_string"]
                for e in inp["edits"]
                if isinstance(e, dict) and e.get("new_string")
            ]
    return path, doc, frags


def _is_prose(line: str) -> bool:
    # Interior ` | ` catches GFM table rows written without outer pipes.
    return not NON_PROSE_RE.match(line) and " | " not in line


def find_hard_wraps(content: str) -> list[str]:
    hits = []
    fence = None  # (marker char, length) of the open fence, or None
    lines = content.splitlines()
    for line, nxt in zip(lines, lines[1:]):
        m = FENCE_RE.match(line)
        if m:
            tick = m.group(1)
            if fence is None:
                fence = (tick[0], len(tick))
            elif tick[0] == fence[0] and len(tick) >= fence[1]:
                fence = None
            continue
        if fence:
            continue
        if not _is_prose(line) or not nxt.strip() or not _is_prose(nxt):
            continue
        if (
            len(line.strip()) > 40
            and ENDS_MID_SENTENCE_RE.search(line.rstrip())
            and STARTS_LOWER_RE.match(nxt.strip())
        ):
            hits.append(line.strip())
    return hits


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    path, doc, frags = extract(data)
    if not path or not path.endswith(".md") or not (doc or frags):
        sys.exit(0)
    if SKIP_PATH_RE.search(path):
        sys.exit(0)

    if doc:  # Write: the content IS the document
        hits = find_hard_wraps(doc)
    else:  # Edit: scan the post-edit file so fence context is real
        written = {
            ln.strip() for f_ in frags for ln in f_.splitlines() if ln.strip()
        }
        # A hit must be a written line that is long and ends mid-sentence —
        # skip the disk read entirely when no fragment line qualifies.
        if not any(
            len(ln) > 40 and ENDS_MID_SENTENCE_RE.search(ln) for ln in written
        ):
            sys.exit(0)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                on_disk = f.read(MAX_DOC_BYTES)
            hits = [h for h in find_hard_wraps(on_disk) if h in written]
        except OSError:
            # No document context: scan each fragment independently, skipping
            # any whose fence state is unknowable.
            hits = [
                h
                for f_ in frags
                if not any(FENCE_RE.match(ln) for ln in f_.splitlines())
                for h in find_hard_wraps(f_)
            ]

    if not hits:
        sys.exit(0)

    more = f" (+{len(hits) - 1} more)" if len(hits) > 1 else ""
    print(json.dumps({
        "systemMessage": (
            f"NUDGE: hard-wrapped paragraph(s) in {path.rsplit('/', 1)[-1]}, "
            f"e.g. “{hits[0][:60]}…”{more}. One paragraph = one line "
            "— join the lines; blank lines separate paragraphs "
            "(rules/communication.md)."
        )
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
