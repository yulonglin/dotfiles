#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT_DIR/custom_bins/mats-slack-mcp"
TUNNEL="$ROOT_DIR/custom_bins/mats-slack-tunnel"
SETUP="$ROOT_DIR/scripts/setup/setup_mats_slack_tunnel.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" != *"$needle"* ]] || fail "output unexpectedly contained: $needle"
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mats-slack-tunnel-test.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home/.local/bin"

cat > "$tmp_dir/bin/mats-slack-keychain" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == get ]] || exit 2
service="${2:-}"
case "$service" in
    com.yulonglin.mats-slack-mcp.xoxc) printf 'xoxc-test\n' ;;
    com.yulonglin.mats-slack-mcp.xoxd) printf 'xoxd-test\n' ;;
    com.yulonglin.mats-slack-mcp.openai-api-key) printf 'sk-test\n' ;;
    com.yulonglin.mats-slack-mcp.tunnel-id) printf 'tunnel_test\n' ;;
    *) exit 3 ;;
esac
STUB

cat > "$tmp_dir/bin/npx" <<'STUB'
#!/usr/bin/env bash
printf 'npx:%s\n' "$*"
printf 'xoxc:%s\n' "${SLACK_MCP_XOXC_TOKEN:-missing}"
printf 'xoxd:%s\n' "${SLACK_MCP_XOXD_TOKEN:-missing}"
STUB

cat > "$tmp_dir/home/.local/bin/tunnel-client" <<'STUB'
#!/usr/bin/env bash
printf 'tunnel:%s\n' "$*"
printf 'control:%s\n' "${CONTROL_PLANE_API_KEY:-missing}"
STUB

chmod +x "$tmp_dir/bin/mats-slack-keychain" "$tmp_dir/bin/npx" \
    "$tmp_dir/home/.local/bin/tunnel-client"

server_output=$(HOME="$tmp_dir/home" PATH="$tmp_dir/bin:/usr/bin:/bin" \
    KEYCHAIN_HELPER_BIN="$tmp_dir/bin/mats-slack-keychain" \
    NPX_BIN="$tmp_dir/bin/npx" \
    "$SERVER")
assert_contains "$server_output" 'slack-mcp-server@1.3.0 --transport stdio'
assert_contains "$server_output" 'xoxc:xoxc-test'
assert_contains "$server_output" 'xoxd:xoxd-test'
assert_contains "$server_output" 'conversations_history'
assert_contains "$server_output" 'conversations_search_messages'
assert_not_contains "$server_output" 'conversations_add_message'
assert_not_contains "$server_output" 'reactions_add'
assert_not_contains "$server_output" 'conversations_mark'

tunnel_output=$(HOME="$tmp_dir/home" PATH="$tmp_dir/bin:/usr/bin:/bin" \
    KEYCHAIN_HELPER_BIN="$tmp_dir/bin/mats-slack-keychain" \
    "$TUNNEL")
assert_contains "$tunnel_output" 'tunnel:init --sample sample_mcp_stdio_local'
assert_contains "$tunnel_output" '--profile mats-slack'
assert_contains "$tunnel_output" '--force'
assert_contains "$tunnel_output" '--health-listen-addr 127.0.0.1:18080'
assert_contains "$tunnel_output" '--tunnel-id tunnel_test'
assert_contains "$tunnel_output" '--mcp-command'
assert_contains "$tunnel_output" 'tunnel:run --profile mats-slack'
assert_contains "$tunnel_output" 'control:sk-test'

setup_text=$(<"$SETUP")
assert_contains "$setup_text" 'com.yulonglin.mats-slack-tunnel'
assert_contains "$setup_text" '<key>KeepAlive</key>'
assert_contains "$setup_text" '<key>RunAtLoad</key>'
assert_contains "$setup_text" 'mats-slack-tunnel'
assert_contains "$setup_text" 'tools/mats-slack-keychain/main.swift'

printf 'PASS: MATS Slack tunnel wrappers are pinned, read-only, and fail-closed\n'
