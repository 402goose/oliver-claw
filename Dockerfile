# oliver-claw — OpenClaw runtime + custom corpus + jack-speak (TTS off by default)
# Pattern: build small runtime that pulls openclaw at boot via the volume-mounted
# start-gateway.sh. Identical shape to the proven Dee Hock deployment on Fly,
# adapted for Railway (Volume mount at /zeroclaw-data... actually /data here).

FROM --platform=linux/amd64 node:24-bookworm-slim
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates jq git python3 python3-pip \
      build-essential pkg-config libssl-dev sqlite3 zstd unzip \
      ffmpeg yt-dlp pandoc gh openssh-client \
 && curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh \
 && rm -rf /var/lib/apt/lists/* \
 && pip3 install --break-system-packages --no-cache-dir mobi || true \
 && pip3 install --break-system-packages --no-cache-dir -U yt-dlp || true

# Volume-persistent npm prefix (matches Dee Hock pattern). Boot script will
# install @10et/cli + openclaw + qmd into /data/.npm-global on first boot.
ENV NPM_CONFIG_PREFIX=/data/.npm-global
ENV PATH=/data/.npm-global/bin:$PATH

# Bootstrap entrypoint: waits for /data/start-gateway.sh to exist (volume-mounted
# during deploy via railway up), then exec's it. Self-healing on first cold boot.
RUN mkdir -p /data /opt/oliver-claw
COPY bot/start-gateway.sh /opt/oliver-claw/start-gateway.sh
COPY bot/config/openclaw.json /opt/oliver-claw/openclaw.json
COPY bot/prompts /opt/oliver-claw/prompts
COPY bot/scripts /opt/oliver-claw/scripts
COPY bot/skills /opt/oliver-claw/skills
COPY bot/hooks /opt/oliver-claw/hooks
COPY bot/plugins /opt/oliver-claw/plugins
COPY bot/data /opt/oliver-claw/data
COPY knowledge/corpus /opt/oliver-claw/corpus
COPY bot/youtube-cookies.txt* /opt/oliver-claw/
RUN chmod +x /opt/oliver-claw/start-gateway.sh

# On first boot, copy the bundled assets into /data if not present (one-time
# seed; user changes on the volume win after first boot).
ENV ENTRY=/opt/oliver-claw/entry.sh
RUN cat > /opt/oliver-claw/entry.sh <<'EOF' && chmod +x /opt/oliver-claw/entry.sh
#!/bin/sh
set -e
mkdir -p /data/scripts /data/workspace/oliver /data/tenet /data/logs /data/.npm-global /data/corpus
# ALWAYS overwrite the boot script + bundled config + scripts + corpus from the
# image. /data is for state (sessions, sqlite, npm cache); not for code.
cp -f /opt/oliver-claw/start-gateway.sh /data/start-gateway.sh
chmod +x /data/start-gateway.sh
cp -f /opt/oliver-claw/openclaw.json /data/openclaw.json
for f in /opt/oliver-claw/scripts/*; do
  base=$(basename "$f")
  cp -rf "$f" /data/scripts/$base
done
chmod +x /data/scripts/*.sh /data/scripts/*.py 2>/dev/null || true
for f in /opt/oliver-claw/prompts/*; do
  base=$(basename "$f")
  cp -f "$f" /data/workspace/oliver/$base
done
rm -rf /data/workspace/oliver/skills /data/workspace/oliver/hooks
mkdir -p /data/workspace/oliver/skills /data/workspace/oliver/hooks
cp -rT /opt/oliver-claw/skills /data/workspace/oliver/skills
cp -rT /opt/oliver-claw/hooks /data/workspace/oliver/hooks
rm -rf /data/corpus
cp -rT /opt/oliver-claw/corpus /data/corpus
# Seed email allowlist on first boot only — subsequent edits via
# email-allowlist.sh persist on the volume and win.
if [ ! -f /data/workspace/oliver/email-allowlist.json ] && [ -f /opt/oliver-claw/data/email-allowlist.json ]; then
  cp -f /opt/oliver-claw/data/email-allowlist.json /data/workspace/oliver/email-allowlist.json
  echo "[entry] seeded empty email-allowlist.json"
fi
# Seed YouTube cookies for intel.sh:
#   1. YOUTUBE_COOKIES_B64 env var (Railway secret) — base64 of cookies.txt. Wins.
#   2. /opt/oliver-claw/youtube-cookies.txt (build-context fallback for local dev).
# Either path materializes /data/youtube-cookies.txt for yt-dlp.
if [ -n "$YOUTUBE_COOKIES_B64" ]; then
  echo "$YOUTUBE_COOKIES_B64" | base64 -d > /data/youtube-cookies.txt 2>/dev/null
  if [ -s /data/youtube-cookies.txt ]; then
    echo "[entry] youtube cookies seeded from env ($(wc -c < /data/youtube-cookies.txt) bytes)"
  else
    echo "[entry] WARN: YOUTUBE_COOKIES_B64 set but base64 decode produced empty file"
  fi
elif [ -f /opt/oliver-claw/youtube-cookies.txt ] && [ "$(wc -c < /opt/oliver-claw/youtube-cookies.txt)" -gt 500 ]; then
  cp -f /opt/oliver-claw/youtube-cookies.txt /data/youtube-cookies.txt
  echo "[entry] youtube cookies seeded from image ($(wc -c < /data/youtube-cookies.txt) bytes)"
fi
exec /bin/sh /data/start-gateway.sh
EOF

ENV OPENCLAW_STATE_DIR=/data
COPY bot/cacerts.pem /usr/local/share/ca-certificates/visa.crt
RUN update-ca-certificates
COPY bot/cacerts.pem /opt/oliver-claw/cacerts.pem
ENV NODE_EXTRA_CA_CERTS=/opt/oliver-claw/cacerts.pem
ENV NODE_OPTIONS=--use-openssl-ca
ENV OPENCLAW_GATEWAY_PORT=8080
ENV PORT=8080
ENV ZEROCLAW_ALLOW_PUBLIC_BIND=true
EXPOSE 8080
WORKDIR /data
ENTRYPOINT ["/opt/oliver-claw/entry.sh"]
