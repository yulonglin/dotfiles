#!/bin/bash

# ==============================================================================
# SYNC CLAUDE CODE TO ANTIGRAVITY CLI
# Purpose: Ports Claude Code agents/skills into Antigravity CLI (`agy`) by symlinking.
# Source:  ~/.claude/
# Target:  ~/.gemini/antigravity-cli/skills/   (Antigravity reuses the ~/.gemini dir)
#
# Antigravity CLI is Google's official successor to Gemini CLI (consumer Gemini CLI
# access ended 2026-06-18). Project instructions come from AGENTS.md (already in repo),
# so the old GEMINI.md pointer is no longer generated here.
#
# Permission sync: Antigravity stores settings in
# ~/.gemini/antigravity-cli/settings.json with a "permissions" object holding
# allow/deny/ask arrays of action(target) rule strings (e.g. command(git*),
# read_file(*)). Precedence is Deny > Ask > Allow. This script translates Claude's
# permissions.{allow,deny,ask} into that schema and merges them into the live
# settings.json without clobbering other user settings (marker-tracked, idempotent).
#
# Schema confirmed via https://antigravity.google/docs/cli-permissions (2026-06-16):
#   - File: ~/.gemini/antigravity-cli/settings.json
#   - permissions.allow / .deny / .ask  : arrays of "action(target)" strings
#   - action types: command, read_file, write_file, mcp, execute_url, web_*
#   - matching: exact by default; "*" is the per-namespace wildcard; glob/regex supported
#
# Only HIGH-CONFIDENCE mappings (command(), read_file()) are written to the live
# permission arrays. Lower-confidence mappings (WebFetch/WebSearch/MCP action names,
# regex match-mode encoding) are emitted as comments in a sidecar file rather than
# guessed into the live config. See the "VERIFY ON A REAL MAC" notes below.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/helpers/enumerate_claude_skills.sh"
SOURCE_DIR="$HOME/.claude"
TARGET_DIR="$HOME/.gemini/antigravity-cli/skills"

if [ ! -f "$HELPER" ]; then
    echo "Error: enumerate_claude_skills.sh not found at $HELPER" >&2
    exit 1
fi
source "$HELPER"

mkdir -p "$TARGET_DIR"

# Clean stale symlinks (broken or from old *__* pattern)
find "$TARGET_DIR" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
find "$TARGET_DIR" -maxdepth 1 -type l -name '*__*' -delete 2>/dev/null || true

echo ">>> Syncing Claude Code Skills to Antigravity CLI..."

enumerate_claude_skills "$SOURCE_DIR" | while IFS=$'\t' read -r type name path; do
    case "$type" in
        user_skill)
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  User Skill: $name"
            ;;
        standalone_skill)
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Standalone Skill: $name"
            ;;
        plugin_skill)
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  Plugin Skill: $name"
            ;;
        agent_skill)
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Agent Skill: $name"
            ;;
    esac
done

