#!/bin/bash
# SessionStart hook: warn if CWD is not a git root.
# Catches IDE integrations and direct `command claude` that bypass the wrapper.

git_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
physical_cwd=$(realpath "$PWD" 2>/dev/null || pwd -P)

if [[ -n "$git_root" && "$physical_cwd" != "$git_root" ]]; then
    msg="WARNING: CWD ($PWD) is not the git root ($git_root). Plans will be created in the wrong location. Consider: cd $git_root"
    jq -n --arg m "$msg" '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $m
        }
    }'
fi

exit 0
