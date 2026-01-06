# Note: Terminal emulator configuration required:
# - Set "Left Option key" to "Esc+" for Opt+Shift bindings to work
# - For Ghostty, add to ~/.config/ghostty/config:
#     keybind = super+c=text:\x1b[99~
#   This makes Cmd+C send a custom sequence that the shell can bind to copy selected text

# ZSH-only file: exit early in bash to avoid parse errors from ZSH syntax
[ -z "$ZSH_VERSION" ] && return 0 2>/dev/null

# All code below is ZSH-specific (uses zle, bindkey, ZSH for-loop syntax)

# convert a python command to a debug command
function replace-python {
    if [[ $BUFFER =~ ^python\ .* ]]; then
      BUFFER="python3 -m debugpy --listen 5678 --wait-for-client ${BUFFER#python }"
      zle reset-prompt
    fi
  }
  zle -N replace-python
  bindkey "\ed" replace-python

  # prepend sudo to the current command
  function prepend-sudo {
    if [[ $BUFFER != "sudo "* ]]; then
      BUFFER="sudo $BUFFER"; CURSOR+=5
      zle reset-prompt
    fi
  }
  zle -N prepend-sudo
  bindkey "\es" prepend-sudo

  # copy selected text to clipboard
  function copy-region-to-clipboard {
    if ((REGION_ACTIVE)); then
      local start=$MARK
      local end=$CURSOR
      # Ensure start < end
      if (( start > end )); then
        local temp=$start
        start=$end
        end=$temp
      fi
      local selected="${BUFFER:$start:$((end - start))}"

      # Copy to clipboard (macOS/Linux compatible)
      if command -v pbcopy &> /dev/null; then
        echo -n "$selected" | pbcopy
      elif command -v xclip &> /dev/null; then
        echo -n "$selected" | xclip -selection clipboard
      elif command -v xsel &> /dev/null; then
        echo -n "$selected" | xsel --clipboard
      fi

      # Deselect after copying
      ((REGION_ACTIVE = 0))
      zle reset-prompt
    fi
  }
  zle -N copy-region-to-clipboard
  # Bind to custom sequence sent by Ghostty for Cmd+C
  # Configure in ~/.config/ghostty/config with:
  #   keybind = super+c=text:\x1b[99~
bindkey "\e[99~" copy-region-to-clipboard

# Source - https://stackoverflow.com/a/30899296
# Posted by Jamie Treworgy, modified by community. See post 'Timeline' for change history
# Retrieved 2025-11-12, License - CC BY-SA 4.0

# Shift+arrow selection and region handling
r-delregion() {
  if ((REGION_ACTIVE)); then
     zle kill-region
  else 
    local widget_name=$1
    shift
    zle $widget_name -- $@
  fi
}

r-deselect() {
  ((REGION_ACTIVE = 0))
  local widget_name=$1
  shift
  zle $widget_name -- $@
}

r-select() {
  ((REGION_ACTIVE)) || zle set-mark-command
  local widget_name=$1
  shift
  zle $widget_name -- $@
}

for key     kcap   seq        mode   widget (
    sleft   kLFT   $'\e[1;2D' select   backward-char
    sright  kRIT   $'\e[1;2C' select   forward-char
    sup     kri    $'\e[1;2A' select   up-line-or-history
    sdown   kind   $'\e[1;2B' select   down-line-or-history

    send    kEND   $'\E[1;2F' select   end-of-line
    send2   x      $'\E[4;2~' select   end-of-line
    
    shome   kHOM   $'\E[1;2H' select   beginning-of-line
    shome2  x      $'\E[1;2~' select   beginning-of-line

    left    kcub1  $'\EOD'    deselect backward-char
    # right arrow: use default behavior to preserve autocomplete
    # right   kcuf1  $'\EOC'    deselect forward-char

    end     kend   $'\EOF'    deselect end-of-line
    end2    x      $'\E4~'    deselect end-of-line
    
    home    khome  $'\EOH'    deselect beginning-of-line
    home2   x      $'\E1~'    deselect beginning-of-line
    
    # Opt+Shift+Arrow for word selection (modifier 4 = Shift+Alt/Option)
    osleft  x      $'\E[1;4D' select   backward-word
    osright x      $'\E[1;4C' select   forward-word
    osend   x      $'\E[1;4F' select   end-of-line
    oshome  x      $'\E[1;4H' select   beginning-of-line
    
    cleft   x      $'\E[1;5D' deselect backward-word
    cright  x      $'\E[1;5C' deselect forward-word

    del     kdch1   $'\E[3~'  delregion delete-char
    bs      x       $'^?'     delregion backward-delete-char

  ) {
  eval "key-$key() {
    r-$mode $widget \$@
  }"
  zle -N key-$key
  bindkey ${terminfo[$kcap]-$seq} key-$key
}

# restore backward-delete-char for Backspace in the incremental
# search keymap so it keeps working there:
bindkey -M isearch '^?' backward-delete-char
