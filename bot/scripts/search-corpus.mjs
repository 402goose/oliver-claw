#!/usr/bin/env node
// search-corpus.mjs — semantic search over the pre-embedded corpus-vec.sqlite.
// Usage: node search-corpus.mjs "query" [k]
// Output: top-k chunks formatted for prompt injection.

import Database from 'better-sqlite3';
import * as sqliteVec from 'sqlite-vec';

const DB_PATH = '/data/agents/dee/corpus-vec.sqlite';
const KEY = process.env.OPENROUTER_API_KEY;
const query = process.argv[2];
const k = parseInt(process.argv[3] || '8', 10);

if (!query) { console.error('usage: search-corpus.mjs "<query>" [k]'); process.exit(1); }
if (!KEY) { console.error('OPENROUTER_API_KEY missing'); process.exit(1); }

const r = await fetch('https://openrouter.ai/api/v1/embeddings', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${KEY}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ model: 'openai/text-embedding-3-large', input: query }),
});
if (!r.ok) { console.error(`embed http ${r.status}`); process.exit(1); }
const j = await r.json();
const vec = Buffer.from(Float32Array.from(j.data[0].embedding).buffer);

const db = new Database(DB_PATH, { readonly: true });
sqliteVec.load(db);
const rows = db.prepare(`
  SELECT c.file, c.chunk_idx, c.text, v.distance
  FROM vec_chunks v JOIN chunks c ON c.id = v.rowid
  WHERE v.embedding MATCH ? AND k = ? ORDER BY v.distance
`).all(vec, k);
db.close();

console.log(`# Top ${rows.length} corpus matches for "${query}"\n`);
for (const [i, row] of rows.entries()) {
  console.log(`## ${i+1}. ${row.file} (chunk ${row.chunk_idx}, distance ${row.distance.toFixed(4)})\n`);
  console.log(row.text.trim().slice(0, 1200));
  console.log('\n---\n');
}
