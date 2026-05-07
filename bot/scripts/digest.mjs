#!/usr/bin/env node
// digest.mjs — daily digest of room activity, in Jack's voice, DM'd to Real Jack.
//
// Pulls last 24h of memories tagged scope:room (or with content-dump / visa-cli-core
// group tags), summarizes via the agent's primary model, formats as a Jack-Pack
// shape (Top X things / Why it matters / Open questions), and prints to stdout.
//
// The boot script's background loop calls this nightly. Real Jack receives it as a
// DM (handled separately by start-gateway.sh).
//
// Usage: digest.mjs [hours_back]   default: 24

import Database from 'better-sqlite3';

const MEMORY_DB = '/data/tenet/.tenet/memory.db';
const HOURS_BACK = parseInt(process.argv[2] || '24', 10);
const KEY = process.env.OPENROUTER_API_KEY;
const MODEL = process.env.DIGEST_MODEL || 'openrouter/openai/gpt-5.5';

if (!KEY) {
  console.error('OPENROUTER_API_KEY required');
  process.exit(1);
}

// Pull memories from last HOURS_BACK hours, scoped to room/group context
const db = new Database(MEMORY_DB, { readonly: true });
const cutoff = new Date(Date.now() - HOURS_BACK * 3600 * 1000).toISOString();

const rows = db.prepare(`
  SELECT m.id, m.title, m.content, m.created_at, m.source, m.type,
         COALESCE(GROUP_CONCAT(t.tag, ','), '') AS tags
  FROM memories m
  LEFT JOIN tags t ON t.memory_id = m.id
  WHERE m.created_at > ?
  GROUP BY m.id
  ORDER BY m.created_at ASC
`).all(cutoff);
db.close();

if (rows.length === 0) {
  console.log(`# Digest: last ${HOURS_BACK}h\n\n_Nothing new in memory. Quiet day._`);
  process.exit(0);
}

// Build the digest input
const memoryDump = rows.map(r => {
  const tagStr = r.tags ? ` [${r.tags}]` : '';
  return `### ${r.title} (${r.created_at})${tagStr}\n${r.content}`;
}).join('\n\n');

const prompt = `You are Jack Forestell's digital exec lens. Below are the memories captured in the last ${HOURS_BACK} hours from the Visa CLI Core team's rooms (Content Dump, Visa CLI Core, testing). Write Real Jack a tight daily digest in his voice — direct, declarative, no AI tells, no em dashes, no "Hope this helps" closes.

Format:

## Today's roll-up
One sentence: what's the single thread running through today's intake?

## Top 3-5 things worth your time
For each: bold the headline, one sentence on what it is, one sentence on what it means for our roadmap. Don't list everything — filter through your lens (strategic fit, platform leverage, monetization, trust architecture).

## Where the team is heading
2-3 sentences on what the room seems to be converging or diverging on. What questions are unresolved.

## What I'd flag for you specifically
1-3 short items where you specifically should weigh in — corrections you might want to make, opinions only you can give, or threads that stall without your call.

End with: "Reply 'good' if this lands, or correct me on anything specific. Your corrections rank above the public corpus."

Keep total length under 600 words. Don't pad.

Memories:

${memoryDump}`;

const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${KEY}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    model: MODEL.replace(/^openrouter\//, ''),
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 1500,
  }),
});

if (!r.ok) {
  console.error(`digest http ${r.status}: ${await r.text()}`);
  process.exit(2);
}

const j = await r.json();
const text = j.choices?.[0]?.message?.content?.trim() || '_Empty response from model._';

console.log(`# Digest for the last ${HOURS_BACK}h (${rows.length} memories considered)\n`);
console.log(text);
console.log(`\n---\n_Generated ${new Date().toISOString()} from /data/scripts/digest.mjs_`);
