#!/usr/bin/env bash
# Smoke test for the model-router gateway (Option C, decision spec 2026-09-06).
# One command, run after every Claude Code upgrade and every router refresh.
# Legs, each printed as [ok]/[FAIL] and named on failure:
#   unit       the OS user service is running (launchd on macOS, systemd elsewhere)
#   doctor     `bootstrap.sh doctor --json` reports every check ok
#   providers  `verify-providers` finds every configured model at its host
#   settings   the deployed settings carry the loopback base URL; HEAD's copy does not
#   route:<id> `claude -p --model <id>` answers through the router: the router log
#              gains a request for that routing ID and the answer does not claim
#              to be Claude (routed IDs get an honest-identity block)
#   romp       the dashboard answers on the tailnet IP forwarder (skipped where ~/romp is absent)
#
# Options: --skip-probes (no claude -p calls), --routes id,id (probe a subset;
# default is every modelPicker row in the deployed settings).
# Loopback is blocked inside the Claude Code Bash sandbox, so run this with the
# sandbox off or from a plain shell; a healthy router reads as down otherwise.
# macOS ships Python 3.9 (no tomllib); the tomllib leg falls back to uv's interpreter.
set -u

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
LOG="$HOME/.local/state/model-router/logs/router.log"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
skip_probes=0
routes_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-probes) skip_probes=1 ;;
    --routes) shift; routes_arg="$1" ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

failed=()
ok()   { printf '[ok]   %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; failed+=("${1%% *}"); }
skip() { printf '[skip] %s\n' "$1"; }
# tomllib needs Python 3.11+; macOS ships 3.9, so fall back to uv's managed interpreter.
py311() { if python3 -c 'import tomllib' 2>/dev/null; then python3 "$@"; else uv run --quiet --no-project --python '>=3.11' python "$@"; fi; }

bootstrap="$(find "$HOME"/.claude/plugins/cache/alignment-hive/model-router -path '*/scripts/bootstrap.sh' 2>/dev/null | sort | tail -n1)"
if [ -z "$bootstrap" ]; then
  fail "plugin  model-router plugin not installed"
  echo "failed: ${failed[*]}"; exit 1
fi

# unit: launchd on macOS, systemd user unit elsewhere
if [ "$(uname -s)" = "Darwin" ]; then
  if launchctl print "gui/$(id -u)/com.alignment-hive.model-router" 2>/dev/null | grep -q 'state = running'; then ok "unit      com.alignment-hive.model-router running"; else fail "unit      com.alignment-hive.model-router not running (launchctl)"; fi
elif systemctl --user is-active --quiet model-router.service; then ok "unit      model-router.service active"; else fail "unit      model-router.service not active"; fi

# doctor
doctor_json="$("$bootstrap" doctor --json 2>/dev/null)"
doctor_bad="$(printf '%s' "$doctor_json" | python3 -c 'import json,sys
d=json.load(sys.stdin); print(", ".join(c["name"] for c in d.get("checks",[]) if not c.get("ok")))' 2>/dev/null)"
if [ -n "$doctor_json" ] && [ -z "$doctor_bad" ]; then ok "doctor    every check green"; else fail "doctor    failing checks: ${doctor_bad:-no JSON}"; fi
base_url="$(printf '%s' "$doctor_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("base_url",""))' 2>/dev/null)"

# providers
if "$bootstrap" verify-providers >/dev/null 2>&1; then ok "providers verify-providers passed"; else fail "providers verify-providers failed: $("$bootstrap" verify-providers 2>&1 | head -n1)"; fi

# settings: deployed carries the loopback URL, committed does not
deployed_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("env",{}).get("ANTHROPIC_BASE_URL",""))' "$SETTINGS" 2>/dev/null)"
committed_url="$(git -C "$REPO" show HEAD:claude/settings.json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("env",{}).get("ANTHROPIC_BASE_URL",""))' 2>/dev/null)"
case "$deployed_url" in
  http://127.0.0.1:*) ok "settings  deployed file wired to loopback" ;;
  "") fail "settings  deployed file has no ANTHROPIC_BASE_URL (run: model-router-wire apply)" ;;
  *) fail "settings  deployed ANTHROPIC_BASE_URL is not loopback: $deployed_url" ;;
