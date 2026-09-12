# Terminal, Shell & Dev Tools Reference

Operational detail for the terminal/shell/dev-tool components, moved out of the README. Deploy mechanics live in [`deploy-components.md`](./deploy-components.md); this file holds the usage detail documented nowhere else.

## Ghostty Theme Aliases

Default Ghostty config uses Catppuccin Mocha. The `g0`–`g9` aliases launch a **single fresh window** (no tab restoration) with a different theme — useful for visually distinguishing contexts:

| Alias | Theme                          | Character                        |
| ----- | ------------------------------ | -------------------------------- |
| `g0`  | TokyoNight                     | Deep blue bg — neon city         |
| `g1`  | Dracula                        | Purple-grey bg — vibrant classic |
| `g2`  | Nord                           | Arctic blue-grey bg — calm       |
| `g3`  | Rose Pine                      | Deep purple bg — botanical       |
| `g4`  | Kanagawa Dragon                | Warm near-black bg — Japanese ink |
| `g5`  | Gruvbox Dark                   | Neutral warm bg — retro          |
| `g6`  | Everforest Dark Hard           | Green-grey bg — forest           |
| `g7`  | Solarized Dark Higher Contrast | Dark teal bg — high contrast     |
| `g8`  | Melange Dark                   | Warm brown bg — earthy           |
| `g9`  | Material Ocean                 | Near-black bg — minimal          |

```bash
g1                        # Launch Ghostty with Dracula theme
gtheme "Tomorrow Night"   # Launch with any theme by name
ghostty +list-themes      # See all available themes
```

## SSH Color Switching

Terminal colors automatically change when SSH-ing to help identify which machine you're on; colors revert when the session ends.

```bash
ssh myserver     # In Ghostty: colors change automatically
sshc myserver    # Explicit color-changing SSH (works in any terminal)
```

Configure per-host colors by editing `SSH_HOST_COLORS` in `config/ssh_themes.sh`:

```bash
# Format: "background:foreground:cursor" in hex
SSH_HOST_COLORS[prod*]="#3d0000:#ffffff:#ff6666"      # Red-tinted for production
SSH_HOST_COLORS[dev*]="#002200:#ffffff:#66ff66"       # Green-tinted for dev
SSH_HOST_COLORS[gpu*]="#1a0033:#ffffff:#cc66ff"       # Purple for GPU servers
SSH_HOST_COLORS[default]="#0d1926:#c5d4dd:#88c0d0"    # Blue-gray fallback
```

Patterns support wildcards (`prod*` matches `prod1`, `prod-web`, etc.); the `default` key applies to any host without a specific match.

## Powerlevel10k Prompt

