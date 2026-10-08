#!/usr/bin/env zsh
# PreToolUse hook for the Bear MCP: refuse a guessed argument, and an uncapped search.
#
# The Bear server ignores an argument it does not know instead of rejecting it.
# On 2026-10-08 an agent that had not loaded the schema passed `section=` to
# read_note_content three times; each call returned the whole 43 KB note.
# On edit_note the same slip would widen a find/replace from one section to the
# whole note. search_notes and list_notes with no `limit` returned 98 and 67
# notes of metadata for a lookup that needed three titles.
#
# Contract (same as block_bulky_mcp_search.sh): exit 0 = allow; exit 2 = block,
# reason on stderr.
#
# Checks:
#   every tool in ALLOWED   argument keys must be in its allowlist
#   search_notes, list_notes  limit set, 0..MAX; includeContent needs limit <= MAX_CONTENT
#
# The allowlists copy the bear-mcp schemas as of 2026-10-08. When Bear adds a
# parameter, add it here; a legitimate call blocked by a stale list says so.

input=$(cat)
(( $+commands[jq] )) || exit 0

MAX=10
MAX_CONTENT=3
HOOK_PATH='claude/hooks/guard_bear_mcp_args.sh'

tool=$(print -r -- "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[[ $tool == mcp__*[Bb]ear__* ]] || exit 0
name=${tool##*__}

typeset -A ALLOWED=(
    get_note          'id title includeContent'
    read_note_content 'id title address offset limit'
    read_note_outline 'id title address'
    search_in_note    'id title address string context limit'
    search_notes      'query includeContent limit location offset sort'
    list_notes        'includeContent limit location offset sort tag'
    edit_note         'id title address edits expectedRemovedAttachments'
    overwrite_note    'id title address baseHash content expectedRemovedAttachments'
    append_to_note    'id title address content position'
    create_note       'title content tags ifNotExists'
)
(( $+ALLOWED[$name] )) || exit 0

allowed=${ALLOWED[$name]}
keys=$(print -r -- "$input" | jq -r '(.tool_input // {}) | keys[]' 2>/dev/null) || exit 0

typeset -a unknown reasons
for k in ${(f)keys}; do
    (( ${${=allowed}[(Ie)$k]} )) || unknown+=$k
done
(( $#unknown )) && reasons+="unknown argument(s) ${(j:, :)unknown}; $name takes only: ${allowed// /, }"

if [[ $name == search_notes || $name == list_notes ]]; then
    cap=$(print -r -- "$input" | jq -r --argjson max $MAX --argjson maxc $MAX_CONTENT '
        (.tool_input.limit | if . == null then null else (tonumber? // null) end) as $n
        | (.tool_input.includeContent == true) as $c
        | if $n == null then "limit is unset; pass limit <= \($max) (0 returns only the count)"
          elif $n < 0 or $n > $max then "limit is \($n); pass limit <= \($max)"
          elif $c and $n > $maxc then "includeContent with limit \($n); pass limit <= \($maxc) when pulling note bodies"
          else "" end' 2>/dev/null) || exit 0
    [[ -n $cap ]] && reasons+=$cap
fi

(( $#reasons )) || exit 0

print -u2 -r -- "Blocked: $tool (${(j:; :)reasons}).

Bear silently ignores an argument it does not know, so a guessed name turns a section read into a whole-note read, or a section edit into a whole-note edit. An unlimited search returns metadata for every matching note.

Do this:
- Load the schema before the first call: ToolSearch \"select:$tool\". Load the \`bear\` skill too (Read playbook: get_note for size, read_note_outline, then read_note_content with address=).
- Find a note by name with search_notes(query=\"@title \\\"exact words\\\"\", limit=5), not loose common words.
- If Bear has really added this argument, add it to ALLOWED in $HOOK_PATH."
exit 2
