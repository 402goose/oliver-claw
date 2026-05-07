#!/bin/sh
# oliver-claw boot script — runs inside the Railway container.
# /data is the persistent volume; /opt/oliver-claw is the immutable image
# whose entry.sh has already seeded /data on first boot.

CONFIG=/data/openclaw.json
BACKUP=/data/openclaw.known-good.json
WORKSPACE=/data/workspace
TENET_HOME=/data/tenet
NPM_PREFIX=/data/.npm-global

mkdir -p /data/logs /data/tenet "$NPM_PREFIX" \
         "$WORKSPACE/oliver/memory" "$WORKSPACE/oliver/notes" "$WORKSPACE/oliver/decisions" \
         /root/.cache/qmd /root/.cache/tenet /root/.config \
         /root/.openclaw/agents/oliver/qmd

# Lock memory dir so the agent must use mcp__tenet-context__memory_add (indexed
# + searchable) instead of writing markdown files (unstructured + unsearchable).
chmod 555 "$WORKSPACE/oliver/memory" 2>/dev/null || true

export PATH="$NPM_PREFIX/bin:/root/.bun/bin:$PATH"
npm config set prefix "$NPM_PREFIX" 2>/dev/null || true

# --- one-time installs into the volume-persistent npm prefix ---
if [ ! -x "$NPM_PREFIX/bin/tenet" ]; then
  echo "[boot] installing @10et/cli (tenet)"
  npm install -g @10et/cli@1.15.15 2>&1 | tail -3 || echo "[boot] tenet install warning"
fi
if [ ! -x "$NPM_PREFIX/bin/qmd" ]; then
  echo "[boot] installing @tobilu/qmd"
  npm install -g @tobilu/qmd@2.1.0 2>&1 | tail -3 || echo "[boot] qmd install warning"
fi
if [ ! -x /root/.bun/bin/bun ]; then
  echo "[boot] installing bun (required by some openclaw deps)"
  curl --max-time 60 -fsSL https://bun.sh/install | bash 2>&1 | tail -3 || echo "[boot] bun install warning"
fi
if [ ! -d "$NPM_PREFIX/lib/node_modules/openclaw" ]; then
  echo "[boot] installing openclaw"
  npm install -g openclaw@2026.4.29 2>&1 | tail -3 || echo "[boot] openclaw install warning"
fi
if [ ! -x "$NPM_PREFIX/bin/visa-cli" ]; then
  echo "[boot] installing @visa/cli (provides visa-cli binary used by oc-visa-cli-plugin)"
  npm install -g @visa/cli@1.15.0 2>&1 | tail -3 || echo "[boot] visa-cli install warning"
fi
# openclaw skills for content intake (steipete): summarize for YouTube/articles
# without yt-dlp, bird for X via GraphQL+cookies. intel.sh tries these first.
if [ ! -x "$NPM_PREFIX/bin/summarize" ]; then
  echo "[boot] installing @steipete/summarize (YouTube/article extract+summary)"
  npm install -g @steipete/summarize 2>&1 | tail -3 || echo "[boot] summarize install warning"
fi
if [ ! -x "$NPM_PREFIX/bin/bird" ]; then
  echo "[boot] installing @steipete/bird (X CLI — cookie or app-bearer)"
  npm install -g @steipete/bird 2>&1 | tail -3 || echo "[boot] bird install warning"
fi
# Confirm bin symlink exists; install retry if not
if [ ! -x "$NPM_PREFIX/bin/openclaw" ]; then
  echo "[boot] openclaw bin missing; reinstalling"
  npm install -g --force openclaw@2026.4.29 2>&1 | tail -3 || true
fi
if [ -f /data/scripts/package.json ] && [ ! -d /data/scripts/node_modules ]; then
  echo "[boot] installing /data/scripts npm deps"
  ( cd /data/scripts && npm install --omit=dev 2>&1 | tail -3 ) || echo "[boot] scripts npm install warning"
fi

