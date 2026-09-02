#!/usr/bin/env bash
# EX-9 tripwire wrapper: run the detector daily, notify on findings only.
#
# vault_sync.py tripwire exits 2 when it finds something and 0 when clean, so a
# clean run stays silent by design -- a daily "nothing to report" message trains
# you to ignore the channel.
#
# This wrapper exits 0 only when it has nothing to report OR it reported
# successfully. Findings it could not deliver -- failed send, no token -- exit
# non-zero, so a green unit always means "you have been told everything".
#
# Telegram delivery is optional and off until a token exists. Create
# ~/.claude/channels/telegram/tripwire.env with:
#     TELEGRAM_BOT_TOKEN=...
#     TELEGRAM_CHAT_ID=...
# Findings are always written to the log regardless, so detection never depends
# on the notification channel being configured.
#
# The same token gates --auto-exclude, which is the only thing here that writes:
# detection is safe to run unattended and unheard, mutation is not. Until a
# token exists this is a pure reporter.

set -uo pipefail

TOOL="${VAULT_SYNC_TOOL:-$HOME/code/dotfiles/scripts/vault/vault_sync.py}"
LOG_DIR="${VAULT_SYNC_LOG_DIR:-$HOME/.local/state/vault-sync}"
ENV_FILE="${VAULT_SYNC_TELEGRAM_ENV:-$HOME/.claude/channels/telegram/tripwire.env}"

# systemd user units (and cron) run with a minimal PATH that omits ~/.local/bin,
# which is where uv lives -- so an interactively-working wrapper dies at exit 127
# every night without ever looking at the vault. Verified against this box:
# `systemctl --user show-environment` yields PATH=/usr/local/sbin:...:/snap/bin,
# with no ~/.local/bin, while uv resolves to $HOME/.local/bin/uv.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

UV="${VAULT_SYNC_UV:-$(command -v uv 2>/dev/null || true)}"
if [ -z "$UV" ]; then
  # Fail loudly rather than writing an empty report that reads as "all clear".
  echo "vault-sync tripwire: uv not found (PATH=$PATH); detector did NOT run" >&2
  exit 127
fi

mkdir -p "$LOG_DIR"
# Reports quote vault paths; keep them readable only by their owner.
chmod 700 "$LOG_DIR" 2>/dev/null || true
stamp=$(date -u +%Y-%m-%d_%H-%M-%S)
report="$LOG_DIR/tripwire-$stamp.txt"

# Sourced BEFORE the run, not after: whether a notification channel exists is
# what decides whether this run may CHANGE anything. --auto-exclude rewrites
# ignoreFolders, and the running daemon only re-reads filters at startup -- so
# an unattended run that mutates the config and then cannot tell anyone leaves
# the config and the live daemon disagreeing, silently, which is strictly worse
# than not excluding at all. Fail closed: report-only until a token exists, and
# auto-exclude turns itself on the day one is configured.
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090  # runtime path, not resolvable at lint time
  . "$ENV_FILE"
fi

args=("$@")
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  case " $* " in
    *" --auto-exclude "*) ;;  # caller was explicit; do not duplicate the flag
    *) args+=(--auto-exclude) ;;
  esac
fi

"$UV" run "$TOOL" tripwire ${args[@]+"${args[@]}"} >"$report" 2>&1
status=$?

ln -sfn "$report" "$LOG_DIR/latest.txt"

if [ "$status" -eq 0 ]; then
  exit 0
fi

if [ "$status" -ne 2 ]; then
  echo "vault-sync tripwire errored (exit $status); see $report" >&2
  exit "$status"
fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  # Telegram caps messages at 4096 chars; the summary lines are what matter.
  # Action lines first: head(1) truncates from the END, and these are the only
  # lines that ask the operator to do something. A report carrying twenty
  # findings would otherwise push RESTART REQUIRED -- emitted last, and the one
  # line without which an applied exclusion does not take effect -- clean off
  # the message, delivering an alert that omits the thing to act on.
  body=$( { grep -E "RESTART REQUIRED|EXCLUDED BUT ON SERVER|STRANDED|ALREADY ON SERVER|Excluded [0-9]" "$report"
            grep -E "REGENERABLE|OVER THE|regenerable dir|safe to exclude" "$report"
          } | head -25 )
  # Never send an empty body: Telegram rejects a blank `text` and the message
  # would be lost even though the run did find something.
  [ -n "$body" ] || body="(exit 2, but no summary line matched -- read the report)"
  # The URL carries the bot token, and argv is world-readable via ps(1).
  # -K - takes the URL from stdin instead, keeping the token out of argv.
  # --fail-with-body: without --fail, curl exits 0 on HTTP 400/401/429 (bad chat
  # id, revoked token, rate limit), so the failure branch never runs and the unit
  # reports success while no alert was ever delivered -- a silent-failure shape
  # identical to the exit-127 one above. Keep the body: it carries Telegram's
  # JSON description of what was wrong.
  if ! tg_out=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" \
    | curl -sS --fail-with-body --max-time 30 -K - \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      --data-urlencode "text=vault sync tripwire found something:

${body}

full report: ${report}" 2>&1); then
    # Never echo the URL: it carries the bot token. curl's own error text is safe.
    echo "tripwire: telegram delivery FAILED (${tg_out}); report at $report" >&2
    exit 1
  fi
  exit 0
fi

echo "tripwire: findings recorded at $report (no telegram token configured)" >&2
# Undelivered findings are not a success. The wrapper exits 0 in exactly two
# cases -- nothing to report, or something to report that was reported -- so a
# green unit always means "you have been told everything I know". Exiting 0
# here instead would make an unreachable operator look identical to a clean
# vault, which is the same silent-failure shape as the exit-127 and the
# missing-`--fail` bugs above. Expect this to stay red until EX-9's bot token
# is configured; that redness is the signal, not noise.
exit 1
