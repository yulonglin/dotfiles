# GWS & Email Safety

Proactive guidance for Gmail/Drive/Calendar/Tasks via `gws` CLI or MCP. PreToolUse hooks (`block_gws_delete.sh`, `block_email_send.sh`) enforce the hard limits below at the tool level regardless of whether this file is loaded — follow it proactively so you don't rely on the hook to catch you.

## Never Delete, Only Trash

Deletions across Google Workspace are irreversible. Use trash/archive (`messages trash`, `threads trash`, Drive trash) — never `delete`, `batchDelete`, `emptyTrash`, or `clear`. If something must be permanently gone, tell the user to do it via the Google Workspace UI.

## Never Send Email, Only Draft

Emails are irreversible once sent. Create drafts (`gws gmail +send --draft`, MCP `gmail_create_draft`) and let the user review and send manually — even if they say "send it." Never call `+send`/`+reply`/`+reply-all`/`+forward` without `--draft`, and never send an existing draft programmatically.

## Draft Formatting

Use `contentType: "text/html"` for Gmail drafts (MCP `gmail_create_draft`) — plain text loses line breaks when edited in Gmail's compose window. `<div>` per line, `<br>` between paragraphs; no inline `<br>` within a paragraph.
