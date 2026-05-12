// voice-sampler hook — posts real (prompt, response) pairs to spawn-salon.
// Channel-agnostic: taps openclaw events that fire for all transports.
//
// Events: message:received (stash inbound), message:sent (emit pair)
// Side effect: outbound POST to spawn-salon over Railway private network.
// Non-blocking: errors logged and swallowed.

const SPAWN_URL = process.env.VOICE_SAMPLER_SPAWN_URL || "http://spawn-salon.railway.internal:8080";
const BOT_SLUG = process.env.VOICE_SAMPLER_BOT_SLUG || "unknown";
const ADMIN_TOKEN = process.env.DEFAULT_SPAWN_SALON_ADMIN_TOKEN || "";
const SELF_BOT_ID = String(process.env.LURKER_SELF_BOT_ID || "");

// In-memory pairing cache. Keyed by sessionKey; capped at 200 entries to bound memory.
const pending = new Map();
const PENDING_MAX = 200;

function setPending(key, value) {
  if (pending.size >= PENDING_MAX) {
    // drop oldest
    const first = pending.keys().next().value;
    if (first !== undefined) pending.delete(first);
  }
  pending.set(key, value);
}

function extractChannel(event) {
  const ctx = event?.context || {};
  // openclaw tags the transport in context.transport OR context.channel OR context.metadata.transport
  return (
    ctx.transport ||
    ctx.channel ||
    ctx.metadata?.transport ||
    ctx.metadata?.channel ||
    "unknown"
  );
}

function sessionKeyOf(event) {
  const ctx = event?.context || {};
  return (
    ctx.sessionKey ||
    ctx.sessionId ||
    ctx.metadata?.sessionKey ||
    ctx.channelId ||
    ctx.roomId ||
    "unknown-session"
  );
}

async function post(path, body) {
  try {
    await fetch(`${SPAWN_URL}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${ADMIN_TOKEN}`,
      },
      body: JSON.stringify(body),
      // Keep timeout tight — this must NEVER block the agent's response path
      signal: AbortSignal.timeout(3000),
    });
  } catch (e) {
    console.warn("[voice-sampler] post failed (swallowed):", e?.message || e);
  }
}

const handler = async (event) => {
  if (!ADMIN_TOKEN) return; // not configured, no-op

  if (event.type === "message" && event.action === "received") {
    const ctx = event.context || {};
    const meta = ctx.metadata || {};
    const senderId = String(meta.senderId || meta.from || "");
    if (senderId && senderId === SELF_BOT_ID) return; // ignore bot-originated
    const text = (ctx.content || "").toString().trim();
    if (!text) return;
    setPending(sessionKeyOf(event), {
      prompt_text: text.slice(0, 30_000),
      prompt_tokens: null,
      received_at: new Date().toISOString(),
      room_id: String(meta.guildId || meta.channelId || ctx.channelId || ""),
      sender_id: senderId,
      sender_name: meta.senderName || meta.firstName || meta.username || null,
      channel: extractChannel(event),
    });
    return;
  }

  if (event.type === "message" && event.action === "sent") {
    const ctx = event.context || {};
    const text = (ctx.content || "").toString().trim();
    if (!text) return;
    const key = sessionKeyOf(event);
    const inbound = pending.get(key);
    if (!inbound) return; // no paired prompt (e.g., unprompted outbound)
    pending.delete(key);

    await post("/api/voice-samples", {
      bot_slug: BOT_SLUG,
      channel: inbound.channel || extractChannel(event),
      prompt_text: inbound.prompt_text,
      response_text: text.slice(0, 60_000),
      prompt_tokens: null,
      response_tokens: null,
      room_id: inbound.room_id,
      sender_id: inbound.sender_id,
      sender_name: inbound.sender_name,
      model: ctx.model || ctx.metadata?.model || null,
      sent_at: new Date().toISOString(),
    });
  }
};

export default handler;
