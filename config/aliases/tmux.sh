# aliases/tmux.sh — tmux session aliases and chmod helpers

#-------------------------------------------------------------
# tmux
#-------------------------------------------------------------

alias ta="tmux attach"
alias taa="tmux attach -t"
alias tad="tmux attach -d -t"
alias td="tmux detach"
alias tn="tmux new-session -s"
alias tl="tmux list-sessions"
alias tkill="tmux kill-server"
alias tdel="tmux kill-session -t"

# ls/tree aliases → config/modern_tools.sh (single source of truth)

#-------------------------------------------------------------
# tmux-resume opt-in
#-------------------------------------------------------------
# tmux-resume (hourly) only sends keystrokes into windows whose name starts with
# the opt-in prefix (default `auto-`). Everything else is detected, logged, and
# left alone to stop at the rate limit. These helpers toggle that opt-in on the
# CURRENT window, which is the common case: you decide a session should run
# unattended after starting it, not before. Config + rationale:
# config/tmux-resume-patterns.conf
#
# `rename-window` also disables tmux's automatic-rename for the window, so the
# name sticks instead of being overwritten by the running command.

# The prefix is configurable (env var or a patterns-file directive), so ask
# tmux-resume for the resolved value rather than assuming `auto-`. Hard-coding it
# here would rename windows to a prefix the gate rejects — the helper would report
# success while leaving the pane opted out. Empty means sending is disabled.
_tmux_resume_prefix () {
  command -v tmux-resume >/dev/null 2>&1 || { echo "tmux-resume not on PATH" >&2; return 1; }
  local p; p="$(tmux-resume --print-optin-prefix 2>/dev/null)"
  [ -n "$p" ] || { echo "opt-in prefix is empty — sending is disabled" >&2; return 1; }
  printf '%s' "$p"
}

# tauto [topic] — opt this window in. Defaults to prefixing the current name.
tauto () {
  [ -n "$TMUX" ] || { echo "tauto: not inside tmux" >&2; return 1; }
  local prefix; prefix="$(_tmux_resume_prefix)" || return 1
  local topic="${1:-$(tmux display-message -p '#{window_name}')}"
  # Prefix quoted in the pattern so it is matched literally, not as a glob.
  case "$topic" in "$prefix"*) ;; *) topic="$prefix$topic" ;; esac
  tmux rename-window "$topic" && echo "opted in: $topic"
}

# tnoauto — opt this window back out.
tnoauto () {
  [ -n "$TMUX" ] || { echo "tnoauto: not inside tmux" >&2; return 1; }
  local prefix; prefix="$(_tmux_resume_prefix)" || return 1
  local cur; cur="$(tmux display-message -p '#{window_name}')"
  case "$cur" in
    "$prefix"*) tmux rename-window "${cur#"$prefix"}" && echo "opted out: ${cur#"$prefix"}" ;;
    *) echo "already opted out: $cur" ;;
  esac
}

# tautols — every window that will be auto-resumed, across all sessions.
tautols () {
  local prefix; prefix="$(_tmux_resume_prefix)" || return 1
  local out
  # Tab-delimited so names containing spaces stay one field, as tmux-resume reads them.
  # awk, not `grep -P '\tauto-'` — BSD grep on macOS has no -P. The prefix is passed
  # as an awk var and matched with index(), so regex metacharacters stay literal.
  out="$(tmux list-windows -a -F '#{session_name}:#{window_index}	#{window_name}' 2>/dev/null \
    | awk -F'\t' -v p="$prefix" 'index($2, p) == 1' || true)"
  if [ -z "$out" ]; then echo "(no windows opted in)"; else printf '%s\n' "$out"; fi
}

#-------------------------------------------------------------
# chmod
#-------------------------------------------------------------

chw () {
  if [ "$#" -eq 1 ]; then
    chmod a+w $1
  else
    echo "Usage: chw <dir>" >&2
  fi
}
chx () {
  if [ "$#" -eq 1 ]; then
    chmod a+x $1
  else
    echo "Usage: chx <dir>" >&2
  fi
}
