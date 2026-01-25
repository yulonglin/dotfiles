# Plan: Add ~/.claude to Working Directory (dotfiles project only)

## Goal
Configure Claude Code to include `~/.claude` in its accessible directories for the dotfiles project only.

## Approach
Use the `additionalDirectories` setting in the project-level `.claude/settings.json`.

## Implementation

Edit `/Users/yulong/code/dotfiles/.claude/settings.json` to add the `additionalDirectories` array:

```json
{
  "permissions": {
    "allow": [
      "Bash(chmod:*)",
      "Bash(python3:*)",
      "Bash(shortcuts list:*)",
      "Bash(git checkout:*)"
    ],
    "deny": [],
    "ask": [],
    "additionalDirectories": [
      "~/.claude"
    ]
  }
}
```

## Files to Modify
- `/Users/yulong/code/dotfiles/.claude/settings.json` (add `additionalDirectories` array)

## Notes
- This only affects the dotfiles project (not global)
- Uses `~/.claude` format (tilde expansion)