# --- inject VISA_API_KEY into plugin config (patched plugin reads only from config) ---
if [ -n "$VISA_API_KEY" ]; then
  RUNTIME_CFG="${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-/data/openclaw.json}}"
  if [ -f "$RUNTIME_CFG" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq --arg key "$VISA_API_KEY" '.plugins.entries["oc-visa-cli-plugin"].config.apiKey = $key' "$RUNTIME_CFG" > "$RUNTIME_CFG.tmp" && mv "$RUNTIME_CFG.tmp" "$RUNTIME_CFG"
      echo "[boot] injected VISA_API_KEY via jq into $RUNTIME_CFG"
    elif command -v python3 >/dev/null 2>&1; then
      RUNTIME_CFG="$RUNTIME_CFG" python3 -c "
import json, os
p = os.environ['RUNTIME_CFG']
key = os.environ.get('VISA_API_KEY', '')
d = json.load(open(p))
d.setdefault('plugins', {}).setdefault('entries', {}).setdefault('oc-visa-cli-plugin', {})['config'] = {'apiKey': key}
json.dump(d, open(p, 'w'), indent=2)
"
      echo "[boot] injected VISA_API_KEY via python3 into $RUNTIME_CFG"
    else
      echo "[boot] WARNING: no jq or python3 to inject VISA_API_KEY"
    fi
  else
    echo "[boot] skipping API key injection: $RUNTIME_CFG not found"
  fi
fi

# --- install bundled openclaw plugins from /opt/oliver-claw/plugins/*.tgz ---
# These are local .tgz packs (e.g. @visa/oc-visa-cli-plugin) baked into the image.
# Reinstall on every boot — fast (npm cache) and ensures version drift is corrected.
if [ -d /opt/oliver-claw/plugins ]; then
  for tgz in /opt/oliver-claw/plugins/*.tgz; do
    [ -f "$tgz" ] || continue
    echo "[boot] installing plugin: $(basename $tgz)"
    openclaw plugins install "$tgz" 2>&1 | tail -3 || echo "[boot] plugin install warning: $tgz"
  done
fi

# --- TENET workspace bootstrap ---
export TENET_HOME
if [ ! -d "$TENET_HOME/.tenet" ]; then
  echo "[boot] initializing TENET at $TENET_HOME"
  ( cd "$TENET_HOME" && tenet init --no-interactive --name oliver-claw 2>&1 | tail -3 ) || \
    echo "[boot] tenet init returned non-zero (likely already initialized) — continuing"
fi

# --- sync persona + corpus from the bundled image into /data on every boot ---
# This way updates we ship in the image override stale /data state. The user can
# still write to non-persona/non-corpus paths in /data/workspace/oliver/{notes,decisions}.
if [ -f /opt/oliver-claw/prompts/PERSONA.md ]; then
  cp -f /opt/oliver-claw/prompts/PERSONA.md "$WORKSPACE/oliver/SOUL.md"
fi
# Append persistent persona overrides (authority-gated mutations from
# /data/scripts/persona-update.sh). Survives deploys.
if [ -f "$WORKSPACE/oliver/persona-overrides.md" ]; then
  {
    echo ""
    echo "---"
    echo ""
    echo "# Persistent Persona Overrides (volume-mounted, authority-gated)"
    echo ""
    echo "These rules were added via /data/scripts/persona-update.sh by an authorized TG id (Tagga/Real Jack/Cuy). They override the base persona above when in conflict. Real Jack's overrides outrank everyone else's regardless of position."
    echo ""
    cat "$WORKSPACE/oliver/persona-overrides.md"
  } >> "$WORKSPACE/oliver/SOUL.md"
  echo "[boot] appended $(wc -l < "$WORKSPACE/oliver/persona-overrides.md") lines from persona-overrides.md"
fi
if [ -d /opt/oliver-claw/corpus ]; then
  rm -rf /data/corpus
  cp -rT /opt/oliver-claw/corpus /data/corpus
fi

# --- patch the openclaw audio module so Groq STT works ---
# OpenClaw's transcribeOpenAiCompatibleAudio mangles multipart Content-Type
# when the request flows through its SSRF guard + pinned-DNS dispatcher. Patch
# it to bypass and use plain fetch(). Idempotent. Verified with Dee Hock bot.
AUDIO_FILE="$NPM_PREFIX/lib/node_modules/openclaw/dist/media-understanding-CdgTl3Vo.js"
if [ -f "$AUDIO_FILE" ] && [ -f /data/scripts/patch-audio.py ]; then
  python3 /data/scripts/patch-audio.py "$AUDIO_FILE" 2>&1 | head -3 || echo "[boot] audio patch returned non-zero (continuing)"
fi

# --- locate the openclaw entrypoint (npm install -g lays it out under various paths) ---
OPENCLAW_BIN=""
if command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN="openclaw"
elif [ -f "$NPM_PREFIX/lib/node_modules/openclaw/openclaw.mjs" ]; then
  OPENCLAW_BIN="node $NPM_PREFIX/lib/node_modules/openclaw/openclaw.mjs"
elif [ -f "$NPM_PREFIX/lib/node_modules/openclaw/dist/openclaw.mjs" ]; then
  OPENCLAW_BIN="node $NPM_PREFIX/lib/node_modules/openclaw/dist/openclaw.mjs"
else
  echo "[boot] FATAL: cannot locate openclaw entrypoint"
  echo "[boot] looking in $NPM_PREFIX/lib/node_modules/openclaw/"
  ls -la "$NPM_PREFIX/lib/node_modules/openclaw/" 2>&1 | head
  exit 1
fi
echo "[boot] using openclaw entrypoint: $OPENCLAW_BIN"

# --- validate config (best effort); skip if validate command not supported ---
if [ -f "$CONFIG" ]; then
  if $OPENCLAW_BIN config validate 2>/dev/null; then
    cp "$CONFIG" "$BACKUP" 2>/dev/null || true
  else
    echo "[boot] config validate skipped (returns non-zero or not implemented)"
  fi
fi

# --- daily intake re-embed loop (background) ---
# Drains tenet memory.db Content Dump intake into markdown, then re-embeds
# /data/corpus + /data/intake-export into the shared corpus-vec.sqlite.
# Runs once at boot (5min after) and every 6h thereafter.
if [ -x /data/scripts/daily-reembed.sh ]; then
  (
    sleep 300   # let the gateway settle before first run
    while true; do
      /data/scripts/daily-reembed.sh >> /data/logs/daily-reembed-loop.log 2>&1 || true
      sleep 21600   # 6h between cycles
    done
  ) &
  echo "[boot] spawned daily-reembed loop (PID $!)"
fi

# --- daily digest loop (background) ---
# Generates 24h roll-up of room activity in Jack's voice, DMs Real Jack.
# Runs first time 30min after boot, then every 24h.
if [ -x /data/scripts/daily-digest.sh ]; then
  (
    sleep 1800  # 30min after boot, after re-embed has had time to settle
    while true; do
      /data/scripts/daily-digest.sh >> /data/logs/daily-digest-loop.log 2>&1 || true
      sleep 86400   # 24h
    done
  ) &
  echo "[boot] spawned daily-digest loop (PID $!)"
fi

# --- device-pairing auto-approve loop (background) ---
# openclaw 2026.4.x feature gates (e.g. Telegram Native Approvals) need new
# scopes on the paired device. After deploys / scope expansions, the gateway
# generates pending pairing requests that nothing in-container can approve →
# bot enters tight reconnect loop, channels go dark. Auto-approve every 30s.
(
  sleep 60   # let gateway pair the operator device first
  while true; do
    OUT=$($OPENCLAW_BIN devices approve --latest 2>&1 | grep -v "No pending\|gateway connect failed\|fallback" || true)
    [ -n "$OUT" ] && echo "[pairing-watch] $OUT"
    sleep 30
  done
) >> /data/logs/pairing-watch.log 2>&1 &
echo "[boot] spawned pairing-watch loop (PID $!)"

echo "[boot] starting oliver-claw gateway (logs → /data/logs/openclaw.log)"
exec $OPENCLAW_BIN gateway run \
  --allow-unconfigured --port "${PORT:-8080}" --bind lan --verbose 2>&1 \
  | tee -a /data/logs/openclaw.log
