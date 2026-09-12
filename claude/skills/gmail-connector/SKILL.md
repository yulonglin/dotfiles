---
name: gmail-connector
description: "Pull receipts, invoices and attachments out of Gmail with the claude.ai Gmail MCP connector — search operators that work, the RAW-MIME route that recovers attachments the connector has no download call for, the read-only rules, and the script that decodes them. Use when asked to find receipts or invoices in Gmail, save an email attachment, sweep a mailbox for a claim or audit, or when a Gmail search returns nothing for a vendor that definitely bills by email."
---

# Gmail connector — receipts, invoices and attachments

The claude.ai Gmail connector (`mcp__claude_ai_Gmail__*`) can read every message but has **no attachment-download tool**. The way round it is the `RAW` message format, which returns the whole MIME document with attachments embedded in base64. This skill is the playbook that produced 44 vendor-original PDFs plus 39 text receipts for the Sep 2026 AISI claim in one pass.

## Preconditions

- The connectors only appear when `ANTHROPIC_API_KEY` is **absent** from the session (the dotfiles wrapper strips it; a stale daemon or an `.envrc` can reintroduce it). If `mcp__claude_ai_Gmail__*` is missing from the tool list, that is the first thing to check — see `spawn-session`.
- Load the tools in one call: `ToolSearch "select:mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Gmail__get_thread,mcp__claude_ai_Gmail__get_message"`.
- `gws` is not installed on this machine; do not plan around it.

## The three calls

| Step | Tool | Notes |
|:--|:--|:--|
| Find | `search_threads` | Full Gmail operator syntax: `after:2026/05/08 before:2026/09/02`, `from:`, `filename:pdf`, `(invoice OR receipt OR rechnung)`. Returns thread ids. |
| Read | `get_thread` / `get_message` with `messageFormat: PLAIN_TEXT` | Body as text or markdown, plus `attachment_ids` and attachment names. Enough for HTML-only receipts (Stripe, Google Play, Uber, Booking.com). |
| Fetch attachment | `get_message` with `messageFormat: RAW` | Returns `{"id": ..., "raw": <base64url MIME>}`. Large results are spilled to a file under `~/.claude/projects/<project>/<session>/tool-results/mcp-claude_ai_Gmail-get_message-*.txt` and the tool result gives the path; small ones arrive inline, so write them to `work/raw/<id>.json` yourself. Fails above roughly 10 MB — see below. |

**Never say what a message does or does not contain without having read its body.** `MINIMAL` and `METADATA_ONLY` return no body at all, and the `snippet` they and `search_threads` carry is a truncation of the opening ~100 characters that routinely cuts off mid-sentence, before the substance. Reading one of those and concluding a message omitted something is a hallucination with a tool call attached. Every claim about an email's content — that it asked a question, missed a point, agreed, refused — is a `verify-before-instructing` claim and needs `PLAIN_TEXT`.

This bites hardest on the user's **own sent mail**: being told "you forgot to mention X" when X is in paragraph three is both wrong and insulting, because he wrote it. Observed 2026-09-11 on a Fox Rent A Car balance thread, where `MINIMAL` hid a full corrected payment ledger and produced a confident, false "one thing is missing".

Context economy is never the reason to skip the body. A long thread is long because of quoted history, not because of the message; read it in a subagent if the size genuinely matters, or spend the tokens. `MINIMAL` and `METADATA_ONLY` are for enumerating ids, dates and senders — for deciding *which* message to read, never *what it said*.

## RAW has a size ceiling, and hitting it kills the session

A message of about 15 MB returns `MCP server "claude.ai Gmail" session expired`, every time, immediately. It is not a timeout and not a rate limit: nine attempts across three sessions and two model families, including paced retries a minute apart, produced the identical error, while messages up to about 1 MB in the same sessions succeeded instantly (observed 2026-09-09 on a 15.3 MB Fox Rent A Car message carrying 25 photos and four PDFs). **The failed call also invalidates the connector session**, so the next `search_threads` or `get_message` fails the same way until the session is re-established — do the RAW attempt on a big message last, or in a subagent, so it cannot take the rest of a sweep down with it.

