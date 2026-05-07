#!/bin/sh
# daily-reembed.sh — drain memory.db intake → markdown, then re-embed corpus.
# Runs against /data/corpus (image corpus) AND /data/intake-export (memories).
# Both feed the shared /data/agents/dee/corpus-vec.sqlite vector store.
#
# Invoke directly or from start-gateway.sh's background loop.

set -e
LOG=/data/logs/daily-reembed.log
mkdir -p /data/logs /data/intake-export /data/agents/dee

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

{
  echo ""
  echo "===== $(ts) reembed cycle start ====="

  echo "[$(ts)] step 1/3: intake-export"
  node /data/scripts/intake-export.mjs || echo "[$(ts)] WARN intake-export non-zero"

  if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "[$(ts)] OPENROUTER_API_KEY missing; skipping embed"
    echo "===== $(ts) cycle aborted ====="
    exit 0
  fi

  echo "[$(ts)] step 2/3: embed image corpus (/data/corpus)"
  CORPUS_ROOT=/data/corpus \
    CORPUS_DB=/data/agents/dee/corpus-vec.sqlite \
    node /data/scripts/embed-corpus.mjs || echo "[$(ts)] WARN embed-corpus(corpus) non-zero"

  echo "[$(ts)] step 3/3: embed intake corpus (/data/intake-export)"
  CORPUS_ROOT=/data/intake-export \
    CORPUS_DB=/data/agents/dee/corpus-vec.sqlite \
    node /data/scripts/embed-corpus.mjs || echo "[$(ts)] WARN embed-corpus(intake) non-zero"

  echo "===== $(ts) cycle complete ====="
} 2>&1 | tee -a "$LOG"
