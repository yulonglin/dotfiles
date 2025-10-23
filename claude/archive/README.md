# Archive Directory

This directory contains files from previous Claude Code setups that may or may not be useful for the current dotfiles deployment. They are archived here for review and potential future integration.

## Contents

### hooks/
Python hook scripts for Claude Code that provide automation and validation:
- `hook_utils.py` - Shared utilities for hooks
- `notification.py` - Notification handling
- `post_tool_use.py` - Post-tool-use hook
- `pre_tool_use_simple.py` - Pre-tool-use validation
- `stop.py` - Stop hook for session cleanup
- `subagent_stop.py` - Subagent stop handling

**Status**: Archived for review. May be useful if you want automated validation, but some appear research-specific.

### scripts/
Python automation scripts for research workflows:
- `analyze-logs.py` - Log analysis utilities
- `auto-commit-research.py` - Automatic research commit workflow (research-specific)
- `extract-claude-session.py` - Extract session data
- `format-python.py` - Python code formatting
- `log-activity.py` - Activity logging
- `notify.py` - Notification script
- `validate-file-organization.py` - File organization validation
- `validate-no-mock.py` - Mock data detection (research-specific)
- `test-*.py` - Test files for hooks and validation

**Status**: Archived for review. Some are research-specific (auto-commit-research.py, validate-no-mock.py), others may be generally useful.

### docs/
Documentation and templates:
- `guides/` - Usage guides
- `reference/` - Reference documentation
- `templates/` - Document templates
- `quick-start-guide.md` - Quick start documentation
- `todo.md` - Todo tracking

**Status**: Archived for review. May be useful if you want structured documentation for Claude Code workflows.

## Next Steps

Review these directories to decide:
1. **Integrate**: Move useful scripts/hooks into the main dotfiles structure
2. **Keep as reference**: Useful to have but not needed for deployment
3. **Remove**: No longer needed

## Notes

- The `notify.sh` script in the parent directory (`claude/notify.sh`) replaces the notification functionality and is actively used via hooks in `settings.json`
- Research-specific validation may not be applicable to general dotfiles/admin work
