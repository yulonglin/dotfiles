#!/usr/bin/env bash
# Parse-checks every tracked shell script with the interpreter it declares.
#
# This replaces the two-file `bash -n install.sh && bash -n deploy.sh` check in
# .gitlab-ci.yml, which was checking the wrong thing in two ways:
#
#   1. Wrong interpreter. deploy.sh, install.sh, config.sh and
#      scripts/shared/helpers.sh are all `#!/usr/bin/env zsh`. `bash -n
#      deploy.sh` fails outright on line 768's zsh glob qualifiers
#      (`"$ctx_src"/*.json(N)`) -- a valid line reported as a syntax error.
#   2. Wrong scope. Two files out of ~140 tracked shell scripts, none of the 46
#      shebanged executables in custom_bins/, and none of the hooks.
#
# Dispatch is by shebang rather than by extension, because custom_bins/ carries
# no extensions and config/ carries .sh on files that are zsh-only.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

PASS=0; FAIL=0; SKIP=0

have_zsh=0
command -v zsh >/dev/null 2>&1 && have_zsh=1

check() {
    local file="$1" interp="$2"
    if "$interp" -n "$file" 2>/tmp/syntax-err.$$; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$interp -n] $file"
        sed 's/^/        /' /tmp/syntax-err.$$
    fi
    rm -f /tmp/syntax-err.$$
}

while IFS= read -r f; do
    [ -f "$f" ] || continue

    # `read` on a binary yields nothing useful; the regexes below simply miss,
    # which is the intended outcome for the committed claude-tools binaries.
    IFS= read -r shebang < "$f" 2>/dev/null || continue

    case "$shebang" in
        '#!'*zsh*)
            if [ "$have_zsh" -eq 1 ]; then
                check "$f" zsh
            else
                SKIP=$((SKIP + 1))
            fi
            ;;
        '#!'*bash*|'#!'*/sh|'#!'*'env sh')
            check "$f" bash
            ;;
        *)
            # No shebang. Sourced fragments live here (config/*.sh,
            # config/aliases/*.sh), and they are a mix of bash- and zsh-syntax.
            # Accept if either shell can parse it: the goal is catching typos,
            # not adjudicating dialect on a file that declares none.
            case "$f" in
                *.sh|*.bash|*.zsh)
                    if bash -n "$f" 2>/dev/null; then
                        PASS=$((PASS + 1))
                    elif [ "$have_zsh" -eq 1 ] && zsh -n "$f" 2>/dev/null; then
                        PASS=$((PASS + 1))
                    elif [ "$have_zsh" -eq 0 ]; then
                        SKIP=$((SKIP + 1))
                    else
                        FAIL=$((FAIL + 1))
                        echo "FAIL [neither bash nor zsh can parse] $f"
                        bash -n "$f" 2>&1 | sed 's/^/        /'
                    fi
                    ;;
            esac
            ;;
    esac
done < <(git ls-files | grep -v '^archive/')

echo "syntax: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$SKIP" -gt 0 ]; then
    echo "  ($SKIP skipped because zsh is not installed — CI installs it)"
fi
[ "$FAIL" -eq 0 ]