esac
if [ -n "$committed_url" ]; then fail "settings  HEAD's claude/settings.json carries ANTHROPIC_BASE_URL"; else ok "settings  committed copy carries no base URL"; fi

# source: everything rendered from config/model-router.toml is current
if drift="$("$REPO/custom_bins/model-router-wire" apply --check 2>&1)"; then ok "source    rendered files match config/model-router.toml"; else fail "source    $(printf '%s' "$drift" | tr '\n' ' ' | cut -c1-200)"; fi

# route probes
if [ "$skip_probes" -eq 0 ]; then
  if [ -n "$routes_arg" ]; then
    routes="${routes_arg//,/ }"
  else
    routes="$(python3 -c 'import json,sys; print(" ".join(o["model"] for o in json.load(open(sys.argv[1])).get("modelPicker",{}).get("options",[])))' "$SETTINGS" 2>/dev/null)"
  fi
  if [ -z "$routes" ]; then
    fail "routes    no modelPicker rows to probe and no --routes given"
  fi
  probe_url="${deployed_url:-$base_url}"
  for id in $routes; do
    before="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
    answer="$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDECODE ANTHROPIC_BASE_URL="$probe_url" \
      timeout 150 "$CLAUDE_BIN" -p 'Which model are you? Reply with your model family and version in at most six words.' \
      --model "$id" --max-budget-usd 0.5 --output-format json 2>/dev/null \
      | python3 -c 'import json,sys
t=sys.stdin.read().strip()
try:
    d=json.loads(t)
except Exception:
    print("NO-JSON " + t[:160].replace("\n"," ")); sys.exit()
if isinstance(d, list):  # some versions emit the message stream as an array
    d=next((m for m in d if isinstance(m, dict) and m.get("type")=="result"), d[-1] if d else {})
print("ERROR " + str(d.get("result") or d.get("error") or "")[:120] if d.get("is_error") else (d.get("result") or "EMPTY").replace("\n"," ")[:120])')"
    hop="$(tail -n +"$((before + 1))" "$LOG" 2>/dev/null | grep -c -- "$id")"
    case "$answer" in
      NO-JSON*|ERROR*|EMPTY|"") fail "route:$id no answer (${answer:-empty output})"; continue ;;
    esac
    if [ "$hop" -eq 0 ]; then fail "route:$id answered but the router log shows no request for it: $answer"; continue; fi
    if printf '%s' "$answer" | sed -E 's/[Cc]laude [Cc]ode//g' | grep -qi claude; then fail "route:$id answered as Claude: $answer"; continue; fi
    ok "route:$id $answer"
  done

  # agent-file probes (the F3 re-measurement): an agent whose model is a served
  # routing ID must reach the router; one naming an unserved ID must fail loudly
  # rather than answer as Claude. `--agents` stands in for a file on disk.
  agent_probe() {
    env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDECODE ANTHROPIC_BASE_URL="$probe_url" \
      timeout 200 "$CLAUDE_BIN" -p 'Use the Task tool to run the agent named probe with the prompt: Which model are you? Reply with your model family and version in at most six words. Then reply with exactly the text the agent returned, or the exact error text if it failed, nothing else.' \
      --agents "{\"probe\":{\"description\":\"Identity probe\",\"prompt\":\"Answer the question you are given.\",\"model\":\"$1\"}}" \
      --permission-mode default --allowedTools Agent Task \
      --model sonnet --max-budget-usd 2.5 --output-format json 2>/dev/null \
      | python3 -c 'import json,sys
t=sys.stdin.read().strip()
try:
    d=json.loads(t)
except Exception:
    print("NO-JSON " + t[:160].replace("\n"," ")); sys.exit()
if isinstance(d, list):
    d=next((m for m in d if isinstance(m, dict) and m.get("type")=="result"), d[-1] if d else {})
print(("ERROR " if d.get("is_error") else "") + str(d.get("result") or "EMPTY").replace("\n"," ")[:160])'
  }
  infra_error() { printf '%s' "$1" | grep -qiE 'auto mode|determine the safety|rate.limited|budget|NO-JSON|^ERROR EMPTY$'; }
  served="${routes%% *}"
  if [ -n "$served" ]; then
    before="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
    answer="$(agent_probe "$served")"
    hop="$(tail -n +"$((before + 1))" "$LOG" 2>/dev/null | grep -c -- "$served")"
    if infra_error "$answer"; then fail "agent:$served probe could not run (harness, not routing): $answer"
    elif printf '%s' "$answer" | sed -E 's/[Cc]laude [Cc]ode//g' | grep -qiE 'claude|opus|sonnet|fable|haiku'; then fail "agent:$served answered as Claude: $answer"
    elif [ "$hop" -eq 0 ]; then fail "agent:$served no router request for it: $answer"
    else ok "agent:$served $answer"; fi
  fi
  unserved="zz-unserved-probe"
  answer="$(agent_probe "$unserved")"
  if infra_error "$answer"; then fail "agent:$unserved probe could not run (harness, not routing): $answer"
  elif printf '%s' "$answer" | grep -qiE 'error|not found|issue|fail|unavailable|could not|does not exist'; then ok "agent:$unserved failed loudly: $answer"
  elif printf '%s' "$answer" | grep -qiE 'claude|opus|sonnet|fable|haiku'; then fail "agent:$unserved answered as Claude (silent fallback): $answer"
  else fail "agent:$unserved unclear outcome: $answer"; fi
