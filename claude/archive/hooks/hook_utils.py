#!/usr/bin/env python3
"""Shared utilities for Claude hooks"""

from pathlib import Path


def find_claude_dir():
    """Find .claude directory by searching upward from current directory"""
    current = Path.cwd()
    while current != current.parent:  # Stop at filesystem root
        claude_dir = current / ".claude"
        if claude_dir.is_dir():
            return claude_dir
        current = current.parent
    # Fallback to current directory if not found
    return Path.cwd() / ".claude"