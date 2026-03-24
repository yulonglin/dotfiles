#-------------------------------------------------------------
# Modern CLI Tools Enhancements
#-------------------------------------------------------------

# eza: Modern ls replacement with git integration and colors
# ALL ls/tree aliases live here — single source of truth
if command -v eza &> /dev/null; then
    alias ls='eza'
    alias l='eza -F'                                 # Classify with type indicators
    alias ll='eza -lah --git'                        # Long, hidden, headers, git status
    alias la='eza -lah --git'                        # Same as ll (muscle memory)
    alias lt='eza -l --sort=modified --reverse'      # Sort by modification time, newest last
    alias tree='eza --tree --icons --git-ignore'     # Tree view with icons
    alias t1='eza --tree --level=1'
    alias t2='eza --tree --level=2'
    alias t3='eza --tree --level=3'
else
    alias l='ls -CF --color=auto'
    alias ll='ls -lah --group-directories-first'
    alias la='ls -Al'
    alias lt='ls -ltr'                               # Sort by date, most recent last
    alias t1='tree -L 1'
    alias t2='tree -L 2'
    alias t3='tree -L 3'
fi

# bat: Enhanced file viewer with syntax highlighting
if command -v bat &> /dev/null; then
    alias view='bat'                            # Enhanced file viewer with syntax highlighting
    alias bat-less='bat --paging=always'        # bat as pager (not overriding less — different flags)
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"  # Use bat for colorized man pages
fi

# fd: Fast file finder (available as separate command)
if command -v fd &> /dev/null; then
    alias findfile='fd'                         # Access to fd tool without conflicting with existing fd alias
    alias findf='fd'                            # Short alternative
fi

# ripgrep: Ultra-fast text search tool
if command -v rg &> /dev/null; then
    alias search='rg'                           # Enhanced search without overriding grep
    alias rgrep='rg'                            # Alternative name
    alias plaingrep='command grep'              # Access original grep when needed
fi

#-------------------------------------------------------------
# Git enhancements with fzf (fuzzy finder integration)
#-------------------------------------------------------------

# fgb: Fuzzy Git Branch - Interactive branch switcher
# Usage: fgb
# Shows all branches (local and remote) in fzf for quick switching
fgb() {
    git branch -a | grep -v HEAD | sed 's/^[ *]*//' | sed 's/^remotes\///g' | sort -u | fzf --height=20% --reverse --info=inline | xargs git checkout
}

# fgc: Fuzzy Git Commit - Interactive commit viewer
# Usage: fgc
# Browse git commits with preview and show selected commit details
fgc() {
    git log --oneline --color=always | fzf --ansi --height=50% --reverse --info=inline --preview 'git show --color=always {1} | head -50' | cut -d' ' -f1 | xargs git show
}

# fga: Fuzzy Git Add - Interactive file staging
# Usage: fga
# Select multiple files from git status to stage with preview of changes
fga() {
    git status --porcelain | fzf -m --height=20% --reverse --info=inline --preview 'git diff --color=always {2}' | awk '{print $2}' | xargs git add
}

#-------------------------------------------------------------
# fzf enhancements (fuzzy finder configuration)
#-------------------------------------------------------------

# Set fzf default appearance and behavior
# --height=50%: Use half the terminal height
# --layout=reverse: Show input at top, results below
# --border: Add border around fzf interface
# --inline-info: Show info on same line as input
export FZF_DEFAULT_OPTS="--height=50% --layout=reverse --border --inline-info"

# Configure fzf to use fd for better file finding
if command -v fd &> /dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'  # Find files, include hidden, follow symlinks, exclude .git
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"                           # Use same command for Ctrl-T file finder
fi

# fcd: Fuzzy Change Directory - Interactive directory navigation
# Usage: fcd [starting_directory]
# Navigate to any directory using fuzzy search
fcd() {
    local dir
    dir=$(find ${1:-.} -path '*/\.*' -prune -o -type d -print 2> /dev/null | fzf +m) && cd "$dir"
}

# fkill: Fuzzy Kill Process - Interactive process termination
# Usage: fkill [signal_number]
# Select processes to kill interactively, default signal is 9 (SIGKILL)
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')  # Show all processes, let user select multiple
    [ -n "$pid" ] && echo $pid | xargs kill -${1:-9}    # Kill selected processes with specified signal (default 9)
}

