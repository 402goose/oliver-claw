---
name: voice-sampler
description: "Capture (prompt, response) pairs from real user interactions and POST to spawn-salon for drift detection. Channel-agnostic — works for telegram, teams, mcp, web."
metadata:
  {
    "openclaw": {
      "emoji": "🎙",
      "events": ["message:received", "message:sent"],
      "requires": { "bins": ["node"] }
    }
  }
---

# voice-sampler

Passively records `(prompt, response)` pairs on every real user interaction. Forwards them over Railway private network to spawn-salon's `/api/voice-samples` endpoint. Drift detection runs on the aggregated corpus — no synthetic probing, no admin surface, zero channel coupling.

## Why this shape

- **Transport-agnostic:** taps `message:received` / `message:sent` which fire for every channel openclaw supports (telegram today, teams coming, mcp / web / slack possible).
- **Zero admin surface:** no new public endpoint on the bot; bot initiates outbound POST to spawn-salon instead.
- **Real traffic > synthetic:** drift detected from how users ACTUALLY interact, not contrived probes that bypass the real pipeline.
- **Scales to `tenet personal`:** every teammate's agent ships with this hook, their spawn-salon aggregates their samples, drift alert before they notice voice shift.

## Behavior

1. On `message:received` → stash the inbound message in an in-memory map keyed by `sessionKey`.
2. On `message:sent` → look up the paired inbound, compose a sample payload, POST to spawn-salon.
3. Never blocks the response path — errors are logged and swallowed.
4. Drops samples from the bot itself (skip self-reply loops).

## Config

```json
{
  "hooks": {
    "internal": {
      "entries": {
        "voice-sampler": {
          "enabled": true,
          "env": {
            "VOICE_SAMPLER_SPAWN_URL": "http://spawn-salon.railway.internal:8080",
            "VOICE_SAMPLER_BOT_SLUG": "oliver"
          }
        }
      }
    }
  }
}
```

`DEFAULT_SPAWN_SALON_ADMIN_TOKEN` is read from env — same shared secret already set on all bots + spawn-salon.

## What's captured per sample

- `bot_slug`, `channel`, `prompt_text`, `response_text`
- `room_id`, `sender_id`, `sender_name` (for category/segmentation)
- `model` (which model actually served this reply)
- `sent_at` (when the bot replied)

## Observability

Once samples flow, `/admin/spend/bots/[slug]` surfaces:
- count per channel (telegram vs teams vs …) last 24h / 7d
- aggregate drift score (comparing recent samples to older baselines)
- model routing distribution across real replies (cross-checks with /api/spend/bot-health)
