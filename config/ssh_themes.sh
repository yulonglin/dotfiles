# shellcheck shell=bash
# shellcheck disable=SC2066,SC2296,SC2034,SC2154,SC2206,SC2051
# ^ zsh-only syntax: (@k) param flags, $match, ${=...}, brace ranges
# -------------------------------------------------------------------
# SSH Ghostty Theme Switching
# -------------------------------------------------------------------
# Deterministically maps SSH hostnames to Ghostty themes via hashing.
# Switches the current terminal's colors on connect, restores on disconnect.
# Uses OSC escape sequences (per-terminal, no config file changes).
#
# Replaces the old SSH_HOST_COLORS system in aliases.sh.
# Sourced by zshrc.sh (Ghostty-only; other terminals get no-op).
# -------------------------------------------------------------------

# Only activate in Ghostty
[[ "$TERM_PROGRAM" != "ghostty" ]] && return 0

# -------------------------------------------------------------------
# Curated dark themes — visually distinct from each other and from
# the default Catppuccin Mocha. Edit this list to customize.
# Names must match `ghostty +list-themes` output exactly.
# -------------------------------------------------------------------
SSH_THEME_LIST=(
  "Dracula"                        # Purple-grey bg, vibrant pastels
  "Nord"                           # Arctic blue-grey, muted
  "TokyoNight"                     # Deep blue, neon accents
  "Rose Pine"                      # Deep purple, lavender
  "Kanagawa Dragon"                # Warm near-black, Japanese ink
  "Gruvbox Dark"                   # Warm brown-grey, retro
  "Everforest Dark Hard"           # Green-grey, forest
  "Solarized Dark Higher Contrast" # Dark teal, high contrast
  "Melange Dark"                   # Warm brown, parchment
  "Material Ocean"                 # Near-black, minimal
  "Night Owl"                      # Navy blue, purple cursor
  "Ayu Mirage"                     # Blue-grey, amber accents
  "Monokai Pro"                    # Warm dark grey, classic
)

# Default theme (must match ghostty.conf)
SSH_DEFAULT_THEME="Catppuccin Mocha"

# Manual overrides: host pattern → theme name (checked before hash)
# Supports zsh glob patterns (e.g., prod* matches prod1, prod-web, etc.)
typeset -A SSH_THEME_OVERRIDES
# SSH_THEME_OVERRIDES[prod*]="Cyberpunk Scarlet Protocol"
# SSH_THEME_OVERRIDES[staging*]="Synthwave"

# Ghostty theme directory
_SSH_THEME_DIR="/Applications/Ghostty.app/Contents/Resources/ghostty/themes"
# Linux fallback
[[ ! -d "$_SSH_THEME_DIR" ]] && _SSH_THEME_DIR="/usr/share/ghostty/themes"

# -------------------------------------------------------------------
# Internal: parse a Ghostty theme file into OSC escape sequences
# -------------------------------------------------------------------
_ssh_theme_to_osc() {
  local theme_name="$1"
  local theme_file="$_SSH_THEME_DIR/$theme_name"

  if [[ ! -f "$theme_file" ]]; then
    # Theme file not found — skip silently
    return 1
  fi

  local line key value idx color
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Parse "key = value" (tolerates missing spaces around =)
    key="${line%%=*}"
    key="${key%% }"
    value="${line#*=}"
    value="${value# }"

    case "$key" in
      background)          printf '\e]11;%s\a' "$value" ;;
      foreground)          printf '\e]10;%s\a' "$value" ;;
      cursor-color)        printf '\e]12;%s\a' "$value" ;;
      selection-background) printf '\e]17;%s\a' "$value" ;;
      selection-foreground) printf '\e]19;%s\a' "$value" ;;
      "palette")
        # "palette = N=#RRGGBB" — already split at first =, so value is "N=#RRGGBB"
        idx="${value%%=*}"
        idx="${idx## }"
        idx="${idx%% }"
        color="${value#*=}"
        color="${color## }"
        # OSC 4;N;color sets palette entry N
        printf '\e]4;%s;%s\a' "$idx" "$color"
        ;;
    esac
  done < "$theme_file"
}

# -------------------------------------------------------------------
# Internal: hash hostname → theme index (deterministic)
# -------------------------------------------------------------------
_ssh_hash_theme() {
  local hostname="$1"
  local count=${#SSH_THEME_LIST[@]}

  # Use cksum for portability (available on macOS + Linux, no external deps)
  local hash
  hash=$(printf '%s' "$hostname" | cksum | awk '{print $1}')

  # Modulo into theme list (zsh arrays are 1-indexed)
  local idx=$(( (hash % count) + 1 ))
  echo "${SSH_THEME_LIST[$idx]}"
}

# -------------------------------------------------------------------
# Internal: resolve hostname → theme (overrides first, then hash)
# -------------------------------------------------------------------
_ssh_resolve_theme() {
  local hostname="$1"

  # Check manual overrides first (glob pattern matching)
  local pattern
  for pattern in "${(@k)SSH_THEME_OVERRIDES}"; do
    if [[ "$hostname" == $~pattern ]]; then
      echo "${SSH_THEME_OVERRIDES[$pattern]}"
      return
    fi
  done

  # Fall back to deterministic hash
  _ssh_hash_theme "$hostname"
}

# -------------------------------------------------------------------
# SSH wrapper: switch theme on connect, restore on disconnect
# -------------------------------------------------------------------
sshc() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: sshc <host> [ssh args...]"
    echo "Run 'ssh-themes' to see host→theme mappings."
    return 1
  fi

  # Find the hostname by scanning past SSH flags
  # Flags with a value argument (e.g., -p 2222) consume the next arg
  local hostname="" arg skip_next=false
  for arg in "$@"; do
    if $skip_next; then skip_next=false; continue; fi
    case "$arg" in
      -[bcDeFIiJLlmOopQRSwWY]) skip_next=true ;;
      -*) ;;
      *) hostname="${arg#*@}"; break ;;
    esac
  done

  # Resolve theme for this host
  local theme
  theme=$(_ssh_resolve_theme "$hostname")

  # Apply theme colors via OSC
  _ssh_theme_to_osc "$theme"

  # Run SSH (pass all original args through)
  command ssh "$@"
  local exit_code=$?

  # Restore default theme + clean up terminal modes
  _ssh_theme_to_osc "$SSH_DEFAULT_THEME"
  _reset_terminal_modes_soft

  return $exit_code
}

# Replace ssh with sshc in Ghostty
alias ssh='sshc'

# -------------------------------------------------------------------
# ssh-themes: preview host → theme mappings
# -------------------------------------------------------------------
ssh-themes() {
  local ssh_config="${HOME}/.ssh/config"
  local hosts=() unique_hosts=()
  local line host_entry _ssh_words _w h theme

  [[ ! -f "$ssh_config" ]] && { echo "No SSH config at $ssh_config"; return 1; }

  echo "Default: $SSH_DEFAULT_THEME"
  echo ""

  # Extract Host lines, skip wildcards
  while IFS= read -r line; do
    if [[ "$line" =~ ^Host[[:space:]]+(.+)$ ]]; then
      _ssh_words=( ${=match[1]} )
      for _w in "${_ssh_words[@]}"; do
        [[ "$_w" == *'*'* ]] && continue
        hosts+=("$_w")
      done
    fi
  done < "$ssh_config"

  for h in "${(uo)hosts[@]}"; do
    theme=$(_ssh_resolve_theme "$h")
    printf "  %-20s → %s\n" "$h" "$theme"
  done
}