TOTAL=$(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
echo "  Synced $TOTAL skills to $TARGET_DIR"

# ---------- Permissions Sync ----------
#
# Translate Claude Code permissions.{allow,deny,ask} -> Antigravity
# permissions.{allow,deny,ask} (action(target) rule strings) and merge into the
# live settings.json. The merge is marker-tracked so re-runs replace our block
# rather than duplicating, and user-authored rules outside the block survive.

echo ">>> Syncing Claude Code Permissions to Antigravity CLI..."

# Prefer the in-repo source of truth; fall back to the deployed symlink target.
CLAUDE_SETTINGS="$DOTFILES_DIR/claude/settings.json"
[ -f "$CLAUDE_SETTINGS" ] || CLAUDE_SETTINGS="$HOME/.claude/settings.json"

ANTIGRAVITY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
ANTIGRAVITY_SIDECAR="$HOME/.gemini/antigravity-cli/claude_sync_unmapped.txt"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "  Skipping: Claude settings not found at $CLAUDE_SETTINGS"
elif ! command -v python3 >/dev/null 2>&1; then
    echo "  Skipping: python3 not installed"
else
    mkdir -p "$(dirname "$ANTIGRAVITY_SETTINGS")"
    python3 - "$CLAUDE_SETTINGS" "$ANTIGRAVITY_SETTINGS" "$ANTIGRAVITY_SIDECAR" <<'PY'
import json
import re
import sys
from pathlib import Path

claude_path = Path(sys.argv[1])
ag_path = Path(sys.argv[2])
sidecar_path = Path(sys.argv[3])

# Marker tags wrapping the rules we own inside each permission array, so re-runs
# can replace our contribution while leaving user-authored rules untouched.
BEGIN = "// BEGIN CLAUDE SYNC (auto-generated)"
END = "// END CLAUDE SYNC"

try:
    claude = json.loads(claude_path.read_text())
except (OSError, json.JSONDecodeError) as exc:
    print(f"  Skipping: cannot read Claude settings ({exc})")
    sys.exit(0)

perms = claude.get("permissions", {})


def claude_bash_to_command_target(pattern):
    """Map a Claude `Bash(...)` permission to an Antigravity command(...) target.

    Claude uses prefix-glob with a trailing ` *` (e.g. `Bash(git *)`), plus some
    exact forms (e.g. `Bash(pueue status)`). Antigravity matches `command(...)`
    targets exactly by default and treats `*` as a glob wildcard, so:
        Bash(git *)         -> command(git*)     (glob: any git subcommand/args)
        Bash(pueue status)  -> command(pueue status)  (exact)
    Returns None for anything we can't confidently express.
    """
    m = re.match(r"^Bash\((.*)\)$", pattern, re.DOTALL)
    if not m:
        return None
    inner = m.group(1).strip()
    if not inner:
        return None
    # Trailing " *" is Claude's "this command with any args" idiom -> glob.
    if inner.endswith(" *"):
        stem = inner[:-2].strip()
        if not stem:
            return None
        return f"command({stem}*)"
    # Otherwise treat as an exact command string. If it still contains a glob
    # star, Antigravity's glob matcher handles it; pass through verbatim.
    return f"command({inner})"


# High-confidence: tools whose Antigravity action name + target we can map
# faithfully. Lower-confidence tools go to the sidecar instead of being guessed.
def map_rule(item):
    """Return (antigravity_rule, None) if confidently mapped,
    else (None, reason) to record as unmapped."""
    if item.startswith("Bash("):
        target = claude_bash_to_command_target(item)
        if target:
            return target, None
        return None, "unparsable Bash pattern"
    if item == "Read":
        return "read_file(*)", None
    if item.startswith("Read("):
        m = re.match(r"^Read\((.*)\)$", item, re.DOTALL)
        if m and m.group(1).strip():
            return f"read_file({m.group(1).strip()})", None
        return None, "unparsable Read pattern"
    # --- Lower-confidence / unverified action namespaces ---
    # The following Claude tools have plausible Antigravity equivalents, but the
    # exact action name (web_fetch vs web_search vs web) and the mcp() target
    # encoding are NOT confirmed from docs. We deliberately do NOT write these to
    # the live config. Best-effort guesses are recorded in the sidecar for a human
    # to verify on a real Mac with `agy` (see /permissions output).
    if item == "WebFetch":
        return None, "WebFetch -> web_fetch(*)?  [action name unverified]"
    if item.startswith("WebFetch(domain:"):
        return None, f"{item} -> web_fetch(<domain>)?  [encoding unverified]"
    if item == "WebSearch":
        return None, "WebSearch -> web_search(*)?  [action name unverified]"
    if item.startswith("mcp__"):
        return None, f"{item} -> mcp(<server/tool>)?  [target encoding unverified]"
    if item in ("Glob", "Grep", "Search"):
        return None, f"{item} (Claude built-in; no Antigravity equivalent)"
    return None, f"{item} (no mapping rule)"


mapped = {"allow": [], "deny": [], "ask": []}
unmapped = []
for bucket in ("allow", "deny", "ask"):
    for item in perms.get(bucket, []):
        rule, reason = map_rule(item)
        if rule is not None:
            if rule not in mapped[bucket]:
                mapped[bucket].append(rule)
        else:
            unmapped.append(f"[{bucket}] {item}  ->  {reason}")

# --- Merge into the existing settings.json, preserving non-permission keys and
#     any user-authored rules that live outside our marker block. ---
settings = {}
if ag_path.exists():
    try:
        settings = json.loads(ag_path.read_text())
        if not isinstance(settings, dict):
            settings = {}
    except (OSError, json.JSONDecodeError):
        # Don't clobber an unreadable/hand-edited file; bail loudly instead.
        print(f"  Skipping: {ag_path} exists but is not valid JSON; "
              "leaving it untouched.")
        sys.exit(0)

perm_obj = settings.get("permissions")
if not isinstance(perm_obj, dict):
    perm_obj = {}


def merge_bucket(existing, ours):
    """Drop any prior CLAUDE-SYNC block, keep user rules, append fresh block.

    Our block is delimited by BEGIN/END sentinel strings inserted as array
    elements. Re-runs strip the old block (between the sentinels) and re-add a
    current one, so user-authored entries outside the block are preserved and
    our contribution never duplicates.
    """
    existing = existing if isinstance(existing, list) else []
    kept = []
    skipping = False
    for el in existing:
        if el == BEGIN:
            skipping = True
            continue
        if el == END:
            skipping = False
            continue
        if not skipping:
            kept.append(el)
    if not ours:
        return kept
    return kept + [BEGIN] + ours + [END]


changed_buckets = []
for bucket in ("allow", "deny", "ask"):
    new_list = merge_bucket(perm_obj.get(bucket), mapped[bucket])
    perm_obj[bucket] = new_list
    changed_buckets.append(f"{bucket}:{len(mapped[bucket])}")

settings["permissions"] = perm_obj

ag_path.parent.mkdir(parents=True, exist_ok=True)
ag_path.write_text(json.dumps(settings, indent=2) + "\n")
print(f"  Wrote {ag_path}")
print(f"  Synced rules ({', '.join(changed_buckets)})")

# Record everything we did NOT confidently map, for human verification.
header = [
    "# Claude -> Antigravity permission sync: UNMAPPED / UNVERIFIED entries",
    f"# Source: {claude_path}",
    "# These Claude permissions were NOT written to settings.json because the",
    "# Antigravity action name or target encoding is not confirmed from docs.",
    "# Verify against `agy` /permissions on a real Mac, then map by hand.",
    "",
]
if unmapped:
    sidecar_path.write_text("\n".join(header + sorted(set(unmapped))) + "\n")
    print(f"  {len(set(unmapped))} unmapped/unverified entries -> {sidecar_path}")
else:
    # Nothing unmapped: clear any stale sidecar from a previous run.
    if sidecar_path.exists():
        sidecar_path.unlink()
PY
fi

echo ">>> Done. Antigravity CLI synchronized with Claude Code (skills + permissions)."
echo "    (Project instructions: AGENTS.md. Unmapped perms, if any: ~/.gemini/antigravity-cli/claude_sync_unmapped.txt)"
echo ""
echo "    # TODO: verify Antigravity permission schema on a real Mac (no \`agy\` in CI/Linux):"
echo "    #  - Confirm settings.json 'permissions' merges live (run \`agy\` -> /permissions)."
echo "    #  - Confirm glob target form: does command(git*) auto-approve 'git status'?"
echo "    #    (docs say default match is EXACT; '*' is the glob wildcard — verify the"
echo "    #     trailing-star form is read as glob, not a literal '*' character.)"
echo "    #  - Verify unverified action names in the sidecar: web_fetch / web_search / mcp()."
echo "    #  - Decide whether regex rules (e.g. 'command(git (status|log).*)' with a"
echo "    #    match-mode field) are preferable to globs; docs hint at a per-rule match"
echo "    #    strategy (exact|glob|regex) whose JSON encoding is not yet confirmed."