There is no way round it inside the connector. `get_thread` rejects RAW outright (`RAW format is not supported for GetThread`). `FULL_CONTENT` returns each attachment's id and name but no bytes, and no tool in the Gmail set accepts an attachment id — the underlying `messages.attachments.get` endpoint is simply not exposed. Attachments are not mirrored into Drive, so a Drive title search finds nothing.

So when RAW fails on a big message, stop and check three things in order, rather than retrying: **(1) a smaller message carrying the same file** — vendors resend, and a forwarded or follow-up copy often has one attachment instead of thirty (a 904 KB signed agreement came back cleanly from a sibling message after the 15 MB parent refused); **(2) whether a different document already proves the point** — the plate and VIN wanted from an unreachable signed agreement were both in the rental invoice and the police report; **(3) the user downloads the two files in Gmail**, which takes them a minute and is source-faithful. `gcloud` OAuth with `gmail.readonly` would make attachment ids directly fetchable and IMAP with an app password would too, but both are more setup than one browser click for a one-off, and neither is installed here.

## Keep the mailbox out of main context

An MCP result cannot be piped; whatever the connector returns lands in the calling agent's context. Two facts bound the damage:

- The harness spills any tool result of roughly 50 KB or more to `~/.claude/projects/<slug>/<session>/tool-results/mcp-claude_ai_Gmail-get_message-<ts>.txt` and shows the model only the path. A RAW message with a PDF attached is almost always over that line, so it costs a path, not the payload. Small RAW results (a text-only email) arrive inline in full.
- Everything under that threshold is still written verbatim to the session `.jsonl`, so nothing has to be retyped to reach disk.

So: **always run a sweep as a subagent** (its context is discarded; the lead gets a summary and the files). Inside the sweep, read with `PLAIN_TEXT` first and call `RAW` only for messages whose `attachments` field is non-empty; HTML-only receipts need no RAW at all. Never `Read` or `cat` a spilled result; pass its path to the script below. Decode in one batch at the end rather than per message.

## Decoding RAW

`raw` is base64url (the Gmail API convention), not the readable MIME text — decode it first, then hand the bytes to Python's `email` module. The promoted script does all of it:

```bash
python3 ~/.claude/skills/gmail-connector/scripts/extract_raw_mime.py work/raw/*.json --out work/extract
```

Per message it writes `<out>/<id>/<attachment>`, `_body.txt` (HTML flattened to text) and `_meta.json` (date, from, subject, attachment list), and prints one summary line. Any `.pdf` whose bytes do not start with `%PDF-` is flagged `!! NOT A PDF` and the exit code is 1 — that is the truncation check. Then `cp` (never `mv`) the attachment into its final home under the project's filename convention.

