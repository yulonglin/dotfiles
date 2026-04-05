#!/usr/bin/env node
// PreToolUse enforcement: block ExitPlanMode until a plan-review has completed in this session.
// Hook config: matcher "ExitPlanMode", wrapped by run-with-session-env.sh

import fs from "node:fs";
import { deny, fetchSessionJobs } from "./lib/hook-helpers.mjs";

const input = JSON.parse(fs.readFileSync(0, "utf8"));

const allJobs = fetchSessionJobs();
if (!allJobs) {
  // codex-companion unavailable — fail open
  process.exit(0);
}

// Check if a plan-review is currently running
const runningPlanReview = allJobs.find(
  (job) =>
    job.kind === "plan-review" &&
    (job.status === "queued" || job.status === "running")
);

if (runningPlanReview) {
  deny(
    "A Codex plan review is still running. Wait for it to finish, address any feedback, then try ExitPlanMode again."
  );
  process.exit(0);
}

// Check if a plan-review has completed
const completedPlanReview = allJobs.find(
  (job) => job.kind === "plan-review" && job.status === "completed"
);

if (!completedPlanReview) {
  deny(
    "No Codex plan review has been completed in this session. " +
      "Run `codex-companion plan-review <plan-file>` to get feedback on the plan, " +
      "address any comments, then try ExitPlanMode again."
  );
  process.exit(0);
}

// Plan review completed — allow
process.exit(0);
