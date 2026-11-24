#!/usr/bin/env python3
"""Check which model actually answered a subagent, from its transcript.

An agent's label ("gemini") says what was requested. It does not say what answered:
a routing name the model-router gateway does not serve is answered by the default
Claude model under the foreign label. The answering model is recorded per reply in
the subagent transcript, so attribution comes from there.

Where the evidence is (measured on Claude Code transcripts, 2026-11-20 to 11-24):

  type == "assistant" records, field message.model
      The model the API response named: "google/gemini-4-neon" for the gemini
      agent, "gpt-6.2-astra" for astra, "claude-opus-5-5" for general-purpose.
      One record per content block, so replies are counted by distinct message.id.
  NOT the answering model (all hold the requested name or a sidecar):
      top-level requestedModel ("gemini"), api-request params.model ("gemini"),
      the {"type":"model"} attachment ("You are powered by the model gemini"),
      advisorModel and the advisor_tool attachment (the advisor, e.g. Fable).
  Skipped: records with isApiErrorMessage true or a "<synthetic>" model.

Expected model, first that resolves: --expect; the "model" key of the sibling
agent-<id>.meta.json (the Agent call's override, else the agent's frontmatter,
as Claude Code resolved it); the most common requestedModel in the transcript;
the agent definition's frontmatter `model:`. A requested name is then widened to
the names that may answer it: opus/sonnet/haiku/fable match any claude-<family>-*
model; a claude-* ID matches itself and dated variants; a router name matches its
[[models]] id and slug in config/model-router.toml.

Not checked, logged only: `inherit` (no label to verify, and the parent can switch
models mid-run), and a name the router table does not list unless a Claude model
answered it (that is the silent-fallback signature, so it still counts).

Hook modes (stdin JSON; always exit 0, never block):
  SubagentStop  check the agent; append one line to the check log; on mismatch
                show a systemMessage to the user; for a mismatch, or a match on a
                non-Claude model, leave a pending note for the parent session.
                SubagentStop's additionalContext and decision go to the SUBAGENT
                and keep it running, so neither is used.
  PostToolUse   in the main session only (no agent_id): hand pending notes to
                the main model as additionalContext.
  Stop          the same for mismatches; match notes are dropped unsent, so a
                match never extends a turn (the user already saw it).

The PostToolUse/Stop drain exists because a background Agent call's tool result
is written at launch ("async_launched"), long before the agent finishes, so a
PostToolUse hook on Agent cannot carry the verdict.

CLI: verify_subagent_model.py --transcript PATH [--expect MODEL] [--json]
Exit codes: 0 match, 1 mismatch, 2 usage error, 3 indeterminate (no replies,
inherit, or no expected model could be resolved).
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HOOK_DIR = Path(__file__).resolve().parent
REPO = HOOK_DIR.parents[1]
ROUTER_TOML = Path(
    os.environ.get("MODEL_ROUTER_SOURCE", REPO / "config" / "model-router.toml")
)
CLAUDE_FAMILIES = ("opus", "sonnet", "haiku", "fable")
PENDING_MAX_AGE_S = 2 * 86400


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(base) / "model-router"


def log_path() -> Path:
    return state_dir() / "agent-model-checks.jsonl"


def pending_dir() -> Path:
    return state_dir() / "agent-model-pending"


# --- reading the transcript -------------------------------------------------


def read_records(path: Path):
    with path.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if isinstance(rec, dict):
                yield rec


def answering_models(path: Path) -> tuple[collections.Counter, collections.Counter]:
    """Distinct replies (message.id) per answering model, and requestedModel counts."""
    seen: dict[str, str] = {}
    requested: collections.Counter = collections.Counter()
    for i, rec in enumerate(read_records(path)):
        if rec.get("type") != "assistant" or rec.get("isApiErrorMessage") is True:
            continue
        msg = rec.get("message") or {}
        model = msg.get("model")
        if not isinstance(model, str) or not model or model.startswith("<"):
            continue
        seen.setdefault(str(msg.get("id") or rec.get("uuid") or i), model)
        if isinstance(rec.get("requestedModel"), str):
            requested[rec["requestedModel"]] += 1
    return collections.Counter(seen.values()), requested


def read_meta(transcript: Path) -> dict:
    meta = transcript.with_name(transcript.name[: -len(".jsonl")] + ".meta.json")
    try:
        data = json.loads(meta.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def frontmatter_model(agent_type: str, cwd: str | None) -> str | None:
    """`model:` from the agent definition named agent_type (user or project agents)."""
    if not agent_type or ":" in agent_type:
        return None  # built-ins have no file; plugin agents live in the plugin cache
    dirs = [Path.home() / ".claude" / "agents", HOOK_DIR.parent / "agents"]
    if cwd:
        dirs.insert(0, Path(cwd) / ".claude" / "agents")
    for d in dirs:
        for f in sorted(d.glob("*.md")) if d.is_dir() else []:
            try:
                head = f.read_text(errors="replace").split("\n---", 1)[0]
            except OSError:
                continue
            fields = dict(re.findall(r"^(name|model):\s*(\S+)\s*$", head, re.MULTILINE))
            if fields.get("name") == agent_type:
                return fields.get("model") or "inherit"
    return None


# --- what may answer a requested name ---------------------------------------


def router_models() -> list[dict]:
    try:
        text = ROUTER_TOML.read_text()
    except OSError:
        return []
    try:
        import tomllib  # Python 3.11+

        return [m for m in tomllib.loads(text).get("models", []) if isinstance(m, dict)]
    except ImportError:
        pass
    except ValueError:
        return []
    models: list[dict] = []  # fallback for older Pythons: only the keys used here
    for block in re.split(r"^\[\[models\]\][ \t]*$", text, flags=re.MULTILINE)[1:]:
        block = block.split("\n[", 1)[0]
        entry: dict = {}
        for key in ("id", "slug", "provider"):
            m = re.search(rf'^{key}\s*=\s*"([^"]+)"', block, re.MULTILINE)
            if m:
                entry[key] = m.group(1)
        m = re.search(r"^aliases\s*=\s*\[([^\]]*)\]", block, re.MULTILINE)
        entry["aliases"] = re.findall(r'"([^"]+)"', m.group(1)) if m else []
        models.append(entry)
    return models


def accepted_names(requested: str) -> tuple[list[str], str]:
    """Names an answer may carry for this request, and how they were derived."""
    name = re.sub(r"\[.*\]$", "", requested.strip()).lower()
    if name in CLAUDE_FAMILIES:
        return [f"claude-{name}-*"], f"Claude {name} family"
    if name.startswith("claude-"):
        return [name], "Claude model ID"
    for entry in router_models():
        ids = [entry.get("id", "")] + list(entry.get("aliases") or [])
        if name in [i.lower() for i in ids if i]:
            names = {
                entry.get("id", "").lower(),
                entry.get("slug", entry.get("id", "")).lower(),
            }
            return sorted(n for n in names if n), "config/model-router.toml"
    if name.endswith("-fast"):  # plugin fast-tier agents; untested on real transcripts
        return [name, name[: -len("-fast")]], "unlisted route (fast tier)"
    return [name], "unlisted route"


def matches(actual: str, accepted: list[str]) -> bool:
    a = actual.lower()
    a_bare = a.rsplit("/", 1)[-1]
    for name in accepted:
        if name.endswith("-*"):
            if a_bare.startswith(name[:-1]):
                return True
        elif a == name or a_bare == name.rsplit("/", 1)[-1] or a.startswith(name + "-"):
            return True
    return False


# --- the check ---------------------------------------------------------------


def check(
    transcript: Path,
    expect: str | None = None,
    agent_type: str = "",
    cwd: str | None = None,
) -> dict:
    meta = read_meta(transcript)
    agent_type = agent_type or str(meta.get("agentType") or "")
    actual, requested_counts = answering_models(transcript)

    source = None
    if expect:
        source = "--expect"
    elif isinstance(meta.get("model"), str) and meta["model"]:
        expect, source = meta["model"], "meta.json"
    elif requested_counts:
        expect, source = requested_counts.most_common(1)[0][0], "requestedModel"
    else:
        expect = frontmatter_model(agent_type, cwd)
        source = "frontmatter" if expect else None

    total = sum(actual.values())
    result = {
        "agent_type": agent_type,
        "transcript": str(transcript),
        "requested": expect,
        "expected_source": source,
        "replies": total,
        "actual": dict(actual.most_common()),
    }
    if not expect:
        result.update(
            verdict="unknown",
            accepted=[],
            message=(
                f"agent '{agent_type}': no expected model could be resolved; "
                f"answered from {fmt_counts(actual, total)}"
            ),
        )
        return result
    if expect.lower() == "inherit":
        # No label to verify, and the parent can switch models mid-run: a real fork
        # answered 22 replies from Opus and 13 from Sol after its parent switched.
        result.update(
            verdict="inherit",
            accepted=[],
            message=(
                f"agent '{agent_type}' inherits the parent's model; "
                f"answered from {fmt_counts(actual, total)}"
            ),
        )
        return result
    accepted, how = accepted_names(expect)
    result["accepted"], result["accepted_from"] = accepted, how
    expected_label = " or ".join(accepted)
    if total == 0:
        result.update(
            verdict="no-replies",
            message=(
                f"agent '{agent_type}' has no model replies in its transcript; expected {expected_label}"
            ),
        )
        return result
    wrong = collections.Counter(
        {m: n for m, n in actual.items() if not matches(m, accepted)}
    )
    result["claude_expected"] = expected_label.startswith("claude-")
    claude_answered = any(
        m.lower().rsplit("/", 1)[-1].startswith("claude-") for m in wrong
    )
    if wrong and how.startswith("unlisted") and not claude_answered:
        # A name the router table does not list (a plugin route, or the table is
        # unreadable): only a Claude answer is evidence of the silent fallback.
        result.update(
            verdict="unknown",
            message=(
                f"agent '{agent_type}': '{expect}' is not in config/model-router.toml; "
                f"answered from {fmt_counts(actual, total)}"
            ),
        )
    elif wrong:
        fallback = claude_answered and not result["claude_expected"]
        result.update(
            verdict="mismatch",
            kind="claude-fallback" if fallback else "other-model",
            message=(
                f"agent '{agent_type}' answered from {fmt_counts(wrong, total)}; "
                f"expected {expected_label} (requested '{expect}', from {source})"
                + ("; this is the silent Claude fallback" if fallback else "")
            ),
        )
    else:
        result.update(
            verdict="match",
            message=(
                f"agent '{agent_type}' verified: answered from {fmt_counts(actual, total)} "
                f"(requested '{expect}')"
            ),
        )
    return result


def fmt_counts(counts: collections.Counter, total: int) -> str:
    if not counts:
        return "no models"
    return ", ".join(f"{m} in {n}/{total} replies" for m, n in counts.most_common())


# --- side effects: log and pending notes ------------------------------------


def append_log(result: dict, extra: dict) -> None:
    now = datetime.now(timezone.utc)  # noqa: UP017 -- Python 3.9 has no datetime.UTC
    line = {"ts": now.isoformat(timespec="seconds"), **extra, **result}
    path = log_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(line, sort_keys=True) + "\n")


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", value)[:120] or "unknown"


def leave_pending(session_id: str, agent_id: str, result: dict) -> None:
    d = pending_dir() / safe_name(session_id)
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / f".{safe_name(agent_id)}.tmp"
    tmp.write_text(
        json.dumps({"verdict": result["verdict"], "message": result["message"]})
    )
    tmp.replace(
        d / f"{safe_name(agent_id)}.json"
    )  # one note per agent; a resume overwrites


def take_pending(session_id: str, mismatches_only: bool) -> list[str]:
    """Consume this session's notes. With mismatches_only (Stop), match notes are
    dropped unsent, so a match never extends a turn and the shell gate closes."""
    root = pending_dir()
    d = root / safe_name(session_id)
    notes: list[str] = []
    for f in sorted(d.glob("*.json")) if d.is_dir() else []:
        try:
            note = json.loads(f.read_text())
        except (OSError, ValueError):
            note = {}
        f.unlink(missing_ok=True)
        if not note or (mismatches_only and note.get("verdict") != "mismatch"):
            continue
        notes.append(
            ("MISMATCH: " if note.get("verdict") == "mismatch" else "")
            + str(note.get("message"))
        )
    # Drop this session's folder once empty, and any session's folder left for days,
    # so the shell gate in settings.json finds nothing and skips Python.
    for folder in [p for p in root.iterdir() if p.is_dir()] if root.is_dir() else []:
        try:
            if folder != d and time.time() - folder.stat().st_mtime > PENDING_MAX_AGE_S:
                for f in folder.iterdir():
                    f.unlink()
            folder.rmdir()  # fails, harmlessly, while notes remain
        except OSError:
            pass
    return notes


# --- entry points -----------------------------------------------------------


def run_hook(raw: str) -> int:
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        return 0
    if not isinstance(data, dict):
        return 0
    event = data.get("hook_event_name")
    session_id = str(data.get("session_id") or "")
    if event == "SubagentStop":
        path = data.get("agent_transcript_path")
        if not path or not Path(path).expanduser().is_file():
            return 0
        result = check(
            Path(path).expanduser(),
            agent_type=str(data.get("agent_type") or ""),
            cwd=data.get("cwd"),
        )
        verdict = result["verdict"]
        notable = verdict == "mismatch" or (
            verdict == "match" and not result.get("claude_expected")
        )
        try:  # best effort: a full disk or odd state dir must not swallow the warning
            append_log(
                result, {"session_id": session_id, "agent_id": data.get("agent_id")}
            )
            if notable and session_id:
                leave_pending(
                    session_id,
                    str(data.get("agent_id") or result["agent_type"]),
                    result,
                )
        except OSError as exc:
            print(f"verify_subagent_model: state not written: {exc}", file=sys.stderr)
        if notable:
            prefix = "⚠️ Model mismatch: " if verdict == "mismatch" else ""
            print(json.dumps({"systemMessage": prefix + result["message"]}))
        return 0
    if event in ("PostToolUse", "Stop") and session_id and not data.get("agent_id"):
        notes = take_pending(session_id, mismatches_only=(event == "Stop"))
        if notes:
            text = (
                "Subagent model check (from each agent's transcript, message.model; "
                "attribute work by this, not by the agent label):\n- "
                + "\n- ".join(notes)
            )
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": event,
                            "additionalContext": text,
                        }
                    }
                )
            )
    return 0


def run_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="verify_subagent_model.py",
        description="Report which model answered a subagent, from its transcript "
        "(message.model on assistant records), and compare it with the expected model. "
        "With no arguments, runs as a Claude Code hook reading JSON on stdin.",
        epilog="Router aliases resolve through today's config/model-router.toml, so for a "
        "transcript older than an alias change (astra named gpt-6-astra until 2026-11-17) "
        "pass --expect. Exit codes: 0 match, 1 mismatch, 2 usage error, "
        "3 indeterminate (no replies, inherit, or no resolvable expected model).",
    )
    parser.add_argument(
        "--transcript",
        required=True,
        type=Path,
        help="subagent transcript, e.g. ~/.claude/projects/<p>/<session>/subagents/agent-<id>.jsonl",
    )
    parser.add_argument(
        "--expect",
        help="expected model or routing name (default: from meta.json, "
        "requestedModel, or the agent's frontmatter)",
    )
    parser.add_argument(
        "--json", action="store_true", help="print the full result as JSON"
    )
    args = parser.parse_args(argv)
    path = args.transcript.expanduser()
    if not path.is_file():
        print(f"verify_subagent_model: no such transcript: {path}", file=sys.stderr)
        return 2
    result = check(path, expect=args.expect)
    print(json.dumps(result, indent=2) if args.json else result["message"])
    return {"match": 0, "mismatch": 1}.get(result["verdict"], 3)


def main(argv: list[str]) -> int:
    if argv:
        return run_cli(argv)
    try:
        return run_hook(sys.stdin.read())
    except Exception as exc:  # noqa: BLE001 -- fail open: a broken check must never disturb the session
        print(f"verify_subagent_model: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
