#!/usr/bin/env node
// recall.mjs — priority-ranked retrieval over memory + corpus.
//
// Why: the agent's persona says "search memory before answering" but it's a
// soft instruction the model often skips. This script forces a unified recall
// that ranks results by source authority:
//   1. jack-authoritative memory (Real Jack's input)
//   2. scope:room memory (team-shared context)
//   3. corpus chunks (public substrate)
//
// Usage: node recall.mjs "<query>" [k]
// Defaults: k=5 per source band.

import Database from 'better-sqlite3';
import * as sqliteVec from 'sqlite-vec';

const MEMORY_DB = '/data/tenet/.tenet/memory.db';
const CORPUS_DB = '/data/agents/dee/corpus-vec.sqlite';
const KEY = process.env.OPENROUTER_API_KEY;
const query = process.argv[2];
const k = parseInt(process.argv[3] || '5', 10);

if (!query) { console.error('usage: recall.mjs "<query>" [k]'); process.exit(1); }

// ---- 1. memory.db priority search (FTS-style on content + title) ----
function searchMemory(q, limit) {
  const db = new Database(MEMORY_DB, { readonly: true });
  // Build LIKE patterns from query terms (lowercase, alphanumeric)
  const terms = q.toLowerCase().split(/\W+/).filter(t => t.length >= 3);
  if (!terms.length) { db.close(); return []; }
  const likes = terms.map(() => `(LOWER(m.content) LIKE ? OR LOWER(m.title) LIKE ?)`).join(' OR ');
  const params = terms.flatMap(t => [`%${t}%`, `%${t}%`]);
  const sql = `
    SELECT m.id, m.title, m.content, m.created_at, m.source, m.type,
           COALESCE(GROUP_CONCAT(t.tag, ','), '') AS tags,
           CASE
             WHEN COALESCE(GROUP_CONCAT(t.tag, ','), '') LIKE '%jack-authoritative%' THEN 0
             WHEN COALESCE(GROUP_CONCAT(t.tag, ','), '') LIKE '%scope:room%' THEN 1
             ELSE 2
           END AS priority
    FROM memories m
    LEFT JOIN tags t ON t.memory_id = m.id
    WHERE ${likes}
    GROUP BY m.id
    ORDER BY priority ASC, m.created_at DESC
    LIMIT ?
  `;
  const rows = db.prepare(sql).all(...params, limit);
  db.close();
  return rows;
}

// ---- 2. corpus vector search ----
async function searchCorpus(q, limit) {
  if (!KEY) return [];
  const r = await fetch('https://openrouter.ai/api/v1/embeddings', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'openai/text-embedding-3-large', input: q }),
  });
  if (!r.ok) return [];
  const j = await r.json();
  const vec = Buffer.from(Float32Array.from(j.data[0].embedding).buffer);

  const db = new Database(CORPUS_DB, { readonly: true });
  sqliteVec.load(db);
  const rows = db.prepare(`
    SELECT c.file, c.chunk_idx, c.text, v.distance
    FROM vec_chunks v JOIN chunks c ON c.id = v.rowid
    WHERE v.embedding MATCH ? AND k = ?
    ORDER BY v.distance
  `).all(vec, limit);
  db.close();
  return rows;
}

// ---- 3. format and print ----
const memHits = searchMemory(query, k);
const jackAuth = memHits.filter(m => (m.tags || '').includes('jack-authoritative'));
const room = memHits.filter(m => (m.tags || '').includes('scope:room') && !(m.tags || '').includes('jack-authoritative'));
const otherMem = memHits.filter(m => !(m.tags || '').includes('jack-authoritative') && !(m.tags || '').includes('scope:room'));

const corpusHits = await searchCorpus(query, k);

console.log(`# Recall for: "${query}"`);
console.log('');

if (jackAuth.length) {
  console.log('## [JACK-AUTHORITATIVE] — what Real Jack has actually said (highest priority)');
  console.log('');
  for (const m of jackAuth) {
    console.log(`### ${m.title} (${m.created_at})`);
    console.log(m.content.slice(0, 1500));
    console.log('');
  }
}

if (room.length) {
  console.log('## [ROOM] — shared team context (Content Dump, Visa CLI Core)');
  console.log('');
  for (const m of room) {
    console.log(`### ${m.title} (${m.created_at})`);
    console.log(m.content.slice(0, 1000));
    console.log('');
  }
}

if (otherMem.length) {
  console.log('## [MEMORY] — other saved context');
  console.log('');
  for (const m of otherMem) {
    console.log(`### ${m.title} (${m.created_at})`);
    console.log(m.content.slice(0, 800));
    console.log('');
  }
}

if (corpusHits.length) {
  console.log('## [CORPUS] — public substrate (Wolfe, MS-TMT, Product Drop, Moonshots, earnings, articles)');
  console.log('');
  for (const r of corpusHits) {
    console.log(`### ${r.file} (chunk ${r.chunk_idx}, distance ${r.distance.toFixed(4)})`);
    console.log(r.text.slice(0, 800));
    console.log('');
  }
}

if (!jackAuth.length && !room.length && !otherMem.length && !corpusHits.length) {
  console.log('_No matches in memory or corpus._');
}
