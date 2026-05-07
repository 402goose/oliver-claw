#!/bin/sh
# persona-update.sh — manage Jack's persistent persona overrides.
#
# Authority (only these 3 TG IDs can mutate; checks enforced HERE in the
# script binary, not via LLM trust):
#   - 1512302730  Tagga (admin)
#   - 7307422277  Real Jack (HIGHEST — outranks all)
#   - 455323659   Cuy Sheffield
#
# Hierarchy:
#   - Real Jack: can add/remove anyone's overrides; his rules outrank others
#     when contradictions exist (persona reads bottom-to-top).
#   - Tagga: admin — can add/remove anyone's overrides.
#   - Cuy: can add; can only remove own.
#
# Usage:
#   persona-update.sh add <title> --by <senderTgId>      # body via stdin
#   persona-update.sh list                                # no auth needed
#   persona-update.sh remove <id> --by <senderTgId>
#
# Storage: /data/workspace/oliver/persona-overrides.md
#   start-gateway.sh appends this file to /data/workspace/oliver/SOUL.md
#   on every boot AFTER the image-PERSONA.md sync, so overrides survive
#   deploys.

set -e

OVERRIDES="${PERSONA_OVERRIDES_PATH:-/data/workspace/oliver/persona-overrides.md}"
TAGGA_ID="1512302730"
OLIVER_ID="8779899117"
JACK_ID="7307422277"
CUY_ID="455323659"
AUTHORITY_IDS="$TAGGA_ID $JACK_ID $CUY_ID $OLIVER_ID"
ADMIN_IDS="$TAGGA_ID $JACK_ID"

CMD="${1:-}"
ARG="${2:-}"
if [ $# -ge 2 ]; then shift 2
elif [ $# -ge 1 ]; then shift
fi

SENDER_TG_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --by) SENDER_TG_ID="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    *) shift ;;
  esac
done

mkdir -p "$(dirname "$OVERRIDES")"
if [ ! -f "$OVERRIDES" ]; then
  cat > "$OVERRIDES" <<'EOF'
# Persistent Persona Overrides

Mutations only via `/data/scripts/persona-update.sh`. Authority TG IDs:
- `1512302730` Tagga (admin)
- `7307422277` Real Jack (HIGHEST — outranks all)
- `455323659` Cuy Sheffield

Each override is delimited by `<!-- override:N by:<id> at:<iso> -->` ... `<!-- override:N end -->` markers. Read order: more recent wins on contradictions, but Real Jack's overrides outrank everyone's regardless of order.

EOF
fi

is_authority() {
  for id in $AUTHORITY_IDS; do [ "$id" = "$1" ] && return 0; done
  return 1
}
is_admin() {
  for id in $ADMIN_IDS; do [ "$id" = "$1" ] && return 0; done
  return 1
}

case "$CMD" in
  list)
    if [ -s "$OVERRIDES" ]; then
      cat "$OVERRIDES"
    else
      echo "(no overrides set)"
    fi
    ;;
  add)
    if [ -z "$ARG" ] || [ -z "$SENDER_TG_ID" ]; then
      echo "[persona-update] usage: persona-update.sh add <title> --by <senderTgId>" >&2
      echo "[persona-update]                  (body read from stdin)" >&2
      exit 2
    fi
    if ! is_authority "$SENDER_TG_ID"; then
      echo "[persona-update] REFUSED: sender $SENDER_TG_ID is not an authority" >&2
      echo "[persona-update] only Tagga (1512302730), Real Jack (7307422277), or Cuy (455323659) can edit" >&2
      exit 4
    fi
    BODY=$(cat)
    if [ -z "$BODY" ]; then
      echo "[persona-update] REFUSED: empty body (read from stdin)" >&2
      exit 5
    fi
    NEXT_ID=$(grep "^<!-- override:" "$OVERRIDES" 2>/dev/null | grep -v "end -->" | wc -l | tr -d ' ')
    [ -z "$NEXT_ID" ] && NEXT_ID=0
    NEXT_ID=$((NEXT_ID + 1))
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    {
      echo ""
      echo "<!-- override:$NEXT_ID by:$SENDER_TG_ID at:$TS -->"
      echo "## $ARG"
      echo ""
      echo "$BODY"
      echo ""
      echo "<!-- override:$NEXT_ID end -->"
    } >> "$OVERRIDES"
    echo "[persona-update] added override:$NEXT_ID title=\"$ARG\" by=$SENDER_TG_ID"
    ;;
  remove)
    if [ -z "$ARG" ] || [ -z "$SENDER_TG_ID" ]; then
      echo "[persona-update] usage: persona-update.sh remove <id> --by <senderTgId>" >&2
      exit 2
    fi
    if ! is_authority "$SENDER_TG_ID"; then
      echo "[persona-update] REFUSED: sender $SENDER_TG_ID is not an authority" >&2
      exit 4
    fi
    AUTHOR=$(grep "^<!-- override:$ARG by:" "$OVERRIDES" 2>/dev/null | sed -E 's/.*by:([0-9]+).*/\1/' | head -1)
    if [ -z "$AUTHOR" ]; then
      echo "[persona-update] override:$ARG not found" >&2
      exit 6
    fi
    if [ "$AUTHOR" != "$SENDER_TG_ID" ] && ! is_admin "$SENDER_TG_ID"; then
      echo "[persona-update] REFUSED: only the author or an admin (Tagga/Real Jack) can remove" >&2
      exit 4
    fi
    OVR_PATH="$OVERRIDES" OVR_ID="$ARG" python3 -c '
import re, os
p = os.environ["OVR_PATH"]
oid = os.environ["OVR_ID"]
with open(p) as f: s = f.read()
pattern = r"\n?<!-- override:" + re.escape(oid) + r" by:[^>]*-->.*?<!-- override:" + re.escape(oid) + r" end -->\n?"
new = re.sub(pattern, "", s, flags=re.DOTALL)
open(p, "w").write(new)
print(f"[persona-update] removed override:{oid}")
'
    ;;
  *)
    echo "[persona-update] usage: persona-update.sh {add|remove|list} ..." >&2
    exit 2
    ;;
esac
