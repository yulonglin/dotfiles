#!/usr/bin/env bash
# Global PreToolUse hook: BLOCKS all email sending.
# Emails are irreversible — only drafts are allowed, never sends.
#
# Blocks:
#   - gws gmail +send (without --draft)
#   - gws gmail users drafts send
#   - gws gmail users messages send
#   - gws gmail +reply/+reply-all/+forward (without --draft)
#   - Any of the above inside bash -c / sh -c wrappers
#
# TOKENIZATION: the command is split into segments and each segment is
# normalised through shlex before matching, and --draft/--dry-run/--help are
# recognised only as real argv tokens. Matching the raw string fails OPEN two
# ways: `--body "mentions --draft literally"` is body TEXT, not a flag, yet a
# naive regex reads it as one and permits a live send; and `gws gmail +se""nd`
# is executed by Bash as `+send` but never matches. Both are silent permission.
#
# Reads Bash tool_input JSON from stdin, checks the command field.
# Exit 0 = allow, Exit 2 = block.
#
# MCP coverage audit (2026-07-27): the Gmail connector exposes NO send tool —
# only create_draft / update_draft / list_drafts, plus label operations. So there
# is no MCP send path to block here, and no matcher is wired: a matcher naming a
# nonexistent tool is dead config. Re-check after connector updates; if a
# send/send_draft tool appears, add a tool_name branch like block_gws_delete.sh.
# (Out of scope but adjacent: mcp__claude_ai_Slack__slack_send_message IS a live
# unilateral send, with slack_send_message_draft as the safe sibling.)

set -uo pipefail

INPUT=$(cat)

# One line per segment: "F:<flags>\t<shlex-normalised segment>", where <flags> is
# a comma-separated set drawn from draft,dryrun,help — computed from real argv
# tokens, never from substrings of a quoted value.
#
# The literal "F:" prefix is load-bearing: `read` strips LEADING IFS whitespace,
# and a tab is IFS whitespace, so a line starting with an empty flags field would
# shift every field left — SEGMENT ends up empty and the guard skips the segment
# entirely. Silent permission. Keeping field 1 non-empty removes the whole class.
FIELDS=$(printf '%s' "$INPUT" | python3 -c "
import sys, json, shlex, re

SPLIT = re.compile(r'\|\||&&|[;\n|]')
SHELLS = {'bash', 'sh', 'zsh', 'dash', 'ksh', 'ash'}


def rows(cmd, depth=0):
    out = []
    for seg in SPLIT.split(cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        if not toks:
            continue
        flags = []
        if any(t == '--draft' or t.startswith('--draft=') for t in toks):
            flags.append('draft')
        if any(t == '--dry-run' or t.startswith('--dry-run=') for t in toks):
            flags.append('dryrun')
        if toks[-1] == '--help':
            flags.append('help')
        out.append('F:' + ','.join(flags) + '\t' + ' '.join(toks))
        # \`bash -c '<nested>'\` keeps the whole nested command as one token.
        if depth < 4:
            for i, t in enumerate(toks):
                if t.rsplit('/', 1)[-1] not in SHELLS:
                    continue
                for j in range(i + 1, len(toks) - 1):
                    if toks[j] == '-c':
                        out.extend(rows(toks[j + 1], depth + 1))
                        break
    return out


try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        raise ValueError
    inp = d.get('tool_input', d)
    if not isinstance(inp, dict):
        inp = {}
    for r in rows(inp.get('command', '') or ''):
        print(r)
except Exception:
    print('PARSE_ERROR\t')
" 2>/dev/null)

# Fail CLOSED: unparseable payload that still looks like a Gmail send.
if printf '%s' "$FIELDS" | grep -q '^PARSE_ERROR'; then
    if printf '%s' "$INPUT" | grep -qE 'gws.*gmail' && \
       printf '%s' "$INPUT" | grep -qE '\+send|\+reply|\+forward|drafts.*send|messages.*send'; then
        printf 'BLOCKED: could not parse this command, and it mentions a Gmail send.\n' >&2
        printf 'Rewrite it as a plain, unquoted command so the guard can inspect it.\n' >&2
        exit 2
    fi
    exit 0
fi

# No parseable command = not a Bash tool call, allow.
[ -z "$FIELDS" ] && exit 0

check_segment() {
    local flags="${1#F:}" seg="$2"

    # Not a gws gmail call — nothing to gate.
    printf '%s' "$seg" | grep -q 'gws.*gmail' || return 0

    # Exemptions, scoped to this segment and to real argv tokens.
    case ",$flags," in
        *,help,*|*,dryrun,*) return 0 ;;
    esac

    local has_draft=1
    case ",$flags," in
        *,draft,*) has_draft=0 ;;
    esac

    # Block: gws gmail users drafts send (sends an existing draft)
    if printf '%s' "$seg" | grep -qE 'gws.*gmail.*users.*drafts.*send'; then
        printf 'BLOCKED: Cannot send Gmail drafts programmatically.\n' >&2
        printf 'Emails are irreversible. Review and send manually from Gmail.\n' >&2
        exit 2
    fi

    # Block: gws gmail users messages send (raw API send)
    if printf '%s' "$seg" | grep -qE 'gws.*gmail.*users.*messages.*send'; then
        printf 'BLOCKED: Cannot send emails via raw Gmail API.\n' >&2
        printf 'Emails are irreversible. Review and send manually from Gmail.\n' >&2
        exit 2
    fi

    # Block: gws gmail +send WITHOUT a real --draft flag
    if [ "$has_draft" -ne 0 ] && printf '%s' "$seg" | grep -qE 'gws.*gmail.*\+send'; then
        printf 'BLOCKED: Cannot send emails directly.\n' >&2
        printf 'Use --draft flag to create a draft instead. Send manually from Gmail.\n' >&2
        exit 2
    fi

    # Block: gws gmail +reply, +reply-all, +forward (also sends)
    if [ "$has_draft" -ne 0 ] && printf '%s' "$seg" | grep -qE 'gws.*gmail.*\+(reply|reply-all|forward)'; then
        printf 'BLOCKED: Cannot send email replies/forwards programmatically.\n' >&2
        printf 'Use --draft flag to create a draft instead. Send manually from Gmail.\n' >&2
        exit 2
    fi

    return 0
}

while IFS=$'\t' read -r FLAGS SEGMENT; do
    [ -n "$SEGMENT" ] && check_segment "$FLAGS" "$SEGMENT"
done < <(printf '%s\n' "$FIELDS")

exit 0
