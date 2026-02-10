# Plan: Add profile listing to claude-context --help

## Context
`claude-context --help` shows static usage text but doesn't list available profiles. Users need to know what profiles exist and what each enables.

## Change
In `custom_bins/claude-context`, update the `if args.help:` block (~line 516) to dynamically load and display profiles from `profiles.yaml` after the docstring.

## File
- `custom_bins/claude-context` — edit the help handler

## Verification
`claude-context --help` → shows PROFILES section with names, comments, and plugin lists.
