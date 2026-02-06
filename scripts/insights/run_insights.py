#!/usr/bin/env python3
"""Claude Code Usage Insights — extract, analyze, and report on all sessions.

Processes session transcripts through Gemini for deep facet analysis,
then generates an HTML report. Caches facets per-session with mtime-based
invalidation for fast incremental re-runs.

Usage:
    python scripts/insights/run_insights.py [--project X] [--since 30] [--force] [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLAUDE_PROJECTS_DIR = Path.home() / ".claude" / "projects"
OUTPUT_DIR = Path.home() / ".claude" / "custom-insights"
FACETS_DIR = OUTPUT_DIR / "facets"
PROMPTS_DIR = Path(__file__).parent / "prompts"

NOISE_TYPES = frozenset({
    "progress", "file-history-snapshot", "system", "queue-operation",
})
BATCH_SIZE = 12          # transcripts per Gemini call
BATCH_CHAR_LIMIT = 700_000  # soft cap on chars per batch
MAX_RETRIES = 3
RETRY_BACKOFF = [30, 60, 120]  # seconds


# ---------------------------------------------------------------------------
# Phase 1: Extract & Clean
# ---------------------------------------------------------------------------

def discover_sessions(project_filter=None, since_days=None, limit=None):
    """Find all session JSONL files, excluding subagent directories."""
    sessions = []
    if not CLAUDE_PROJECTS_DIR.exists():
        print(f"Error: {CLAUDE_PROJECTS_DIR} not found", file=sys.stderr)
        sys.exit(1)

    for project_dir in sorted(CLAUDE_PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        project_name = project_dir.name

        if project_filter and project_filter not in project_name:
            continue

        for jsonl in sorted(project_dir.glob("*.jsonl")):
            # Skip files inside subagent directories
            if "subagents" in str(jsonl):
                continue

            stat = jsonl.stat()
            mtime = stat.st_mtime
            size = stat.st_size

            if size < 100:  # skip near-empty files
                continue

            if since_days is not None:
                cutoff = time.time() - (since_days * 86400)
                if mtime < cutoff:
                    continue

            session_id = jsonl.stem
            sessions.append({
                "session_id": session_id,
                "project": project_name,
                "path": jsonl,
                "mtime": mtime,
                "size": size,
            })

    # Sort by mtime descending (newest first)
    sessions.sort(key=lambda s: s["mtime"], reverse=True)

    if limit:
        sessions = sessions[:limit]

    return sessions


def clean_transcript(jsonl_path):
    """Extract clean text from a session JSONL. Returns (text, start_ts, end_ts)."""
    lines = []
    timestamps = []
    errors = 0

    with open(jsonl_path, "r") as f:
        for raw_line in f:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                entry = json.loads(raw_line)
            except json.JSONDecodeError:
                errors += 1
                continue

            entry_type = entry.get("type", "")

            # Skip noise
            if entry_type in NOISE_TYPES:
                continue

            ts = entry.get("timestamp")
            if ts:
                timestamps.append(ts)

            # Summary lines
            if entry_type == "summary":
                summary = entry.get("summary", "")
                if summary:
                    lines.append(f"[SUMMARY] {summary}")
                continue

            # User and assistant messages
            if entry_type in ("user", "assistant"):
                msg = entry.get("message", {})
                content = msg.get("content", "")
                role = msg.get("role", entry_type)

                if isinstance(content, str) and content.strip():
                    # Truncate very long individual messages
                    text = content.strip()
                    if len(text) > 20_000:
                        text = text[:20_000] + "\n[...truncated...]"
                    lines.append(f"[{role.upper()}] {text}")
                elif isinstance(content, list):
                    # Multi-part content (text blocks)
                    for part in content:
                        if isinstance(part, dict) and part.get("type") == "text":
                            text = part.get("text", "").strip()
                            if text:
                                if len(text) > 20_000:
                                    text = text[:20_000] + "\n[...truncated...]"
                                lines.append(f"[{role.upper()}] {text}")

    transcript = "\n".join(lines)
    start_ts = min(timestamps) if timestamps else None
    end_ts = max(timestamps) if timestamps else None

    if errors > 0 and len(lines) == 0:
        return "", start_ts, end_ts

    return transcript, start_ts, end_ts


def filter_cached(sessions, force=False):
    """Return sessions that need (re)processing based on mtime cache."""
    if force:
        return sessions

    to_process = []
    for s in sessions:
        facet_path = FACETS_DIR / f"{s['session_id']}.json"
        if facet_path.exists():
            try:
                facet = json.loads(facet_path.read_text())
                cached_mtime = facet.get("_source_mtime", 0)
                if cached_mtime == s["mtime"]:
                    continue  # cached and up-to-date
            except (json.JSONDecodeError, KeyError):
                pass  # corrupted cache, reprocess
        to_process.append(s)

    return to_process


# ---------------------------------------------------------------------------
# Phase 2: Generate Facets (Gemini CLI)
# ---------------------------------------------------------------------------

def make_batches(sessions_with_transcripts):
    """Group sessions into batches respecting size and count limits."""
    batches = []
    current_batch = []
    current_chars = 0

    for item in sessions_with_transcripts:
        item_chars = len(item["transcript"])

        # Very large sessions: process individually
        if item_chars > 200_000:
            if current_batch:
                batches.append(current_batch)
                current_batch = []
                current_chars = 0
            batches.append([item])
            continue

        # Check if adding would exceed limits
        if (len(current_batch) >= BATCH_SIZE or
                current_chars + item_chars > BATCH_CHAR_LIMIT):
            if current_batch:
                batches.append(current_batch)
            current_batch = [item]
            current_chars = item_chars
        else:
            current_batch.append(item)
            current_chars += item_chars

    if current_batch:
        batches.append(current_batch)

    return batches


def build_batch_prompt(batch, facet_prompt):
    """Assemble the prompt for a batch of sessions."""
    parts = [facet_prompt, "\n\n"]
    for item in batch:
        parts.append(f"===SESSION_BOUNDARY::{item['session_id']}===\n")
        parts.append(item["transcript"])
        parts.append("\n\n")
    return "".join(parts)


def call_gemini(prompt_text):
    """Call Gemini CLI via temp file to avoid stdin pipe limits."""
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, dir="/tmp/claude"
    ) as f:
        f.write(prompt_text)
        tmp_path = f.name

    try:
        # Use shell pipe from file to avoid ARG_MAX and stdin buffer limits
        result = subprocess.run(
            f'cat "{tmp_path}" | gemini -m gemini-2.5-pro -p "" -o json',
            shell=True,
            capture_output=True,
            text=True,
            timeout=300,  # 5 min per call
        )

        if result.returncode != 0:
            stderr_snippet = result.stderr[:500] if result.stderr else "(no stderr)"
            return None, f"Exit code {result.returncode}: {stderr_snippet}"

        stdout = result.stdout.strip()
        if not stdout:
            return None, "Empty stdout"

        envelope = json.loads(stdout)
        return envelope, None

    except subprocess.TimeoutExpired:
        return None, "Timeout (300s)"
    except json.JSONDecodeError as e:
        return None, f"JSON parse error: {e}"
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def parse_facets_response(response_text, expected_count):
    """Parse facets from Gemini's response string. Returns (facets_list, error)."""
    text = response_text.strip()

    # Strip markdown code fences if present
    if text.startswith("```"):
        lines = text.split("\n")
        # Remove first line (```json or ```) and last line (```)
        if lines[-1].strip() == "```":
            lines = lines[1:-1]
        else:
            lines = lines[1:]
        text = "\n".join(lines).strip()

    try:
        parsed = json.loads(text)
        if isinstance(parsed, list):
            return parsed, None
        elif isinstance(parsed, dict):
            return [parsed], None
        else:
            return None, f"Unexpected type: {type(parsed)}"
    except json.JSONDecodeError:
        # Try extracting individual JSON objects
        facets = []
        depth = 0
        start = None
        for i, ch in enumerate(text):
            if ch == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0 and start is not None:
                    try:
                        obj = json.loads(text[start:i + 1])
                        facets.append(obj)
                    except json.JSONDecodeError:
                        pass
                    start = None

        if facets:
            return facets, None
        return None, "Could not parse any JSON objects from response"


