# Fix: Mouse scroll should scroll scrollback, not command history

## Context

Mouse wheel/trackpad scrolling in Ghostty navigates command history (sends arrow keys to shell) instead of scrolling through terminal output. Happens both inside and outside tmux.

**Most likely root cause**: Alternate scroll mode (`\e[?1007h`) is left enabled by a program, causing Ghostty to convert scroll events to Up/Down arrow keys. When this happens:
- Outside tmux: Arrow keys go to ZSH → `zsh-history-substring-search` navigates history
- Inside tmux: Ghostty converts scroll to arrow keys *before* they reach tmux's mouse protocol, so `mouse on` never sees them — tmux passes them to the shell as keyboard input

**Less likely**: Terminal stuck in alternate screen mode (`\e[?1049h`) after a TUI crash.

## Phase 1: Diagnose (before implementing)

Run these checks to confirm root cause:

```bash
# 1. Fresh Ghostty window (no tmux) — does scroll work as scrollback?
#    If YES: problem is triggered by something (TUI app, tmux)
#    If NO: Ghostty is always converting scroll to arrow keys

# 2. Check if alternate screen is active at prompt:
printf '\e[?1049$p'
# Response: \e[?1049;1$y = SET (stuck), \e[?1049;2$y = RESET (normal)

# 3. Check if alternate scroll mode is active:
printf '\e[?1007$p'
# Response: \e[?1007;1$y = SET (scroll→arrows), \e[?1007;2$y = RESET (normal)

# 4. Run vim, quit, then scroll — does it break?
```

## Phase 2: Fix (`config/zshrc.sh`)

### Add `\e[?1007l` to soft reset (targeted fix)

Add alternate scroll mode reset to `_reset_terminal_modes_soft`. This is the most targeted fix — it tells the terminal to stop converting scroll to arrow keys.

**File**: `config/zshrc.sh` lines 137-155

```diff
 _reset_terminal_modes_soft() {
     [[ -t 1 ]] || return
     local reset=''
     reset+='\e[?1000l'  # mouse click tracking
     reset+='\e[?1002l'  # mouse button-event tracking
     reset+='\e[?1003l'  # mouse any-event tracking
     reset+='\e[?1006l'  # SGR mouse mode (the 35M sequences)
+    reset+='\e[?1007l'  # alternate scroll mode (scroll → arrow keys)
     reset+='\e[?1004l'  # focus event reporting
     ...
 }
```

**Do NOT move `\e[?1049l` to precmd** — `Ctrl-Z` on a TUI app (vim, htop) triggers precmd while the app is suspended, which would corrupt the display when resumed with `fg`. Keep it in `_reset_terminal_modes` (manual `fix-term` only).

### Separate QoL: Increase tmux scrollback (`config/tmux.conf`)

Independent of the scroll bug. 1000 lines is quite low.

```diff
-set-option -g history-limit 1000
+set-option -g history-limit 10000
```

## Verification

1. Run diagnostic commands from Phase 1 to confirm current state
2. Apply the `\e[?1007l` fix
3. Outside tmux: `base64 /dev/urandom | head -100`, then mouse-scroll up → should scroll output
4. Inside tmux: Same test → should enter copy-mode and scroll pane history
5. Run `vim`, quit, scroll → should work
6. Run `vim`, `Ctrl-Z`, scroll, `fg` → vim should display correctly (no corruption)
7. If `\e[?1007l` alone doesn't fix it, escalate: check `\e[?1049$p` state and consider Ghostty config options