[Powerlevel10k](https://github.com/romkatv/powerlevel10k) provides a fast ZSH prompt with custom segments for SSH-aware machine identification.

**Requirements**: a [Nerd Font](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k) for icons.

**Reconfigure**: run `p10k configure` (when prompted, overwrite `p10k.zsh` but don't apply to `.zshrc`).

| Segment         | Description                                              |
| --------------- | -------------------------------------------------------- |
| **Remote host** | Machine name + emoji (SSH sessions only)                 |
| **Directory**   | Current path with git root highlighting                  |
| **Git status**  | Branch, dirty indicator, stash count                     |
| **Right side**  | Exit code, command duration, Python venv, cloud contexts |

### SSH-Aware Machine Identification

When SSH'd to a remote machine, the prompt shows a consistent machine name derived from your SSH config — `🌊 mats ~/code/project (main)` instead of `user@ip-172-31-42-17` — with a unique emoji hashed from the name.

How it works: (1) looks up your public IP against `~/.ssh/config` `HostName` entries; (2) uses the matching `Host` alias as the display name; (3) falls back to abbreviated hostname if no match; (4) hashes the name to assign a stable emoji from a curated palette.

Customization: `SERVER_NAME` env var overrides everything; `MACHINE_EMOJI` overrides the auto-assigned emoji.

## Statusline separates session and provider usage

Configured in `claude/settings.json` (`statusLine.command = "claude-tools statusline"`), with the renderer in [`tools/claude-tools/src/statusline.rs`](../tools/claude-tools/src/statusline.rs).

- The first line shows the machine (SSH only), active context profiles, directory, and Git branch.
- The session line shows the model, effort, context usage, duration, and classifier state when available.
- The Claude usage line shows subscription quota gauges and reset pacing, including model-specific limits when reported.
- The Codex usage line shows Codex subscription quotas for the signed-in ChatGPT account. These are Codex limits, not ChatGPT conversation counts or OpenAI API spend. Window labels come from the reported durations; the primary window is not assumed to be five hours. Only the aggregate Codex quota is rendered: per-model allowances that Codex reports beside it (Spark) are separate limits and are not shown.

Context usage is color-coded. Quota gauges show the percentage **used**, not remaining; their pace indicator compares usage with elapsed time in the quota window.

Codex usage comes from the installed CLI's read-only `account/rateLimits/read` app-server method, implemented in [`codex_usage.rs`](../tools/claude-tools/src/codex_usage.rs). Successful snapshots are cached for five minutes; failed refreshes back off for one minute and keep old data visibly marked as stale. The collector honors `CODEX_HOME` (default `~/.codex`) and invalidates the cache when login-file metadata changes. It requires an `auth.json` file: keyring-only logins are not detected, and no Codex line is shown when that file is absent. API-key authentication does not expose ChatGPT subscription quotas; it shows `Codex usage unavailable` with the same one-minute retry backoff.

`ccusage statusline` is deliberately not wired into the live Claude hook path because it can OOM on large local histories; guard logic still uses lightweight `ccusage blocks --active --json` where available.

### Model usage is reported from existing records

[`claude-usage-audit --model-usage [--days N] [--json]`](../custom_bins/claude-usage-audit) reports, as separate sections, deduplicated token usage from local transcripts, the custom hook's direct API usage from the rotating approval-classifier `USAGE:` log lines, retained native auto-mode classifier failures, and quota snapshots sampled from the existing statusline cache when the command runs. The JSON schema retains the legacy `requests` key, where each count is one persisted response. `--project` is a case-insensitive substring match on the project *directory name* under `~/.claude/projects` (so `--project dotfiles` also selects every `-claude-worktrees-` directory of that repo); it filters transcript usage and native failures, while custom approval-hook and quota data remain host-wide. `--days N` is a rolling window of N×24 h ending now (one epoch cutoff shared by every section, not a calendar-day boundary); only the rendered day and hour buckets are UTC. A transcript that fails mid-read keeps its readable prefix in the token section and is counted only in the native section's `coverage.unreadable_files`; the token coverage has no counter of its own. The approval section's **token counts** cover direct API calls only: a CLI subscription fallback call writes no `USAGE:` line, so its tokens are unobserved. Its backend outcomes are reported separately, below. The report carries no transcript content, commands or prompts. It does carry attribution — session ids, working directories, branches, CLI versions, the conversation model and, for the custom hook, the signed-in account — because on 2026-09-09 the boundary was moved so a failure can be sliced by where and on what it happened; the log and the report are local files, never committed. Non-persisted calls are absent, and token counts are not subscription quota.

### The same command counts approval-classifier backend failures

The same `--model-usage` run reports how often the custom PermissionRequest hook's backends failed, under `approval_classifier_failures`. Backend failures and failed actions are counted separately, because one action can lose both backends and a successful subscription fallback can follow a failed API call: `backend_failures` counts backend outcomes, `actions` counts **failure-path attempts only** — a successful API classification writes no event, and a retry in a new hook process counts as a separate attempt — as `recovered`, `unresolved`, or `incomplete`, which means no fallback outcome was retained at scan time (rotation, a call still in flight, or a failed log write all look the same, so it is never read as a dead process). Failures are bucketed into a closed category set — `rate_limit`, `auth`, `credits`, `usage_limit`, `overloaded`, `timeout`, `network`, `other`.

The approval log carries two record formats, and they never overlap. A line written before this change starts with the human sentence (`API BACKEND FAILED: …`) and carries no action id, so its failures are counted under `legacy_unattributed` and are never attributed to an action. A line written after starts with `BACKEND-EVENT` and one versioned JSON object, followed by that same human sentence. A `v: 1` payload (2026-09-08) carries backend, outcome, failure category, tool name, an opaque per-process action id, a hashed session id, and the permission mode when the harness sent one (`permission_mode_observed` says whether it did). A `v: 2` payload (2026-09-09) replaces the hash with the session id in the clear and adds the backend's own model (`model`: the API path's Sonnet 5 or the CLI fallback's alias, never the conversation model) plus where the attempt ran — `host`, `cwd`, `repo` (git toplevel basename), `remote`, `commit` (12-char HEAD), `branch`, `cli_version` and `session_model` (both from the transcript's newest rows), and `account` (the email `show_auth_account.sh` caches at session start in `~/.cache/claude/auth-account.json`; absent until that hook has run). Every one of these is read from a file already on disk — `.git/HEAD` and one ref, the transcript tail, the cache — never from a subprocess, since this runs inside the 30 s hook budget; a field that cannot be read is `null`, never guessed. The audit reads both versions the same way and slices structured failures `by_model`, `by_host`, `by_repo`, `by_commit`, `by_cli_version`, `by_session_model` and `by_account` (a v1 line reads as `unknown`), and lists each failure under `records`. The **JSON payload** still records no command, tool input, prompt or provider error text; the **human sentence after it** is the same one the log has always carried, so for an API failure it may still hold a provider diagnostic — that is unchanged pre-existing behaviour, and nothing in the counts reads it. One backend outcome is one line and nothing is de-duplicated: when both backends fail, the hook prints the loud combined `WARNING:` for the user but no longer logs it, because both headlines are already on the two structured lines. A `subscription fallback also failed` warning in the log was therefore written by an older hook and is counted as a legacy subscription failure whenever it appears, with no dependence on the surrounding lines. Damaged, truncated and future-version lines are counted in `coverage` rather than aborting the scan, and the rotating 1 MB log's retained boundary is reported alongside.

**Limits of the custom-hook section.** It covers the custom hook only. The built-in auto-mode classifier writes nothing to this log; its recognized retained transcript failures are counted in the separate native section below, not inferred from custom-hook outcomes. Reporting is passive: it changes no permission mode, approval rule, classifier decision, retry count, backend order or deadline, and does not reduce the number of classifier calls.

### Native failures count identified retained calls

The same command adds `native_auto_mode_classifier_failures` from the shared transcript scan (the JSON key is exactly that string). It accepts only typed user-message `tool_result` errors whose string content starts at character zero with the complete recognized native-unavailability diagnostic. Ordinary quotations, assistant discussion, command inputs, embedded diagnostics, unrelated errors, safety-policy denials and unsupported content shapes do not count. The classifier model is the bounded identifier token at the start of that diagnostic, never the conversation model, and it is not always an Anthropic catalogue ID: `claude-opus-5[1m]` was observed on Claude-model sessions and `astra` on a session routed to a foreign model (both 2026-09-08). The token names whatever served the classifier call; why it varies is not verified here. The flip side: any token that completes the full template counts, model-shaped or not, so a tool that emitted this exact sentence would be counted under its own name — an exposure declared in `coverage.limits`, not guarded against. The three reasons the CLI's error reference documents map to their own categories — `rate-limited` → `rate_limit` (a 429), `overloaded` → `overloaded` (a 529), `server-error` → `server_error` (a 5xx) — and any other reason in the same format maps to `other` with its text retained under `by_reason` (capped at 200 characters). Synthetic compatibility tests for unfamiliar reasons are not evidence that those incidents occurred.

- `total` counts failed tool calls with a nonempty string `tool_use_id` and a valid in-period row timestamp. IDs are deduplicated globally across every selected file and session, in two steps: first the earliest valid timestamp is chosen for each ID over the whole selected scan, then the UTC date cutoff is applied to that one timestamp. So an ID first seen before the period never counts, even when a later mirror of it falls inside the period. Different IDs count separately even when their diagnostics match. Because the dedup is global over the selection, per-`--project` totals can add up to more than the host-wide total when one ID is mirrored across project directories.
- Each counted failure is a record carrying what the CLI stamped on the failing row — `cwd`, `cli_version` (the row's `version`), `branch` (`gitBranch`), `session_id` — plus the `tool` and `reason` from the diagnostic sentence, the classifier `model`, and `session_model`: the newest assistant `message.model` seen earlier in the same file, so it is absent when the failure precedes every assistant row. `records` lists them oldest-first; `by_category`, `by_model`, `by_reason`, `by_tool`, `by_day`, `by_hour`, `by_cwd`, `by_cli_version`, `by_branch`, `by_session_model` and `by_session_id` are counts over the same records, and `sessions` is the number of distinct session ids. Hour keys use `YYYY-MM-DDTHH:00:00Z`. Human output shows the total, categories, the model, session-model, CLI-version, tool and cwd slices, the daily line described next and the peak UTC hour; JSON retains everything.
- `exposure` is the denominator the daily count is read against. `classifier_bound_calls_by_day` counts assistant `tool_use` blocks for the tools that reach the auto-mode classifier in auto mode — Bash, PowerShell, Monitor, Agent, Task — once per tool-use id (so a transcript mirrored across project directories does not double it); `failures_per_100_bound_calls_by_day` divides the day's failures by it; `cli_versions_by_day` counts rows per CLI version so an upgrade date is visible beside a change in the rate; `by_day_and_session_model` splits each day's bound calls and failures by the conversation model, which is the slice that separates a bad day or gateway from sessions on one model failing (measured 2026-09-06 to 09-09: Fable 5.1 sessions failed on 11 to 38 of every 100 bound calls while Opus 5 and Sonnet 5 sessions on the same days failed on none). The human report prints one line per day: `failures / bound calls, rate, versions`, then one line per day of `model failures/bound calls`. It is an **upper bound on classifier calls, not a count of them**: a call an allow rule or a cached verdict resolved, or one made outside auto mode, is counted as bound but never reached the classifier, and the CLI records no classifier call of its own.
- What stays out of the native section: the text after the recognised sentence (the diagnostic's suffix is neither parsed nor exported), raw commands, prompts, transcript file paths and row UUIDs. `auto-mode-classifier-error.txt` snapshots are not counted or added to transcript totals: their overwrite semantics are unverified and their evidence may overlap.

**Limits of the native section.** These are retained failures with recognized wording, not a complete history. The report does not measure successful native classifier calls, hidden HTTP attempts, native classifier tokens, identical-command retries, or whether goals caused retries; the exposure denominator bounds classifier calls from above rather than counting them. Missing or unreadable evidence is a coverage gap, not proof of zero failures. There is no "unrecognized native-like error" counter, so a `total` of 0 cannot distinguish "no failures" from "the CLI changed its wording" — if the CLI is upgraded and the count drops to zero, check one recent error row by hand before trusting it. Repeated observations do not establish a cause or fix upstream rate limits. Parser and privacy regressions are covered in [`test_claude_usage_audit.py`](../tests/test_claude_usage_audit.py).

Quota history is stored at `~/.claude/usage-data/quota-history.jsonl` without account attribution. Samples can interleave accounts because no identity is recorded. Each row contains only the cache observation time and allowlisted quota bucket utilization/reset fields; the current-cache report states its age and whether it exceeds the statusline cache's five-minute freshness window.

## Ignore Pattern Management

`claude-tools ignore` manages per-repo `.gitignore` and `.ignore` patterns interactively.

```bash
claude-tools ignore                    # Launch TUI (same as `ignore apply`)
claude-tools ignore apply              # Interactive pattern selection
claude-tools ignore apply --dry-run    # Preview without writing
claude-tools ignore apply --non-interactive  # Apply defaults without TUI
claude-tools ignore status             # Show current managed patterns
```

The TUI shows patterns grouped by category with tri-state toggles:

- `[   ]` skip — pattern not applied
- `[ G ]` gitignore — added to `.gitignore` only
- `[G+S]` gitignore + searchable — added to `.gitignore` AND negated in `.ignore`

Patterns in `[G+S]` state are git-ignored but remain searchable by rg, fd, Claude Code, and Cursor. Pattern definitions live in `config/ignore/patterns`.

## SSH Key Management

The ZSH config automatically adds your SSH key to ssh-agent on shell startup (interactive shells only):

- Checks for `~/.ssh/id_ed25519` (customizable via `SSH_KEY_PATH`, e.g. `export SSH_KEY_PATH=~/.ssh/id_rsa`)
- **Prompts to generate** if the key doesn't exist (never overwrites existing keys)
- Adds to macOS Keychain (`--apple-use-keychain`) or Linux ssh-agent; skips if already loaded

First-time flow: shell starts → detects no key → prompts "Generate a new ed25519 SSH key now? [y/N]" → if yes, generates and shows the command to copy the public key. Configuration: `config/ssh_setup.sh`.

## htop

`./deploy.sh --htop` deploys `config/htop/htoprc`, whose dynamic layout adapts CPU meters to the machine's core count — no manual adjustment across machines.

## pdb++ (Python Debugger)

`./deploy.sh --pdb` deploys a high-contrast color scheme for [pdb++](https://github.com/pdbpp/pdbpp) to `~/.pdbrc.py` (symlinked).

**Global config works with per-project installations**: pdb++ is installed per-project via `uv add --dev pdbpp` but reads the global config at runtime.

**Auto-detects terminal background** via the OSC 11 escape sequence: light terminals get solarized-light, dark get monokai, and detection failures (SSH, older terminals) fall back to the dark theme. Detection succeeds in iTerm2, Ghostty, Kitty, Alacritty.

Test: `uv add --dev pdbpp && python -c "import pdb; pdb.set_trace()" <<< "c"` should show high-contrast colors. Per-project override: a `.pdbrc.py` in the project root takes precedence.

## macOS Media Recovery

If Spotify, FaceTime, FineTune, or other audio apps hang together, use the manual `reset-mac-media` helper. It saves a private diagnostic bundle before restarting only CoreAudio and FaceTime's supporting services; it does not quit the affected GUI apps or restart Bluetooth or WindowServer.

```bash
reset-mac-media --dry-run   # Preview the bounded action
reset-mac-media             # Capture diagnostics, restart media services, verify recovery
```

The real run requires administrator authentication and briefly interrupts all audio, video, and active calls. Reports go to `~/Library/Logs/reset-mac-media/`; a bundle can contain device metadata, local paths, and call or app context, so review it before sharing. If the helper cannot verify that the old service PIDs disappeared while their launchd jobs remain loaded, it exits nonzero and keeps the report; rebooting remains the fallback. To reduce recurrence, add FaceTime to FineTune's ignore list and use the MacBook microphone when Bluetooth call routing is unstable.

## Automation Extras

Detail missing from the per-component docs:

- **Claude Code session cleanup**: manual control via `clear-claude-code` (aliases `ccl`, `cci`, `ccf`); status with `clear-claude-code --list`; uninstall with `scripts/cleanup/setup_claude_cleanup.sh --uninstall`.
- **Gist sync**: uninstall with `scripts/cleanup/setup_gist_sync.sh --uninstall`. **Secret gists are unlisted, not encrypted** — only non-secret config (SSH config, authorized_keys, git identity) should be synced via gist.

## Codex Layout

`codex/` (symlinked to `~/.codex` by `./deploy.sh --codex`): `AGENTS.md` (global instructions, references CLAUDE.md as source of truth), `config.toml` (model settings, status line, per-project trust levels), `rules/` (synced from Claude Code's `rules/`), and `skills/` → symlink to `claude/skills/` so both CLIs share one skill set. Sync mechanics: [`cross-tool-extensibility.md`](./cross-tool-extensibility.md).

The default is **Approve for me**: `approval_policy = "on-request"`, `approvals_reviewer = "auto_review"`, and `sandbox_mode = "workspace-write"` in `codex/config.toml`. Eligible approval requests go to Codex's automatic reviewer, which can approve or reject them; the workspace sandbox stays enabled. See the [OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). The CLI also exposes this mode as `codex --approve-for-me`.

Check the live `~/.codex/config.toml` when diagnosing defaults: it may be a separate file, and deployment preserves an existing config during the directory merge.

## Shell Utility Functions & Aliases

- **`config/modern_tools.sh`**: `mkd` (mkdir+cd), `cdf` (cd to Finder window, macOS), `targz` (smart compression), `dataurl`, `digga` (DNS lookup), `getcertnames` (SSL certs), `o` (cross-platform open), `server` (quick HTTP server)
- **`config/aliases/net.sh`**: `flush` (DNS cache), `afk` (lock screen, macOS), `week` (ISO week number)
- Aliases are themed per file under `config/aliases/` (git.sh, nav.sh, net.sh, …); add your own to the matching file.
