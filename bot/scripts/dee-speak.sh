#!/bin/sh
# dee-speak.sh — generate Dee Hock's cloned voice for a given text.
# Reads ElevenLabs config from /data/openclaw.json (apiKey + voiceId + voiceSettings),
# POSTs to ElevenLabs TTS, converts mp3 → ogg/opus (Telegram voice format),
# prints absolute path of resulting .ogg to stdout.
# The agent then calls its message.send tool with asVoice=true and media=<path>.
set -e
TEXT="$*"
[ -z "$TEXT" ] && { echo "usage: dee-speak.sh '<text>'" >&2; exit 1; }

CFG=/data/openclaw.json
KEY=$(node -e "console.log(require('$CFG').messages.tts.providers.elevenlabs.apiKey)")
VID=$(node -e "console.log(require('$CFG').messages.tts.providers.elevenlabs.voiceId)")
MODEL=$(node -e "console.log(require('$CFG').messages.tts.providers.elevenlabs.modelId)")
VS=$(node -e "console.log(JSON.stringify(require('$CFG').messages.tts.providers.elevenlabs.voiceSettings))")

# Write into OpenClaw's allowed-media dir so the agent can attach the file
# directly via message.send asVoice without a cp roundtrip.
OUTDIR=/data/media/outbound
mkdir -p "$OUTDIR"
ID=$(date +%s%N | tail -c 12)
OGG="$OUTDIR/dee-$ID.ogg"

# Ask ElevenLabs for opus_48000_64 directly — Telegram voice-compatible container.
BODY=$(node -e "
const text = process.argv[1];
const model = process.argv[2];
const vs = JSON.parse(process.argv[3]);
console.log(JSON.stringify({ text, model_id: model, voice_settings: vs }));
" "$TEXT" "$MODEL" "$VS")

HTTP=$(curl -sS -o "$OGG" -w "%{http_code}" \
  -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VID?output_format=opus_48000_64" \
  -H "xi-api-key: $KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/ogg" \
  --data "$BODY")
if [ "$HTTP" != "200" ] || [ ! -s "$OGG" ]; then
  echo "ElevenLabs $HTTP: $(head -c 300 "$OGG")" >&2
  rm -f "$OGG"
  exit 2
fi

echo "$OGG"
