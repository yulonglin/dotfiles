#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016  # child bash snippets expand variables after .envrc load
# Regression tests for the direnv secrets startup path.
set -euo pipefail

DOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$DOT_DIR/custom_bins/dotfiles-secrets"
SETUP_ENVRC="$DOT_DIR/custom_bins/setup-envrc"
TMP_ROOT="$DOT_DIR/tmp"
mkdir -p "$TMP_ROOT"
TEST_HOME=$(mktemp -d "$TMP_ROOT/secrets-fast.XXXXXX")
# shellcheck disable=SC2317  # invoked indirectly by the EXIT trap
cleanup() {
    if command -v trash >/dev/null 2>&1; then
        trash "$TEST_HOME" >/dev/null 2>&1 || true
    else
        rm -r "$TEST_HOME"
    fi
}
trap cleanup EXIT

pass=0
fail=0
check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  ok  %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$name"
        printf '    expected: %q\n' "$expected"
        printf '    actual:   %q\n' "$actual"
        fail=$((fail + 1))
    fi
}

printf '== parallel per-project BWS reads ==\n'
FAKE_BIN="$TEST_HOME/fake-bin"
BARRIER="$TEST_HOME/barrier"
mkdir -p "$FAKE_BIN" "$BARRIER"
cat > "$FAKE_BIN/bws" <<'FAKE_BWS'
#!/usr/bin/env bash
set -euo pipefail

while [[ $# -gt 0 ]]; do
    case "$1" in
        --color|-c|--output|-o|--access-token|-t|--config-file|-f|--profile|-p|--server-url|-u)
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

case "${1:-} ${2:-}" in
    "project list")
        printf '%s\n' '[{"id":"project-a","name":"A"},{"id":"project-b","name":"B"}]'
        ;;
    "secret list")
        project_id="${3:-}"
        [[ -n "$project_id" ]] || {
            printf 'unfiltered secret list is intentionally unavailable in this test\n' >&2
            exit 40
        }
        printf 'attempt\n' >> "$BWS_TEST_BARRIER/$project_id.attempts"
        if [[ "${BWS_TEST_RATE_LIMIT_ONCE:-0}" == 1 && "$project_id" == project-a ]]; then
            retry_marker="$BWS_TEST_BARRIER/$project_id.rate-limited"
            if [[ ! -f "$retry_marker" ]]; then
                : > "$retry_marker"
                printf 'Received error message from server: [429 Too Many Requests] Slow down! Try again in 0s.\n' >&2
                exit 43
            fi
        fi
        if [[ "${BWS_TEST_FATAL_PROJECT:-}" == "$project_id" ]]; then
            printf 'permission denied\n' >&2
            exit 44
        fi
        : > "$BWS_TEST_BARRIER/$project_id.started"
        other=project-a
        [[ "$project_id" == project-a ]] && other=project-b
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            [[ -f "$BWS_TEST_BARRIER/$other.started" ]] && break
            sleep 0.05
        done
        [[ -f "$BWS_TEST_BARRIER/$other.started" ]] || {
            printf 'project reads were sequential\n' >&2
            exit 41
        }
        if [[ "$project_id" == project-a ]]; then
            printf '%s\n' '[{"id":"uuid-a","projectId":"project-a","key":"ALPHA_TOKEN","value":"alpha","note":""}]'
        else
            printf '%s\n' '[{"id":"uuid-b","projectId":"project-b","key":"BETA_TOKEN","value":"beta","note":""}]'
        fi
        ;;
    *)
        printf 'unexpected fake bws command: %s\n' "$*" >&2
        exit 42
        ;;
esac
FAKE_BWS
chmod +x "$FAKE_BIN/bws"

parallel_out=$(env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    BWS_ACCESS_TOKEN=test-token \
    BWS_TEST_BARRIER="$BARRIER" \
    DOTFILES_SECRETS_BACKEND=bws \
    DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
    TMPDIR="$TEST_HOME" \
    "$HELPER" shell ALPHA_TOKEN BETA_TOKEN 2>"$TEST_HOME/parallel.err" || true)
check "all project secrets resolve" \
    $'export ALPHA_TOKEN=alpha\nexport BETA_TOKEN=beta' \
    "$parallel_out"
check "parallel project fetch has no error" "" "$(<"$TEST_HOME/parallel.err")"

list_full_out=$(env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    BWS_ACCESS_TOKEN=test-token \
    BWS_TEST_BARRIER="$BARRIER" \
    DOTFILES_SECRETS_BACKEND=bws \
    DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
    TMPDIR="$TEST_HOME" \
    "$HELPER" list-full 2>"$TEST_HOME/list-full.err" || true)
check "list-full also uses project-scoped reads" \
    $'uuid-a\tALPHA_TOKEN\tALPHA_TOKEN\talpha\t\nuuid-b\tBETA_TOKEN\tBETA_TOKEN\tbeta\t' \
    "$list_full_out"
check "list-full project fetch has no error" "" "$(<"$TEST_HOME/list-full.err")"