fi

# every agent file names a Claude alias, a Claude ID or a routing ID the router serves
offenders="$(py311 - "$REPO/claude/agents" "$HOME/.config/model-router/config.toml" <<'PY'
import re, sys, glob, tomllib, pathlib
agents_dir, config = sys.argv[1], sys.argv[2]
served = set()
try:
    cfg = tomllib.loads(pathlib.Path(config).read_text())
    served = {m["routing-id"] for m in cfg.get("models", [])} | {m["routing-id"] for p in cfg.get("openai-providers", []) for m in p.get("models", [])}
except FileNotFoundError:
    pass
bad = []
for f in sorted(glob.glob(f"{agents_dir}/*.md")):
    text = pathlib.Path(f).read_text()
    m = re.search(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        continue
    mm = re.search(r"^model:\s*(\S+)", m.group(1), re.M)
    if not mm:
        continue
    model = mm.group(1).strip("'\"")
    if model in {"sonnet", "opus", "haiku", "fable", "inherit"} or model.startswith("claude-") or model in served:
        continue
    bad.append(f"{pathlib.Path(f).name}={model}")
print(" ".join(bad))
PY
)"
if [ -n "$offenders" ]; then fail "agents    unserved model in agent files: $offenders"; else ok "agents    every agent file names a Claude model or a served route"; fi

# romp over the tailnet (hetzner only: skipped where ~/romp is absent)
if [ ! -d "$HOME/romp" ]; then
  skip "romp      ~/romp not on this machine"
else
  ts_ip="$(tailscale ip -4 2>/dev/null | head -n1)"
  if [ -z "$ts_ip" ]; then
    fail "romp      tailscale ip -4 returned nothing"
  else
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://$ts_ip:8080/" 2>/dev/null)"
    if [ "$code" = "200" ]; then ok "romp      http://$ts_ip:8080/ answers 200"; else fail "romp      http://$ts_ip:8080/ returned ${code:-nothing}"; fi
  fi
fi

echo "run: $(date -u +%Y-%m-%dT%H:%M:%SZ) claude $("$CLAUDE_BIN" --version 2>/dev/null | head -n1) router $(printf '%s' "$doctor_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null)"
if [ "${#failed[@]}" -gt 0 ]; then echo "failed: ${failed[*]}"; exit 1; fi
echo "all legs passed"
