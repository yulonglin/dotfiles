# Specification: Proactive AI Coach Agent — "nudge" (v3)

## Context

**Created**: 2026-02-17 | **Revised**: 2026-02-18 (post-interview + 3-critic review)
**Status**: Ready for implementation

Yulong wants an always-on AI agent that proactively messages him via Telegram for accountability: sleep timing, waking up, replying to people, task follow-through, and weekly reflection. The core problem isn't lack of awareness — it's lack of timely nudges with judgment at the decision point.

This spec supersedes v2, incorporating design interview decisions and fixes from three independent reviews (Codex plan-critic, Claude architecture review, Gemini security/ops audit).

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Project home | Separate repo (`~/code/nudge`) | Independent lifecycle from dotfiles |
| Platform | Audit Nanobot first → DIY fallback | 4k LOC audit is tractable; DIY is ~200-500 lines |
| Messaging | **Single Telegram bot** | Two-bot design breaks on `getUpdates` semantics (consuming queue, not chat history). `/ping` command on main bot is simpler and eliminates token management complexity. (3 critics agreed) |
| Activity signal | `/ping` command on main bot + iOS Shortcut | Bot silently logs activity pings, excludes from conversation context |
| Memory model | **Markdown files (human-edited) + SQLite (runtime state)** | SQLite gives atomic writes, crash recovery, and concurrent read for free. Markdown stays human-readable for GOALS.md and MEMORY.md. (3 critics agreed on file corruption risk) |
| Goals editing | Git + Telegram | Agent writes, user can also `git push` (sync on explicit `/sync` command) |
| Google Calendar/Email | Skip in v1 | Simplify. Add after core loop proves useful |
| Judgment model | Full judgment heartbeat (every 45min) | Agent should surprise with observations, not just execute cron |
| LLM provider | Direct Anthropic API | Haiku heartbeats, Sonnet conversations |
| Schedule targets | Flexible — stored in GOALS.md, re-parsed on every write | Agent reads targets, not hardcoded. Changes take effect immediately. |
| Weekly review | Saturday morning | Per Neel Nanda's recommendation, more relaxed |
| Message cap | No hard cap, trust agent personality | Personality prompt handles restraint |
| Feedback loop | Conversation + direct file edits | Quick corrections via chat, structural via git |
| Testing | Local dev → VPS prod | Standard dev workflow |
| Phasing | Phased rollout over 3 weeks | De-risk incrementally |

---

## Architecture

### System Overview

```
┌──────────────────────────────────────────────────────┐
│  VPS (always-on, single Python process + asyncio)    │
│                                                      │
│  ┌──────────────┐   ┌─────────────────────────────┐  │
│  │ APScheduler  │──▶│ Heartbeat Engine             │  │
│  │              │   │ - Read GOALS.md, MEMORY.md   │  │
│  │ Heartbeat:   │   │ - Query SQLite (reminders,   │  │
│  │  every 45min │   │   state, recent context)     │  │
│  │              │   │ - LLM decides: msg or ∅      │  │
│  │ Cron jobs:   │   └──────────┬──────────────────┘  │
│  │  morning,    │              │                      │
│  │  bedtime,    │              ▼                      │
│  │  weekly,     │   ┌─────────────────────────────┐  │
│  │  monthly     │   │ Telegram Bot (single)        │  │
│  └──────────────┘   │ - Long polling (asyncio)     │  │
│                     │ - Send/receive messages      │  │
│                     │ - /ping (activity signal)    │  │
│                     │ - /status, /sync, /redact    │  │
│                     └──────────┬──────────────────┘  │
│                                │                      │
│  ┌─────────────────────────────┴──────────────────┐  │
│  │ Data Layer                                     │  │
│  │                                                │  │
│  │ Markdown (human-edited, git-tracked):          │  │
│  │   GOALS.md · MEMORY.md · AGENTS.md ·           │  │
│  │   HEARTBEAT.md                                 │  │
│  │                                                │  │
│  │ SQLite (runtime, crash-safe, not git-tracked): │  │
│  │   nudge.db — tables: state, reminders,         │  │
│  │   conversations, activity_pings                │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  iOS Shortcut ──▶ /ping to bot (phone activity)      │
└──────────────────────────────────────────────────────┘
```

