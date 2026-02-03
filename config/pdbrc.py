# pdb++ configuration
# High-contrast color scheme with auto-detection of terminal background

import pdb
import sys
import os
import termios
import tty
import select


def detect_terminal_background():
    """
    Detect if terminal has light or dark background using OSC 11.
    Returns: "light" or "dark" (defaults to "dark" if detection fails)
    """
    # Skip detection if not a TTY or in non-interactive context
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        return "dark"

    try:
        # Save terminal settings
        old_settings = termios.tcgetattr(sys.stdin)

        try:
            # Set terminal to raw mode for reading response
            tty.setraw(sys.stdin.fileno())

            # Query background color with OSC 11
            sys.stdout.write("\033]11;?\033\\")
            sys.stdout.flush()

            # Wait up to 100ms for response
            response = ""
            if select.select([sys.stdin], [], [], 0.1)[0]:
                # Read response (format: ESC ] 11 ; rgb:RRRR/GGGG/BBBB ESC \)
                while True:
                    if select.select([sys.stdin], [], [], 0.01)[0]:
                        char = sys.stdin.read(1)
                        response += char
                        # Check for terminator
                        if char == "\\" and len(response) > 1 and response[-2] == "\033":
                            break
                        if len(response) > 50:  # Sanity limit
                            break
                    else:
                        break

                # Parse response: rgb:RRRR/GGGG/BBBB
                if "rgb:" in response:
                    rgb_part = response.split("rgb:")[1].split("\033")[0]
                    r, g, b = rgb_part.split("/")[:3]
                    # Convert hex to int (first 2 chars of each component)
                    r_val = int(r[:2], 16)
                    g_val = int(g[:2], 16)
                    b_val = int(b[:2], 16)
                    # Calculate luminance (perceived brightness)
                    luminance = 0.299 * r_val + 0.587 * g_val + 0.114 * b_val
                    return "light" if luminance > 127 else "dark"

        finally:
            # Restore terminal settings
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)

    except (OSError, ValueError, termios.error):
        pass  # Detection failed, use default

    # Default to dark theme (most common for developers)
    return "dark"


# Detect terminal background
_THEME = detect_terminal_background()


class Config(pdb.DefaultConfig):
    # ─── Syntax Highlighting (Pygments) ───────────────────────────────────
    pygments_formatter_class = "pygments.formatters.Terminal256Formatter"

    if _THEME == "light":
        # Light background: use dark, readable colors
        pygments_formatter_kwargs = {"style": "solarized-light"}
        line_number_color = "34;01"        # Dark blue, bold
        current_line_color = "33;01;7"     # Dark yellow, bold, inverse
        filename_color = "35;01"           # Dark magenta, bold
    else:
        # Dark background: use bright, high-contrast colors
        pygments_formatter_kwargs = {"style": "monokai"}
        line_number_color = "96;01"        # Bright cyan, bold
        current_line_color = "93;01;7"     # Bright yellow, bold, inverse
        filename_color = "95;01"           # Bright magenta, bold

    # Enable syntax highlighting
    highlight = True
    use_pygments = True

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
