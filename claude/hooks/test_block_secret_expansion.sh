#!/usr/bin/env bash
# shellcheck disable=SC2016  # test commands are data; expanding them would leak
# Tests for block_secret_expansion.sh
# Run: bash claude/hooks/test_block_secret_expansion.sh

HOOK="$(cd "$(dirname "$0")" && pwd)/block_secret_expansion.sh"
PASS=0
FAIL=0

run_test() {
    local desc="$1" cmd="$2" expect="$3" tool="${4:-Bash}"
    local input
    input=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': sys.argv[2],
                  'tool_input': {'command': sys.argv[1]}}))" "$cmd" "$tool")
    local rc=0
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
    if [ "$expect" = "block" ] && [ "$rc" -eq 2 ]; then
        PASS=$((PASS + 1))
    elif [ "$expect" = "allow" ] && [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got exit %d)\n' "$desc" "$expect" "$rc"
    fi
}

echo "=== SHOULD BLOCK: wholesale environment dumps ==="
run_test "bare env"                'env'                              block
run_test "env piped to grep"       'env | grep -i key'                block
run_test "env with only -u"        'env -u FOO'                       block
run_test "bare printenv"           'printenv'                         block
run_test "printenv secret"         'printenv ANTHROPIC_API_KEY'       block
run_test "printenv -0"             'printenv -0'                      block
run_test "bare export"             'export'                           block
run_test "export -p"               'export -p'                        block
run_test "bare set"                'set'                              block
run_test "declare -p"              'declare -p'                       block
run_test "declare -x"              'declare -x'                       block
run_test "typeset -p"              'typeset -p'                       block
run_test "direnv export"           'direnv export bash'               block
run_test "direnv dump"             'direnv dump'                      block
run_test "dump after innocuous"    'ls -la; env'                      block
run_test "dump behind &&"          'cd /tmp && printenv'              block
run_test "quote-obfuscated"        'pri""ntenv'                       block
run_test "path-qualified"          '/usr/bin/printenv'                block

echo "=== SHOULD BLOCK: non-empty default on a secret-named variable ==="
run_test "the original leak"       'echo "${ANTHROPIC_API_KEY:-not set}"'      block
run_test "assign-default"          'echo "${OPENAI_API_KEY:=missing}"'         block
run_test "no-colon dash form"      'V=${HF_TOKEN-fallback}; echo done'         block
run_test "no-colon equals form"    'V=${GH_PAT=fallback}; echo done'           block
run_test "outside a print sink"    'curl -H "auth: ${BWS_ACCESS_TOKEN:-none}" http://x'  block
run_test "lowercase name"          'echo "${anthropic_api_key:-unset}"'        block
# ${VAR:?msg} expands to the VALUE when VAR is set -- it only errors when unset,
# so it is a leak, not a presence test.
run_test "error-if-unset form"     'echo "${ANTHROPIC_API_KEY:?not set}"'      block

echo "=== SHOULD BLOCK: secret-named variable in a print sink ==="
run_test "echo bare"               'echo $HF_TOKEN'                            block
run_test "echo double-quoted"      'echo "$AWS_SECRET_ACCESS_KEY"'             block
run_test "echo braced"            'echo "${CLIENT_SECRET}"'                    block
run_test "printf"                  'printf "%s\n" "$GH_PAT"'                   block
run_test "long slice"              'echo "${MODAL_TOKEN_SECRET:0:100}"'        block
run_test "13-char slice"           'echo "${HF_TOKEN:0:13}"'                   block
run_test "offset-only slice"       'echo "${ANTHROPIC_API_KEY:13}"'            block
run_test "nonzero-offset slice"    'echo "${ANTHROPIC_API_KEY:1:4}"'          block
run_test "suffix too long"         'echo "${ANTHROPIC_API_KEY: -12}"'          block
run_test "suffix with length"      'echo "${ANTHROPIC_API_KEY: -4:4}"'         block
run_test "no-space suffix=default" 'echo "${ANTHROPIC_API_KEY:-4}"'            block
run_test "echo -n"                 'echo -n "$MY_PASSWORD"'                    block
run_test "passphrase"              'echo "$SSH_PASSPHRASE"'                    block
run_test "credential"              'echo "$GCP_CREDENTIALS"'                   block
run_test "bearer"                  'echo "$BEARER_TOKEN"'                      block