### Single-Process Architecture (Critical)

All components run in **one Python process** using `asyncio`:
- Telegram long-polling loop
- APScheduler (async) for heartbeat + cron
- All state mutations go through a single event loop → no concurrent writes, no file locking needed
- SQLite in WAL mode for the rare case of read during write

This eliminates the concurrent write corruption risk flagged by all three critics.

### Data Layer

**Markdown files** (human-readable, git-tracked):

| File | Purpose | Read | Write |
|------|---------|------|-------|
| `GOALS.md` | Goal hierarchy, schedule targets, people list | Every heartbeat | Via Telegram or git push |
| `MEMORY.md` | Preferences, commitments, patterns, **recent context summary** | Every heartbeat | After conversations |
| `AGENTS.md` | Personality config, system prompt | On startup + hot-reload | Rarely (via git) |
| `HEARTBEAT.md` | Heartbeat evaluation checklist | Every heartbeat | Rarely (via git) |

**SQLite database** (`nudge.db`, runtime, `.gitignore`d):

| Table | Purpose |
|-------|---------|
| `state` | Single row: last_heartbeat, last_user_message, last_activity_ping, today_proactive_count, flags (bedtime_nudge_sent, morning_brief_sent, weekly_review_in_progress, quiet_mode_until). Day key derived from user timezone for daily flag resets. |
| `reminders` | id, text, created_at, due_at, status, nudge_count, last_nudged |
| `conversations` | id, timestamp, role (user/assistant/system), content, message_type (conversation/ping/cron/heartbeat). Rotation: auto-archive entries >30 days. |
| `activity_pings` | id, timestamp. Rotation: keep last 7 days. |

### GOALS.md Structure

```markdown
# Goals — Last updated: [date]

## North Star (revisit quarterly)
- [1 sentence]

## This Quarter (revisit monthly)
1. [Process-oriented goal]
2. [Process-oriented goal]
3. [Process-oriented goal, max]

## This Week (revisit at weekly review)
1. [Specific, completable]
2. [Specific, completable]
3. [Specific, completable, max]

## Today (revisit at morning briefing)
1. [Single most important task]
2. [Second task if time]
3. [Third task, nice-to-have]

## Standing Commitments
- Sleep: In bed by 1am, awake by 10am
- Replies: Check and respond to important messages daily
- Friends: Reach out to at least 1 person per week

## Schedule Targets
- bedtime_target: "01:00"
- wake_target: "10:00"
- quiet_hours: "02:00-10:00"
- weekly_review: "Saturday 10:00"
- timezone: "America/Toronto"

## People to Stay in Touch With
- [Name] — [context, e.g., "MATS mentor, check in monthly"]
```

**Parser requirements**: Strict parser with fallback defaults for every field. If `## Schedule Targets` is missing or malformed, use last-known-good config and notify user via Telegram. Never crash on parse failure.

**Schedule reload**: Re-parse GOALS.md on every write (via Telegram or git pull). Reschedule APScheduler jobs if targets changed. Validate before applying.

### Memory Design

**MEMORY.md** (structured, ~50-200 lines):
```markdown
# Memory — Last updated: [date]

## Preferences
- Prefers casual tone, not preachy
- Don't ask "how are you feeling" — ask "what's the plan"
- [Corrections from conversations accumulate here]

## Active Commitments
- Reply to Mary about MATS paper (set 2026-02-18, due: Friday)
- Submit workshop application (due: March 1)

## Observed Patterns
- Tends to stay up past 1am when working on papers
- Most productive in evening hours (8pm-midnight)
- Usually responsive on Telegram within 30 min during waking hours

## Recent Context
[Rolling 3-5 sentence summary updated after each conversation exchange.
This is how the heartbeat "remembers" what happened in recent conversations
without loading full conversation history. Updated by conversation handler.]

## Conference Mode
- [empty until first conference]
```

**MEMORY.md pruning**: During weekly review, agent summarizes and rewrites MEMORY.md to resolve contradictions (e.g., "don't message about sleep" from week 1 vs "you can message about sleep after midnight" from week 3). Keeps file under 200 lines.

