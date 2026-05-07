#!/usr/bin/env node
// embed-corpus.mjs — embed the corpus via OpenRouter, store in sqlite-vec
//
// Usage:
//   OPENROUTER_API_KEY=sk-or-... node embed-corpus.mjs
//
// Walks /data/repo/knowledge/corpus/**/*.md, chunks at 800 tokens (15% overlap),
// embeds via openai/text-embedding-3-large (3072-dim) through OpenRouter, stores
// in /data/agents/dee/corpus-vec.sqlite as a vec0 virtual table.

import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import Database from 'better-sqlite3';
import * as sqliteVec from 'sqlite-vec';

const CORPUS_ROOT = process.env.CORPUS_ROOT || '/data/repo/knowledge/corpus';
const DB_PATH = process.env.CORPUS_DB || '/data/agents/dee/corpus-vec.sqlite';
const MODEL = process.env.EMBED_MODEL || 'openai/text-embedding-3-large';
const DIM = MODEL.includes('large') ? 3072 : 1536;
const CHUNK_TOKENS = 800;
const OVERLAP_TOKENS = 120;
const BATCH = 16;
const MAX_CHUNKS_PER_FILE = parseInt(process.env.MAX_CHUNKS_PER_FILE || '40', 10);
// SEC filings are huge (some 4MB+). Cap chunks per file so we sample
// evenly across long docs rather than embedding 1500 chunks of 10-Q boilerplate.
const KEY = process.env.OPENROUTER_API_KEY;
if (!KEY) { console.error('OPENROUTER_API_KEY required'); process.exit(1); }

// ------ utilities ------
async function* walk(dir) {
  for (const e of await fs.readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (e.isFile() && p.endsWith('.md')) yield p;
  }
}

// rough tokenization: ~4 chars/token average for english, more for code
function approxTokens(s) { return Math.ceil(s.length / 4); }

function chunk(text) {
  const chars = CHUNK_TOKENS * 4;
  const overlap = OVERLAP_TOKENS * 4;
  const out = [];
  for (let i = 0; i < text.length; i += chars - overlap) {
    const piece = text.slice(i, i + chars);
    if (piece.trim().length < 50) continue;
    out.push({ start: i, text: piece });
    if (i + chars >= text.length) break;
  }
  // Cap per-file: if a giant doc would produce more than MAX_CHUNKS_PER_FILE
  // chunks, sample evenly across the doc to preserve coverage.
  if (out.length > MAX_CHUNKS_PER_FILE) {
    const step = out.length / MAX_CHUNKS_PER_FILE;
    const sampled = [];
    for (let i = 0; i < MAX_CHUNKS_PER_FILE; i++) {
      sampled.push(out[Math.min(out.length - 1, Math.floor(i * step))]);
    }
    return sampled;
  }
  return out;
}

function sha(s) { return createHash('sha256').update(s).digest('hex').slice(0, 16); }

async function embedBatch(inputs) {
  const r = await fetch('https://openrouter.ai/api/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: MODEL, input: inputs }),
  });
  if (!r.ok) throw new Error(`embed http ${r.status}: ${await r.text()}`);
  const json = await r.json();
  return json.data.map(d => d.embedding);
}

// ------ db ------
const db = new Database(DB_PATH);
sqliteVec.load(db);
db.exec(`
  CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY,
    file TEXT NOT NULL,
    chunk_idx INTEGER NOT NULL,
    sha TEXT NOT NULL UNIQUE,
    text TEXT NOT NULL,
    char_start INTEGER NOT NULL,
    char_end INTEGER NOT NULL,
    file_mtime INTEGER,
    created_at INTEGER DEFAULT (strftime('%s','now'))
  );
  CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file);
  CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
    embedding float[${DIM}]
  );
`);

const insertChunk = db.prepare(`INSERT OR IGNORE INTO chunks
  (file, chunk_idx, sha, text, char_start, char_end, file_mtime)
  VALUES (?,?,?,?,?,?,?)`);
const insertVec = db.prepare(`INSERT INTO vec_chunks(rowid, embedding) VALUES (?, ?)`);
const haveSha = db.prepare(`SELECT id FROM chunks WHERE sha = ?`);

// ------ main ------
console.log(`embed-corpus → ${DB_PATH}`);
console.log(`model=${MODEL} dim=${DIM} chunk=${CHUNK_TOKENS}t overlap=${OVERLAP_TOKENS}t`);

const queue = [];
let scanned = 0, skipped = 0;
for await (const file of walk(CORPUS_ROOT)) {
  scanned++;
  const stat = await fs.stat(file);
  const text = await fs.readFile(file, 'utf8');
  const rel = path.relative(CORPUS_ROOT, file);
  const chunks = chunk(text);
  for (let i = 0; i < chunks.length; i++) {
    const c = chunks[i];
    const id = sha(`${rel}:${c.start}:${c.text.slice(0, 64)}`);
    if (haveSha.get(id)) { skipped++; continue; }
    queue.push({
      file: rel,
      chunk_idx: i,
      sha: id,
      text: c.text,
      char_start: c.start,
      char_end: c.start + c.text.length,
      file_mtime: Math.floor(stat.mtime.getTime() / 1000),
    });
  }
}
console.log(`scanned ${scanned} files, ${queue.length} new chunks, ${skipped} already-embedded`);

let done = 0;
const t0 = Date.now();
for (let i = 0; i < queue.length; i += BATCH) {
  const batch = queue.slice(i, i + BATCH);
  let vecs;
  try {
    vecs = await embedBatch(batch.map(b => b.text));
  } catch (e) {
    console.error(`batch ${i}: ${e.message} — retrying once`);
    await new Promise(r => setTimeout(r, 1500));
    vecs = await embedBatch(batch.map(b => b.text));
  }
  const tx = db.transaction(() => {
    for (let k = 0; k < batch.length; k++) {
      const b = batch[k];
      const info = insertChunk.run(b.file, b.chunk_idx, b.sha, b.text, b.char_start, b.char_end, b.file_mtime);
      if (info.changes === 0) continue;
      // Read back the integer rowid via SELECT — better-sqlite3's lastInsertRowid
      // can be BigInt which sqlite-vec's vec0 table rejects.
      const row = haveSha.get(b.sha);
      if (!row) continue;
      const f32 = Float32Array.from(vecs[k]);
      // sqlite-vec vec0 wants BigInt for rowid binding, not Number
      insertVec.run(BigInt(row.id), Buffer.from(f32.buffer, f32.byteOffset, f32.byteLength));
    }
  });
  tx();
  done += batch.length;
  const rate = done / ((Date.now() - t0) / 1000);
  process.stdout.write(`\r${done}/${queue.length} (${rate.toFixed(1)}/s)  `);
}
console.log(`\ndone in ${((Date.now() - t0) / 1000).toFixed(1)}s`);

const total = db.prepare(`SELECT COUNT(*) as n FROM chunks`).get().n;
const veccount = db.prepare(`SELECT COUNT(*) as n FROM vec_chunks`).get().n;
console.log(`db: ${total} chunks, ${veccount} vectors`);
db.close();
