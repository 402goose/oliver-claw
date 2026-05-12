// tool-sampler hook — captures tool invocations and POSTs to spawn-salon.
// Channel/runtime-agnostic: subscribes to any openclaw event name that might
// fire on tool activity. If none fire, this is a no-op.

const SPAWN_URL = process.env.TOOL_SAMPLER_SPAWN_URL || "http://spawn-salon.railway.internal:8080";
const BOT_SLUG = process.env.TOOL_SAMPLER_BOT_SLUG || "unknown";
const ADMIN_TOKEN = process.env.DEFAULT_SPAWN_SALON_ADMIN_TOKEN || "";

// Track start timestamps per (run, tool) so we can compute duration on end.
const starts = new Map();

async function post(body) {
  try {
    await fetch(`${SPAWN_URL}/api/tool-events`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${ADMIN_TOKEN}` },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(3000),
    });
  } catch (e) {
    console.warn("[tool-sampler] post failed (swallowed):", e?.message || e);
  }
}

function safeGet(obj, path) {
  const parts = path.split(".");
  let cur = obj;
  for (const p of parts) {
    if (cur == null) return undefined;
    cur = cur[p];
  }
  return cur;
}

function extractToolInfo(event) {
  const ctx = event?.context || {};
  // Try several shapes openclaw might use
  const name =
    ctx.tool ||
    ctx.toolName ||
    ctx.name ||
    safeGet(ctx, "metadata.tool") ||
    safeGet(ctx, "tool.name") ||
    safeGet(event, "tool.name") ||
    null;
  const runId =
    ctx.runId ||
    ctx.run_id ||
    safeGet(ctx, "metadata.runId") ||
    null;
  const args = ctx.args || ctx.input || safeGet(ctx, "tool.args");
  const result = ctx.result || ctx.output || safeGet(ctx, "tool.result");
  const error = ctx.error || ctx.errorMessage || safeGet(ctx, "tool.error");
  return {
    toolName: name ? String(name).slice(0, 120) : null,
    runId: runId ? String(runId) : null,
    argsSize: args ? JSON.stringify(args).length : null,
    resultSize: result ? (typeof result === "string" ? result.length : JSON.stringify(result).length) : null,
    errorMessage: error ? String(error).slice(0, 400) : null,
  };
}

const handler = async (event) => {
  if (!ADMIN_TOKEN) return;
  const type = event?.type || "";
  const action = event?.action || "";
  const combined = `${type}:${action}`.toLowerCase();

  // Only process tool-related events
  if (!combined.includes("tool") && type !== "tool") return;

  const info = extractToolInfo(event);
  if (!info.toolName) return; // nothing useful to log

  const now = Date.now();
  const startKey = `${info.runId || "-"}:${info.toolName}`;

  let phase = "invoked";
  if (/start|begin|call$/.test(combined)) phase = "start";
  else if (/end|result|complete/.test(combined)) phase = "end";
  else if (/error|fail/.test(combined)) phase = "error";

  let durationMs = null;
  if (phase === "start") {
    starts.set(startKey, now);
    // Cap memory at 500 active starts
    if (starts.size > 500) {
      const first = starts.keys().next().value;
      if (first !== undefined) starts.delete(first);
    }
    return; // don't POST on start; wait for end
  }
  if (phase === "end" || phase === "error") {
    const startedAt = starts.get(startKey);
    if (startedAt) {
      durationMs = now - startedAt;
      starts.delete(startKey);
    }
  }

  await post({
    bot_slug: BOT_SLUG,
    tool_name: info.toolName,
    run_id: info.runId,
    phase,
    duration_ms: durationMs,
    args_size: info.argsSize,
    result_size: info.resultSize,
    is_error: phase === "error" || !!info.errorMessage,
    error_message: info.errorMessage,
    ts: new Date(now).toISOString(),
  });
};

export default handler;
