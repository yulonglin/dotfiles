# aliases/core.sh — core utilities: safety-wrapped file ops, find, storage, venv/conda

# -------------------------------------------------------------------
# general
# -------------------------------------------------------------------

# file and directories
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'

# find/read files
# Note: NOT aliasing find="fd" - they have different syntax
# Use fd directly, or findfile/findf aliases from modern_tools.sh
alias ff='fd --type f'
# fd-find package on Debian/Ubuntu installs as 'fdfind'
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    alias fd='fdfind'
fi
alias which='type -a'

# storage: use dust (du) and duf (df) directly — modern_tools.sh

# add to path
function add_to_path() {
    p=$1
    if [[ "$PATH" != *"$p"* ]]; then
      export PATH="$p:$PATH"
    fi
}

#-------------------------------------------------------------
# env
#-------------------------------------------------------------
# Homebrew's python@3.14 (config/apps.conf) ships python3 but no bare python
command -v python >/dev/null 2>&1 || alias python=python3
alias sv="source .venv/bin/activate"
alias de="deactivate"

alias fda='fd -HI'  # fd all (include hidden + gitignored)