HTML-only receipts: `_body.txt` (or the `html_body` from `FULL_CONTENT`) is a working note under `work/raw/`, never an attachment — a text file proves nothing (`rules/evidence.md`). What goes in the pack is a printout: render the HTML with headless Chrome, or list the Gmail link next to a "print to PDF" step for the user when the render is not faithful:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --print-to-pdf=out.pdf file:///abs/path/receipt.html
```

**Set `--timezone` to the zone of the events, not your own and not UTC.** It defaults to UTC, which is wrong for an evidence pack: a message received at 16:08 Pacific carries a `00:08Z` header the following day, so a UTC render puts a purchase on the wrong calendar date and can contradict the filing it is attached to (observed 2026-09-10 on a RentalCover pack, where the purchase confirmation read 10 December for a 9 December purchase). The flag takes an IANA name and handles DST, so `America/Los_Angeles` yields PST in December and PDT in July. Re-rendering with a different zone is legitimate — it is the same generator over the same source data, and the page declares itself a reconstruction in its footer — but the native Gmail print is stronger still where the user can produce it.

For a whole thread the two scripts in `scripts/` do it end to end: `build.py` turns a `get_thread` result (`messageFormat: FULL_CONTENT`, so `htmlBody` is present; save the spilled JSON as `<basename>.txt`, the output takes the file stem) or the delimited `threads.txt` capture (format in its docstring) into a Gmail-print-style page — account header, subject, message count, each message boxed with From/To/Cc/Date/Attachments, tracking pixels and tokenised links stripped; `render.py` prints those pages to PDF and reports bytes and page count:

```bash
python3 ~/.claude/skills/gmail-connector/scripts/build.py work/threads.txt work/<basename>.txt --out work/html --account lin.yulong@gmail.com --timezone America/Los_Angeles
python3 ~/.claude/skills/gmail-connector/scripts/render.py work/html/*.html --out work/pdf   # sandbox off
```

Gmail's own print view cannot be pulled through the claude-in-chrome extension: its redaction fires on `a=b; c=d` shapes in the page HTML, and the auto-mode classifier blocks working around it, so the printout is built from the API body plus headers instead. Chrome 152 headless needs the sandbox off and never exits after `--print-to-pdf`; `render.py` polls until the PDF size is stable, then kills it, and flags anything under 10 KB as a blank page.

## Search lessons from the 2026-09 sweep

- **`from:` fails for relayed senders.** Hetzner arrives via an iCloud relay, so `from:hetzner.com` returns nothing; search the keyword `hetzner` instead. When a monthly vendor shows zero hits, retry by keyword and by invoice-number prefix before concluding there is nothing.
- **Card notices are the backstop.** Bank alert emails (`from:maribank.sg`) prove a charge when the vendor invoice never reached Gmail (OpenAI and Anthropic both did this). Save the notice as evidence and list the invoice under "needs manual download from the dashboard".
- **Forwarded accounts** (`linyulong97@gmail.com`, `yl688@cantab.ac.uk`) only show what was forwarded after forwarding was set up; an idle series (a vendor that bills monthly but shows a gap) usually means the receipts went to the source mailbox before then.
- **Record coverage.** End the inventory with every query run and what was not searched (trash, taxi apps by sender, meal merchants). The next pass extends rather than repeats.
- **Link a message for the user** as `https://mail.google.com/mail/u/0/#all/<message-id>`.

## Google Drive binaries: the same trick, plus a no-parse alternative

`mcp__claude_ai_Google_Drive__download_file_content` returns `{"content": <base64>, ...}` inline. **Never retype the base64 into a heredoc** — a 48 KB xlsx lost its `styles.xml` that way in 2026-09. The harness writes every tool result verbatim to the session transcript, so recover the exact bytes from disk instead:

```python
# grep the session jsonl for '"content":"UEsDB...","id":"<fileId>"', b64decode, then zipfile.testzip() before trusting it
~/.claude/projects/<project-slug>/<session-id>.jsonl   # inline results
~/.claude/projects/<project-slug>/<session-id>/tool-results/mcp-claude_ai_Google_Drive-*.txt  # spilled results
```

If the user asks for a plain download with no parsing, a Chrome tab at `https://drive.google.com/uc?export=download&id=<fileId>` lands the file in `~/Downloads` (needs the user's OK: it is a file download).

## Rules

Read-only by default: never `send_message`, `reply`, `forward`, label, archive, mark spam or trash. `create_draft` only when the user asks for a draft — never send, even when told to (see `rules/safety.md`, Google Workspace). Never invent an invoice number or amount; write "unreadable" and keep the file. Saved message bodies are notes, not evidence: an attachment list carries only PDFs and images from the source system, and the inventory names each file's format — `rules/evidence.md`. Personal-versus-work charges are the user's call: list them under `AMBIGUOUS:` with a recommendation instead of deciding.
