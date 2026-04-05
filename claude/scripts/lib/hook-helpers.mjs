// Shared utilities for PreToolUse enforcement hooks.

import { execSync } from "node:child_process";

export function deny(reason) {
  const output = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason
    }
  };
  process.stdout.write(JSON.stringify(output) + "\n");
}

/**
 * Fetch all Codex jobs for the current session.
 * Returns a flat array of jobs, or null if codex-companion is unavailable (fail open).
 */
export function fetchSessionJobs() {
  let statusData;
  try {
    const raw = execSync("codex-companion status --all --json", {
      encoding: "utf8",
      timeout: 10000
    });
    statusData = JSON.parse(raw);
  } catch {
    return null;
  }

  return [
    ...(statusData.running ?? []),
    ...(statusData.recent ?? []),
    ...(statusData.latestFinished ? [statusData.latestFinished] : [])
  ];
}
