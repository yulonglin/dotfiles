# Refusal Alternatives & Friction Prevention

Rules for avoiding the top friction patterns identified from 480 sessions of usage data.

## Ambiguity Resolution (Instead of Guessing Wrong)

The #1 friction source (314 events): Claude interprets ambiguous instructions confidently and acts on the wrong interpretation.

| Trigger | Instead of guessing... | Do this instead |
|---------|----------------------|-----------------|
| **Ambiguous spec** ("fix this", "clean up", "simplify") | Interpreting literally and acting immediately | **Restate your understanding** in 1-2 sentences before making changes |
| **Multiple valid interpretations** | Picking the "obvious" one | **Ask which interpretation** the user intends, or list options |
| **Codebase assumptions** (which file, which function, what format) | Assuming based on naming conventions | **Verify with Grep/Read** before acting — read the actual code |
| **Partial instructions** (user says what, not how) | Filling in blanks with defaults | **State your planned approach** briefly before executing |

**Rule:** On any task touching 3+ files or involving unfamiliar code, state your interpretation of the goal BEFORE writing any code. One sentence is enough: "I'll X by doing Y to files Z."

## Non-Destructive Editing (Instead of Overwriting)

Rare (5 sessions) but the most frustrating friction. Claude replaces user code with simplified versions or stubs.

| NEVER do this | Do this instead |
|---------------|-----------------|
| Replace implementation with `TODO` stubs or `pass` | **Add** to existing code; only remove what you're replacing with equivalent or better |
| "Simplify" by removing functionality or data | **Ask first**: "This simplification would remove X — is that OK?" |
| Use `Write` to overwrite entire file when `Edit` fails | **Pause**, re-read the file, retry `Edit` with correct `old_string` |
| Remove code/content to meet a length target | **Ask** which parts the user wants cut; never decide unilaterally |
| Rewrite working code you weren't asked to touch | **Leave it alone** — only modify what was requested |

**Rule:** Treat every line of existing user code as intentional. If you need to remove something, say what and why before doing it.

## Tool Failure Alternatives (Instead of Getting Stuck)

When a tool or sandbox blocks you, don't retry the same thing — pivot immediately.

| When this fails... | Try this alternative |
|--------------------|---------------------|
| `rm` / `rm -rf` blocked | `trash` (macOS) > `mv` to `.bak` or `archive/` |
| Writing to `/tmp` | Use `$TMPDIR` (set to `/tmp/claude/`), `/run/user/$(id -u)/` (Linux XDG runtime), or project-local `./tmp/` |
| Heredoc in git commit | `printf > $TMPDIR/commit_msg.txt && git commit -F` |
| `Edit` fails ("file modified since read") | Re-read file, retry with fresh `old_string` — **never** fall back to `Write` |
| Sub-agent fails or times out | Do the work directly in main context (don't retry same agent) |
| Codex/delegated agent fails | Fall back to doing it yourself — don't retry delegation |
| API/network timeout | Check if client-side config is the cause (e.g., `max_connections` too high) before blaming infrastructure |
| MCP tool not found | Try alternative tool names, then fall back to Bash/direct approach |
| **Auth-gated service** (Notion, Google Drive, private repos, Confluence, Jira, etc.) | **Ask user immediately** — don't try WebFetch, Playwright login pages, or unauthenticated API calls. Request: copy-paste content, export as file, or provide credentials/token to configure access |

**Rule:** After any tool failure, **immediately** try an alternative approach. Never retry the same failing command more than once.

**Rule:** When a task requires accessing an authenticated service you can't reach, **ask the user on the first attempt** — don't burn context trying multiple doomed approaches (WebFetch → Playwright → curl). Recognize auth walls instantly and escalate.

## Over-Caution Alternatives (Instead of Being Too Conservative)

When Claude defaults to cautious suggestions that don't match user intent (3 sessions, but annoying).

| Over-cautious pattern | Better alternative |
|-----------------------|-------------------|
| Suggesting `.gitignore` for files user wants committed | **Match the user's git workflow** — if they want to commit it, help them commit it |
| Advising against syncing/committing a directory | **Ask** "Are you sure?" once, then proceed if confirmed |
| Proposing project-specific settings for a global config | **Read the context** — if the file is `~/.claude/CLAUDE.md`, it's global by definition |
| Adding safety disclaimers to every destructive suggestion | State the risk **once**, then execute if user confirms |
| Refusing to act on personal repos with the same caution as shared repos | **Personal repos have different norms** — direct pushes to main, less ceremony |

**Rule:** For personal repos and dotfiles, prefer action over caution. Don't suggest defensive patterns (`.gitignore`, branching, PRs) unless the user asks. They know their repo.

## Quality Gates (Instead of Under-Delivering)

When Claude produces output that misses stated requirements (10 sessions).

| Check | Before presenting output |
|-------|------------------------|
| **Length requirements** | If user specified N pages/words, verify your output meets it |
| **Completeness** | If user asked for "all X", verify you didn't miss any |
| **Spec fidelity** | Re-read the original request and compare against your output |
| **Data accuracy** | If citing numbers, verify from source — don't estimate or hallucinate |
| **Post-cutoff claims** | If asserting facts about recent models/tools, verify with web search |

**Rule:** Before presenting substantial output (>50 lines), do a 10-second self-check: does this match what was actually asked for?
