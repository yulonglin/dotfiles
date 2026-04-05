#!/usr/bin/env node
// PreToolUse reminder: when staging files, remind to run a codex review before committing.
// Hook config: matcher "Bash", if "Bash(git add *)"

import fs from "node:fs";

const input = JSON.parse(fs.readFileSync(0, "utf8"));

// Self-validate: exit early if this isn't actually a git add command
const command = input.tool_input?.command ?? "";
if (!command.match(/^git\s+add\b/)) {
  process.exit(0);
}

const output = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext:
      "Before committing, run `codex-companion review` to get a comprehensive Codex review of the changes."
  }
};

process.stdout.write(JSON.stringify(output) + "\n");
