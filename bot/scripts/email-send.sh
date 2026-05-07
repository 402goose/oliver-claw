#!/bin/sh
# email-send.sh — send mail from agent-jack@agentmail.to via AgentMail API.
# Outbound is unrestricted: Jack can email anyone.
#
# Usage:
#   email-send.sh "to@example.com" "Subject line" "Body text (multiline ok)"
#   email-send.sh "to@example.com" "Subject" - <<EOF
#   Multi-line body
#   from stdin
#   EOF
#
# Env (must be set on Railway):
#   AGENTMAIL_API_KEY  — Bearer token from agentmail.to console

set -e

INBOX="agent-jack@agentmail.to"
API="https://api.agentmail.to"

if [ -z "$AGENTMAIL_API_KEY" ]; then
  echo "[email-send] FATAL: AGENTMAIL_API_KEY not set" >&2
  exit 1
fi

TO="$1"
SUBJECT="$2"
BODY="$3"

if [ -z "$TO" ] || [ -z "$SUBJECT" ]; then
  echo "[email-send] usage: email-send.sh <to> <subject> <body|->" >&2
  exit 2
fi

if [ "$BODY" = "-" ]; then
  BODY=$(cat)
fi

PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'to': [sys.argv[1]],
    'subject': sys.argv[2],
    'text': sys.argv[3],
}))
" "$TO" "$SUBJECT" "$BODY")

RESP=$(curl -sS -w "\n%{http_code}" -X POST "$API/inboxes/$INBOX/messages/send" \
  -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')

if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  echo "[email-send] FAILED http=$CODE body=$BODY_RESP" >&2
  exit 3
fi

MSG_ID=$(echo "$BODY_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message_id') or d.get('id') or 'unknown')")
echo "[email-send] sent to=$TO subject=\"$SUBJECT\" message_id=$MSG_ID"