def process_batch(batch, facet_prompt, batch_idx, total_batches, verbose=False):
    """Process a single batch through Gemini. Returns list of (session_id, facet) tuples."""
    batch_chars = sum(len(item["transcript"]) for item in batch)
    n = len(batch)
    print(f"  [Batch {batch_idx}/{total_batches}] Processing {n} sessions ({batch_chars // 1000}K chars)...",
          end="", flush=True)

    prompt = build_batch_prompt(batch, facet_prompt)
    session_ids = [item["session_id"] for item in batch]
    session_map = {item["session_id"]: item for item in batch}

    for attempt in range(MAX_RETRIES):
        envelope, error = call_gemini(prompt)
        if error:
            wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
            print(f" error: {error}", flush=True)
            if attempt < MAX_RETRIES - 1:
                print(f"    Retrying in {wait}s (attempt {attempt + 2}/{MAX_RETRIES})...",
                      end="", flush=True)
                time.sleep(wait)
                continue
            print(f"    FAILED after {MAX_RETRIES} attempts", flush=True)
            return []

        response_text = envelope.get("response", "")
        facets, parse_error = parse_facets_response(response_text, n)

        if parse_error:
            print(f" parse error: {parse_error}", flush=True)
            if attempt < MAX_RETRIES - 1:
                wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                print(f"    Retrying in {wait}s...", end="", flush=True)
                time.sleep(wait)
                continue
            print(f"    FAILED to parse after {MAX_RETRIES} attempts", flush=True)
            return []

        # Validate count
        if len(facets) != n:
            print(f" count mismatch: got {len(facets)}, expected {n}", flush=True)
            if attempt < MAX_RETRIES - 1:
                wait = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
                print(f"    Retrying in {wait}s...", end="", flush=True)
                time.sleep(wait)
                continue
            # Partial success — match what we can
            print(f"    Using {len(facets)} of {n} (partial)", flush=True)

        # Match facets to sessions
        results = []
        matched_ids = set()
        for facet in facets:
            fid = facet.get("session_id", "")
            if fid in session_map:
                item = session_map[fid]
                facet["project"] = item["project"]
                facet["start_timestamp"] = item.get("start_ts")
                facet["end_timestamp"] = item.get("end_ts")
                facet["_source_mtime"] = item["mtime"]
                results.append((fid, facet))
                matched_ids.add(fid)

        # Report unmatched
        unmatched = set(session_ids) - matched_ids
        if unmatched and verbose:
            print(f"    Unmatched session IDs: {unmatched}", flush=True)

        elapsed = envelope.get("stats", {}).get("models", {}).get(
            "gemini-2.5-pro", {}).get("api", {}).get("totalLatencyMs", 0)
        print(f" done ({elapsed // 1000}s, {len(results)} facets)", flush=True)
        return results

    return []