#-------------------------------------------------------------
# Development shortcuts
#-------------------------------------------------------------

# venv: Smart Python Virtual Environment Activator
# Usage: venv
# Automatically finds and activates Python venv in current directory
# Looks for: venv/, .venv/, or env/ directories
venv() {
    if [ -d "venv" ]; then
        source venv/bin/activate               # Standard venv directory
    elif [ -d ".venv" ]; then
        source .venv/bin/activate              # Hidden venv directory (common in modern projects)
    elif [ -d "env" ]; then
        source env/bin/activate                # Alternative env directory name
    else
        echo "No virtual environment found"    # No venv found in current directory
    fi
}

# gss: Git Status Short - Enhanced git status with branch info
# Usage: gss
# Shows git status in compact format with current branch
# Note: unalias first since oh-my-zsh git plugin defines gss='git status -s'
unalias gss 2>/dev/null || true
gss() {
    git status --short --branch  # --short: compact format, --branch: show branch info
}

# hist: Enhanced History Search
# Usage: hist [search_terms]
# Interactive history search with fzf, or traditional grep if arguments provided (renamed to avoid conflict with existing h alias)
hist() {
    if [ $# -eq 0 ]; then
        history | fzf --tac --no-sort          # Interactive search: --tac (reverse), --no-sort (keep chronological order)
    else
        history | grep "$@"                    # Traditional grep search if arguments provided
    fi
}

#-------------------------------------------------------------
# JSON/Data processing shortcuts
#-------------------------------------------------------------

# json: Smart JSON Pretty Printer
# Usage: json [file] OR echo '{"key":"value"}' | json
# Pretty prints JSON from file or stdin with syntax highlighting
json() {
    if [ -t 0 ]; then
        jq . "$1"                              # If stdin is terminal, read from file argument
    else
        jq .                                   # If stdin is piped, read from pipe
    fi
}

# jpath: JSON Path Extractor
# Usage: jpath '.path.to.field' file.json
# Extract specific fields from JSON files using jq path syntax
jpath() {
    jq -r "$1" "$2"                            # -r: raw output (no quotes), $1: jq path, $2: file
}

#-------------------------------------------------------------
# Network and system utilities
#-------------------------------------------------------------

# myip: Get Public IP Address
# Usage: myip
# Fetches your public IP address from external service
myip() {
    curl -s ifconfig.me                        # -s: silent mode, fetches public IP
}

# localip: Get Local IP Address
# Usage: localip
# Shows all local network IP addresses (excludes loopback 127.0.0.1)
localip() {
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'  # Extract local network IPs
}

# port: Check What's Using a Port
# Usage: port 8080
# Shows process ID using the specified port number
port() {
    lsof -ti:$1                                # -t: terse output (PID only), -i: internet connections, :$1: specific port
}

# Additional disk usage option (doesn't conflict with existing usage alias)
alias disksize='eza -la --total-size'          # Enhanced disk usage with eza (when available)

#-------------------------------------------------------------
# Additional modern tool alternatives
#-------------------------------------------------------------

# Add new disk usage options without replacing the working usage alias
dirsize() {
    if command -v eza &> /dev/null; then
        eza -la --total-size                   # Use eza with total size calculation
    else
        du -sh * 2>/dev/null | sort -rh | head -20  # Traditional: disk usage, sort by size, show top 20
    fi
}

#-------------------------------------------------------------
# zoxide: Smarter directory jumping
#-------------------------------------------------------------
# Usage: z <partial-path>  |  zi (interactive with fzf)
# Note: Intentionally NOT aliasing cd='z' - z is probabilistic, cd is explicit
# zoxide init is in zshrc.sh

#-------------------------------------------------------------
# dust: Modern du with visual size breakdown (NOT aliasing du — different flags)
# Usage: dust (current dir), dust <path>

# duf: Modern df with color table (NOT aliasing df — different flags)
# Usage: duf

# htop: Better top (NOT aliasing top — different flags)
# Usage: htop

# delta: Better diffs with syntax highlighting
# delta is configured in gitconfig for git operations (NOT aliasing diff — different interface)
# Usage: delta <file1> <file2>

#-------------------------------------------------------------
# Utility functions (inspired by mathiasbynens/dotfiles)
#-------------------------------------------------------------

# mkd: Create directory and cd into it
mkd() {
    command mkdir -p "$1" && cd "$1"
}

# cdf: cd to the frontmost Finder window (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
    cdf() {
        local target
        target="$(osascript -e 'tell application "Finder" to if (count of Finder windows) > 0 then get POSIX path of (target of front Finder window as text)' 2>/dev/null)"
        if [[ -z "$target" ]]; then
            echo "No Finder window found" >&2
            return 1
        fi
        cd "$target" || return
    }
fi

# targz: Create a .tar.gz archive using best available compression
targz() {
    local tmpFile="${1%/}.tar"
    tar -cf "$tmpFile" "${1}" || return 1

    local size
    size=$(stat -f"%z" "$tmpFile" 2>/dev/null || stat -c"%s" "$tmpFile" 2>/dev/null)

    local cmd=""
    if (( size < 52428800 )) && command -v zopfli &>/dev/null; then
        cmd="zopfli"
    elif command -v pigz &>/dev/null; then
        cmd="pigz"
    else
        cmd="gzip"
    fi

    echo "Compressing with ${cmd}..."
    "${cmd}" -f "$tmpFile" || return 1
    [ -f "${tmpFile}" ] && rm "$tmpFile"

    local gzFile="${tmpFile}.gz"
    local origSize
    origSize=$(stat -f"%z" "${1}" 2>/dev/null || stat -c"%s" "${1}" 2>/dev/null)
    local gzSize
    gzSize=$(stat -f"%z" "$gzFile" 2>/dev/null || stat -c"%s" "$gzFile" 2>/dev/null)
    echo "${gzFile} ($(( origSize / 1000 ))kB → $(( gzSize / 1000 ))kB)"
}

# dataurl: Create a base64 data URL from a file
dataurl() {
    local mimeType
    mimeType=$(file -b --mime-type "$1")
    if [[ "$mimeType" == text/* ]]; then
        mimeType="${mimeType};charset=utf-8"
    fi
    echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')"
}

# digga: All DNS records for a domain
digga() {
    if \! command -v dig &>/dev/null; then
        echo "dig not found — install via: brew install bind" >&2
        return 1
    fi
    dig +nocmd "$1" any +multiline +noall +answer
}

# getcertnames: Show CN and SANs for an SSL certificate
getcertnames() {
    if [[ -z "$1" ]]; then
        echo "Usage: getcertnames <domain>" >&2
        return 1
    fi

    local domain="${1}"
    echo "Testing ${domain}..."

    local tmp
    tmp=$(echo -e "GET / HTTP/1.0\nEOT" \
        | openssl s_client -connect "${domain}:443" -servername "${domain}" 2>&1)

    if [[ "${tmp}" == *"-----BEGIN CERTIFICATE-----"* ]]; then
        local certText
        certText=$(echo "${tmp}" \
            | openssl x509 -text -certopt "no_aux, no_header, no_issuer, no_pubkey, \
            no_serial, no_sigdump, no_signame, no_validity, no_version")
        echo ""
        echo "Common Name:"
        echo "${certText}" | grep "Subject:" | sed -e "s/^.*CN=//" | sed -e "s/\/.*$//"
        echo ""
        echo "Subject Alternative Name(s):"
        echo "${certText}" | grep -A 1 "Subject Alternative Name:" \
            | sed -e "2s/DNS://g" -e "s/ //g" | tr "," "\n" | tail -n +2
    else
        echo "ERROR: Certificate not found." >&2
        return 1
    fi
}

# o: Cross-platform open command
o() {
    if [[ $# -eq 0 ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            open .
        elif command -v xdg-open &>/dev/null; then
            xdg-open .
        fi
    else
        if [[ "$(uname)" == "Darwin" ]]; then
            open "$@"
        elif command -v xdg-open &>/dev/null; then
            xdg-open "$@"
        fi
    fi
}

# server: Start a simple HTTP server in the current directory
server() {
    python3 -m http.server "${1:-8000}"
}
