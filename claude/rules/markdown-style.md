# Writing Style

**One paragraph = ONE line** in `.md` files. Never a hard newline inside a paragraph — not mid-sentence, not between sentences; blank lines separate paragraphs and readers soft-wrap. Applies to prose, bullet bodies, and table cells.

**Links never end with a full stop** — a trailing period gets copied into the URL.

**No checkbox checklists in specs/docs** — never `[ ]` markers, neither inline in prose nor as `- [ ]` sub-bullets; use plain itemised `-` bullets. Checkbox syntax belongs only in actual working todo lists.

**Mermaid diagrams favour vertical space** — `flowchart TD` over `LR` (same for other diagram types' orientation choices), but TD alone is not enough: several siblings at one rank (parallel sources, unlinked nodes in a subgraph) still render wide. Stack them with invisible `~~~` links and wrap long node/edge labels with `<br/>`. Scrolling vertically is easy; panning horizontally is not. When wrapping a label with `<br/>`, keep explicit spaces in the text around joins and keep each node's label on ONE source line — labels assembled across source lines or tight against `<br/>` render as words concatenated without spaces (observed in Artifact-rendered mermaid, 2026-08-12).

**Bear markdown** (Bear's FAQ omits the colour encoding, so Yulong's copied-from-Bear examples are the source of truth): highlight `==text==`; a coloured highlight is a coloured-dot emoji at the START of the span, `==🔴text==` (🔴 = flag this / verify before shipping); strikethrough `~~text~~`; underline `~text~`. Don't use `==` or `~text~` in files that render as plain GitHub markdown.

**Drafting messages on Yulong's behalf** (email, Slack, Telegram): optimise for friendliness, then clarity, then persuasiveness. "Critique and improve" means apply all three lenses and say what changed.
