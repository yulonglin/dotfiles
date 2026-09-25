# aliases/brew.sh — `brew upgrade` that leaves running apps alone
#
# A cask upgrade swaps an app's bundle on disk under the running process. On
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
        for arg in "$@"; do
            case "$arg" in
                --greedy|--greedy-latest|--greedy-auto-updates) greedy=(--greedy) ;;
                --cask|--casks) only=cask ;;
                --formula|--formulae) only=formula ;;
                -*) flags+=("$arg") ;;
                *) command brew upgrade "$@"; return ;;
            esac
        done

        local running=""
        [[ "$only" == formula ]] || running="$(brew-running-casks "${greedy[@]}")"
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
                local -a safe=("${(@f)$(brew-running-casks "${greedy[@]}" --outdated-names)}")
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