rm -f "$BARRIER"/*.started "$BARRIER"/*.rate-limited "$BARRIER"/*.attempts
retry_out=$(env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    BWS_ACCESS_TOKEN=test-token \
    BWS_TEST_BARRIER="$BARRIER" \
    BWS_TEST_RATE_LIMIT_ONCE=1 \
    DOTFILES_SECRETS_BACKEND=bws \
    DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
    TMPDIR="$TEST_HOME" \
    "$HELPER" shell ALPHA_TOKEN BETA_TOKEN 2>"$TEST_HOME/retry.err" || true)
check "one 429 is retried" \
    $'export ALPHA_TOKEN=alpha\nexport BETA_TOKEN=beta' \
    "$retry_out"
check "successful retry is quiet" "" "$(<"$TEST_HOME/retry.err")"

rm -f "$BARRIER"/*.started "$BARRIER"/*.rate-limited "$BARRIER"/*.attempts
env \
    HOME="$TEST_HOME" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    BWS_ACCESS_TOKEN=test-token \
    BWS_TEST_BARRIER="$BARRIER" \
    BWS_TEST_FATAL_PROJECT=project-a \
    DOTFILES_SECRETS_BACKEND=bws \
    DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
    TMPDIR="$TEST_HOME" \
    "$HELPER" shell ALPHA_TOKEN >/dev/null 2>"$TEST_HOME/fatal.err" || true
fatal_count_after=0
[[ -f "$BARRIER/project-a.attempts" ]] && fatal_count_after=$(wc -l < "$BARRIER/project-a.attempts" | tr -d ' ')
check "non-429 error runs once" "1" "$fatal_count_after"

printf '== one runtime helper call for mixed bindings ==\n'
FIXTURE="$TEST_HOME/fixture"
REPO="$TEST_HOME/repo"
COUNT_FILE="$TEST_HOME/helper-calls"
mkdir -p "$FIXTURE" "$REPO"
printf 'HF_TOKEN=hf_fixture\nOPENAI_API_KEY=sk_personal\n' > "$FIXTURE/secrets"
printf '%s\n' \
    $'HF_TOKEN\tHF_TOKEN\t\tuuid-hf' \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - personal\tpersonal\tuuid-personal' \
    > "$FIXTURE/meta"
{
    printf '%s\t%s\t%s\t%s\n' HF_TOKEN "$(printf hf_fixture | base64 | tr -d '\n')" "" uuid-hf
    printf '%s\t%s\t%s\t%s\n' 'OPENAI_API_KEY - personal' "$(printf sk_personal | base64 | tr -d '\n')" personal uuid-personal
} > "$FIXTURE/raw"

git -C "$REPO" init -q
(
    cd "$REPO"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_SECRETS_BACKEND=fixture \
        DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \
        DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
        "$SETUP_ENVRC" 'LOCAL_HF=HF_TOKEN' 'LOCAL_OPENAI=bws-id:uuid-personal'
) >"$TEST_HOME/setup.out" 2>"$TEST_HOME/setup.err"

cat > "$TEST_HOME/counting-helper" <<COUNTING_HELPER
#!/usr/bin/env bash
printf 'call\n' >> "$COUNT_FILE"
exec "$HELPER" "\$@"
COUNTING_HELPER
chmod +x "$TEST_HOME/counting-helper"
python3 - "$REPO/.envrc" "$TEST_HOME/counting-helper" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
helper = sys.argv[2]
lines = path.read_text().splitlines()
for index, line in enumerate(lines):
    if line.startswith("DOTFILES_SECRETS_BIN="):
        lines[index] = f"DOTFILES_SECRETS_BIN={helper}"
path.write_text("\n".join(lines) + "\n")
PY

load_out=$(
    cd "$REPO"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_SECRETS_BACKEND=fixture \
        DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \
        DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
        HF_TOKEN=stale-source \
        LOCAL_HF=stale-destination \
        LOCAL_OPENAI=stale-pinned-destination \
        bash -c 'watch_file() { :; }; source ./.envrc; printf "%s|%s|%s" "${HF_TOKEN-unset}" "$LOCAL_HF" "$LOCAL_OPENAI"'
)
check "mixed bindings resolve and plain source stays scrubbed" "unset|hf_fixture|sk_personal" "$load_out"
call_count=0
[[ -f "$COUNT_FILE" ]] && call_count=$(wc -l < "$COUNT_FILE" | tr -d ' ')
check "generated envrc loads backend once" "1" "$call_count"

printf '== failed batch clears every managed variable ==\n'
BROKEN_FIXTURE="$TEST_HOME/broken-fixture"
mkdir -p "$BROKEN_FIXTURE"
printf 'HF_TOKEN=hf_fixture\n' > "$BROKEN_FIXTURE/secrets"
printf '%s\n' $'HF_TOKEN\tHF_TOKEN\t\tuuid-hf' > "$BROKEN_FIXTURE/meta"
printf '%s\t%s\t%s\t%s\n' HF_TOKEN "$(printf hf_fixture | base64 | tr -d '\n')" "" uuid-hf > "$BROKEN_FIXTURE/raw"

failure_state=$(
    cd "$REPO"
    env \
        HOME="$TEST_HOME" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_SECRETS_BACKEND=fixture \
        DOTFILES_SECRETS_FIXTURE_DIR="$BROKEN_FIXTURE" \
        DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-scope.conf" \
        HF_TOKEN=stale-source \
        LOCAL_HF=stale-destination \
        LOCAL_OPENAI=stale-pinned-destination \
        bash -c 'watch_file() { :; }; source ./.envrc >/dev/null 2>&1; printf "%s|%s|%s" "${HF_TOKEN-unset}" "${LOCAL_HF-unset}" "${LOCAL_OPENAI-unset}"'
)
check "failed resolution does not retain stale values" "unset|unset|unset" "$failure_state"

printf '\nPassed: %d  Failed: %d\n' "$pass" "$fail"
exit "$fail"
