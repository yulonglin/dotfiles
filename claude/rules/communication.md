# Communication

## Write for a reader who soft-wraps

One paragraph is ONE line in `.md` files; blank lines separate paragraphs and readers soft-wrap. This covers prose, bullet bodies and table cells. `md-unwrap --check <path>` finds violations and `md-unwrap --fix <path>` repairs them; it gates staged Markdown under `claude/` in pre-commit and CI.

**Todos and separate points are bullet lists, one item per line, sub-points nested** — in notes, plans, schedules and replies alike. Several items packed into one line with commas, semicolons or "then" is a list you have not drawn yet; a todo is its own `- [ ]` line, tickable alone. Bear-specific mechanics: `bear`.

**Every header asserts a point, not a topic** — in specs, plans, reports, READMEs and slide titles alike, in roughly four to seven plain words with concrete referents, not a metaphor the body must decode; qualifying detail goes in the line below. Setup, methods and appendix sections, having no finding to state, take a plain descriptive name. Full standard: `presentation.md`; artifact titles: `artifact-writing`.

**Results belong in figures, not in paragraphs.** A passage carrying three or more numbers with intervals is a figure you have not drawn yet — in papers, reports, artifacts, specs and slides alike. Keep a number inline only when it is the single headline value, or the one figure a reader must be able to quote. Every comparison plot shows its chance line and its null. Plot versus table: `presentation.md`. Tooling and style: `house-plots` for papers, `dataviz` for artifact pages.

**Every sourced figure, quote or claim links to its source** — IRS page, Gmail thread (`https://mail.google.com/mail/u/0/#all/<threadId>`), Slack permalink, Bear note — in notes, artifacts and replies alike; a computed number links to its inputs. A page generated from linked text (a diff, comparison, digest or export) keeps those links clickable and the text's line structure (nested lists and indentation, via real lists or `white-space: pre-wrap`; a diff treats a line's indent as part of the line, not a word gap); a script may strip links to count or compare words, but must put them back in what it shows (2026-10-12). An attachment to an official or third-party submission is the source system's own printout, never a text transcription (`evidence-packs`). Links never end with a full stop — a trailing period is copied into the URL. No checkbox checklists in specs or docs; `[ ]` belongs only where something ticks it — a working todo list, or an `md2artifact` review control.

**Stale items never sit there looking current.** When a plan step, draft, todo, document row or decision is superseded, dropped or cancelled, strike, rewrite or delete it (whichever leaves least clutter) and, where the reason matters, add a trailing note on why and what replaced it: "~~Send the Anti Entropy request~~ dropped 3 Sep 2026: the signed variation covers the period". Completed items are ticked, not struck; struck means cancelled. Deletion is fine in git-tracked files, whose history keeps the old text; Bear has none, so rewrite or strike instead.

**Never write "arm"**; say condition. Name a baseline by what it does ("always flags").

**Model attribution names the exact model, not the family** — "Proofread by Claude Fable 5.1, 8 Sep", not "by Claude"; for other labs, "reviewed by GPT-6 Astra", not "by GPT". This covers any label, stamp or annotation crediting work to a model, in notes, artifacts, commit messages or code comments. Readers recognise the human-readable name; the model ID (`claude-fable-5-1`) goes only in machine-facing metadata.

Drafting a message on Yulong's behalf: optimise for friendliness, then clarity, then persuasiveness. "Critique and improve" means apply all three and say what changed.

## Bundle questions rather than drip them

One or two rounds of ten to twenty. `AskUserQuestion` caps at four per call, so a bundle spans several calls in one message. The `interview-me` skill drives this for stress-testing a plan. `AskUserQuestion` questions and option labels never say "I", "you", "me" or "my", since the reader cannot tell whether Claude or Yulong is meant; name the actor.

## These recurring habits cost Yulong time

- **A correction naming one example means the class.** Sweep the siblings (other rows, panels, files, call sites) in the same pass, and if the sweep is ambiguous say what you covered and what you left. This includes rules and tooling changes: encode the principle, not the cited case.
- **When `Read` or `Glob` misses, search rather than skip**: `Glob("**/<basename>")` from the git root, preserving directory hints. Never silently skip a referenced file.
- **For auth-gated services** (Notion, private repos, Confluence, Jira) ask at once for a paste, export or token rather than burn context on WebFetch, then Playwright, then curl. Google Workspace is the exception — `gws` reaches it directly.
- **No uncalculated time or cost estimates**: agents run at machine speed across parallel worktrees, so human duration intuitions don't transfer. Calculate precisely or omit.
- **On personal repos, act rather than propose ceremony** — no unprompted `.gitignore`, branching or PR suggestions.
- **After pushback, don't defend.** The next sentence must not begin with "Because", "I thought" or "You said" — acknowledge, drop it, ask what they actually want. Short affirmations are compliance, not resistance; don't re-pitch.
- **Reply on the channel you were messaged on**, not just the terminal.
- **Every path in a reply is absolute, from `/`**, and Artifacts are links — never repo-relative, brace shorthand or a bare filename (2026-10-11).
- **"Where is X?" is answered by the path, first.** The reply's first line is the path (or URL) in a code block, one per thing asked for, before any status, caveat or pending work. If it does not exist yet, that line says so and names the file it will become. Never bury it in a paragraph (2026-09-08). Interpret transcription artifacts charitably: VoiceInk produces phonetic errors ("VAR" → "FAR").
- **A shell command Yulong runs himself is written multiline**, one option or argument group per line with `\` continuations. A single long line soft-wraps in his terminal and the paste breaks at the wrap: the shell answers `command not found: --force-with-lease` and he retypes it (2026-09-12).

```
git -C /home/yulong/code/dotfiles/.claude/worktrees/rq-installer-stall \
  push --force-with-lease \
  origin worktree-installer-stall
```

## Behavioural instructions become config, not memory

Behavioral instructions ("allow X", "always do Y", "stop doing Z") become `settings.json` permissions, a hook or a rules file; memory is only for what config cannot encode. Never create a `.local.md` unless asked; `.md` is version-controlled and the default.
