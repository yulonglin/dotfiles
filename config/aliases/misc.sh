# aliases/misc.sh — personal aliases, Ghostty themes, call helpers, Things 3, miscellaneous

# -------------------------------------------------------------------
# Source additional alias files
# -------------------------------------------------------------------
if [ -f "$DOT_DIR/config/aliases_inspect.sh" ]; then
    source "$DOT_DIR/config/aliases_inspect.sh"
fi

# -------------------------------------------------------------------
# personal
# -------------------------------------------------------------------

alias dot="cd $DOT_DIR"
alias jp="jupyter lab"
alias hn="hostname"
# Manual gist sync (SSH config + authorized_keys + git identity); daily 8AM via launchd/cron
alias sync-gist='"$DOT_DIR/scripts/sync_gist.sh"'
# Define bearcli alias only if Bear is installed (avoids cryptic runtime failures)
# Skipped automatically when /usr/local/bin/bearcli symlink exists (deploy.sh)
[[ -x /Applications/Bear.app/Contents/MacOS/bearcli && ! -x /usr/local/bin/bearcli ]] && \
    alias bearcli='/Applications/Bear.app/Contents/MacOS/bearcli'

# Supply chain defense: 7-day quarantine for uv (exclude-newer needs absolute date)
export UV_EXCLUDE_NEWER="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

#-------------------------------------------------------------
# Ghostty themed windows
#-------------------------------------------------------------

# Launch Ghostty with a specific theme
# Uses window-save-state=never to prevent window restoration (single fresh window)
gtheme() {
    local theme=""
    local title=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--title)
                title="${2:-}"
                shift 2
                ;;
            --title=*)
                title="${1#*=}"
                shift
                ;;
            -h|--help)
                echo "Usage: gtheme <theme-name> [title] [--title <title>]"
                echo "Example: gtheme 'Catppuccin Mocha' 'Docs'"
                echo "Example: gtheme 'Catppuccin Mocha' --title 'Docs'"
                echo ""
                echo "List themes: ghostty +list-themes"
                return 0
                ;;
            *)
                if [[ -z "$theme" ]]; then
                    theme="$1"
                elif [[ -z "$title" ]]; then
                    title="$1"
                else
                    echo "Error: unexpected argument '$1'"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$theme" ]]; then
        echo "Usage: gtheme <theme-name> [title] [--title <title>]"
        echo "Example: gtheme 'Catppuccin Mocha' 'Docs'"
        echo "Example: gtheme 'Catppuccin Mocha' --title 'Docs'"
        echo ""
        echo "List themes: ghostty +list-themes"
        return 1
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use open, disable window restoration for fresh single window
        if [[ -n "$title" ]]; then
            open -na Ghostty --args --window-save-state=never --theme="$theme" --title="$title"
        else
            open -na Ghostty --args --window-save-state=never --theme="$theme"
        fi
    else
        # Linux: launch directly
        if [[ -n "$title" ]]; then
            ghostty --window-save-state=never --theme="$theme" --title="$title" &
        else
            ghostty --window-save-state=never --theme="$theme" &
        fi
        disown
    fi
}

# Quick theme aliases - 10 dark themes, diverse backgrounds + cursors
# Default (ghostty.conf): Catppuccin Mocha — pastel purple-blue, pink cursor
# Run `ghostty +list-themes` for full list, or `gtheme <name>` for any theme
g0() { gtheme "TokyoNight" --title "${1:+$1 | }🌙 [g0] TokyoNight"; }             # Deep blue bg, blue cursor — neon city
g1() { gtheme "Dracula" --title "${1:+$1 | }🧛 [g1] Dracula"; }                 # Purple-grey bg, white cursor — vibrant classic
g2() { gtheme "Nord" --title "${1:+$1 | }❄️ [g2] Nord"; }                        # Arctic blue-grey bg, white cursor — calm
g3() { gtheme "Rose Pine" --title "${1:+$1 | }🌹 [g3] Rose Pine"; }              # Deep purple bg, lavender cursor — botanical
g4() { gtheme "Kanagawa Dragon" --title "${1:+$1 | }🐉 [g4] Kanagawa Dragon"; }  # Warm near-black bg, warm cursor — Japanese ink
g5() { gtheme "Gruvbox Dark" --title "${1:+$1 | }🍂 [g5] Gruvbox Dark"; }        # Neutral warm bg, cream cursor — retro
g6() { gtheme "Everforest Dark Hard" --title "${1:+$1 | }🌲 [g6] Everforest"; }   # Green-grey bg, orange cursor — forest
g7() { gtheme "Solarized Dark Higher Contrast" --title "${1:+$1 | }☀️ [g7] Solarized"; } # Dark teal bg, red-orange cursor
g8() { gtheme "Melange Dark" --title "${1:+$1 | }🪨 [g8] Melange Dark"; }         # Warm brown bg, parchment cursor — earthy
g9() { gtheme "Material Ocean" --title "${1:+$1 | }🌊 [g9] Material Ocean"; }     # Near-black bg, yellow cursor — minimal

