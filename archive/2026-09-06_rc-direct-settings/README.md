# rc-direct-settings.json, archived 2026-09-06

`rc-direct-settings.json` blanked the model-router gateway keys for one session so that Remote Control (which needs `api.anthropic.com`) could connect. The `claude()` wrapper in `config/aliases/claude.sh` and `custom_bins/claude-spawn` prepended it as `--settings` to every interactive session by default until 2026-09-06.

Under Option C of the model-routing decision spec the gateway is the default and Remote Control is off by design. The wrapper made the override opt-in (`CLAUDE_RC_OVERRIDE=1`) in PR #101, but every zsh started before that merge still carried the old function and kept un-gating sessions (a session on `astra` failed with "There's an issue with the selected model" at 09:57 UTC). Both old and new wrappers skip the override silently when the file is missing, so archiving the file is what fixes every already-running shell at once.

To run the Remote Control unix-socket experiment (spec plan step 1), copy this file back to `claude/rc-direct-settings.json` for the duration and launch with `CLAUDE_RC_OVERRIDE=1`, or pass `--settings` with the same JSON inline.
