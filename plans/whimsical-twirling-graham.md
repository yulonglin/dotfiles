# Fix: Ghostty garbled escape sequences after SSH disconnect

## Context

After SSH disconnect (broken pipe / network drop), Ghostty shows raw SGR mouse tracking escape sequences as visible text: `65;57;35M...`. The remote app (tmux, vim, htop) enabled mouse tracking but couldn't send the disable sequence before the connection died. User doesn't see this in iTerm2 (Shell Integration auto-resets modes) or Warp.

Additional symptom: scrollback is inaccessible after disconnect — caused by stuck alternate screen buffer mode (`?1049`).

## Root Cause

When SSH drops ungracefully, the remote app can't send mode-disable sequences. The local terminal still has mouse tracking, alt screen, bracketed paste, etc. enabled. Mouse events and keystrokes are rendered as raw escape sequences.

## Approach (3 layers, informed by Codex/Claude/Gemini critique)

### Action 1: `precmd` hook in zsh (PRIMARY fix)

**File**: `config/zshrc.sh`

The Claude agent's key insight: a `precmd` hook fires before every prompt display, regardless of how the previous command exited. This catches ALL stuck terminal modes — SSH crash, ctrl-c during SSH, any misbehaving program — not just the `sshc` wrapper path.

```zsh
# Reset terminal modes that may be left enabled after ungraceful process exit
# (e.g., SSH disconnect while running mouse-enabled app like tmux/vim/htop)
# All sequences are no-ops when modes aren't active — safe to always run
_reset_terminal_modes() {
    [[ -t 1 ]] || return
    local reset=''
    reset+='\e[?1000l'  # mouse click tracking
    reset+='\e[?1002l'  # mouse button-event tracking
    reset+='\e[?1003l'  # mouse any-event tracking
    reset+='\e[?1006l'  # SGR mouse mode (the 35M sequences)
    reset+='\e[?1004l'  # focus event reporting
    reset+='\e[?1049l'  # alternate screen buffer (restores scrollback access)
    reset+='\e[?2004l'  # bracketed paste mode
    reset+='\e[?1l'     # application cursor keys
    reset+='\e[?66l'    # application keypad mode
    reset+='\e[?25h'    # cursor visible
    reset+='\e(B'       # ASCII charset
    printf "$reset"
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _reset_terminal_modes
```

**Why `?1049l` is critical**: This exits the alternate screen buffer. Without it, scrollback is inaccessible even after disabling mouse modes. This was the missing piece in the original workaround.

**Why no downside**: All sequences are no-ops when modes aren't active. Cost is ~100 bytes written to the TTY per prompt — invisible and instant.

**One risk**: If a program legitimately wants modes to persist across prompts, precmd disables them. In practice this never happens — programs that want mouse mode re-enable it on their own redraw cycle.

### Action 2: `fix-term` manual alias

**File**: `config/aliases.sh`

For when you're already in a corrupted state and need immediate recovery without waiting for the next prompt:

```zsh
# Fix corrupted terminal state (preserves scrollback, unlike `reset`)
alias fix-term='_reset_terminal_modes'
```

### Action 3: Keep `sshc()` wrapper reset (belt-and-suspenders)

**File**: `config/aliases.sh` (modify existing `sshc()` function)

The `precmd` hook is the primary fix, but adding the reset to `sshc()` provides defense-in-depth — resets modes immediately on SSH exit rather than waiting for the next prompt.

Changes to existing `sshc()`:
1. Add `_ssh_reset_terminal_modes` call after line 1109 (`command ssh "$host" "$@"`) before `_ssh_restore_colors`
2. Add `_ssh_reset_terminal_modes` call after line 1116 (`command ssh "$host" "$@"` in the else branch)
3. Ensure `$?` is preserved in both paths

Note: `sshc()` can call the same `_reset_terminal_modes` function — no separate helper needed.

### Action 4: File Ghostty discussion (reframed per Claude agent's insight)

Don't ask "why doesn't Ghostty handle SSH disconnect?" — ask "should Ghostty's shell integration reset private modes at each new prompt boundary, like iTerm2 does?"

**Title**: Should shell integration reset private modes at prompt boundaries?

**Key points**:
- When a process exits abnormally (SSH broken pipe, crashed TUI app), terminal modes like mouse tracking, bracketed paste, and alt screen persist
- `reset` clears scrollback — users want a targeted fix
- iTerm2's Shell Integration detects "new prompt being drawn" and resets modes at that boundary
- Ghostty already has shell integration (auto-injects for bash/zsh/fish) — this is a natural extension
- Proposed: opt-in config option `shell-integration-reset-modes = true` that sends DECRST for common modes when shell integration marks a new prompt
- Reference existing discussions: #6679, #10547, #10714, #11042

(Draft the full discussion body during implementation)

## Files to modify

| File | Change |
|------|--------|
| `config/zshrc.sh` | Add `_reset_terminal_modes()` function + `add-zsh-hook precmd` |
| `config/aliases.sh` | Add `fix-term` alias, add reset call to `sshc()` |

## Verification

1. **Test precmd fix**: SSH to remote, run `htop` (mouse-enabled), kill SSH from another terminal (`kill -9 $(pgrep -f "ssh.*host")`), move mouse — should NOT print garbage. Scroll up — scrollback should be accessible.
2. **Test fix-term**: Manually enable mouse tracking (`printf '\e[?1003h\e[?1006h'`), move mouse (garbage prints), run `fix-term` — garbage stops immediately.
3. **Test sshc wrapper**: Same as #1 but verify terminal colors also restore correctly.
4. **Test no regression**: Run local programs that use mouse (less with mouse, vim, tmux) — verify they still work normally after exiting.
5. **Test scrollback preservation**: Verify `fix-term` and precmd hook don't clear scrollback (scroll up after running).
