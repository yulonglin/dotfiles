# Shell Compatibility - COMPLETED

## Summary
Converted `deploy.sh` and `scripts/shared/helpers.sh` to zsh to avoid bash 3.2 limitations on macOS.

## What Was Done
- ✅ Changed shebangs to `#!/bin/zsh`
- ✅ Converted bash 4+ features to zsh equivalents (`typeset`, `${(U)}`, `${(k)}`)
- ✅ Fixed zsh local variable quirk
- ✅ Kept `install.sh` as bash 3.2-compatible for portability

## Decision: Keep Current Setup
User has Homebrew bash installed but chose to keep the current approach:
- `install.sh` → bash 3.2-compatible (runs before dependencies installed)
- `deploy.sh` + `helpers.sh` → zsh (modern, guaranteed on macOS)

No further action needed.
