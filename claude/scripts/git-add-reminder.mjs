#!/usr/bin/env node
// PreToolUse reminder: when staging files, remind to run a codex review before committing.
// Hook config: matcher "Bash", if "Bash(git add *)"
//
// Stays quiet if a Codex review has been run for this repo within FRESHNESS_MS,
// so re-staging during a single work session doesn't spam the reminder.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const input = JSON.parse(fs.readFileSync(0, "utf8"));

// Self-validate: exit early if this isn't actually a git add command.
const command = input.tool_input?.command ?? "";
if (!command.match(/^git\s+add\b/)) {
  process.exit(0);
}

const FRESHNESS_MS = 30 * 60 * 1000; // 30 min

function hasRecentCodexReview() {
  let repoRoot;
  try {
    repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
  } catch {
    return false;
  }
  const stateBase = path.join(
    process.env.HOME ?? "",
    ".claude/plugins/data/codex-openai-codex/state"
  );
  if (!fs.existsSync(stateBase)) return false;
  const repoName = path.basename(repoRoot);
  let dirs;
  try {
    dirs = fs.readdirSync(stateBase);
  } catch {
    return false;
  }
  const cutoff = Date.now() - FRESHNESS_MS;
  for (const d of dirs) {
    if (!d.startsWith(repoName + "-")) continue;
    const jobsDir = path.join(stateBase, d, "jobs");
    if (!fs.existsSync(jobsDir)) continue;
    let files;
    try {
      files = fs.readdirSync(jobsDir);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!f.startsWith("review-")) continue;
      try {
        const st = fs.statSync(path.join(jobsDir, f));
        if (st.mtimeMs >= cutoff) return true;
      } catch {
        // ignore
      }
    }
  }
  return false;
}

if (hasRecentCodexReview()) {
  process.exit(0);
}

const output = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext:
      "Before committing, run `codex-companion review` to get a comprehensive Codex review of the changes.",
  },
};

process.stdout.write(JSON.stringify(output) + "\n");
