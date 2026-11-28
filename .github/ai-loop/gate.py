#!/usr/bin/env python3
"""Decide what happens to a PR after the AI reviewers and the repo's checks have run.

Reads the two reviewers' findings, waits for the required checks on the head SHA, posts one
summary comment per head SHA, and prints a decision for the workflow to act on:

  fix           must-fix/should-fix findings or failing checks, and fix rounds remain
  merge         clean, green, and the PR matches this repo's auto-merge rule
  needs-yulong  clean but not auto-mergeable, or rounds exhausted, or a reviewer was unavailable
  clean         clean, green, not eligible to merge, and no attention needed (e.g. a draft)

Stdlib only. Every value that came from the PR reaches this script through the environment
or files, never through the workflow's `run:` text.
"""

from __future__ import annotations

import fnmatch
import json
import os
import subprocess
import sys
import time
from pathlib import Path

MARK_SUMMARY = "<!-- ai-loop:summary -->"
MARK_ROUND = "<!-- ai-loop:fix-round -->"
SEVERITIES = ("must-fix", "should-fix", "nit")


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def gh_json(*args: str):
    return json.loads(gh(*args) or "null")


def load_findings(
    path: Path, reviewer: str, pr_files: list[str]
) -> tuple[list[dict], str | None]:
    """Return (findings, error). A missing or malformed file, or a review that did not cover
    every changed file, means the reviewer was unavailable: an empty review must never read
    as a clean one."""
    if not path.is_file():
        return [], f"{reviewer}: no output (auth failure or crash; see the job log)"
    text = path.read_text()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        # Gemini wraps its answer; take the outermost JSON object in the text.
        start, end = text.find("{"), text.rfind("}")
        try:
            data = json.loads(text[start : end + 1]) if start >= 0 else None
        except json.JSONDecodeError:
            data = None
    if not isinstance(data, dict) or not isinstance(data.get("findings"), list):
        return [], f"{reviewer}: output was not the findings JSON"
    if data.get("verdict") not in ("approve", "changes-requested"):
        return [], f"{reviewer}: verdict missing or invalid"
    if not all(isinstance(f, dict) and f.get("summary") for f in data["findings"]):
        return [], f"{reviewer}: a finding was malformed"
    if data["verdict"] == "changes-requested" and not data["findings"]:
        return [], f"{reviewer}: requested changes but listed no findings"
    seen = set(data.get("files_reviewed") or [])
    missed = [f for f in pr_files if f not in seen]
    if missed:
        return [], f"{reviewer}: did not review {len(missed)} changed file(s), e.g. `{missed[0]}`"
    out = []
    for f in data["findings"]:
        sev = f.get("severity") if f.get("severity") in SEVERITIES else "should-fix"
        out.append({**f, "severity": sev, "reviewer": reviewer})
    return out, None


def wait_for_checks(repo: str, sha: str, required: list[str], own_suite: int, timeout: int):
    """Poll check runs on `sha` until the required ones finish.

    Returns (ok, absent, lines): `absent` is True when a required check never ran or never
    finished, which a code fix cannot cure, so the gate escalates instead of fixing."""
    deadline = time.time() + timeout
    while True:
        runs = gh_json(
            "api", f"repos/{repo}/commits/{sha}/check-runs?per_page=100", "--jq", ".check_runs"
        )
        others = [r for r in runs if r["check_suite"]["id"] != own_suite]
        by_name = {r["name"]: r for r in others}
        pending = [n for n in required if by_name.get(n, {}).get("status") != "completed"]
        pending += [r["name"] for r in others if r["status"] != "completed"]
        if not pending or time.time() > deadline:
            break
        time.sleep(30)

    lines, ok, absent = [], True, False
    for name in required:
        r = by_name.get(name)
        if r is None:
            ok, absent = False, True
            lines.append(f"- ❌ `{name}`: never ran on this SHA")
        elif r["status"] != "completed":
            ok, absent = False, True
            lines.append(f"- ❌ `{name}`: still {r['status']} after {timeout // 60} min")
        elif r["conclusion"] != "success":
            ok = False
            lines.append(f"- ❌ `{name}`: {r['conclusion']} ({r['html_url']})")
    # Cancelled runs are superseded ones (an older loop run on the same SHA), not failures.
    for r in others:
        if r["name"] in required:
            continue
        if r["status"] == "completed" and r["conclusion"] not in (
            "success", "skipped", "neutral", "cancelled"
        ):
            ok = False
            lines.append(f"- ❌ `{r['name']}`: {r['conclusion']} ({r['html_url']})")
    if ok:
        lines.append(f"- ✅ checks green ({', '.join(required) or 'none required'})")
    return ok, absent, lines


def automerge_reason(cfg: dict, pr: dict, files: list[str]) -> str | None:
    """None when the PR may merge itself; otherwise the reason it may not."""
    rule = cfg.get("automerge", {})
    if not rule.get("enabled", False):
        return "auto-merge is off for this repo"
    if pr["isDraft"]:
        return "PR is a draft"
    if any(lab["name"] == "hold" for lab in pr["labels"]):
        return "`hold` label"
    prefixes = rule.get("branch_prefixes")
    if prefixes and not any(pr["headRefName"].startswith(p) for p in prefixes):
        return f"only branches starting {', '.join(prefixes)} auto-merge here"
    for f in files:
        for g in rule.get("protected_globs", []):
            if fnmatch.fnmatch(f, g):
                return f"touches protected path `{f}`"
    allow = rule.get("allow_globs")
    if allow:
        outside = [f for f in files if not any(fnmatch.fnmatch(f, g) for g in allow)]
        if outside:
            return f"`{outside[0]}` is outside the auto-merge paths ({', '.join(allow)})"
    if rule.get("simple_rule"):
        non_md = [f for f in files if not f.endswith(".md")]
        if len(non_md) > 1:
            return f"{len(non_md)} non-Markdown files changed (simple = Markdown-only or one file)"
    return None


