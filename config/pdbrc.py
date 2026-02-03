# pdb++ configuration
# High-contrast color scheme for better readability

import pdb


class Config(pdb.DefaultConfig):
    # ─── Syntax Highlighting (Pygments) ───────────────────────────────────
    # Use high-contrast Pygments style for source code
    # Options: "monokai" (high contrast), "native" (dark), "vim" (terminal-friendly)
    pygments_formatter_class = "pygments.formatters.Terminal256Formatter"
    pygments_formatter_kwargs = {"style": "monokai"}  # High-contrast dark theme

    # Enable syntax highlighting
    highlight = True
    use_pygments = True

    # ─── Line Numbers and Current Line ────────────────────────────────────
    # Bright cyan for line numbers (96 = bright cyan, 01 = bold)
    line_number_color = "96;01"

    # Bright yellow for current line indicator (93 = bright yellow, 01 = bold)
    # Format: "foreground;background;attribute" - using inverse video for visibility
    current_line_color = "93;01;7"  # Bright yellow, bold, inverse video

    # ─── File and Function Names ──────────────────────────────────────────
    # Bright magenta for filenames (95 = bright magenta, 01 = bold)
    filename_color = "95;01"

    # ─── Display Settings ─────────────────────────────────────────────────
    # Show full file path in prompts
    show_hidden_frames_count = True

    # Sticky mode: show surrounding context automatically
    sticky_by_default = False

    # Number of lines to show in context
    default_context = 5

    # Enable filename and line number in prompt
    show_traceback_on_error = True

    # Truncate long strings for readability
    truncate_long_lines = True
    max_line_length = 120

    # ─── Editor Integration ───────────────────────────────────────────────
    # Editor command (use $EDITOR environment variable)
    editor = '${EDITOR:-vim}'

    # ─── Advanced Features ────────────────────────────────────────────────
    enable_hidden_frames = True

    # Better output formatting
    def setup(self, pdb):
        # Add custom commands or setup here if needed
        pass


# Alias for convenience
Pdb = pdb.Pdb
