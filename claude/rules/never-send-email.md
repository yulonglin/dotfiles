# NEVER Send Emails Programmatically

Emails are IRREVERSIBLE. You must NEVER send emails on the user's behalf.

## What you CAN do
- Create Gmail drafts (`gws gmail +send --draft`)
- Search and read emails
- Draft email content and show it to the user

## What you MUST NEVER do
- Send emails directly (`gws gmail +send` without `--draft`)
- Send existing drafts (`gws gmail users drafts send`)
- Reply/forward emails (`gws gmail +reply`, `+reply-all`, `+forward` without `--draft`)
- Use any MCP tool that sends email (not just creates drafts)

## Why
Emails cannot be unsent. The user must always review and send manually from their email client (Spark/Gmail). Even if the user says "send it", create a draft and tell them it's ready to send from Spark.

## The only exception
If the user says something like "I've reviewed the draft in Spark, send draft ID X" — this is still NOT allowed programmatically. They should click send in Spark.

A PreToolUse hook (`block_email_send.sh`) enforces this at the tool level as a safety net.
