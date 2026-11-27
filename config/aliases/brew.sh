# aliases/brew.sh — `brew upgrade` that leaves running apps alone
#
# A cask upgrade quits a running app or swaps its bundle underneath it. On
# 2026-09-24 that was followed by an avconferenced crash loop that wedged
# CoreAudio and, through it, Safari, Chrome and Spark (docs/macos-media-wedge.md).
# This wrapper only changes a bare `brew upgrade` on macOS: it lists outdated
# casks whose app is running (brew-running-casks), offers to skip them or quit
# and relaunch them around the upgrade, and runs `reset-mac-media --check` afterwards.
# `command brew upgrade` bypasses it, and an upgrade that names packages passes
# straight through. After a formula upgrade it also offers to remove formulae
# nothing needs (_brew_tidy).

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
            [[ "$only" == cask ]] || _brew_tidy
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
        local -a quit_tokens=() quit_apps=() quit_pids=()
        read "answer?Skip them and upgrade everything else? [Y/n/q, a = quit, upgrade & restart] "
        if [[ "$answer" == [aA] ]]; then
            _brew_quit_running "$running"
            answer=y
        fi
        case "$answer" in
            q|Q) return 1 ;;
            n|N) command brew upgrade "$@" || return ;;
            *)
                local rc=0 scanned=0
                local -a safe=()
                if [[ "$only" != cask ]]; then
                    command brew upgrade --formula "${flags[@]}" || rc=$?
                fi
                if (( rc == 0 )); then
                    local safe_out=""
                    if ! safe_out="$(brew-running-casks "${greedy[@]}" --outdated-names)"; then
                        print -u2 "brew: running-app scan failed; skipped all cask upgrades."
                        rc=1
                    else
                        scanned=1
                        safe=("${(@f)safe_out}")
                        safe=(${safe:#})
                        if (( ${#safe} )); then
                            command brew upgrade --cask "${greedy[@]}" "${flags[@]}" "${safe[@]}" || rc=$?
                        fi
                    fi
                fi
                if (( ${#quit_apps} )); then
                    _brew_relaunch_quit
                fi
                (( rc == 0 )) || return "$rc"
                # Ask brew what is still outdated rather than reprinting the first
                # scan: an app quit at the prompt is upgraded by the second scan.
                local still=""
                if still="$(command brew outdated --cask --quiet "${greedy[@]}")" && [[ -n "$still" ]]; then
                    print "Not upgraded (quit them, then 'brew upgrade --cask <name>'):"
                    print -r -- "$still" | sed 's/^/  /'
                fi
                ;;
        esac
        [[ "$only" == cask ]] || _brew_tidy
        reset-mac-media --check --since 15
        return 0
    }

    # Offer to remove formulae nothing needs. Homebrew autoremoves only on
    # `brew uninstall` and its 30-day periodic cleanup, and never drops a
    # dependency that an out-of-date install record still lists (2026-10-30:
    # poppler's record held icu4c@78). brew-orphans finds both; the answer
    # defaults to yes, and end of input (a pipe, a script) means no.
    _brew_tidy() {
        [[ -z "${HOMEBREW_NO_AUTOREMOVE:-}" ]] || return 0
        (( $+commands[brew-orphans] )) || return 0
        local color=never report="" rc=0
        [[ -t 1 && -z "${NO_COLOR:-}" ]] && color=always
        report="$(brew-orphans --color="$color")" || rc=$?
        (( rc == 1 )) || return 0
        print -r -- "$report"
        local answer=""
        read "answer?Remove them now? [Y/n] " || return 0
        [[ "$answer" == [nN]* ]] && return 0
        local -a holders=("${(@f)$(brew-orphans --reinstall-names)}")
        holders=(${holders:#})
        if (( ${#holders} )); then
            command brew reinstall "${holders[@]}" || return 0
        fi
        command brew autoremove
    }

    # Quit each listed app the normal way (it may ask to save), then wait up to
    # BREW_QUIT_WAIT (30) s for its processes to exit. Populates the caller's
    # quit_tokens/quit_apps/quit_pids with each app asked to quit so
    # _brew_relaunch_quit can reopen the ones that actually stopped after the
    # upgrade. The default branch rescans afterwards, so an app that refused to
    # quit is skipped and reported, never swapped live. The app hosting this
    # shell is left alone: quitting it would kill the upgrade.
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
            [[ -n "$token" ]] || continue
            # A cask whose bundle path could not be resolved has no app to quit
            # or relaunch; leave it for the rescan to report.
            if [[ "$app" != /* || "$pids" == "?" ]]; then
                print "  $token: bundle path unknown, left running"
                continue
            fi
            # A tmux pane's parent is the tmux server, not the terminal attached
            # to it now, so neither check below can find that terminal. Never
            # quit a terminal app; the rescan reports it as not upgraded.
            if [[ "$token" == (ghostty|iterm2|warp|kitty|wezterm|alacritty|tabby|hyper)* ]]; then
                print "  $token: a terminal app, left running"
                continue
            fi
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
            quit_tokens+=("$token")
            quit_apps+=("$app")
            quit_pids+=("$pids")
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

    # Relaunch apps that _brew_quit_running quit, in the background so they do
    # not steal terminal focus. When the rescan ran, only apps confirmed no
    # longer running (present in safe) are relaunched, so an app that refused
    # to quit is never touched. If an earlier step failed before the rescan,
    # fall back to checking whether the app's tracked PIDs exited so quit apps
    # are not left closed.
    _brew_relaunch_quit() {
        local idx token app pid alive
        for (( idx = 1; idx <= ${#quit_apps}; idx++ )); do
            token="${quit_tokens[$idx]}"
            app="${quit_apps[$idx]}"
            if (( scanned )); then
                (( ${safe[(Ie)$token]} )) || continue
            else
                alive=0
                for pid in ${(s:,:)quit_pids[$idx]}; do
                    [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null && alive=1
                done
                (( alive )) && continue
            fi
            print "  restarting ${app:t:r}"
            open -g "$app" >/dev/null 2>&1 \
                || print -u2 "  ${app:t:r}: restart failed"
        done
    }
fi
