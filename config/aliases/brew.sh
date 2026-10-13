# aliases/brew.sh — `brew upgrade` that leaves running apps alone
#
# A cask upgrade quits a running app or swaps its bundle underneath it. On
# 2026-09-24 that was followed by an avconferenced crash loop that wedged
# CoreAudio and, through it, Safari, Chrome and Spark (docs/macos-media-wedge.md).
# This wrapper only changes a bare `brew upgrade` on macOS: it lists outdated
# casks whose app is running (brew-running-casks), offers to skip them or quit
# them first, and runs `reset-mac-media --check` afterwards. `command brew upgrade` bypasses it,
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
        if [[ -n "${HOMEBREW_UPGRADE_GREEDY:-}" ]]; then greedy=(--greedy); fi
        for arg in "$@"; do
            case "$arg" in
                -g|--greedy) greedy+=(--greedy) ;;
                --greedy-latest|--greedy-auto-updates) greedy+=("$arg") ;;
                --cask|--casks) only=cask ;;
                --formula|--formulae) only=formula ;;
                -*) flags+=("$arg") ;;
                *) command brew upgrade "$@"; return ;;
            esac
        done

        # Refresh once, then scan and upgrade against the same metadata, so the
        # upgrade cannot auto-update into a new version the scan never saw.
        if [[ -z "${HOMEBREW_NO_AUTO_UPDATE:-}" ]]; then
            command brew update || return
        fi
        local -x HOMEBREW_NO_AUTO_UPDATE=1

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
            elif [[ "$audio" == unknown ]]; then
                print "  $token  $app  <- cannot tell if it is running; treated as running"
            else
                print "  $token  (${app:t})"
            fi
        done
        local answer=""
        read "answer?Skip them and upgrade everything else? [Y/n/q, a = quit them first] "
        if [[ "$answer" == [aA] ]]; then
            _brew_quit_running "$running"
            answer=y
        fi
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
                # Ask brew what is still outdated rather than reprinting the first
                # scan: an app quit at the prompt is upgraded by the second scan.
                local still=""
                if still="$(command brew outdated --cask --quiet "${greedy[@]}")" && [[ -n "$still" ]]; then
                    print "Not upgraded (quit them, then 'brew upgrade --cask <name>'):"
                    print -r -- "$still" | sed 's/^/  /'
                fi
                ;;
        esac
        reset-mac-media --check --since 15
        return 0
    }

    # Quit each listed app the normal way (it may ask to save), then wait up to
    # BREW_QUIT_WAIT (30) s for its processes to exit. The default branch
    # rescans afterwards, so an app that refused to quit is skipped and
    # reported, never swapped live. The app hosting this shell is left alone:
    # quitting it would kill the upgrade.
    _brew_quit_running() {
        local -a ancestors=()
        local p=$$
        while [[ "$p" == <-> ]] && (( p > 1 )); do
            ancestors+=("$p")
            p="$(/bin/ps -o ppid= -p "$p" 2>/dev/null)"
            p="${p// /}"
        done

        local token app pids pid hosting
        local -a waiting=()
        while IFS=$'\t' read -r token app pids _; do
            hosting=0
            for pid in ${(s:,:)pids}; do
                (( ${ancestors[(Ie)$pid]} )) && hosting=1
            done
            # A shell started by an app inherits its bundle ID, which still
            # holds when ps cannot walk the process tree (a sandbox, say).
            if [[ -n "${__CFBundleIdentifier:-}" ]] && [[ "$(/usr/libexec/PlistBuddy \
                    -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" \
                    == "$__CFBundleIdentifier" ]]; then
                hosting=1
            fi
            if (( hosting )); then
                print "  $token: hosts this shell, left running"
                continue
            fi
            print "  quitting ${app:t:r}"
            osascript -e "quit app \"${app:t:r}\"" >/dev/null 2>&1 \
                || print -u2 "  ${app:t:r}: quit request failed"
            for pid in ${(s:,:)pids}; do
                [[ "$pid" == <-> ]] && waiting+=("$pid")
            done
        done <<< "$1"

        local i
        for (( i = 0; i < ${BREW_QUIT_WAIT:-30} && ${#waiting}; i++ )); do
            waiting=(${waiting:#})
            for pid in "${waiting[@]}"; do
                kill -0 "$pid" 2>/dev/null || waiting=(${waiting:#$pid})
            done
            (( ${#waiting} )) && sleep 1
        done
    }
fi
