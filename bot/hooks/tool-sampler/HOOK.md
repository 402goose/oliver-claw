---
name: tool-sampler
description: "Capture every tool call the agent makes — name, duration, success. POSTs to spawn-salon /api/tool-events for fleet-wide tool usage observability."
metadata:
  {
    "openclaw": {
      "emoji": "🔧",
      "events": ["tool:start", "tool:end", "tool:error", "tool:call", "agent:tool_call", "agent:tool_result"],
      "requires": { "bins": ["node"] }
    }
  }
---

# tool-sampler

Passively records every tool call made by the agent. POSTs each event to spawn-salon over Railway private network. Matches the voice-sampler pattern for drift detection but at the tool-use layer.

## Why

Today we see LOAD-time tool failures (`plugin tool factory returned null`) but NOT which tools the agent actually invokes during runs. Without this:
- Can't tell if tools are working end-to-end
- Can't trim unused tools from the tool schema (system prompt cost)
- Can't detect "tool always fails" patterns
- Can't compare tool-use patterns across bots to identify best practices

## Event shape (guessed — openclaw's event taxonomy isn't documented here)

Subscribes to multiple event names that openclaw MAY emit on tool activity. The handler inspects the event and extracts whatever makes sense. If none fire, the hook is a no-op.

## Config

```json
{
  "hooks": {
    "internal": {
      "entries": {
        "tool-sampler": {
          "enabled": true,
          "env": {
            "TOOL_SAMPLER_SPAWN_URL": "http://spawn-salon.railway.internal:8080",
            "TOOL_SAMPLER_BOT_SLUG": "oliver"
          }
        }
      }
    }
  }
}
```

Shares the `DEFAULT_SPAWN_SALON_ADMIN_TOKEN` admin secret.
