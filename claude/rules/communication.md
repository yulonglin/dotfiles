# Communication

## Write for a reader who soft-wraps

One paragraph is ONE line in `.md` files; blank lines separate paragraphs and readers soft-wrap. This covers prose, bullet bodies and table cells. `md-unwrap --check <path>` finds violations and `md-unwrap --fix <path>` repairs them; it gates staged Markdown under `claude/` in pre-commit and CI.

**Todos and separate points are bullet lists, one item per line, sub-points nested** — in notes, plans, schedules and replies alike. Items joined by commas, semicolons or "then" still need a list; each todo gets a separately tickable `- [ ]` line. Bear-specific mechanics: `bear`.

**Every header asserts a point, not a topic** — in specs, plans, reports, READMEs and slide titles alike, use roughly four to seven plain, concrete words, not a metaphor; put qualifications on the line below. Setup, methods and appendix sections have no finding to state: use plain descriptive names. Full standard: `presentation.md`; artifact titles: `artifact-writing`.

**Results belong in figures, not in paragraphs.** Show three or more numbers with intervals as a figure — in papers, reports, artifacts, specs and slides alike. Keep a number inline only for the single headline value or the one figure a reader must be able to quote. Every comparison plot shows its chance line and its null. Plot versus table: `presentation.md`. Tooling and style: `house-plots` for papers, `dataviz` for artifact pages.

**Every sourced figure, quote or claim links to its source** — IRS page, Gmail thread (`https://mail.google.com/mail/u/0/#all/<threadId>`), Slack permalink, Bear note — in notes, artifacts and replies alike; a computed number links to its inputs. A page generated from linked text (a diff, comparison, digest or export) keeps those links clickable and the text's line structure (nested lists and indentation, via real lists or `white-space: pre-wrap`; a diff treats a line's indent as part of the line, not a word gap); a script may strip links to count or compare words, but must put them back in what it shows (2026-10-12). An attachment to an official or third-party submission is the source system's own printout, never a text transcription (`evidence-packs`). Links never end with a full stop — a trailing period is copied into the URL. No checkbox checklists in specs or docs; `[ ]` belongs only where something ticks it — a working todo list, or an `md2artifact` review control.

**Stale items never sit there looking current.** Strike, rewrite or delete superseded, dropped or cancelled plan steps, drafts, todos, document rows or decisions, whichever leaves least clutter. Where the reason matters, append why and what replaced it: "~~Send the Anti Entropy request~~ dropped 3 Sep 2026: the signed variation covers the period". Completed items are ticked, not struck; struck means cancelled. Deletion is fine in git-tracked files, whose history keeps the old text; Bear has none, so rewrite or strike instead.

**Never write "arm"**; say condition. Name a baseline by what it does ("always flags").

**Model attribution names the exact model, not the family** — "Proofread by Claude Fable 5.1, 8 Sep", not "by Claude"; for other labs, "reviewed by GPT-6 Astra", not "by GPT". Use the human-readable name in every model-credit label, stamp or annotation in notes, artifacts, commit messages or code comments; the model ID (`claude-fable-5-1`) goes only in machine-facing metadata.

Drafting a message on Yulong's behalf: optimise for friendliness, then clarity, then persuasiveness. "Critique and improve" means apply all three and say what changed.

## Bundle questions rather than drip them

One or two rounds of ten to twenty. `AskUserQuestion` caps at four per call, so a bundle spans several calls in one message. The `interview-me` skill drives this for stress-testing a plan. `AskUserQuestion` questions and option labels never say "I", "you", "me" or "my", to avoid ambiguity between Claude and Yulong; name the actor.

## These recurring habits cost Yulong time

- **A correction naming one example means the class.** Sweep siblings (other rows, panels, files, call sites) in the same pass; if ambiguous, state coverage and omissions. For rules and tooling changes too, encode the principle, not the cited case.
- **When `Read` or `Glob` misses, search rather than skip**: `Glob("**/<basename>")` from the git root, preserving directory hints. Never silently skip a referenced file.
- **For auth-gated services** (Notion, private repos, Confluence, Jira) ask at once for a paste, export or token rather than spend context trying WebFetch, Playwright, then curl. Google Workspace is the exception — `gws` reaches it directly.
- **No uncalculated time or cost estimates**: human duration intuitions do not transfer to machine-speed agents in parallel worktrees. Calculate precisely or omit.
- **On personal repos, act rather than propose ceremony** — no unprompted `.gitignore`, branching or PR suggestions.
- **After pushback, don't defend.** The next sentence must not begin with "Because", "I thought" or "You said" — acknowledge, drop it, ask what they actually want. Short affirmations are compliance, not resistance; don't re-pitch.
- **Reply on the channel you were messaged on**, not just the terminal.
- **Every path in a reply is absolute, from `/`**, and Artifacts are links — never repo-relative, brace shorthand or a bare filename (2026-10-11).
- **"Where is X?" is answered by the path, first.** Start with a code-block path (or URL) per requested thing, before status, caveats or pending work. If it does not exist yet, say so there and name its future file. Never bury it in prose (2026-09-08). Interpret transcription artifacts charitably: VoiceInk produces phonetic errors ("VAR" → "FAR").
- **A shell command Yulong runs himself is written multiline**, one option or argument group per line with `\` continuations. Long lines soft-wrap in his terminal, breaking pasted commands (`command not found: --force-with-lease`) and forcing retyping (2026-09-12).

```
git -C /home/yulong/code/dotfiles/.claude/worktrees/rq-installer-stall \
  push --force-with-lease \
  origin worktree-installer-stall
```

## Behavioural instructions become config, not memory

Behavioral instructions ("allow X", "always do Y", "stop doing Z") become `settings.json` permissions, a hook or a rules file; memory is only for what config cannot encode. Never create a `.local.md` unless asked; `.md` is version-controlled and the default.
