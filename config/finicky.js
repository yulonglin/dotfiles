// Finicky Configuration
// Browser routing for specific URLs
// See: https://github.com/johnste/finicky
//
// Claude Desktop auth flow (com.anthropic.claudefordesktop):
// 1. App opens claude.ai/login/app-google-auth → route to Safari for Google OAuth
// 2. Google redirects back to claude.ai callback → must NOT be intercepted by Finicky
// 3. claude.ai fires claude:// deep link → macOS handles natively (no Finicky rule needed)
// Only match the specific app-google-auth URL. Do NOT add broad claude.ai rules.

// Discord channel and message links open in Discord.app via its discord:// scheme.
// Only /channels/ paths are rewritten: invites, login and OAuth pages stay in the browser.
// The new URL is built as a string because WHATWG URL refuses to switch https → discord.
const DISCORD_HOSTS = [
  "discord.com",
  "www.discord.com",
  "ptb.discord.com",
  "canary.discord.com",
  "discordapp.com",
  "www.discordapp.com",
];

module.exports = {
  defaultBrowser: "Safari",

  rewrite: [
    {
      match: (url) =>
        DISCORD_HOSTS.includes(url.host) && url.pathname.startsWith("/channels/"),
      url: (url) => `discord://-${url.pathname}${url.search}${url.hash}`,
    },
  ],

  handlers: [
    {
      // discord:// links (from the rewrite above) → Discord app
      match: (url) => url.protocol === "discord:",
      browser: "com.hnc.Discord",
    },
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
      match: [
        // Figma dropped support for Safari
        "figma.com*",
        // Scrolling issues on TodayTix
        "todaytix.com*",
      ],
      browser: "Google Chrome"
    },
    {
      match: [
        // Local development → default browser (Safari)
        "localhost*",
        "127.0.0.1*",
        // Linear MCP OAuth → default browser (Safari)
        "mcp.linear.app*",
      ],
      browser: "Safari"
    },
    // Keep Zoom HTTPS URLs in the default browser so sign-in can complete.
    // Meeting pages can launch Zoom through its native URL scheme.
    {
      // Notion → Notion app
      match: [
        "notion.so*",
        "*.notion.so*"
      ],
      browser: "notion.id"
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
