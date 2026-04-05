// Finicky Configuration
// Browser routing for specific URLs
// See: https://github.com/johnste/finicky
//
// Claude Desktop auth flow (com.anthropic.claudefordesktop):
// 1. App opens claude.ai/login/app-google-auth → route to Safari for Google OAuth
// 2. Google redirects back to claude.ai callback → must NOT be intercepted by Finicky
// 3. claude.ai fires claude:// deep link → macOS handles natively (no Finicky rule needed)
// Only match the specific app-google-auth URL. Do NOT add broad claude.ai rules.

module.exports = {
  defaultBrowser: "Safari",

  handlers: [
    {
      // Google productivity apps → Chrome
      match: [
        "docs.google.com*",
        "slides.google.com*",
        "sheets.google.com*",
        "drive.google.com*",
        "meet.google.com*",
        "calendar.google.com*",
        "mail.google.com*",
        "colab.research.google.com*",
        "chromewebstore.google.com*",
        "scholar.google.com*",
      ],
      browser: "Google Chrome"
    },
    {
      // Local development → default browser (Safari)
      match: [
        "localhost*",
        "127.0.0.1*"
      ],
      browser: "Safari"
    },
    {
      // Zoom meetings → Zoom app
      match: [
        "*.zoom.us/*",
        "zoom.us/*"
      ],
      browser: "us.zoom.xos"
    },
    {
      // Notion → Notion app
      match: [
        "notion.so*",
        "*.notion.so*"
      ],
      browser: "notion.id"
    },
    {
      // Linear MCP OAuth → Safari
      match: [
        "mcp.linear.app*"
      ],
      browser: "Safari"
    },
    {
      // Linear → Linear app
      match: [
        "linear.app*",
        "*.linear.app*"
      ],
      browser: "com.linear"
    },
    {
      // Claude Desktop auth: only intercept the initial Google OAuth URL → Safari
      // Do NOT match broad claude.ai paths — the OAuth callback must stay unintercepted
      match: ({ url }) =>
        url.host === "claude.ai" &&
        url.pathname.startsWith("/login/app-google-auth"),
      browser: "Safari"
    }
  ]
};
