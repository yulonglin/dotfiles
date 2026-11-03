# Context Review, November 2026

**Most of the 49 "unused" items are not removable, so this review proposes 5 trims and drops and 5 questions.** The largest saving on offer is the Effortful Learning output style (about 1,271 tokens in every session); the largest safe cut is the hookify plugin (about 214 tokens). Everything else is either already free (user-invoked only), routed to by a rule, run on the Mac, or part of a plugin that cannot be split.

From `context-review run` on 3 Nov 2026 (report: `/home/yulong/.local/state/context-review/2026-11-03/report.md`). Proposals by Claude Opus 5.5. Set each item to keep, trim or drop, or comment; nothing changes until you do.

## Read the usage numbers with two blind spots

- **This server only.** Usage comes from this machine's transcripts, and activity here fell from about 385k transcript lines in August to about 69k in October. A skill you use on the Mac reads as unused here.
- **Used without being invoked.** A skill can be in use because a hook injects it or a rule routes to it by name. Every proposal below was checked with `rg -w <name>` across `claude/` and `CLAUDE.md`.
- **Token counts** are description characters divided by 4. They are what each item costs in every session, not its full body.

## Proposals to trim or drop

Every item starts at keep; the lean is in bold at the start of each line.

- [ ] **Lean drop: turn off the hookify plugin** (about 214 tokens: the `conversation-analyzer` agent, the `writing-hookify-rules` skill and four commands). Zero uses ever on this server, and no rule routes to it. Check first: do you use `/hookify` on the Mac? This edits `enabledPlugins` in `claude/settings.json`.
- [ ] **Lean trim: switch off the `gpt-5.6-sol(high)` agent** (about 64 tokens). Never used; GPT-6.1 Sol has its own agent, `sol(high)`. Keep the model itself: it has `writer-priority = 1`, so `write-prose` commissions it. Change: `agent = false` for `gpt-5.6-sol` in `config/model-router.toml`, then `model-router-wire apply`.
- [ ] **Lean trim: switch off the `sol6` agent** (GPT-6 Sol, about 54 tokens). Never used, and superseded by GPT-6.1 Sol in the picker. Its comment says "route and agent stay", so keep the route. Same change in `config/model-router.toml`.
- [ ] **Lean drop: archive the local `strategic-communication` skill** (about 77 tokens). The same skill also loads as `anthropic-skills:strategic-communication`, so every session pays for two copies of one trigger. Keep whichever you edit; the local copy is version-controlled, the other is not. Change: `git mv` to `archive/2026-11-03_strategic-communication/`.
- [ ] **Lean trim: the model-router plugin's eight agents duplicate the local generated ones** (about 326 tokens: `gpt-6-astra`, `gpt-6.1-sol`, `gpt-6.1-terra` and `gpt-6-luna`, each with a `-fast` twin, beside the local `astra(high)`, `sol(high)` and `terra(high)`). None was used. I do not know whether the plugin lets its agents be switched off one by one; if not, this stays a keep.

## Questions only you can answer

- [ ] **Effortful Learning output style: keep it on?** It is the second-largest always-loaded file (5,309 bytes, about 1,271 tokens), loaded in every session including background jobs, where nobody is there to learn. Options: keep; trim it; or switch it off for background jobs only, if the job runner can set a different style.
- [ ] **Dotfiles handoff is 52 days stale.** `~/.remember/-home-yulong-code-dotfiles/remember.md` still describes the 12 Sep project-hub migration and has been delivered 96 times. Lean: refresh it with `/remember` at the end of this session, so it describes today's work. It is never deleted.
- [ ] **Two handoffs and three memory indexes for one project.** nla-vs-cot has handoffs under both `-home-yulong-projects-nla-vs-cot-monitorability-evals` (77 days old) and `-workspace-projects-nla-vs-cot-monitorability-evals` (16 days old), and memory under three encodings, including `/mnt/HC-Volume-…` from before the bind mount. Lean: treat the `/workspace` one as current and merge the older memory into it the next time you work there.
- [ ] **sandbagging-detection memory is the largest: 66 entries, 8,111 bytes.** It loads in every session in that repo. Lean: prune it during the next session there (memory that a rule or skill now covers, and resolved project state).
- [ ] **`learn-quiz` and `application-writer`: still wanted?** Both have zero uses and nothing routes to them (about 190 tokens together). Both sound like Mac-side or occasional tools, so the lean is keep unless you have stopped using them.

## Keep, with the reason

| Items | Why they stay |
|---|---|
| `catalog`, `my-insights`, `skill-invocation-modes`, `wrap-up` | User-invoked only: 0 tokens per session, so dropping saves nothing |
| `bear`, `things3`, `chrome-devtools`, `claude-in-chrome`, `setup-channel` | Mac-side connectors; this server's transcripts cannot see their use |
| `review-draft`, `slidev`, `evidence-packs`, `fast-cli`, `research-loop`, `review-pr-queue`, `autonomous-researcher`, `auto-mode-probe`, `update-auto-mode`, `done` | A rule, checklist or another skill routes to each by name |
| `read-paper`, `sweep-ai-safety`, `write-prose` | Research and writing tools likely used on the Mac; `read-paper` was rated one of the clearest skills in the [clarity audit](https://claude.ai/artifact/1DJKqZ61u1Dp88fxvBk1gP) |
| `deepseek`, `qwen` agents | Council seats; the roster check and `council` name them |
| `using-superpowers`, `diagnosing-superpowers`, `delegating-to-models`, codex `setup` and `hook-setup`, remember `doctor` | Part of plugins that are kept whole; `using-superpowers` is injected by a hook, so it is used without being invoked |

## What happens next

Set the states, then tell me in chat or export the page. I apply only the approved items, each reversibly: `git mv` into `archive/` for skills, `agent = false` plus `model-router-wire apply` for generated agents, and a `settings.json` edit only with your explicit yes. Then `context-review ack` silences the nudge until 1 Dec.
