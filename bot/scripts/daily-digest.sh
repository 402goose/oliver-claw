#!/bin/sh
# daily-digest.sh — generate digest of last 24h room activity, DM to Real Jack.
# Runs nightly via start-gateway.sh background loop.

set -e
JACK_TG_ID="${JACK_TG_ID:-8779899117}"
LOG=/data/logs/digest.log
mkdir -p /data/logs

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "=== digest cycle start ==="

# Generate digest
DIGEST=$(node /data/scripts/digest.mjs 24 2>&1) || {
  log "FAILED to generate: $DIGEST"
  exit 0
}

# Save copy to disk
DIGEST_FILE=/data/logs/digest-$(date -u +%Y-%m-%d).md
echo "$DIGEST" > "$DIGEST_FILE"
log "saved $DIGEST_FILE ($(wc -c < "$DIGEST_FILE") bytes)"

# Skip delivery if "Nothing new" digest
if echo "$DIGEST" | grep -q "Nothing new in memory"; then
  log "skipping delivery: empty digest"
  exit 0
fi

# Resolve bot token — env var first, then openclaw.json
TOKEN="$TELEGRAM_BOT_TOKEN"
if [ -z "$TOKEN" ]; then
  TOKEN=$(node -e "try{const c=require('/data/openclaw.json');const acc=c.channels?.telegram?.accounts?.default;console.log(acc?.token||acc?.botToken||c.channels?.telegram?.token||'')}catch(e){}" 2>/dev/null)
fi
if [ -z "$TOKEN" ]; then
  log "FAILED: no bot token"
  exit 0
fi

# Telegram sendMessage caps at 4096 chars. Chunk + send.
HEADER=$'Yesterday\'s room digest. Reply "good" if this lands, or correct me on anything specific.\n\n'
FULL_TEXT="${HEADER}${DIGEST}"

# Write to temp file then chunk via awk
echo "$FULL_TEXT" > /tmp/.digest-text
awk 'BEGIN{RS="\n\n"} { print $0 ORS }' /tmp/.digest-text | \
  awk -v lim=3500 '{ buf = buf $0; if (length(buf) >= lim) { print buf "<<<CHUNK>>>"; buf="" } } END { if (buf) print buf }' | \
  awk 'BEGIN{RS="<<<CHUNK>>>"}{ if (length($0) > 0) print "===CHUNK===" $0 }' > /tmp/.digest-chunks

while IFS= read -r LINE; do
  if echo "$LINE" | grep -q "^===CHUNK==="; then
    [ -n "$BUF" ] && {
      HTTP=$(curl -sS --max-time 30 -o /tmp/.tg-resp -w "%{http_code}" \
        "https://api.telegram.org/bot$TOKEN/sendMessage" \
        --data-urlencode "chat_id=$JACK_TG_ID" \
        --data-urlencode "text=$BUF")
      log "TG chunk HTTP=$HTTP (size=$(echo -n "$BUF" | wc -c))"
    }
    BUF=$(echo "$LINE" | sed 's/^===CHUNK===//')
  else
    BUF="$BUF
$LINE"
  fi
done < /tmp/.digest-chunks

# Final chunk
[ -n "$BUF" ] && {
  HTTP=$(curl -sS --max-time 30 -o /tmp/.tg-resp -w "%{http_code}" \
    "https://api.telegram.org/bot$TOKEN/sendMessage" \
    --data-urlencode "chat_id=$JACK_TG_ID" \
    --data-urlencode "text=$BUF")
  log "TG final chunk HTTP=$HTTP"
}

rm -f /tmp/.digest-text /tmp/.digest-chunks /tmp/.tg-resp 2>/dev/null
log "=== digest cycle complete ==="
