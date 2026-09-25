# aliases/brew.sh — `brew upgrade` that leaves running apps alone
#
# A cask upgrade quits a running app or swaps its bundle underneath it. On
# 2026-09-24 that was followed by an avconferenced crash loop that wedged
# CoreAudio and, through it, Safari, Chrome and Spark (docs/macos-media-wedge.md).
# This wrapper only changes a bare `brew upgrade` on macOS: it lists outdated
# casks whose app is running (brew-running-casks), offers to skip them, and
# runs `reset-mac-media --check` afterwards. `command brew upgrade` bypasses it,
# and an upgrade that names packages passes straight through.

if [[ "$OSTYPE" == darwin* ]] && [ -n "${ZSH_VERSION:-}" ]; then
    brew() {
        if [[ "${1:-}" != upgrade ]] || ! (( $+commands[brew-running-casks] )); then
            command brew "$@"
            return
        fi
        shift

        local arg
        local -a greedy=() flags=()
        local only=""
        [[ -n "${HOMEBREW_UPGRADE_GREEDY:-}" ]] && greedy=(--greedy)
        for arg in "$@"; do
            case "$arg" in
                --greedy|--greedy-latest|--greedy-auto-updates) greedy=("$arg") ;;
                --cask|--casks) only=cask ;;
                --formula|--formulae) only=formula ;;
                -*) flags+=("$arg") ;;
                *) command brew upgrade "$@"; return ;;
            esac
        done

        local running=""
        if [[ "$only" != formula ]] && ! running="$(brew-running-casks "${greedy[@]}")"; then
            print -u2 "brew: could not tell which apps are running; not upgrading."
            print -u2 "      'brew upgrade --formula' is safe; 'command brew upgrade' bypasses this guard."
            return 1
        fi
        if [[ -z "$running" ]]; then
            command brew upgrade "$@" || return
            reset-mac-media --check --since 15
            return 0
        fi

        print "These outdated apps are running; upgrading them swaps the app under the live process:"
        print -r -- "$running" | while IFS=$'\t' read -r token app pids audio; do
            if [[ "$audio" == audio ]]; then
                print "  $token  (${app:t})  <- using audio right now"
            else
                print "  $token  (${app:t})"
            fi
        done
        local answer=""
        read "answer?Skip them and upgrade everything else? [Y/n/q] "
        case "$answer" in
            q|Q) return 1 ;;
            n|N) command brew upgrade "$@" || return ;;
            *)
                if [[ "$only" != cask ]]; then
                    command brew upgrade --formula "${flags[@]}" || return
                fi
                local safe_out=""
                if ! safe_out="$(brew-running-casks "${greedy[@]}" --outdated-names)"; then
                    print -u2 "brew: running-app scan failed; skipped all cask upgrades."
                    return 1
                fi
                local -a safe=("${(@f)safe_out}")
                safe=(${safe:#})
                if (( ${#safe} )); then
                    command brew upgrade --cask "${greedy[@]}" "${flags[@]}" "${safe[@]}" || return
                fi
                print "Skipped while running (quit them, then 'brew upgrade --cask <name>'):"
                print -r -- "$running" | cut -f1 | sed 's/^/  /'
                ;;
        esac
        reset-mac-media --check --since 15
        return 0
    }
fi
