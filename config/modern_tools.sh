#-------------------------------------------------------------
# Modern CLI Tools Enhancements
#-------------------------------------------------------------

# eza: Modern ls enhancement with git integration and colors
if command -v eza &> /dev/null; then
    alias ls='eza'                              # Enhanced ls with colors (widely accepted override)
    alias ll='eza -l --git'                     # Long format with git status indicators
    alias la='eza -la --git'                    # Show all files including hidden, with git status
    alias lt='eza -l --sort=modified --reverse' # Sort by modification time, newest first
    alias tree='eza --tree'                     # Tree view of directories
fi

# bat: Enhanced file viewer with syntax highlighting
if command -v bat &> /dev/null; then
    alias view='bat'                            # Enhanced file viewer with syntax highlighting
    alias less='bat --paging=always'           # Use bat as pager with syntax highlighting
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"  # Use bat for colorized man pages
    alias plaincat='command cat'               # Access original cat when needed
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
# Shows git status in compact format with current branch (renamed to avoid conflict with existing gst alias)
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
# delta: Better diffs with syntax highlighting
#-------------------------------------------------------------
# delta is configured in gitconfig for git operations
# This alias makes it available for standalone file diffs
if command -v delta &> /dev/null; then
    alias diff='delta'                         # Use delta for standalone diffs
fi