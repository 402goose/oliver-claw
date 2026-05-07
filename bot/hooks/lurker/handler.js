// lurker hook — writes every inbound message in opted-in rooms to memory.db.
// Uses sqlite3 CLI via child_process (no Node module deps; openclaw runtime
// doesn't bundle better-sqlite3).
//
// Triggers on: message:received
// Side effect: SQLite insert into memories + tags. No external API calls.

import { execSync } from 'node:child_process';

const ROOM_ALLOWLIST = (process.env.LURKER_ROOM_ALLOWLIST || '-5020859100,-50208591,-5180909745,-5262769177')
  .split(',').map(s => s.trim()).filter(Boolean);
const SELF_BOT_ID = String(process.env.LURKER_SELF_BOT_ID || '8691785408');
const DB_PATH = process.env.LURKER_DB || '/data/tenet/.tenet/memory.db';

function sqlEscape(s) {
  return String(s).replace(/'/g, "''");
}

const handler = async (event) => {
  // Subscription in HOOK.md ("events": ["message:received"]) already gates
  // dispatch upstream — the old strict event.type/action filter assumed a
  // payload shape that openclaw 2026.4.x changed, silently dropping every
  // event. Be defensive about the shape; bail late, on the actual fields
  // we need.

  const ctx = event?.context || event?.payload || event || {};
  const meta = ctx.metadata || ctx.meta || event?.metadata || {};
  const channel = ctx.channelId || meta.guildId || meta.channelId;
  const senderId = String(meta.senderId || meta.from || meta.sender_id || '');
  const senderName = meta.senderName || meta.firstName || meta.username || meta.name || 'unknown';
  const text = (ctx.content || ctx.text || ctx.body || '').toString().trim();

  if (process.env.LURKER_DEBUG === '1') {
    try {
      const evKeys = Object.keys(event || {}).join(',');
      const ctxKeys = Object.keys(ctx).join(',');
      const metaKeys = Object.keys(meta).join(',');
      console.error(`[lurker:debug] ev=${evKeys} ctx=${ctxKeys} meta=${metaKeys} sid=${senderId} room=${channel || meta.guildId} textlen=${text.length}`);
    } catch {}
  }

  const roomId = String(meta.guildId || channel || '');
  if (!ROOM_ALLOWLIST.includes(roomId)) return;
  if (senderId === SELF_BOT_ID) return;
  if (!text) return;

  try {
    const now = new Date().toISOString();
    const title = sqlEscape(`${senderName}: ${text.slice(0, 60).replace(/\n/g, ' ')}`);
    const content = sqlEscape(text);
    const sourceId = sqlEscape(`tg-${senderId}-${Date.now()}`);

    const tagsList = [
      'scope:room',
      'lurker',
      `room:${roomId}`,
      `speaker:${senderName}`,
      `senderId:${senderId}`,
    ];
    if (senderId === '8779899117') tagsList.push('source:oliver-authoritative');

    // Compose a single SQL transaction: insert memory, then tags
    const tagInserts = tagsList
      .map(t => `INSERT INTO tags (memory_id, tag) VALUES (last_insert_rowid(), '${sqlEscape(t)}');`)
      .join('\n');

    const sql = `BEGIN;
INSERT INTO memories (source, source_id, type, title, content, created_at, indexed_at)
VALUES ('lurker', '${sourceId}', 'room-msg', '${title}', '${content}', '${now}', '${now}');
${tagInserts}
COMMIT;`;

    execSync(`sqlite3 "${DB_PATH}"`, {
      input: sql,
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    console.error('[lurker] failed:', e.message);
  }
};

export default handler;