echo "=== SHOULD BLOCK: nested bash -c ==="
run_test "nested dump"             "bash -c 'printenv'"                        block
run_test "nested echo"             "bash -c 'echo \$ANTHROPIC_API_KEY'"        block
run_test "nested default"          "sh -c 'echo \${HF_TOKEN:-none}'"           block
run_test "zsh -c dump"             "zsh -c 'env'"                              block

echo "=== SHOULD ALLOW: env/printenv with a real command or safe arg ==="
run_test "env assignment prefix"   'env FOO=bar ls'                            allow
run_test "env -u then command"     'env -u ANTHROPIC_API_KEY usage-ping'       allow
run_test "env -i then command"     "env -i PATH=/usr/bin sh -c 'echo hi'"      allow
run_test "printenv PATH"           'printenv PATH'                             allow
run_test "printenv HOME"           'printenv HOME'                             allow
run_test "export assignment"       'export FOO=bar'                            allow
run_test "set -euo pipefail"       'set -euo pipefail'                         allow
run_test "set -x"                  'set -x'                                    allow
run_test "declare -x assignment"   'declare -x FOO=bar'                        allow
run_test "direnv status"           'direnv status'                             allow
run_test "direnv allow"            'direnv allow'                              allow

echo "=== SHOULD ALLOW: the safe presence-test idioms ==="
run_test "empty default"           'echo "${ANTHROPIC_API_KEY:-}"'             allow
run_test "plus-form default"       'echo "${ANTHROPIC_API_KEY:+set}"'          allow
run_test "test -n plus-form"       '[ -n "${ANTHROPIC_API_KEY:+x}" ] && echo present'  allow
run_test "length only"             'echo "${#ANTHROPIC_API_KEY}"'              allow
run_test "redacted 12-char prefix" 'echo "key: ${ANTHROPIC_API_KEY:0:12}..."'  allow
run_test "redacted short prefix"   'echo "${MODAL_TOKEN_SECRET:0:4}"'          allow
run_test "redacted suffix"         'echo "ends ...${ANTHROPIC_API_KEY: -4}"'   allow
run_test "redacted suffix parens"  'echo "${HF_TOKEN:(-6)}"'                   allow
run_test "unquoted suffix"         'echo key ends ${ANTHROPIC_API_KEY: -4}'    allow

echo "=== SHOULD ALLOW: backslash-escaped text does not expand ==="
# This is how a commit message or doc quotes the bug it is describing.
run_test "escaped in printf"       'printf "%s\n" "\${ANTHROPIC_API_KEY:-x}"'  allow
run_test "escaped bare var"       'echo "\$HF_TOKEN"'                          allow

echo "=== SHOULD ALLOW: single-quoted text does not expand ==="
run_test "grep for the pattern"    "rg 'ANTHROPIC_API_KEY:-' scripts/"         allow
run_test "grep for expansion"      "rg '\${HF_TOKEN:-x}' claude/hooks/"        allow
run_test "echo literal name"       "echo 'set ANTHROPIC_API_KEY in .envrc'"    allow

echo "=== SHOULD ALLOW: path-shaped names are locations, not values ==="
run_test "token file path"         'echo "$BWS_TOKEN_FILE"'                    allow
run_test "secrets dir"             'echo "$DOTFILES_SECRETS_DIR"'              allow
run_test "key path"                'echo "$SSH_KEY_PATH"'                      allow

echo "=== SHOULD ALLOW: ordinary commands ==="
run_test "git status"              'git status --short'                        allow
run_test "echo PATH"               'echo "$PATH"'                              allow
run_test "echo plain var"          'echo "$HOME/code"'                         allow
run_test "cat env file"            'cat .env'                                  allow
run_test "get-value by exact key"  "dotfiles-secrets get-value 'ANTHROPIC_API_KEY - mats'"  allow
run_test "non-Bash tool"           'printenv'                                  allow Read

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
