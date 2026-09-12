#!/usr/bin/env python3
"""Install maintained Codex hooks without replacing config, plugins or history.

Dry-run by default. Remove only recognized imports under the target hooks dir,
preserve custom handlers, and back up changed files before atomic replacement.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import shlex
import tempfile
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[2]
LEGACY = {
    "check_loop_bypass.sh", "network_audit.py", "nudge_modern_tools.sh",
    "warn_dep_install.sh", "check_agent_depth.sh", "check_webfetch_domain.sh",
    "block_tab_group_creation.sh", "nudge_html_email.sh", "require_plan_approval.sh",
    "with-anthropic-key.sh", "auto_classify.py", "retry_omitted_grep.sh",
    "agent_spawned.sh", "check_git_root.sh", "check_venv.sh",
    "session_start_notes.sh", "show_auth_account.sh", "context_auto_apply.sh",
    "check_things_mcp.sh", "watchdog_mark.sh", "nudge_remember.sh",
    "session_rename_auto.sh", "context.py",
}
BEGIN = "<!-- BEGIN CODEX TOOL COMPATIBILITY -->"
END = "<!-- END CODEX TOOL COMPATIBILITY -->"


def owned(hook, target):
    if hook.get("type") != "command":
        return False
    try:
        tokens = shlex.split(hook.get("command", ""), comments=True)
    except ValueError:
        return False
    prefixes = (str(target / "hooks") + "/", "$HOME/.codex/hooks/",
                "${HOME}/.codex/hooks/", "~/.codex/hooks/",
                "${CODEX_HOME:-$HOME/.codex}/hooks/")
    def known(token):
        return any(token == prefix + name for prefix in prefixes for name in LEGACY)
    if tokens and tokens[0] in ("bash", "sh", "python3", "/bin/bash", "/usr/bin/python3"):
        tokens = tokens[1:]
    if not tokens or not known(tokens[0]):
        return False
    # Do not remove custom commands that merely mention a managed script.
    allowed_args = {"python3", "working", "idle", "modern-tools",
                    "dependency-install", "session-start"}
    return all(known(token) or token in allowed_args for token in tokens[1:])


def merge_hooks(existing, maintained, target):
    result = copy.deepcopy(existing)
    events = result.setdefault("hooks", {})
    for event, groups in list(events.items()):
        kept = []
        for group in groups:
            group["hooks"] = [h for h in group.get("hooks", []) if not owned(h, target)]
            if group["hooks"]:
                kept.append(group)
        if kept:
            events[event] = kept
        else:
            del events[event]
    for event, groups in maintained["hooks"].items():
        events.setdefault(event, []).extend(copy.deepcopy(groups))
    result.setdefault("description", maintained["description"])
    return result


def merge_instructions(existing, block):
    if BEGIN in existing or END in existing:
        if existing.count(BEGIN) != 1 or existing.count(END) != 1:
            raise ValueError("ambiguous compatibility markers in AGENTS.md")
        before, rest = existing.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        return before + block.rstrip() + after
    return existing.rstrip() + "\n\n" + block


def replacements(target):
    source = REPO / "codex"
    manifest = target / "hooks.json"
    existing = json.loads(manifest.read_text()) if manifest.exists() else {"hooks": {}}
    maintained = json.loads((source / "hooks.json").read_text())
    if manifest.resolve() == (source / "hooks.json").resolve():
        # deploy.sh can symlink the runtime home to codex/. Do not merge the
        # manifest with itself: that would duplicate every custom handler.
        manifest_bytes = manifest.read_bytes()
    else:
        manifest_bytes = (json.dumps(merge_hooks(existing, maintained, target), indent=2) + "\n").encode()
    files = {manifest: manifest_bytes}
    scripts = sorted((source / "hooks").glob("*"))
    for path in scripts:
        if path.is_file() and path.suffix in (".py", ".sh"):
            files[target / "hooks" / path.name] = path.read_bytes()
    agents = target / "AGENTS.md"
    text = agents.read_text() if agents.exists() else (source / "AGENTS.md").read_text()
    files[agents] = merge_instructions(text, (source / "tool-compatibility.md").read_text()).encode()
    return files


def install(target, apply=False):
    # Capture before computing merged content, not afterwards: both are dual-written.
    inputs = [target / "hooks.json", target / "AGENTS.md"]
    originals = {p: p.read_bytes() if p.exists() else None for p in inputs}
    files = replacements(target)
    for path, original in originals.items():
        if (path.read_bytes() if path.exists() else None) != original:
            raise RuntimeError("file changed during preparation: " + str(path))
    snapshots = {p: p.read_bytes() if p.exists() else None for p in files}
    changed = {p: data for p, data in files.items() if snapshots[p] != data}
    for path in changed:
        print(("Update: " if apply else "Would update: ") + str(path))
    if not changed:
        print("Codex hooks already synchronized.")
        return
    if not apply:
        return
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    backup = target / "backups" / ("hooks-" + stamp)
    for path in changed:
        current = path.read_bytes() if path.exists() else None
        if current != snapshots[path]:
            raise RuntimeError("file changed during preparation: " + str(path))
        if path.is_symlink():
            raise RuntimeError("refusing to replace symlink: " + str(path))
        for parent in path.parents:
            if parent == target:
                break
            if parent.is_symlink():
                raise RuntimeError("refusing symlink parent: " + str(parent))
    # Scripts first, manifest last: registrations never point at absent scripts.
    for path in sorted(changed, key=lambda p: p == target / "hooks.json"):
        data = changed[path]
        if snapshots[path] is not None:
            saved = backup / path.relative_to(target)
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(snapshots[path])
            saved.chmod(0o600)
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
        if path.suffix == ".sh":
            mode |= 0o111
        fd, tmp = tempfile.mkstemp(prefix=".codex-hooks-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            os.chmod(tmp, mode)
            if path.is_symlink() or (path.read_bytes() if path.exists() else None) != snapshots[path]:
                raise RuntimeError("file changed during write: " + str(path))
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        if path.read_bytes() != data:
            raise RuntimeError("verification failed: " + str(path))
    print("Backup: " + str(backup))
    print("Open /hooks in a fresh Codex session to review changed hook definitions.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex"))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    install(args.target.expanduser().absolute(), args.apply)


if __name__ == "__main__":
    main()
