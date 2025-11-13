# ZSH completion functions

# Python module completion for `python -m <module>`
# Finds modules by looking for __main__.py files and standalone .py files
_python_module_complete() {
    local cur="${words[CURRENT]}"
    if [[ "${words[CURRENT-1]}" == "-m" ]]; then
        local modules=()
        # Find __main__.py files
        for dir in $(find . -type f -name "__main__.py" | sed 's|/__main__.py||' | sed 's|^\./||'); do
            modules+=(${dir//\//.})
        done
        # Find standalone .py files
        for file in $(find . -type f -name "*.py" ! -name "__*" | sed 's|\.py$||' | sed 's|^\./||'); do
            modules+=(${file//\//.})
        done
        compadd -a modules
    fi
}

compdef _python_module_complete python python3
