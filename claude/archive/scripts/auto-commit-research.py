#!/usr/bin/env python3
"""
Auto-commit hook for research sessions
Automatically commits experiment results and research progress
"""

import json
import sys
import subprocess
import os
import re
from datetime import datetime
from pathlib import Path


def get_git_status():
    """Check if there are changes to commit"""
    result = subprocess.run(
        ["git", "status", "--porcelain"], capture_output=True, text=True
    )
    return result.stdout.strip()


def should_auto_commit_file(file_path):
    """Determine if file should be auto-committed"""
    auto_commit_patterns = [
        'results/', 'experiments/', 'outputs/', 'analysis/', 'logs/',
        'specs/', 'tasks/', 'issues/', 'docs/',
        '.csv', '.json', '.md', '.txt', '.log', '.py',
        'experiment_', 'result_', 'analysis_', 'output_', 'spec_', 'task_'
    ]
    
    return any(pattern in file_path.lower() for pattern in auto_commit_patterns)


def get_changed_files():
    """Get list of changed files that should be auto-committed"""
    result = subprocess.run(
        ["git", "status", "--porcelain"], capture_output=True, text=True
    )
    
    changed_files = []
    for line in result.stdout.strip().split('\n'):
        if line.strip():
            # Parse git status format: "XY filename"
            status = line[:2]
            filename = line[3:]
            
            # Include modified, added, and untracked files
            if status.strip() and should_auto_commit_file(filename):
                changed_files.append(filename)
    
    return changed_files


def is_experiment_session(transcript_path, changes_summary):
    """Check if this was an experiment/research session"""
    experiment_indicators = [
        'experiment', 'analysis', 'research', 'test', 'evaluate',
        'generate', 'create', 'spec', 'task', 'issue', 'results'
    ]
    
    # Check conversation context
    if changes_summary:
        context_text = ' '.join(changes_summary).lower()
        if any(indicator in context_text for indicator in experiment_indicators):
            return True
    
    # Check transcript if available
    if transcript_path and os.path.exists(transcript_path):
        try:
            with open(transcript_path, "r") as f:
                content = f.read().lower()
                if any(indicator in content for indicator in experiment_indicators):
                    return True
        except Exception:
            pass
    
    return False


def parse_transcript_for_changes(transcript_path):
    """Parse conversation transcript to understand what was done"""
    if not transcript_path or not os.path.exists(transcript_path):
        return []

    try:
        changes_summary = []
        with open(transcript_path, "r") as f:
            for line in f:
                try:
                    msg = json.loads(line.strip())
                    if msg.get("type") == "tool_use":
                        tool_name = msg.get("name", "")
                        if tool_name in ["edit_file", "Write", "Edit"]:
                            file_path = msg.get("input", {}).get("file_path", "") or msg.get("input", {}).get("target_file", "")
                            if file_path:
                                changes_summary.append(f"Modified {file_path}")
                        elif tool_name == "run_terminal_cmd":
                            command = msg.get("input", {}).get("command", "")
                            if any(cmd in command.lower() for cmd in ["python", "experiment", "analysis", "test"]):
                                changes_summary.append(f"Executed: {command[:50]}...")
                    elif msg.get("type") == "text" and msg.get("role") == "user":
                        content = msg.get("content", "").lower()
                        if any(keyword in content for keyword in ["create", "generate", "analyze", "experiment", "research"]):
                            changes_summary.append("Research/experiment session")
                except (json.JSONDecodeError, KeyError):
                    continue

        return changes_summary
    except Exception:
        return []


