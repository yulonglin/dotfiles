#!/bin/sh
# PostToolUse hook: Truncate long bash outputs to prevent context pollution
# Outputs JSON with suppressOutput + systemMessage for long outputs
#
# Performance: Single jq call does all extraction + truncation to avoid
# hanging on large outputs (previous version called jq 5x + used shell pipes)

# Check for jq dependency
command -v jq >/dev/null 2>&1 || exit 0

# Single jq call: extract fields, check threshold, truncate, and format output
# This avoids storing huge strings in shell variables
jq -c '
  # Only process Bash tool outputs
  if .tool_name != "Bash" then empty
  else
    .tool_response as $r |
    .tool_input.command as $cmd |
    ($r.stdout // "") as $stdout |
    ($r.stderr // "") as $stderr |
    ($r.exit_code // 0) as $exit |
    (($stdout | length) + ($stderr | length)) as $total |

    # Threshold: 5000 characters
    if $total < 5000 then empty
    else
      # Truncate stdout: first 15 + last 30 lines
      (if ($stdout | length) > 1500 then
        ($stdout | split("\n")) as $lines |
        if ($lines | length) <= 45 then $stdout
        else
          ([$lines[:15][], "", "... [\($stdout | length) chars truncated] ...", "", $lines[-30:][]] | join("\n"))
        end
      else $stdout end) as $trunc_stdout |

      # Truncate stderr: last 20 lines
      (if ($stderr | length) > 500 then
        "... [stderr truncated] ...\n\n" + (($stderr | split("\n"))[-20:] | join("\n"))
      else $stderr end) as $trunc_stderr |

      # Build summary
      "Command: \($cmd)\nExit code: \($exit)\nOutput (truncated from \($total) chars):\n\n\($trunc_stdout)" +
      (if ($trunc_stderr | length) > 0 then "\n\n--- stderr ---\n\($trunc_stderr)" else "" end)
      | {suppressOutput: true, systemMessage: .}
    end
  end
'