**Feedback loop mechanism**: When user says something like "don't message me about X", the LLM outputs a structured update:
```json
{"action": "update_memory", "section": "Preferences", "add": "Don't message about X"}
```
Agent confirms: "Got it, I've noted that in my memory. I won't [X] again."

---

## Heartbeat Engine (Full Judgment)

Every 45 minutes, the scheduler triggers the heartbeat:

1. Load context: GOALS.md, MEMORY.md (including Recent Context section)
2. Query SQLite: due reminders, state flags, last activity ping time
3. **Suppress check**: If `last_user_message` < 5 minutes ago, skip (avoid interrupting active conversations)
4. Build prompt with current time, context, and HEARTBEAT.md checklist
5. Call Haiku with the prompt
6. Parse LLM output (structured JSON response):
   - `HEARTBEAT_OK` → log and exit
   - Message to send → send via Telegram, log to conversations table, update state
   - State update → apply to SQLite
7. Log heartbeat decision to `heartbeat.log` for debugging

### Heartbeat Prompt Template

```
Current time: {time} ({timezone})
Last user message: {last_user_message} ({time_ago})
Last activity ping: {last_activity_ping} ({time_ago})
Today's proactive messages sent: {count}
Bedtime nudge sent today: {yes/no}
Morning brief sent today: {yes/no}
Weekly review in progress: {yes/no}
Quiet mode until: {time or "not set"}

--- GOALS.md ---
{goals_content}

--- MEMORY.md ---
{memory_content}

--- Due reminders ---
{due_reminders_from_sqlite}

--- HEARTBEAT.md (evaluation checklist) ---
{heartbeat_checklist}

Based on all context above, decide:
1. Should you send a message right now? If yes, write it.
2. Should you update any state? If yes, specify what.
3. If no action needed, output exactly: HEARTBEAT_OK

Respond in this JSON format:
{"action": "message"|"heartbeat_ok"|"state_update", "message": "...", "state_updates": {...}}
```

### Token Budget (Resolved)

| Component | Budget |
|-----------|--------|
| System prompt (AGENTS.md) | ~500 tokens |
| GOALS.md | ~400 tokens |
| MEMORY.md | ~500 tokens |
| Due reminders | ~200 tokens |
| HEARTBEAT.md checklist | ~400 tokens |
| State/time header | ~100 tokens |
| **Heartbeat total input** | **~2,100 tokens** |
| Conversation (Sonnet): system + GOALS + MEMORY + last N turns (up to 2K) + current msg | **~4,500 tokens input** |

Truncation strategy: oldest conversation turns first. Hard cap: 4K input for Haiku heartbeats, 8K for Sonnet conversations.

---

## Cron Jobs

Run at fixed times, always trigger an LLM call:

| Job | Schedule | Action |
|-----|----------|--------|
| Morning briefing | At `wake_target` (default 10:00 local) | Read GOALS.md, compose morning message with today's priorities |
| Bedtime first nudge | At `bedtime_target - 1h` (default 00:00 local) | Casual bedtime mention if user active recently |
| Weekly review | Saturday at configured time (default 10:00 local) | Walk through review questions conversationally |
| Monthly goal check | 1st of month, 19:00 local | Prompt quarterly goal revisit |

All schedules derived from GOALS.md `## Schedule Targets`. Re-parsed and rescheduled on every GOALS.md update.

**Timezone handling**: Use `zoneinfo` (Python 3.9+). Store `timezone` in GOALS.md. All internal timestamps in UTC. Convert to local for display and schedule matching. Day boundary for daily flag resets = midnight in user's timezone. DST transitions handled automatically by `zoneinfo`.

---

## Weekly Review (Saturday Morning)

Delivered conversationally. Agent asks one question, waits, asks the next.

**State machine**:
- `weekly_review_in_progress: true` set when review starts
- Track `current_question_index` in state
- If user stops responding mid-review: pause. Next message from user (even next day) resumes from where they left off, or agent asks "Want to finish the review or skip it this week?"
- If user sends unrelated message mid-review: respond to it, then ask "Want to continue the review?"
- Timeout: if no response in 24h, mark review as incomplete, store partial summary

**Questions**: (same as v2.1 — 4 blocks, 9 questions)

