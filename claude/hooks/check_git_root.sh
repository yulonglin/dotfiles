#!/bin/bash
# SessionStart hook: warn if CWD is not a git root
# Catches IDE integrations and direct `command claude` that bypass the wrapper

git_root=$(git rev-parse --show-toplevel 2>/dev/null)
physical_cwd=$(realpath "$PWD" 2>/dev/null || pwd -P)
if [[ -n "$git_root" && "$physical_cwd" != "$git_root" ]]; then
    echo "WARNING: CWD ($PWD) is not the git root ($git_root)"
    echo "Plans will be created in the wrong location."
    echo "Consider: cd $git_root"
fi
exit 0  # Don't block session start