def main() -> int:
    repo, pr_num, sha = os.environ["REPO"], os.environ["PR"], os.environ["HEAD_SHA"]
    cfg = json.loads(Path(os.environ["AI_LOOP_CONFIG"]).read_text())
    rdir = Path(os.environ["REVIEW_DIR"])
    allow_fix = os.environ.get("ALLOW_FIX") == "true"

    pr = gh_json(
        "pr", "view", pr_num, "-R", repo,
        "--json", "isDraft,labels,headRefName,headRefOid,comments,state,changedFiles",
    )
    if pr["headRefOid"] != sha:
        print("decision=stale")
        return 0
    # Every file, past the first 100, and both sides of a rename: a file moved out of a
    # protected path must still count as touching it.
    entries = json.loads(gh("api", "--paginate", "--slurp",
                            f"repos/{repo}/pulls/{pr_num}/files?per_page=100"))
    entries = [e for page in entries for e in page]
    if len(entries) != pr["changedFiles"]:
        raise SystemExit(f"listed {len(entries)} files but the PR has {pr['changedFiles']}")
    files = sorted({p for e in entries for p in (e["filename"], e.get("previous_filename")) if p})

    findings, errors = [], []
    for name, fname in (("GPT", "gpt.json"), ("Gemini", "gemini.json")):
        got, err = load_findings(rdir / fname, name, files)
        findings += got
        if err:
            errors.append(err)

    checks_ok, checks_absent, check_lines = wait_for_checks(
        repo, sha, cfg.get("required_checks", []), int(os.environ["OWN_SUITE"]),
        int(cfg.get("checks_timeout_s", 1500)),
    )

    rounds = sum(MARK_ROUND in c["body"] for c in pr["comments"])
    max_rounds = int(cfg.get("max_fix_rounds", 2))
    must = [f for f in findings if f["severity"] == "must-fix"]
    fixable = [f for f in findings if f["severity"] in ("must-fix", "should-fix")]

    if errors:
        decision = "needs-yulong"
        why = "a reviewer was unavailable, so nothing merges on a half review"
    elif checks_absent:
        decision = "needs-yulong"
        why = "a required check never ran or never finished, which a code fix cannot cure"
    elif must or not checks_ok:
        if allow_fix and rounds < max_rounds:
            decision, why = "fix", f"fix round {rounds + 1} of {max_rounds}"
        else:
            decision = "needs-yulong"
            why = f"{max_rounds} fix rounds used" if rounds >= max_rounds else "fixes run only on PR events"
    elif fixable:
        # should-fix findings are dealt with before anything merges, on every branch alike.
        if allow_fix and rounds < max_rounds:
            decision, why = "fix", f"should-fix findings; fix round {rounds + 1} of {max_rounds}"
        else:
            decision, why = "needs-yulong", f"should-fix findings left after {rounds} fix round(s)"
    else:
        reason = automerge_reason(cfg, pr, files)
        if reason is None:
            decision, why = "merge", "clean, green and inside the auto-merge rule"
        elif pr["isDraft"]:
            decision, why = "clean", reason
        else:
            decision, why = "needs-yulong", reason

    # Findings file for the fixer, and the summary comment for people.
    body = [MARK_SUMMARY, f"### AI review of `{sha[:7]}`: **{decision}** ({why})", ""]
    body += check_lines + [f"- ⚠️ {e}" for e in errors]
    if findings:
        body += ["", "| Severity | Reviewer | Where | Finding |", "|---|---|---|---|"]
        for f in sorted(findings, key=lambda f: SEVERITIES.index(f["severity"])):
            where = f"`{f.get('file', '?')}:{f.get('line', '?')}`"
            text = str(f.get("summary", "")).replace("|", "\\|").replace("\n", " ")
            scen = str(f.get("failure_scenario", "")).replace("|", "\\|").replace("\n", " ")
            body.append(f"| {f['severity']} | {f['reviewer']} | {where} | {text} — {scen} |")
    else:
        body += ["", "No findings."]
    Path(rdir / "summary.md").write_text("\n".join(body) + "\n")
    Path(rdir / "for-fixer.json").write_text(
        json.dumps({"findings": fixable, "checks": check_lines}, indent=2)
    )

    own = [c for c in pr["comments"] if MARK_SUMMARY in c["body"]]
    if own:
        gh("api", "-X", "PATCH", f"repos/{repo}/issues/comments/{own[-1]['url'].rsplit('-', 1)[-1]}",
           "-F", f"body=@{rdir / 'summary.md'}")
    else:
        gh("pr", "comment", pr_num, "-R", repo, "--body-file", str(rdir / "summary.md"))

    if decision == "fix":
        gh("pr", "comment", pr_num, "-R", repo, "--body",
           f"{MARK_ROUND}\nClaude is fixing the findings above (round {rounds + 1} of {max_rounds}).")
    if decision == "needs-yulong":
        gh("label", "create", "needs-yulong", "-R", repo, "--color", "d93f0b", "--force")
        gh("pr", "edit", pr_num, "-R", repo, "--add-label", "needs-yulong")

    print(f"decision={decision}")
    print(f"round={rounds + 1}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
