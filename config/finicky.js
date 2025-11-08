// Finicky Configuration
// Browser routing for specific URLs
// See: https://github.com/johnste/finicky

export default {
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
        "chromewebstore.google.com*"
      ],
      browser: "Google Chrome"
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
      // Linear → Linear app
      match: [
        "linear.app*",
        "*.linear.app*"
      ],
      browser: "com.linear"
    }
  ]
};