**After review**: Agent updates GOALS.md "This Week" section, stores summary in MEMORY.md, prunes MEMORY.md for contradictions.

---

## Coach Personality (AGENTS.md)

Carried forward from original spec:
- Warm but direct, no lectures
- Experiments, not rules ("How did the early bedtime go?" not "Did you follow the plan?")
- Flexible restraint: missing a day isn't failure
- Max 3-message bedtime escalation (casual → direct → serious)
- No messages during quiet hours (derived from GOALS.md)
- If user says "busy"/"focusing": suppress heartbeat for 2 hours
- If user says "leave me alone": suppress until user's next **conversational** message (not `/ping`)
- Respect explicit delays ("30 more min" → check back in 30)
- **Conversation suppression**: Don't send proactive messages while user is in active conversation (last message < 5 min ago)

---

## Activity Signal (Single Bot)

iOS Shortcut sends `/ping` to the main Telegram bot. Bot handles it silently:
- Log timestamp to `activity_pings` table in SQLite
- Do NOT include in conversation context
- Do NOT send a response
- User ID whitelist enforced (same `allowFrom` as all other messages)

**iOS Shortcut setup**:
- Trigger: Automation → When phone is unlocked
- Action: Send Telegram message "/ping" to bot
- Note: iOS may throttle or revoke automation permissions after OS updates

**Degraded signal handling**: If no `/ping` in 24h, agent asks once: "Haven't seen your phone activity in a while — is the Shortcut still running?" Then falls back to time-of-day heuristics only. Don't make strong inferences from absence of signal.

---

## Bot Commands

| Command | Action |
|---------|--------|
| `/ping` | Silent activity signal (no response) |
| `/status` | Returns: last 5 heartbeat decisions, current state summary, active reminders |
| `/sync` | Git pull to refresh GOALS.md/MEMORY.md from repo |
| `/redact [n]` | Delete last n messages from conversation history and memory |
| `/goals` | Show current GOALS.md content |
| `/remind [text] by [date]` | Add a reminder |
| `/quiet [duration]` | Suppress proactive messages for duration |

---

## Error Handling & Reliability

### Retry Strategy

| Error | Response |
|-------|----------|
| Anthropic API 5xx | Exponential backoff: 5s → 15s → 45s → give up, log, try next heartbeat |
| Anthropic API 429 | Respect `Retry-After` header, backoff |
| Telegram 429 (rate limit) | Backoff, queue messages |
| Telegram 409 (conflict) | Another poller running — crash with clear error message |
| Network timeout | Retry once after 10s, then skip heartbeat |
| Parse failure (GOALS.md) | Use last-known-good config, notify user via Telegram |
| SQLite error | Log, skip operation, alert user. Never corrupt DB (WAL mode + single writer) |

### Dead Man's Switch

