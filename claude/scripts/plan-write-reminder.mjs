#!/usr/bin/env node
// PreToolUse reminder: when writing a plan file, remind to run codex plan-review.
// Hook config: matcher "Write", if "Write(*/.claude/plans/*.md)"
// Also matches project-level plans/ directory (plansDirectory: "plans").

import fs from "node:fs";

const input = JSON.parse(fs.readFileSync(0, "utf8"));
const filePath = input.tool_input?.file_path ?? "";

// Match both ~/.claude/plans/ and project-level plans/
if (!filePath.includes("/plans/")) {
  process.exit(0);
}

// Only .md files
if (!filePath.endsWith(".md")) {
  process.exit(0);
}

const output = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext:
      "After finalizing this plan, run `codex-companion plan-review " +
      filePath +
      "` to get Codex feedback, address any comments, then exit plan mode."
  }
};

process.stdout.write(JSON.stringify(output) + "\n");
