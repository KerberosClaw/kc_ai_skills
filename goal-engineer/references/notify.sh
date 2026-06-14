#!/bin/bash
# notify.sh — channel-agnostic traffic-light notifier for unattended loops.
# Reference helper for the goal-engineer skill. Copy into your project, wire the
# channel + credentials per your dispatch doc. NOT meant to run from the skill repo.
#
# Usage:
#   notify.sh <emoji> <text> [local-media-path]
#   notify.sh 🟢 "item-3 done, 4 passing, still running"
#   notify.sh 🟢 "milestone done" /abs/path/review-bundle.png   # image auto-compressed to JPEG
#   notify.sh 🔴 "need you: input missing, NEEDS_INPUT"
#
# Channel:  NOTIFY_CHANNEL = telegram | discord | slack | imessage   (default telegram)
# Optional: NOTIFY_CONFIG = /path/to/private.env  → sourced before sending (TRUSTED shell file you own)
#
# 🔴 Credentials come ONLY from env (or NOTIFY_CONFIG you source) — NEVER hardcode
#    tokens/ids/URLs/handles, NEVER commit them, NEVER write them into a dispatch doc.
#      telegram : TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
#      discord  : DISCORD_WEBHOOK_URL
#      slack    : SLACK_WEBHOOK_URL
#      imessage : IMESSAGE_TO   (macOS only; sends locally via osascript)
#
# Requirements: curl. (discord/slack JSON escaping needs python3. image compress needs magick/convert.)
# Exit code: non-zero if the send fails — so a pre-flight test can actually gate on it.
set -uo pipefail

EMOJI="${1:?usage: notify.sh <emoji> <text> [media]}"
TEXT="${2:?missing text}"
MEDIA="${3:-}"
MSG="${EMOJI} ${TEXT}"
CH="${NOTIFY_CHANNEL:-telegram}"

# optional: load secrets from a config file the operator points at (kept private, never committed)
if [ -n "${NOTIFY_CONFIG:-}" ]; then
  [ -f "$NOTIFY_CONFIG" ] || { echo "[notify] NOTIFY_CONFIG not found: $NOTIFY_CONFIG" >&2; exit 1; }
  set -a; # shellcheck disable=SC1090
  source "$NOTIFY_CONFIG"; set +a
fi

die(){ echo "[notify] $*" >&2; exit 1; }
TMP=""   # cleaned on exit
cleanup(){ [ -n "$TMP" ] && rm -f "$TMP"; }
trap cleanup EXIT

# JSON-encode a string safely (for webhook payloads). Falls back to error if no python3.
json_str(){ command -v python3 >/dev/null 2>&1 || die "discord/slack need python3 for JSON escaping"; printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# compress big images to a unique temp JPEG (avoid upload timeouts); only if media given + is image
prep_media(){
  [ -n "$MEDIA" ] && [ -f "$MEDIA" ] || { MEDIA=""; return; }
  case "$MEDIA" in
    *.png|*.PNG|*.webp|*.WEBP)
      local conv=""
      if command -v magick >/dev/null 2>&1; then conv=magick; elif command -v convert >/dev/null 2>&1; then conv=convert; fi
      [ -n "$conv" ] || { echo "[notify] no image converter (magick/convert); sending original (may be large)" >&2; return; }
      TMP="$(mktemp "${TMPDIR:-/tmp}/notify.XXXXXX.jpg")"
      if "$conv" "$MEDIA" -quality 90 "$TMP" 2>/dev/null; then MEDIA="$TMP"; else echo "[notify] image compress failed; sending original" >&2; fi ;;
  esac
}

# wrapper: curl that actually fails loud
post(){ curl --fail --show-error --silent --max-time 25 "$@"; }

case "$CH" in
  telegram)
    : "${TELEGRAM_BOT_TOKEN:?set TELEGRAM_BOT_TOKEN}"; : "${TELEGRAM_CHAT_ID:?set TELEGRAM_CHAT_ID}"
    api="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
    prep_media
    if [ -n "$MEDIA" ]; then
      post -F chat_id="$TELEGRAM_CHAT_ID" -F caption="$MSG" -F photo="@${MEDIA}" "$api/sendPhoto" >/dev/null || die "telegram send failed"
    else
      post "$api/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" --data-urlencode text="$MSG" >/dev/null || die "telegram send failed"
    fi ;;
  discord)
    : "${DISCORD_WEBHOOK_URL:?set DISCORD_WEBHOOK_URL}"; prep_media
    if [ -n "$MEDIA" ]; then
      post -F "content=$MSG" -F "file1=@${MEDIA}" "$DISCORD_WEBHOOK_URL" >/dev/null || die "discord send failed"
    else
      post -H "Content-Type: application/json" -d "{\"content\":$(json_str "$MSG")}" "$DISCORD_WEBHOOK_URL" >/dev/null || die "discord send failed"
    fi ;;
  slack)
    : "${SLACK_WEBHOOK_URL:?set SLACK_WEBHOOK_URL}"
    [ -n "$MEDIA" ] && echo "[notify] slack incoming-webhook can't upload media; sending text only" >&2
    post -H "Content-Type: application/json" -d "{\"text\":$(json_str "$MSG")}" "$SLACK_WEBHOOK_URL" >/dev/null || die "slack send failed" ;;
  imessage)
    : "${IMESSAGE_TO:?set IMESSAGE_TO}"; command -v osascript >/dev/null 2>&1 || die "imessage needs macOS osascript"
    [ -n "$MEDIA" ] && echo "[notify] imessage path sends text only here; media skipped" >&2
    # pass strings as argv (osascript 'on run') to avoid AppleScript injection / quoting breakage
    osascript - "$IMESSAGE_TO" "$MSG" <<'APPLESCRIPT' >/dev/null || die "imessage send failed"
on run argv
  tell application "Messages" to send (item 2 of argv) to buddy (item 1 of argv)
end run
APPLESCRIPT
    ;;
  *) die "unknown NOTIFY_CHANNEL=$CH (telegram|discord|slack|imessage)" ;;
esac
echo "[notify] sent via $CH"