Register with [Healthchecks.io](https://healthchecks.io) (free tier). Agent pings the healthcheck URL after every successful heartbeat. If no ping in 2× heartbeat interval (90 min), Healthchecks.io sends an alert email.

Startup healthcheck: verify all required paths are writable, SQLite opens, Telegram API responds, Anthropic API key is valid.

### Guarded Runner

Every scheduled job and the polling loop wrapped in:
```python
async def guarded_run(func, name):
    try:
        await func()
    except RetryableError as e:
        logger.warning(f"{name} failed (retryable): {e}")
        await backoff_retry(func, max_retries=3)
    except Exception as e:
        logger.error(f"{name} failed: {e}", exc_info=True)
        await notify_user(f"⚠️ {name} failed: {e}. Check logs.")
```

---

## Git Sync (Simplified)

**Problem identified by critics**: Automatic git push/pull with dirty working tree causes merge conflicts that block all writes.

**Solution**: Git sync is **explicit only**.

- **On startup**: `git pull --rebase` (if clean working tree)
- **On `/sync` command**: `git stash && git pull --rebase && git stash pop`. If conflict, notify user and abort.
- **Periodic auto-commit** (hourly): commit GOALS.md and MEMORY.md changes. Push only on explicit command.
- **Runtime files** (`nudge.db`) are `.gitignore`d — never synced.
- **Config files** (`AGENTS.md`, `HEARTBEAT.md`) are read-only at runtime — sync is safe.

---

## Security

- **No exposed ports**: Telegram long polling (outbound only)
- **Single-user**: `allowFrom` chat ID whitelist (enforced on ALL messages including `/ping`)
- **API keys**: `.env` file, `chmod 600`, loaded at startup, never logged
- **No web UI**: No dashboard, no WebSocket endpoints
- **Container isolation**: Docker with read-only rootfs + named volume for `/data`
- **No email/calendar credentials in v1**

### Docker Volume Layout

```yaml
services:
  nudge:
    image: nudge:latest
    read_only: true
    volumes:
      - nudge-data:/data          # GOALS.md, MEMORY.md, nudge.db, logs
      - nudge-config:/config:ro   # AGENTS.md, HEARTBEAT.md, .env
    tmpfs:
      - /tmp
    restart: unless-stopped
```

### Security Audits (Two-Pass)

**Pre-deployment (Phase 0):**
- Full source audit of any third-party framework (Nanobot or otherwise)
- `pip-audit` on all dependencies
- Verify no telemetry, no phone-home, no obfuscated code
- Check credential storage patterns (tokens in memory only, not logged)
- Verify Telegram `allowFrom` enforcement at code level

**Post-deployment (Phase 4):**
- Review SQLite conversation table for credential leakage
- VPS log audit for unexpected connections
- Dependency CVE re-check (`pip-audit`)
- Telegram API access verification
- Verify Docker container hasn't been modified
- Test `allowFrom` enforcement with a different Telegram account

### Privacy

- Conversation auto-archive: entries >30 days moved to archive table
- `/redact [n]` command deletes last n messages from DB and memory
- Activity pings auto-expire after 7 days
- Agent never logs full `.env` contents or API keys

---

## Phased Rollout

### Phase 0: Setup (1-2 days)

Run Nanobot audit **in parallel** with repo scaffolding (don't let audit block everything):

- [ ] **Security audit: Nanobot** (if considering it)
  - Read all 4k lines of source code
  - Check: dependency tree (`pip-audit`), network calls, credential handling, telemetry
  - Verdict: use Nanobot, modify it, or go DIY
- [ ] **In parallel**: Scaffold `~/code/nudge` repo
- [ ] Create Telegram bot via @BotFather (single bot)
- [ ] Set up VPS: Docker, Python 3.10+, systemd service
- [ ] Write initial GOALS.md with current priorities
- [ ] Configure `.env` with Telegram token + Anthropic API key
- [ ] Set up iOS Shortcut for `/ping`
- [ ] Register Dead Man's Switch (Healthchecks.io)

### Phase 1: Minimum Viable Coach (Week 1)

- [ ] Deploy with: morning briefing cron + bedtime nudge cron
- [ ] AGENTS.md with personality config
- [ ] GOALS.md with current week's priorities + Schedule Targets
- [ ] SQLite setup (state table + conversations table)
- [ ] Basic conversation handler (user → LLM responds with context)
- [ ] State tracking from day one (prevent duplicate messages on restart)
- [ ] Error handling + Dead Man's Switch active
- [ ] `/status` command working
- [ ] NO heartbeat, NO reminders, NO weekly review
- **Measure**: Did I go to bed earlier? Did morning messages help? Annoying or useful?
- **Resilience test**: Kill process mid-operation, verify state recovery. Simulate API timeout, verify retry.

### Phase 2: Add Intelligence (Week 2)

- [ ] Enable full-judgment heartbeat (45min interval)
- [ ] `/ping` activity signal processing
- [ ] Reminders table + `/remind` command
- [ ] MEMORY.md with Recent Context section (rolling summary)
- [ ] Conversation suppression (don't heartbeat during active chats)
- [ ] Context window management (token budgets enforced)
- [ ] `/redact` and `/quiet` commands
- **Measure**: Did proactive nudges lead to action? Right frequency? Any bad judgment calls?
- **Resilience test**: Corrupt `nudge.db`, verify recovery. Remove `## Schedule Targets` from GOALS.md, verify graceful degradation.

### Phase 3: Weekly Review + Polish (Week 3)

- [ ] Weekly review state machine (Saturday morning)
- [ ] Monthly goal check cron
- [ ] Feedback loop: conversation corrections → MEMORY.md Preferences
- [ ] GOALS.md updates via Telegram conversation
- [ ] MEMORY.md pruning during weekly review
- [ ] `/sync` command for git pull
- **Measure**: Was review useful? Which questions produced insight?

### Phase 4: Evaluate (End of Week 3)

- Is this actually changing behavior?
- Which features are useful vs noise?
- Adjust, remove, or add based on 3 weeks of data
- Decide: continue, modify, or abandon
- **Post-deployment security audit** (see Security section)

---

## Cost Estimate (Corrected)

| Component | Monthly cost |
|-----------|-------------|
| Heartbeats (Haiku, 32/day, ~2.1K tokens in) | ~$1.50 |
| Conversations (Sonnet, ~10 msgs/day, ~4.5K tokens in each) | ~$5.40 |
| Cron jobs (Sonnet, ~4/day) | ~$1.50 |
| VPS (already provisioned) | $0 incremental |
| Telegram Bot API | Free |
| Healthchecks.io | Free tier |
| **Total** | **~$8-10/month** |

(Corrected from v2.1's $4.50 estimate. Conversation costs were underestimated — each turn needs ~4.5K input tokens including context history.)

---

## Open Questions (to resolve during implementation)

- [ ] Nanobot vs DIY: depends on Phase 0 audit
- [ ] Initial GOALS.md content: Yulong populates during Phase 0
- [ ] "People to Stay in Touch With" list: populate during Phase 0
- [ ] Exact Saturday morning time for weekly review (suggest 10am)
- [ ] Heartbeat frequency tuning: start at 45min, adjust based on Phase 2 feedback

---

## Out of Scope

- Google Calendar / Gmail integration (v2)
- Shell command execution
- Browser automation
- WhatsApp / Signal integration
- Time tracking / screen time monitoring
- Task management app integration
- Voice messages
- Multi-user support
- Web dashboard

---

## Critic Review Summary

Three independent reviews were conducted. All critical findings have been addressed in v3:

| Finding | Source(s) | Resolution |
|---------|-----------|------------|
| `getUpdates` breaks two-bot design | Codex (C1), Claude | → Single bot with `/ping` command |
| Concurrent file writers corrupt state | All three | → Single-process asyncio + SQLite |
| Docker `--read-only` vs writable files | Codex (C3) | → Named volume layout defined |
| Git sync undefined → merge conflicts | Codex (C4) | → Explicit `/sync` only, runtime files not git-tracked |
| No error handling → silent death | Codex (C5), Gemini | → Guarded runner + Dead Man's Switch |
| Heartbeat missing conversation context | Claude (#1) | → Rolling summary in MEMORY.md `## Recent Context` |
| Cost estimate off by ~2x | Claude | → Corrected to $8-10/month |
| state.json needed in Phase 1 | Claude | → SQLite state table from Phase 1 |
| Heartbeat interrupts active conversations | Codex (I3) | → 5-min conversation suppression |
| Config parse failure crashes bot | Codex (I4) | → Strict parser with fallback defaults |
| conversations.jsonl grows unbounded | Codex (I5), Gemini | → SQLite with 30-day rotation |
| Context window unresolved | Codex (I6) | → Token budgets defined |
| Signal bot has no allowFrom | Codex (I7) | → Single bot, whitelist on all messages |
| iOS Shortcut can silently stop | Codex (I8) | → Degraded signal handling with user notification |
| Verification only tests happy paths | Codex (I9) | → Resilience tests added per phase |
| Weekly review state machine undefined | Claude | → State machine with pause/resume/timeout |
| MEMORY.md pruning needed | Claude | → Weekly review triggers compaction |
| Timezone/DST | Codex (I2) | → `zoneinfo`, UTC internal, local for display |
| Schedule changes need restart | Codex (I1) | → Re-parse + reschedule on every GOALS.md write |
| No monitoring for silent failure | Gemini | → Healthchecks.io Dead Man's Switch |
| No /redact or /status | Gemini | → Bot commands added |
| Atomic file writes needed | Gemini | → SQLite handles this (WAL mode) |