# "About to take a call" — quit bandwidth/CPU hogs before joining.
# Best-effort; missing apps are silently skipped. Run callend afterwards.
callprep() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo "callprep is macOS-only (uses osascript to quit GUI apps)"
        return 1
    fi
    echo "Quitting sync clients & VPN for call..."
    osascript -e 'quit app "NordVPN"'      2>/dev/null && echo "  NordVPN: quit"
    osascript -e 'quit app "Dropbox"'      2>/dev/null && echo "  Dropbox: quit"
    osascript -e 'quit app "Google Drive"' 2>/dev/null && echo "  Google Drive: quit"
    osascript -e 'quit app "Backblaze"'    2>/dev/null && echo "  Backblaze: quit"
    # Quiet iCloud transfers (cloudd/bird respawn but pause briefly)
    killall bird cloudd 2>/dev/null && echo "  iCloud daemons: signalled"
    echo "Done. Run 'callend' afterwards to restart sync."
}

callend() {
    if [[ "$(uname)" != "Darwin" ]]; then return 1; fi
    open -a "Dropbox"      2>/dev/null && echo "  Dropbox: opened"
    open -a "Google Drive" 2>/dev/null && echo "  Google Drive: opened"
    open -a "Backblaze"    2>/dev/null && echo "  Backblaze: opened"
    # NordVPN: not auto-restarted (you may not want VPN back on for the rest of the session).
    # iCloud daemons (cloudd/bird) respawn on their own via launchd.
    echo "Sync clients restarted. Re-enable NordVPN manually if needed."
}

#-------------------------------------------------------------
# Things 3 (things-cloud-mcp)
#-------------------------------------------------------------

things() {
    local cmd="${1:-status}"
    case "$cmd" in
        status)
            if [[ "$(uname)" == "Darwin" ]]; then
                echo "macOS: using things-mcp plugin (local SQLite)"
                pgrep -f things-mcp >/dev/null 2>&1 && echo "  running" || echo "  not running (plugin starts on demand)"
            else
                systemctl --user is-active things-cloud-mcp >/dev/null 2>&1 \
                    && echo "things-cloud-mcp: active" \
                    || echo "things-cloud-mcp: inactive"
                curl -s -m 2 http://127.0.0.1:8080/ 2>/dev/null \
                    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  {d[\"status\"]}') " 2>/dev/null \
                    || echo "  server unreachable"
            fi
            ;;
        start)   systemctl --user start things-cloud-mcp && echo "started" ;;
        stop)    systemctl --user stop things-cloud-mcp && echo "stopped" ;;
        restart) systemctl --user restart things-cloud-mcp && echo "restarted" ;;
        logs)    journalctl --user -u things-cloud-mcp -f --no-pager ;;
        today)
            curl -s http://127.0.0.1:8080/api/tasks/today 2>/dev/null \
                | python3 -c "import sys,json; [print(f'  - {t[\"Title\"]}') for t in json.load(sys.stdin)]" 2>/dev/null \
                || echo "server unreachable"
            ;;
        *)
            echo "Usage: things {status|start|stop|restart|logs|today}"
            ;;
    esac
}