def save_facet(session_id, facet):
    """Save a facet to the cache directory."""
    FACETS_DIR.mkdir(parents=True, exist_ok=True)
    facet_path = FACETS_DIR / f"{session_id}.json"
    facet_path.write_text(json.dumps(facet, indent=2))


# ---------------------------------------------------------------------------
# Phase 3: Generate Report
# ---------------------------------------------------------------------------

def load_all_facets(project_filter=None, since_days=None):
    """Load all cached facets, optionally filtered by project and recency."""
    facets = []
    if not FACETS_DIR.exists():
        return facets

    cutoff_ts = None
    if since_days is not None:
        cutoff_dt = datetime.now(timezone.utc) - timedelta(days=since_days)
        cutoff_ts = cutoff_dt.isoformat()

    for fp in sorted(FACETS_DIR.glob("*.json")):
        try:
            facet = json.loads(fp.read_text())
        except (json.JSONDecodeError, OSError):
            continue

        if project_filter and project_filter not in facet.get("project", ""):
            continue

        if cutoff_ts:
            ts = facet.get("start_timestamp")
            if ts and ts < cutoff_ts:
                continue

        facets.append(facet)
    return facets


def compute_aggregate_stats(facets):
    """Compute aggregate statistics from all facets."""
    stats = {
        "total_sessions": len(facets),
        "goal_categories": {},
        "outcomes": {},
        "helpfulness": {},
        "session_types": {},
        "friction_types": {},
        "sessions_with_friction": 0,
        "projects": {},
    }

    for f in facets:
        # Goal categories
        for cat, count in f.get("goal_categories", {}).items():
            stats["goal_categories"][cat] = stats["goal_categories"].get(cat, 0) + count

        # Outcomes
        outcome = f.get("outcome", "unclear")
        stats["outcomes"][outcome] = stats["outcomes"].get(outcome, 0) + 1

        # Helpfulness
        h = f.get("claude_helpfulness", "unknown")
        stats["helpfulness"][h] = stats["helpfulness"].get(h, 0) + 1

        # Session types
        st = f.get("session_type", "unknown")
        stats["session_types"][st] = stats["session_types"].get(st, 0) + 1

        # Friction
        friction = f.get("friction_counts", {})
        if friction:
            stats["sessions_with_friction"] += 1
        for ft, count in friction.items():
            stats["friction_types"][ft] = stats["friction_types"].get(ft, 0) + count

        # Per-project
        proj = f.get("project", "unknown")
        if proj not in stats["projects"]:
            stats["projects"][proj] = {
                "count": 0, "outcomes": {}, "goal_categories": {},
                "friction_count": 0,
            }
        ps = stats["projects"][proj]
        ps["count"] += 1
        ps["outcomes"][outcome] = ps["outcomes"].get(outcome, 0) + 1
        for cat, count in f.get("goal_categories", {}).items():
            ps["goal_categories"][cat] = ps["goal_categories"].get(cat, 0) + count
        if friction:
            ps["friction_count"] += 1

    return stats


