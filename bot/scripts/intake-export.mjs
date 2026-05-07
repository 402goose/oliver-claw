#!/usr/bin/env node
// intake-export.mjs — drains URL-bearing memories out of tenet memory.db and
// writes them as markdown into a corpus-shaped directory the embedder can walk.
//
// Why: the agent saves Content Dump intake into tenet's memory.db (via
// memory_add). That DB is great for retrieval-by-tag but isn't part of the
// vector corpus. This script bridges them so daily-reembed picks them up.
//
// Usage: node intake-export.mjs
//   MEMORY_DB    default /data/tenet/.tenet/memory.db
//   EXPORT_DIR   default /data/intake-export
//
// Idempotent: existing files are overwritten only if the source memory's
// content hash differs.

import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import Database from 'better-sqlite3';

const MEMORY_DB = process.env.MEMORY_DB || '/data/tenet/.tenet/memory.db';
const EXPORT_DIR = process.env.EXPORT_DIR || '/data/intake-export';

if (!fs.existsSync(MEMORY_DB)) {
  console.error(`memory.db not found at ${MEMORY_DB}`);
  process.exit(0); // not fatal; the bot may be brand new
}

fs.mkdirSync(EXPORT_DIR, { recursive: true });

const db = new Database(MEMORY_DB, { readonly: true });

// Pull memories whose content has a URL. Skip the operating-rule memory.
const rows = db.prepare(`
  SELECT m.id, m.source, m.type, m.title, m.content, m.metadata, m.created_at,
         GROUP_CONCAT(t.tag, ',') AS tags
  FROM memories m
  LEFT JOIN tags t ON t.memory_id = m.id
  WHERE m.content LIKE '%http%'
  GROUP BY m.id
  ORDER BY m.created_at ASC
`).all();

const slugify = (s) => s.toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-|-$/g, '')
  .slice(0, 60);

const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 12);

let written = 0, skipped = 0;
for (const r of rows) {
  const slug = slugify(r.title || `memory-${r.id}`);
  const filename = `${String(r.id).padStart(5, '0')}-${slug}.md`;
  const target = path.join(EXPORT_DIR, filename);

  const header = [
    '---',
    `id: ${r.id}`,
    `source: tenet-memory`,
    `memory_source: ${r.source || ''}`,
    `memory_type: ${r.type || ''}`,
    `title: ${JSON.stringify(r.title || '')}`,
    `tags: ${r.tags || ''}`,
    `created_at: ${r.created_at}`,
    '---',
    '',
    `# ${r.title || `Memory ${r.id}`}`,
    '',
  ].join('\n');

  const body = r.content + '\n';
  const content = header + body;
  const newHash = sha(content);

  if (fs.existsSync(target)) {
    const existing = fs.readFileSync(target, 'utf8');
    if (sha(existing) === newHash) { skipped++; continue; }
  }

  fs.writeFileSync(target, content);
  written++;
}

console.log(`intake-export: ${written} written, ${skipped} unchanged → ${EXPORT_DIR}`);
console.log(`total memories with URLs: ${rows.length}`);