def generate_intelligent_commit_message(changed_files, changes_summary):
    """Generate intelligent commit message based on changed files and context"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
    
    if not changed_files:
        return None
    
    # Analyze file types and patterns
    file_types = {
        'specs': [f for f in changed_files if 'spec' in f.lower()],
        'tasks': [f for f in changed_files if 'task' in f.lower()],
        'experiments': [f for f in changed_files if 'experiment' in f.lower()],
        'results': [f for f in changed_files if 'result' in f.lower()],
        'analysis': [f for f in changed_files if 'analysis' in f.lower()],
        'docs': [f for f in changed_files if f.endswith('.md')],
        'scripts': [f for f in changed_files if f.endswith('.py')],
        'configs': [f for f in changed_files if any(ext in f for ext in ['.json', '.yaml', '.yml', '.toml'])],
        'data': [f for f in changed_files if any(ext in f for ext in ['.csv', '.txt', '.log'])]
    }
    
    # Determine primary activity
    if file_types['specs']:
        commit_type = "docs"
        activity = "specification"
        primary_files = file_types['specs']
    elif file_types['tasks']:
        commit_type = "feat"
        activity = "task implementation"
        primary_files = file_types['tasks']
    elif file_types['experiments']:
        commit_type = "feat"
        activity = "experiment"
        primary_files = file_types['experiments']
    elif file_types['results']:
        commit_type = "feat"
        activity = "results"
        primary_files = file_types['results']
    elif file_types['analysis']:
        commit_type = "docs"
        activity = "analysis"
        primary_files = file_types['analysis']
    elif file_types['scripts']:
        commit_type = "feat"
        activity = "implementation"
        primary_files = file_types['scripts']
    elif file_types['docs']:
        commit_type = "docs"
        activity = "documentation"
        primary_files = file_types['docs']
    else:
        commit_type = "feat"
        activity = "research session"
        primary_files = changed_files[:3]  # First few files
    
    # Ensure primary_files is valid and not empty
    if not primary_files:
        primary_files = changed_files[:3] if changed_files else []
        activity = "research session"
    
    # Log debug info for troubleshooting
    log_to_research(f"Commit generation - Activity: {activity}, Files: {len(primary_files)}, Type: {commit_type}")
    
    # Generate commit message with robust error handling
    try:
        if len(primary_files) == 1:
            filename = os.path.basename(primary_files[0]) if primary_files[0] else "files"
            title = f"{commit_type}: add {filename}"
        elif len(primary_files) <= 3:
            filenames = [os.path.basename(f) for f in primary_files if f]
            if filenames:
                title = f"{commit_type}: add {', '.join(filenames)}"
            else:
                title = f"{commit_type}: add {activity} files"
        else:
            title = f"{commit_type}: add {activity} files ({len(changed_files)} files)"
    except Exception:
        # Fallback if filename extraction fails
        title = f"{commit_type}: add {activity} files ({len(changed_files)} files)"
    
    # Add description
    description_parts = []
    if changes_summary:
        # Use conversation context
        context = ', '.join(changes_summary[:3])
        description_parts.append(f"Research session: {context}")
    
    description_parts.append(f"Session completed: {timestamp}")
    
    if len(changed_files) > 1:
        description_parts.append(f"Files modified: {len(changed_files)}")
    
    description = "\n\n".join(description_parts)
    
    return f"{title}\n\n{description}\n\n🤖 Auto-committed by Claude Code research hook"


def log_to_research(message):
    """Log message to research monitoring system"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_message = f"[{timestamp}] Research Auto-Commit: {message}"
    
    # Log to file
    log_dir = Path.cwd() / ".claude" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "auto-commit.log"
    
    with open(log_file, 'a') as f:
        f.write(log_message + '\n')


def main():
    try:
        # Read input from Claude Code
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    # Check if we're in a git repository
    git_check = subprocess.run(["git", "rev-parse", "--git-dir"], capture_output=True)
    if git_check.returncode != 0:
        sys.exit(0)

    # Extract session info
    session_id = input_data.get("session_id", "unknown")
    transcript_path = input_data.get("transcript_path", "")

    # Get conversation context
    changes_summary = parse_transcript_for_changes(transcript_path)
    
    # Check if this was an experiment/research session
    if not is_experiment_session(transcript_path, changes_summary):
        log_to_research("Session not identified as experiment/research - skipping auto-commit")
        sys.exit(0)

    # Get files that should be auto-committed
    changed_files = get_changed_files()
    
    if not changed_files:
        log_to_research("No eligible files found for auto-commit")
        sys.exit(0)

    # Stage only the files we want to commit
    for file_path in changed_files:
        try:
            subprocess.run(["git", "add", file_path], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            log_to_research(f"Failed to stage {file_path}")

    # Generate intelligent commit message
    commit_message = generate_intelligent_commit_message(changed_files, changes_summary)
    
    if not commit_message:
        log_to_research("Failed to generate commit message")
        sys.exit(0)

    # Create commit
    try:
        result = subprocess.run(
            ["git", "commit", "-m", commit_message], 
            capture_output=True, text=True, check=True
        )

        # Get commit hash
        commit_hash = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], 
            capture_output=True, text=True
        ).stdout.strip()

        log_to_research(f"Successfully committed {len(changed_files)} files: {commit_hash}")
        print(f"📝 Research session auto-committed: {commit_hash}")
        print(f"Files: {', '.join([os.path.basename(f) for f in changed_files[:3]])}")

    except subprocess.CalledProcessError as e:
        log_to_research(f"Commit failed: {e}")

    sys.exit(0)


if __name__ == "__main__":
    main()
