#!/bin/sh
# email-read.sh — list inbox messages, filtered through the read-allowlist.
# Jack can ONLY see mail from senders in the allowlist. Anything else is
# silently dropped — not summarized, not surfaced, not even counted.
#
# This script is the ONLY sanctioned path to inbox content. Persona forbids
# direct curl to AgentMail's list endpoint without this filter.
#
# Usage:
#   email-read.sh                    # last 50 messages, allowlisted only
#   email-read.sh 100                # last 100 messages, allowlisted only
#   email-read.sh --raw-counts       # diagnostic: total vs filtered counts
#                                       (no content from blocked).
#
# Env:
#   AGENTMAIL_API_KEY  — Bearer token

set -e

INBOX="agent-jack@agentmail.to"
API="https://api.agentmail.to"
ALLOWLIST="${EMAIL_ALLOWLIST_PATH:-/data/workspace/oliver/email-allowlist.json}"

if [ -z "$AGENTMAIL_API_KEY" ]; then
  echo "[email-read] FATAL: AGENTMAIL_API_KEY not set" >&2
  exit 1
fi

LIMIT="${1:-50}"
MODE=normal
case "$LIMIT" in
  --raw-counts) MODE=counts; LIMIT=50 ;;
esac

curl -sS -X GET "$API/inboxes/$INBOX/messages?limit=$LIMIT" \
  -H "Authorization: Bearer $AGENTMAIL_API_KEY" \
| ALLOWLIST_PATH="$ALLOWLIST" READ_MODE="$MODE" python3 -c '
import json, sys, os, re

allowlist_path = os.environ["ALLOWLIST_PATH"]
mode = os.environ["READ_MODE"]

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"[email-read] FAILED to parse AgentMail response: {e}", file=sys.stderr)
    sys.exit(3)

if isinstance(data, dict) and "messages" in data:
    msgs = data["messages"]
elif isinstance(data, list):
    msgs = data
else:
    keys = list(data.keys()) if isinstance(data, dict) else type(data).__name__
    print(f"[email-read] FAILED: unexpected shape: {keys}", file=sys.stderr)
    print(raw[:500], file=sys.stderr)
    sys.exit(3)

allow = []
if os.path.isfile(allowlist_path):
    with open(allowlist_path) as f:
        allow_doc = json.load(f)
    allow = [a.lower().strip() for a in allow_doc.get("allowlist", [])]

def sender_addr(m):
    f = m.get("from") or m.get("sender") or ""
    if isinstance(f, dict):
        f = f.get("email") or f.get("address") or ""
    if isinstance(f, list) and f:
        first = f[0]
        f = first.get("email") if isinstance(first, dict) else first
    addr = re.search(r"[\w\.\-\+]+@[\w\.\-]+", str(f or ""))
    return addr.group(0).lower() if addr else ""

def is_allowed(addr):
    if not addr: return False
    if addr in allow: return True
    if "@" in addr:
        domain = "@" + addr.split("@", 1)[1]
        if domain in allow: return True
    return False

allowed = [m for m in msgs if is_allowed(sender_addr(m))]
blocked = [m for m in msgs if not is_allowed(sender_addr(m))]

if mode == "counts":
    print(f"total={len(msgs)} allowed={len(allowed)} blocked={len(blocked)} allowlist_size={len(allow)}")
    if blocked:
        seen = {}
        for m in blocked:
            a = sender_addr(m) or "(no-sender)"
            seen[a] = seen.get(a, 0) + 1
        print("blocked_senders (counts only, no content):")
        for a, c in sorted(seen.items(), key=lambda x: -x[1]):
            print(f"  {c}x  {a}")
    sys.exit(0)

if not allowed:
    print(f"[email-read] 0 allowlisted messages in last {len(msgs)}. (allowlist size: {len(allow)})")
    if not allow:
        print("[email-read] Allowlist is empty. Ask Tagga, Real Jack, or Cuy to add senders via:")
        print("[email-read]   email-allowlist.sh add <email-or-@domain> --by <senderTgId>")
    sys.exit(0)

for m in allowed:
    addr = sender_addr(m)
    subj = m.get("subject", "(no subject)")
    ts = m.get("received_at") or m.get("created_at") or ""
    mid = m.get("id") or m.get("message_id") or ""
    preview = (m.get("preview") or m.get("text") or m.get("snippet") or "").replace("\n", " ")[:200]
    print("---")
    print(f"from:    {addr}")
    print(f"subject: {subj}")
    print(f"at:      {ts}")
    print(f"id:      {mid}")
    print(f"preview: {preview}")
'
