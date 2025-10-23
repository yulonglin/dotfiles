# Automation Hooks Guide

This guide documents the automation hooks available in the AI Safety Research template, particularly focusing on the enhanced auto-commit functionality for research sessions.

## Overview

The automation system provides intelligent hooks that trigger during Claude Code sessions to:
- Automatically commit research progress
- Format code
- Log activities
- Run tests
- Validate data quality

## Enhanced Auto-Commit Research Hook

The auto-commit hook (`/.claude/scripts/auto-commit-research.py`) has been significantly enhanced to provide intelligent, selective commits for research sessions.

### Key Features

#### 1. Intelligent Session Detection

The hook detects research/experiment sessions by analyzing:
- **Conversation content**: Looks for keywords like "experiment", "analysis", "research", "test", "evaluate"
- **Tool usage**: Tracks file modifications and command executions
- **File patterns**: Identifies research-related file changes

#### 2. Selective File Commits

Only commits files matching specific patterns:

**Directory Patterns:**
- `results/` - Experiment results
- `experiments/` - Experiment configurations and outputs
- `outputs/` - Generated outputs
- `analysis/` - Analysis scripts and results
- `logs/` - Session and experiment logs
- `specs/` - Specifications
- `tasks/` - Task files
- `issues/` - Issue tracking
- `docs/` - Documentation

**File Patterns:**
- `.csv`, `.json`, `.md`, `.txt`, `.log`, `.py`
- Files starting with: `experiment_`, `result_`, `analysis_`, `output_`, `spec_`, `task_`

#### 3. Smart Commit Messages

Generates intelligent commit messages based on:
- **File types**: Analyzes what types of files were changed
- **Activity detection**: Determines if it's specs, tasks, experiments, results, etc.
- **Context awareness**: Uses conversation context to enhance messages

Example commit messages:
```
feat: add experiment_001.py

Research session: Modified experiments/experiment_001.py, Executed: python experiment_001.py
Session completed: 2025-07-24 10:30
Files modified: 3

🤖 Auto-committed by Claude Code research hook
```

### Configuration

The hook runs automatically when Claude Code stops, but only commits if:
1. It detects a research/experiment session
2. There are eligible files to commit
3. You're in a git repository

### Logging

All auto-commit activities are logged to:
```
.claude/logs/auto-commit.log
```

Example log entries:
```
[2025-07-24 10:30:45] Research Auto-Commit: Session not identified as experiment/research - skipping auto-commit
[2025-07-24 11:45:23] Research Auto-Commit: Successfully committed 5 files: abc123f
```

## Other Automation Hooks

### Mock Data Validation

- **Purpose**: Prevents committing mock or placeholder data
- **Scope**: All files except those in `docs/`
- **Behavior**: Blocks commits containing obvious mock data patterns

### Python Formatting (Black)

- **Purpose**: Automatically formats Python code
- **Trigger**: After any Python file edit
- **Configuration**: Uses project's `pyproject.toml` if available

### Activity Logging

- **Purpose**: Track all Claude Code actions for debugging
- **Location**: `~/.claude/research-activity.log`
- **Contents**: Tool usage, file modifications, command executions

### Test Execution

- **Purpose**: Run tests automatically when test files change
- **Pattern**: Files matching `test_*.py` or `*_test.py`
- **Behavior**: Runs pytest with minimal output

## Best Practices

### 1. Organize Your Work

Keep research files in the appropriate directories:
- Use `experiments/` for experiment scripts
- Save results to `results/`
- Document findings in `docs/`
- Track tasks in `tasks/`

### 2. Name Files Descriptively

Use clear prefixes to help the auto-commit system:
- `experiment_[name].py` for experiment scripts
- `result_[experiment]_[date].csv` for results
- `analysis_[topic].py` for analysis scripts

### 3. Review Commits

While auto-commit is convenient, periodically review:
```bash
git log --oneline -10
```

### 4. Customize Patterns

To modify which files are auto-committed, edit the patterns in:
```python
# .claude/scripts/auto-commit-research.py
auto_commit_patterns = [
    'results/', 'experiments/', 'outputs/', 'analysis/', 'logs/',
    'specs/', 'tasks/', 'issues/', 'docs/',
    '.csv', '.json', '.md', '.txt', '.log', '.py',
    'experiment_', 'result_', 'analysis_', 'output_', 'spec_', 'task_'
]
```

## Troubleshooting

### Auto-commit not working?

1. **Check if you're in a git repo**:
   ```bash
   git status
   ```

2. **Verify the hook is installed**:
   ```bash
   ls -la .claude/scripts/auto-commit-research.py
   ```

3. **Check the logs**:
   ```bash
   tail -f .claude/logs/auto-commit.log
   ```

### Files not being committed?

1. **Verify file patterns**: Ensure your files match the patterns
2. **Check session detection**: Use research-related keywords in your requests
3. **Manual commit**: You can always commit manually:
   ```bash
   git add .
   git commit -m "Research progress"
   ```

## Advanced Usage

### Custom Session Detection

Add your own keywords to detect sessions:
```python
experiment_indicators = [
    'experiment', 'analysis', 'research', 'test', 'evaluate',
    'generate', 'create', 'spec', 'task', 'issue', 'results',
    'your_custom_keyword'  # Add your keywords here
]
```

### Integration with CI/CD

The auto-commits can trigger CI/CD pipelines:
1. Use commit message patterns in your CI config
2. Filter by the 🤖 emoji to identify auto-commits
3. Run validation on research outputs

### Disabling Auto-commit

To temporarily disable:
```bash
# Rename the hook
mv .claude/scripts/auto-commit-research.py .claude/scripts/auto-commit-research.py.disabled
```

To permanently disable, remove the hook from `.claude/claude_config.json`:
```json
{
  "hooks": {
    "on_session_stop": []  // Remove the hook from here
  }
}
```

## Summary

The enhanced auto-commit system provides:
- ✅ Intelligent session detection
- ✅ Selective file commits (only research files)
- ✅ Smart commit messages with context
- ✅ Comprehensive logging
- ✅ Preserves your research progress automatically

This ensures your valuable research work is never lost while keeping your git history clean and meaningful.