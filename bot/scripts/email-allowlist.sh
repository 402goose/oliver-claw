#!/bin/sh
# email-allowlist.sh — manage Jack's read-allowlist.
#
# Authority: only the 3 hardcoded TG IDs can mutate the allowlist:
#   - 1512302730  Alec Taggart (Tagga, infra owner)
#   - 7307422277  Jack Forestell (the real one)
#   - 455323659  Cuy Sheffield (Visa, head of crypto)
#
# Anyone else issuing an add/remove command gets refused. Authority check is
# enforced HERE in the script — not just in persona — so a prompt-injection
# can't grant itself allowlist write access via the LLM.
#
# Usage:
#   email-allowlist.sh add <email-or-@domain> --by <senderTgId>
#   email-allowlist.sh remove <email-or-@domain> --by <senderTgId>
#   email-allowlist.sh list                       # no auth needed for read
#
# Bare-domain entries (e.g. "@visa.com") allow all senders from that domain.
# Bare-email entries (e.g. "cuy.sheffield@visa.com") allow only that address.

set -e

ALLOWLIST="${EMAIL_ALLOWLIST_PATH:-/data/workspace/oliver/email-allowlist.json}"
AUTHORITY_IDS="1512302730 7307422277 455323659"

CMD="${1:-}"
TARGET="${2:-}"
# Guarded shift — dash's `set -e` fires on `shift N` when N>$# regardless of
# trailing `|| true`, so we check first.
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

mkdir -p "$(dirname "$ALLOWLIST")"
if [ ! -f "$ALLOWLIST" ]; then
  echo '{"allowlist":[],"updated_at":"","updated_by":""}' > "$ALLOWLIST"
fi

case "$CMD" in
  list)
    python3 -c "
import json
d=json.load(open('$ALLOWLIST'))
print('allowlist ('+str(len(d['allowlist']))+' entries):')
for a in sorted(d['allowlist']):
    print('  '+a)
print('updated_at: '+d.get('updated_at',''))
print('updated_by: '+d.get('updated_by',''))
"
    ;;
  add|remove)
    if [ -z "$TARGET" ] || [ -z "$SENDER_TG_ID" ]; then
      echo "[allowlist] usage: email-allowlist.sh $CMD <email-or-@domain> --by <senderTgId>" >&2
      exit 2
    fi
    AUTHORIZED=0
    for id in $AUTHORITY_IDS; do
      if [ "$id" = "$SENDER_TG_ID" ]; then AUTHORIZED=1; fi
    done
    if [ $AUTHORIZED -eq 0 ]; then
      echo "[allowlist] REFUSED: sender $SENDER_TG_ID is not in authority list" >&2
      echo "[allowlist] only Tagga (1512302730), Real Jack (7307422277), or Cuy (455323659) can edit" >&2
      exit 4
    fi
    python3 -c "
import json, datetime, sys
target=sys.argv[1].lower().strip()
cmd=sys.argv[2]
by=sys.argv[3]
d=json.load(open('$ALLOWLIST'))
allow=[a.lower().strip() for a in d.get('allowlist', [])]
if cmd=='add':
    if target not in allow: allow.append(target)
elif cmd=='remove':
    allow=[a for a in allow if a != target]
d['allowlist']=sorted(set(allow))
d['updated_at']=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
d['updated_by']=by
json.dump(d, open('$ALLOWLIST','w'), indent=2)
print(f'[allowlist] {cmd} {target} (by {by}) → {len(d[\"allowlist\"])} entries')
" "$TARGET" "$CMD" "$SENDER_TG_ID"
    ;;
  *)
    echo "[allowlist] usage: email-allowlist.sh {add|remove|list} ..." >&2
    exit 2
    ;;
esac