def generate_report(facets, verbose=False, project_slug=None):
    """Generate HTML report by feeding stats + facets to Gemini."""
    stats = compute_aggregate_stats(facets)

    report_prompt = (PROMPTS_DIR / "report_prompt.txt").read_text()

    if project_slug:
        report_prompt += (
            "\n\nNOTE: These facets are filtered to a single project. "
            "Tailor the report specifically to this project rather than "
            "cross-project comparisons.\n"
        )

    # Build the input: stats + all facets + prompt
    facet_summaries = []
    for f in facets:
        # Compact representation for the report
        facet_summaries.append({
            "session_id": f.get("session_id"),
            "project": f.get("project"),
            "underlying_goal": f.get("underlying_goal"),
            "outcome": f.get("outcome"),
            "claude_helpfulness": f.get("claude_helpfulness"),
            "session_type": f.get("session_type"),
            "goal_categories": f.get("goal_categories"),
            "friction_counts": f.get("friction_counts"),
            "friction_detail": f.get("friction_detail"),
            "primary_success": f.get("primary_success"),
            "improvement_opportunity": f.get("improvement_opportunity", ""),
            "brief_summary": f.get("brief_summary"),
            "start_timestamp": f.get("start_timestamp"),
            "end_timestamp": f.get("end_timestamp"),
        })

    # Strip empty/null values and brief_summary to stay under Gemini CLI's
    # ~400K stdin limit.  The report still has underlying_goal, primary_success,
    # and friction_detail for per-session context.
    compact_facets = []
    for s in facet_summaries:
        compact_facets.append(
            {k: v for k, v in s.items() if v and k != "brief_summary"}
        )

    input_text = (
        f"{report_prompt}\n\n"
        f"## AGGREGATE STATS\n```json\n{json.dumps(stats, indent=2)}\n```\n\n"
        f"## ALL FACETS ({len(compact_facets)} sessions)\n"
        f"```json\n{json.dumps(compact_facets, separators=(',', ':'))}\n```\n"
    )

    input_chars = len(input_text)
    print(f"\nGenerating report ({input_chars // 1000}K chars input)...", flush=True)

    envelope, error = call_gemini(input_text)
    if error:
        print(f"Error generating report: {error}", file=sys.stderr)
        return None

    html = envelope.get("response", "")

    # Strip markdown fences if present
    if html.startswith("```"):
        lines = html.split("\n")
        if lines[-1].strip() == "```":
            lines = lines[1:-1]
        else:
            lines = lines[1:]
        html = "\n".join(lines)

    # Timestamped output with symlink
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    if project_slug:
        slug = project_slug.replace("/", "-").replace(" ", "-").lower()
        report_name = f"report_{slug}_{ts}.html"
    else:
        report_name = f"report_{ts}.html"

    report_path = OUTPUT_DIR / report_name
    report_path.write_text(html)

    # Update latest symlink
    latest = OUTPUT_DIR / "report_latest.html"
    latest.unlink(missing_ok=True)
    latest.symlink_to(report_path.name)

    return report_path


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Claude Code Usage Insights — deep analysis of all sessions"
    )
    parser.add_argument("--project", help="Substring filter for project name")
    parser.add_argument("--since", type=int, help="Only sessions newer than N days")
    parser.add_argument("--limit", type=int, help="Max sessions to process")
    parser.add_argument("--force", action="store_true", help="Regenerate all facets")
    parser.add_argument("--dry-run", action="store_true", help="Show plan without calling Gemini")
    parser.add_argument("--report-only", action="store_true", help="Regenerate report from cached facets")
    parser.add_argument("--verbose", action="store_true", help="Detailed progress output")
    args = parser.parse_args()

    # Report-only mode
    if args.report_only:
        facets = load_all_facets(
            project_filter=args.project,
            since_days=args.since,
        )
        if not facets:
            print("No cached facets found. Run without --report-only first.", file=sys.stderr)
            sys.exit(1)
        if args.project:
            print(f"Loaded {len(facets)} cached facets (filtered: {args.project})")
        else:
            print(f"Loaded {len(facets)} cached facets")
        report_path = generate_report(facets, verbose=args.verbose,
                                       project_slug=args.project)
        if report_path:
            print(f"\nReport: {report_path}")
            open_report(report_path)
        return

    # Phase 1: Discover and extract
    print("Phase 1: Discovering sessions...")
    sessions = discover_sessions(
        project_filter=args.project,
        since_days=args.since,
        limit=args.limit,
    )
    print(f"  Found {len(sessions)} sessions across "
          f"{len(set(s['project'] for s in sessions))} projects")

    if not sessions:
        print("No sessions to process.")
        return

    # Filter to uncached
    to_process = filter_cached(sessions, force=args.force)
    cached_count = len(sessions) - len(to_process)
    print(f"  {cached_count} already cached, {len(to_process)} to process")

    if not to_process and not args.force:
        print("\nAll sessions cached. Regenerating report...")
        facets = load_all_facets(project_filter=args.project, since_days=args.since)
        report_path = generate_report(facets, verbose=args.verbose,
                                       project_slug=args.project)
        if report_path:
            print(f"\nReport: {report_path}")
            open_report(report_path)
        return

    # Extract transcripts
    print("\nExtracting transcripts...")
    items = []
    empty_count = 0
    for s in to_process:
        transcript, start_ts, end_ts = clean_transcript(s["path"])
        if not transcript.strip():
            empty_count += 1
            continue
        items.append({
            **s,
            "transcript": transcript,
            "start_ts": start_ts,
            "end_ts": end_ts,
        })

    total_chars = sum(len(item["transcript"]) for item in items)
    print(f"  Extracted {len(items)} transcripts ({total_chars // 1000}K chars total)")
    if empty_count:
        print(f"  Skipped {empty_count} empty sessions")

    if not items:
        print("No transcripts to process.")
        return

    # Phase 2: Batch and process
    batches = make_batches(items)
    print(f"\nPhase 2: Processing {len(items)} sessions in {len(batches)} batches")

    if args.dry_run:
        print("\n--- DRY RUN ---")
        for i, batch in enumerate(batches, 1):
            chars = sum(len(item["transcript"]) for item in batch)
            ids = [item["session_id"][:8] for item in batch]
            print(f"  Batch {i}: {len(batch)} sessions, {chars // 1000}K chars")
            if args.verbose:
                for item in batch:
                    print(f"    - {item['session_id'][:12]}... "
                          f"({len(item['transcript']) // 1000}K chars, "
                          f"{item['project']})")
        est_minutes = len(batches) * 0.5  # ~30s per batch
        print(f"\nEstimated time: {est_minutes:.0f}-{est_minutes * 1.5:.0f} min")
        return

    # Load facet prompt
    facet_prompt = (PROMPTS_DIR / "facet_prompt.txt").read_text()

    total_facets = 0
    start_time = time.time()

    for i, batch in enumerate(batches, 1):
        results = process_batch(batch, facet_prompt, i, len(batches), verbose=args.verbose)
        for session_id, facet in results:
            save_facet(session_id, facet)
            total_facets += 1

    elapsed = time.time() - start_time
    print(f"\nPhase 2 complete: {total_facets} facets generated in {elapsed:.0f}s")

    # Phase 3: Generate report
    print("\nPhase 3: Generating report...")
    facets = load_all_facets(project_filter=args.project, since_days=args.since)
    print(f"  Total facets (cached + new): {len(facets)}")

    report_path = generate_report(facets, verbose=args.verbose,
                                   project_slug=args.project)
    if report_path:
        print(f"\nReport: {report_path}")
        open_report(report_path)

    print("\nDone!")


def open_report(path):
    """Open the report in the default browser."""
    import platform
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.run(["open", str(path)], check=False)
        elif system == "Linux":
            subprocess.run(["xdg-open", str(path)], check=False)
    except FileNotFoundError:
        pass  # No browser opener available


if __name__ == "__main__":
    main()
