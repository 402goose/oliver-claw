---
name: lurker
description: "Capture every Telegram message in opted-in rooms to memory.db with speaker tag, room tag, scope:room. Bypasses agent routing — silent ingest."
metadata:
  {
    "openclaw": {
      "emoji": "👂",
      "events": ["message:received"],
      "requires": { "bins": ["node"] }
    }
  }
---

# lurker

Listens to every inbound message via `message:received` and writes structured memory entries — without triggering the agent. Built to give the agent rich context on what the team has been saying, even when no one @-mentioned the bot.

## Why

Default openclaw flow drops non-mention messages before the agent sees them. That means the agent only "knows" about messages that triggered it. For a room like Visa CLI Core where the team is debating product strategy, most messages don't mention the bot — but they're exactly the context the agent needs when later asked "what did the team conclude about X?"

This hook bypasses that by writing every message to `memory.db` directly, with rich tags so `recall.sh` and `memory_search` can surface them.

## Behavior

- Filters on **opted-in rooms only** (env var `LURKER_ROOM_ALLOWLIST`). Default: Visa CLI Core groups + Content Dump + Testing.
- Skips messages from the bot itself (would create infinite-feedback memory entries).
- Skips empty messages.
- For each captured message, inserts into `memories` table with:
  - `source = "lurker"`
  - `type = "room-msg"`
  - `content = full message text`
  - `title = "<speaker_name>: <first 50 chars>"`
  - tags: `scope:room`, `room:<chat_id>`, `speaker:<sender_name>`, `senderId:<tg_id>`, `lurker`
- Does NOT compute embeddings inline (would add latency + cost). The `recall.sh` keyword path still surfaces these. Periodic re-embed cron can backfill embeddings later.

## Config

```json
{
  "hooks": {
    "internal": {
      "entries": {
        "lurker": {
          "enabled": true,
          "env": {
            "LURKER_ROOM_ALLOWLIST": "-5020859100,-50208591,-5180909745,-5262769177",
            "LURKER_SELF_BOT_ID": "8691785408",
            "LURKER_DB": "/data/tenet/.tenet/memory.db"
          }
        }
      }
    }
  }
}
```

## Output

Each captured message becomes a row in `memory.db.memories` plus 4-5 rows in `memory.db.tags`. Visible via:

```bash
sqlite3 /data/tenet/.tenet/memory.db "
  SELECT m.id, m.title, m.created_at, GROUP_CONCAT(t.tag, ',') AS tags
  FROM memories m LEFT JOIN tags t ON t.memory_id = m.id
  WHERE m.source = 'lurker'
  GROUP BY m.id ORDER BY m.created_at DESC LIMIT 20"
```
