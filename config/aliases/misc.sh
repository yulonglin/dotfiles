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

# `dot`/`jp`/`hn` removed 2026-08-18: dot duplicated `dotfiles` (nav.sh), jp was
# jupyter-lab-era, and hn=hostname collided with the `hn` Hetzner SSH host (srv).
# Manual gist sync (SSH config + authorized_keys + git identity); daily 8AM via launchd/cron
alias sync-gist='"$DOT_DIR/scripts/sync_gist.sh"'
# Define bearcli alias only if Bear is installed (avoids cryptic runtime failures)
# Skipped automatically when /usr/local/bin/bearcli symlink exists (deploy.sh)
[[ -x /Applications/Bear.app/Contents/MacOS/bearcli && ! -x /usr/local/bin/bearcli ]] && \
    alias bearcli='/Applications/Bear.app/Contents/MacOS/bearcli'

# Supply chain defense: rolling 7-day quarantine for uv.
# P7D (ISO-8601 duration) is resolved by uv at invocation time, so it never goes stale —
# unlike the previous $(date ...) form, whose absolute date froze in Claude Code shell
# snapshots and drifted weeks out of date. Duration syntax verified on uv 0.11.x.
export UV_EXCLUDE_NEWER="P7D"
# Supply chain defense: block lockfile syncs (uv add/sync) of packages with OSV MAL advisories
# (uv >=0.11.16, floor enforced in install.sh; preview feature; does NOT cover uv pip/tool install)
export UV_MALWARE_CHECK=1

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

#-------------------------------------------------------------
# music-roulette — random country + genre, for Spotify exploration
#-------------------------------------------------------------

# Draw one genre, then one country from that genre's eligible set, from $1 (a
# music-roulette.tsv path). $2/$3 are random numbers that MUST be expanded by
# the calling shell: zsh does not re-seed $RANDOM in forked subshells, so a
# $RANDOM referenced inside $( ) returns the same value every call and every
# draw comes out identical. bash re-seeds, which hides the bug. Randomising in
# the caller works under both. Emits "country<TAB>genre".
#
# Genre first, then country, is what makes dead pairs unconstructible: a genre
# never sees a country outside its own scope, so "Mongolia Reggaeton" has no
# code path. Drawing the country first would need a rejection loop instead.
_music_roulette_draw() {
    awk -F'\t' -v r1="$2" -v r2="$3" '
        /^#/ || NF == 0 { next }
        $1 == "C" { cn[++nc] = $2; ct[nc] = $3; known[$2] = 1 }
        $1 == "G" { gn[++ng] = $2; gs[ng] = $3 }
        END {
            if (nc == 0 || ng == 0) { exit 3 }
            g = (r1 % ng) + 1
            if (gs[g] == "*mod")        { for (i = 1; i <= nc; i++) if (ct[i] == "1") e[++ne] = cn[i] }
            else if (gs[g] == "*trad")  { for (i = 1; i <= nc; i++)                   e[++ne] = cn[i] }
            else { n = split(gs[g], p, ","); for (i = 1; i <= n; i++) if (p[i] in known) e[++ne] = p[i] }
            if (ne == 0) { exit 4 }
            printf "%s\t%s\n", e[(r2 % ne) + 1], gn[g]
        }
    ' "$1"
}

# music-roulette        one country + genre pairing, with a Spotify search link
# music-roulette 5      five pairings
# music-roulette -o     also open the first pairing's Spotify search
music-roulette() {
    local do_open=0 count=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--open) do_open=1 ;;
            [0-9]*)    count="$1" ;;
            *)         echo "Usage: music-roulette [-o] [count]"; return 1 ;;
        esac
        shift
    done

    local data="${MUSIC_ROULETTE_DATA:-$DOT_DIR/config/data/music-roulette.tsv}"
    if [[ ! -r "$data" ]]; then
        echo "music-roulette: cannot read data file: $data" >&2
        return 1
    fi

    local i draw country genre query url r1 r2
    for ((i = 0; i < count; i++)); do
        # Expand $RANDOM HERE, not inside the $( ) below: zsh evaluates
        # arguments to a command substitution in the forked subshell, where it
        # does not re-seed, so every draw would come out identical.
        r1=$RANDOM
        r2=$RANDOM
        draw=$(_music_roulette_draw "$data" "$r1" "$r2") || {
            echo "music-roulette: no usable country/genre data in $data" >&2
            return 1
        }
        country="${draw%%	*}"
        genre="${draw##*	}"
        query="$country $genre"
        url="https://open.spotify.com/search/${query// /%20}"
        printf '%s — %s\n  %s\n' "$country" "$genre" "$url"
        if (( do_open )); then
            # `o` is the repo's cross-platform opener (config/modern_tools.sh);
            # bare `open` is macOS-only and would silently do nothing on Linux.
            o "$url"
            do_open=0
        fi
    done
}

# Transitional: `smix` was the original name. Kept so muscle memory still works.
# A function, not an alias: zsh expands aliases at parse time, so an alias
# defined by a sourced file is invisible to anything parsed alongside the
# `source` itself (scripts, `zsh -c`). A function resolves at call time.
smix() { music-roulette "$@"; }
