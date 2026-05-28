---
name: check-bib-references
description: Catch LLM-fabricated citations in BibTeX files. Verifies arXiv/OpenReview entries against live metadata (titles, first authors), then guides manual verification of authorless prose claims. Use before submitting papers, after any LLM-assisted citation generation, or when a reference smells off.
---

# Check BibTeX references against authoritative sources

## When to invoke

- **Before any paper submission** — even one wrong citation damages credibility
- **After LLM-assisted bib generation** — any cite added by Claude, Codex, or another LLM should be checked
- **When a reference looks suspicious** — generic-sounding title, vague author list ending in `others`, no eprint/url
- User asks to "fact-check the bib", "verify references", "check citations"

## The failure mode this catches

LLMs fabricate plausible-looking citations. Common patterns:

| Failure | Example |
|---------|---------|
| **Wrong arXiv ID** — title looks right, but ID points to an unrelated paper | `betley2025-wmdp-sycophancy` cited arXiv 2501.01962 = a plant proteins paper |
| **Wrong title** — paper exists but title is paraphrased/invented | `gupta2025-rl-obfuscation`: bib said "Can Models Learn to Evade Monitors?", real title is "Can Language Models Learn to Evade Latent-Space Monitors?" |
| **Wrong/fabricated authors** — first author swapped, middle authors invented | `vct-2025`: bib first author "Gopal, Sanskriti" — real first author is "Götting, Jasper". `ward2025-ctrl-alt-deceit`: 21 fabricated authors (real list has 9, mostly different people) |
| **Fully hallucinated entry** — paper doesn't exist | `betley2025-wmdp-sycophancy` titled "Sycophancy Hacks: Evaluators Gaming without Scheming" — no such paper |
| **Fabricated venue** — wrong workshop/conference name (e.g. "BioSafe GenAI" instead of "Biosecurity Safeguards for Generative AI") |
| **Expanded handles / pseudonyms** — source publishes under a handle, LLM "helpfully" replaces with a guessed real name | LessWrong post bylined `merizian`, `alexdzm`, `jacoba` — bib invented real names like "Alexandra Souly" for `alexdzm`. Even if you think you know who the handle belongs to, you don't have evidence the *author* wanted that attribution |

## Workflow

### 1. Automated check (catches ~80% of issues)

```bash
uv run ~/.claude/skills/check-bib-references/check_bib.py path/to/main.bib --only-mismatches
```

The script:
- Parses BibTeX (regex-based, no `bibtexparser` dep)
- Extracts arXiv IDs from `eprint=`, `journal={arXiv preprint arXiv:...}`, `url=`, `howpublished=`
- Extracts OpenReview forum IDs from `url=`
- Batches arXiv requests (avoids rate-limit on >5 entries)
- Diffs bib title (Jaccard >=0.85) and first author lastname (LaTeX accents normalized)
- Exit code 1 if any mismatches/errors

Flags:
- `--only-mismatches` — quieter; suppresses OK/skip lines
- `--key <citekey>` — check a single entry

### 2. Manual verification (the script can't catch these)

After the script is clean, **still verify**:

| Check | How | Why |
|-------|-----|-----|
| **Full author list** (script only checks first author) | `curl -sL https://arxiv.org/abs/<id> \| grep citation_author` | LLMs often fabricate middle authors. ward2025 had 21 mostly-fake authors past a real first author |
| **Venue / workshop name** in `booktitle=` | WebSearch the paper title + "accepted to" | LLMs invent plausible-sounding venue names |
| **Skipped entries** (no arxiv/openreview ID) | WebFetch the `url=` directly | Tech reports, blog posts — only direct verification works |
| **Prose claims about the paper** in `main.tex` | Read the paper abstract/intro via WebFetch or any2md | Citation can be real but the claim attached to it can be wrong (e.g. "X showed Y" when X showed Z) |
| **Citation context in tex** | `grep -n '\\cite[pt]\\?{<key>}' main.tex` | A correct bib entry attached to a wrong claim is still a fact-check failure |

### 3. If sub-agent fact-checking is used

⚠️ **Do not trust subagent output for specific factual claims about authors or venues.** Sub-agents (writing:fact-checker etc.) without web access will confidently invent author names, conference names, paper titles. Always verify high-stakes findings (claims of fabrication, claims about who is or isn't on a paper) via direct WebFetch in the main context. See `~/.claude/rules/agents-and-delegation.md` § Factual Verification.

## Source-of-truth APIs

| Source | Endpoint | Notes |
|--------|----------|-------|
| arXiv | `http://export.arxiv.org/api/query?id_list=2401.05566,2412.14093` | Atom XML. **Batch via comma-separated `id_list`** — single requests get IP-throttled at ~5 in a row. Rate limit: 1 req/3s, sticky penalty ~30-60s |
| OpenReview v2 | `https://api2.openreview.net/notes?id=<forum_id>` | Use `id=` not `forum=` — `forum=` returns the "Paper Decision" note first |
| arXiv HTML (full author list) | `https://arxiv.org/abs/<id>` then `grep citation_author` | Use when full author list matters |

## Lessons from building/using this

- **Batch arXiv requests.** 17 single-ID requests will get the IP throttled for ~60s. One batched `id_list=` request is fine.
- **Follow redirects.** httpx doesn't by default; arXiv API redirects http→https.
- **Strip LaTeX accents before comparing authors.** `B{\"u}rger` and `Bürger` are the same person. Regex: `\\[\"'`^~=.](?:\{(\w)\}|(\w))` → group(1)|group(2).
- **Token Jaccard at 0.85** is the sweet spot for title similarity — catches paraphrases without flagging legitimate punctuation/casing differences.
- **The script flags candidates; the human decides.** A 0.80 score isn't necessarily wrong — a single missing word like "Detection" can drop you below 0.85. Read the diff.
- **OpenReview's `forum=` returns the wrong note.** Use `id=<forum_id>` to get the actual paper.
- **`others` in author lists hides fabrication.** The script can't tell `Wijk and Chan and Korbak and others` from `Wijk and Chan and Korbak and FabricatedAuthor and others`. Manually expand `others` for important refs.
- **Prose can lie even when the bib is right.** A correct citation can support a wrong claim. The script doesn't read `.tex` — you must.
- **Preserve handles and pseudonyms verbatim.** When the source byline is `merizian`, `alexdzm`, `jacoba` (LessWrong, Substack, blog posts, anonymous workshop submissions), cite them under those handles. Do NOT "expand" to a guessed real name — you don't have evidence the author wants that attribution, and you may be wrong. If the bib has a suspiciously full real name for a post you can only find under a handle, treat it as fabrication until proven otherwise.

## Files

- `check_bib.py` — the script (PEP 723 self-contained, `uv run` directly)

## Adapting to other repos

The script is generic — point it at any `.bib`. Drop the file into the repo's scripts/ for per-project use, or always invoke from `~/.claude/skills/check-bib-references/check_bib.py`.

For repos with a different bib structure (e.g. `\bibitem` in raw .tex, BibLaTeX-only fields), the regex parser may need extending. The current parser handles `@type{key, field={value}, field="value", ...}` with optional whitespace.
