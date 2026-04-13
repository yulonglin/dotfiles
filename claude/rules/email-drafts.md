# Email Draft Conventions

## Always Use HTML Content Type

When creating Gmail drafts via MCP (`gmail_create_draft`), **always use `contentType: "text/html"`**.

Plain text drafts (`text/plain`) lose line breaks when edited in Gmail's compose window. HTML preserves formatting.

**Template:**
```
contentType: "text/html"
body: "<div>First paragraph</div><br><div>Second paragraph</div><br><div>Cheers,</div><div>Yulong</div>"
```

Use `<div>` for lines and `<br>` for blank lines between paragraphs. Do not use inline `<br>` within paragraphs — let text flow naturally.
